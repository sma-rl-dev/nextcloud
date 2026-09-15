# Nextcloud — tester-env Deployment Notes

Status: accepted app. Fork `sma-rl-dev/nextcloud`, branch `tester-env-baseline`
on top of upstream tag `v34.0.3` (`b11c68e25d6030187e02477d3d82013405f62965`,
3rdparty submodule at `1dfcc090aca75a859729d1b7614d9b53ec445233`).
Source build, browser smoke (login + Files + folder-create workflow),
deterministic reset, and deterministic seed all verified this session.

## What this is

Single-container Nextcloud (PHP 8.4 + Apache) built **from editable source**
with `Dockerfile.tester-env`, backed by SQLite. Tester-env tooling at the
fork root (on `tester-env-baseline`):

- `tester-env` — CLI (deploy/seed/verify/reset/stop/logs/status/help).
- `Dockerfile.tester-env` — editable-source build (php:8.4-apache +
  gd/intl/zip/exif/gmp/bcmath/pcntl/apcu, composer install --no-dev,
  prebuilt `dist/` used, no npm build).
- `docker-entrypoint-tester-env.sh` — auto-installs SQLite via
  `occ maintenance:install` (admin/admin12345) on first boot; reboots reuse
  the install on the data volume.
- `.dockerignore` — tester-env tooling exclusions so tooling-only edits do
  not bust the Docker build cache.

## Quick start

```bash
./tester-env deploy    # build from source, start container, auto-install
./tester-env seed      # deterministic users + Files seed via WebDAV/occ
./tester-env verify    # occ status + status.php + users + seeded files
./tester-env status    # container state + URL
./tester-env logs      # container logs
./tester-env reset     # remove container AND volume -> clean slate
```

Deterministic sequence: `./tester-env reset && ./tester-env deploy &&
./tester-env seed` (seed is idempotent: users are enforced to fixed
passwords/display names, WebDAV MKCOL tolerates 201/405, PUT overwrites
fixed content, and seed DELETEs known smoke-test leftovers
`smoke-test-2026-09-15`/`SmokeFolder` before reseeding. Verified:
seed→verify→seed→verify plus reset→deploy→seed→verify this session.)

URL: http://localhost:8083/ (status.php at `/status.php`, login at `/login`).

## Seed data (deterministic, occ + WebDAV)

`./tester-env seed` creates fixed users and admin-owned Files content;
`./tester-env verify` asserts them via `occ user:info`, `occ files:get`,
and a content grep.

- Users: `admin` (admin12345), `alice` (alice12345, Alice Rivera),
  `bob` (bob12345, Bob Chen). Passwords and display names are enforced on
  every seed run.
- Admin Files: `Projects/`, `Projects/Website-Redesign/`, `Notes/`,
  `Shared/` plus 4 fixed-content files:
  - `Projects/Website-Redesign/launch-plan.md` (greps "Acme Studio launch
    plan"; checklist: homepage copy approved by Alice, screenshots from Bob)
  - `Projects/budget-2026.txt` (BUDGET-2026, total 2200 EUR)
  - `Notes/weekly-standup-2026-09-07.md` (Alice/Bob standup notes)
  - `Shared/reading-list.txt` (Acme Studio reading list, 3 items)
- `files:scan --quiet admin alice bob` refreshes the filecache after seeding.

Expected visible state after login (`admin` / `admin12345`): Files view
(`http://localhost:8083/apps/files/`) shows seeded Projects/Notes/Shared
names.

Calendar/Contacts apps are NOT installed in this baseline (would need an
appstore fetch), so seeding is Files-only by design.

## Credentials / auth posture

- Fixed admin `admin` / `admin12345`, provisioned by the entrypoint via
  `occ maintenance:install --database=sqlite` against a fresh volume.
- `trusted_domains` includes `localhost` + `host.docker.internal`;
  `overwrite.cli.url` set to `http://localhost:${APP_PORT}`; pretty URLs via
  `maintenance:update:htaccess`; background jobs set to ajax.
- SQLite data lives in named volume `nextcloud-data[-RUN_ID]` mounted at
  `/var/www/data` (see below).

## Env vars (CLI)

| Var | Default | Purpose |
|-----|---------|---------|
| `IMAGE_TAG` | `tester-env-nextcloud:dev` | Image name/tag. Set by `scripts/rl-env` to a content-addressed tag. Never RUN_ID-scoped. |
| `RUN_ID` | `default` | Scopes container (`tester-env-nextcloud[-$RUN_ID]`) and volume (`nextcloud-data[-$RUN_ID]`) only. |
| `PORT` | `8083` | Host port bound to container port 80. |

## Volumes & reset path

- Named volume `nextcloud-data[-RUN_ID]` holds all app state (SQLite + data
  dir at `/var/www/data`).
- `reset` = `docker stop` + `docker rm` + `docker volume rm`: removes only
  this run's container and volume. The image is NOT removed
  (content-addressed tags may be shared; cleanup is
  `scripts/rl-env gc --prune-images`).
- Verified deterministic: reset+deploy reproduces identical state
  (seed-engineer ran reset→deploy→seed→verify this session).

## Ports / layout

| Port | Where |
|------|-------|
| 8083 (host) -> 80 (container) | Nextcloud web UI + WebDAV + status.php |

## Build performance (mutation workflow)

- Cold build ~8-10 min (PHP extension compile); dependency layers
  (apt + composer) are cached.
- Mutation workflow: 1-line PHP edit rebuilds in ~11s (apt+composer layers
  cached); MUTPROBE title edit verified visible in `/login` HTML.
- Prebuilt `dist/` is used; no npm build inside the image.

## Deviations from upstream (all deliberate)

1. Fixed `admin`/`admin12345` auto-install (see above) instead of
   first-run wizard.
2. SQLite backend (`/var/www/data` volume) instead of external MySQL/PgSQL.
3. `.dockerignore`: added `tester-env`, `DEPLOY-SMA.md` so tooling stays
   out of the image context (`docker-entrypoint-tester-env.sh` must stay
   IN the context — the Dockerfile COPYs it as ENTRYPOINT; excluding it
   breaks `deploy` after `reset` — fixed 2026-09-15). Upstream
   checkout itself is otherwise unmodified.
4. Omitted optional extensions: imagick/redis/ldap (admin overview shows
   setup warnings for some of these).

## Caveats

- The admin overview shows setup warnings (imagick/redis/ldap omitted).
- First `deploy` cold-builds PHP extensions (~8-10 min); subsequent
  mutation rebuilds are ~11s.

## Evidence

- 2026-09-14 source_build: editable-source image `tester-env-nextcloud:dev`
  (875MB, php:8.4-apache + gd/intl/zip/exif/gmp/bcmath/pcntl/apcu, composer
  install --no-dev, prebuilt dist/); deploy auto-installs SQLite via
  `occ maintenance:install` (admin/admin12345); `status.php`
  installed:true v34.0.3.2; `/login` 200 'Login - Nextcloud'.
- 2026-09-14 browser_smoke (deterministic playwright-core headless chromium
  script `.work/tmp/nextcloud-smoke/smoke.cjs`, NOT the browser-checker
  subagent which reported BLOCKED/no MCP tools): login page title
  "Login – Nextcloud"; admin/admin12345 login lands on dashboard; Files view
  shows seeded Projects/Notes/Shared names; state-changing workflow =
  created folder SmokeFolder via UI, visible in Files list, then cleaned up
  via WebDAV DELETE + files:scan; logout control present. Screenshots +
  result.json at `.work/tmp/nextcloud-smoke/` (6 PNGs 1280x720, all 5 steps
  PASS). Container left RUNNING.
- 2026-09-14 data_seed: deterministic users admin/alice/bob; admin-owned
  folders Projects/, Projects/Website-Redesign/, Notes/, Shared/ + 4
  fixed-content files (launch-plan.md greps "Acme Studio launch plan");
  idempotent (seed→verify→seed→verify); reset→deploy→seed→verify passes;
  status.php installed:true. Static manifest at
  `scenarios/nextcloud/seed.manifest.json` (3 requirements, all present).
  Calendar/Contacts skipped (apps not installed; would need appstore fetch).
- 2026-09-14 reset: `./tester-env reset` (stop+rm container+volume, keeps
  image) + deploy reproduces identical state, verified this session by
  seed-engineer.

## Tested refs

- nextcloud source: tag `v34.0.3` @ `b11c68e25d6030187e02477d3d82013405f62965`
  (3rdparty submodule at `1dfcc090aca75a859729d1b7614d9b53ec445233`)
