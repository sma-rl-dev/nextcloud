#!/bin/bash
# Tester-env entrypoint: auto-install Nextcloud with SQLite on first boot,
# then run Apache. Reboots reuse the existing install on the data volume.
set -e

DATA_DIR="${NEXTCLOUD_DATA_DIR:-/var/www/data}"
APP_PORT="${APP_PORT:-8083}"
ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
ADMIN_PASS="${NEXTCLOUD_ADMIN_PASSWORD:-admin12345}"

mkdir -p "${DATA_DIR}"
chown www-data:www-data "${DATA_DIR}"

occ() {
    su -s /bin/bash www-data -c "php /var/www/html/occ $*"
}

if ! occ status 2>/dev/null | grep -q 'installed: *true'; then
    echo "==> Installing Nextcloud (SQLite, admin: ${ADMIN_USER})..."
    occ maintenance:install \
        --database=sqlite \
        --database-name=nextcloud \
        --admin-user="${ADMIN_USER}" \
        --admin-pass="${ADMIN_PASS}" \
        --data-dir="${DATA_DIR}"
    occ config:system:set trusted_domains 1 --value=localhost
    occ config:system:set trusted_domains 2 --value=host.docker.internal
    occ config:system:set overwrite.cli.url --value="http://localhost:${APP_PORT}"
    occ maintenance:update:htaccess
    occ background-job:set ajax 2>/dev/null || true
    echo "==> Install complete."
else
    echo "==> Nextcloud already installed, skipping setup."
fi

exec "$@"
