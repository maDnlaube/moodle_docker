#!/usr/bin/env bash
# Restore a backup created by ./scripts/backup.sh.
#
# Usage:
#   ./scripts/restore.sh backups/db-<timestamp>.sql.gz [backups/moodledata-<timestamp>.tar.gz]
#
# The database dump is required; the moodledata archive is optional but
# recommended — database and files belong together, so restore the pair
# taken at the same timestamp whenever possible.
#
# WARNING: this OVERWRITES the current site content. It asks for
# confirmation before touching anything.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "ERROR: .env not found. Run this on a configured deployment (where docker compose runs)." >&2
    exit 1
fi
set -a; source ./.env; set +a

DB_DUMP="${1:-}"
DATA_TAR="${2:-}"

if [ -z "$DB_DUMP" ]; then
    echo "Usage: $0 backups/db-<timestamp>.sql.gz [backups/moodledata-<timestamp>.tar.gz]" >&2
    exit 1
fi
[ -f "$DB_DUMP" ] || { echo "ERROR: file not found: $DB_DUMP" >&2; exit 1; }
if [ -n "$DATA_TAR" ] && [ ! -f "$DATA_TAR" ]; then
    echo "ERROR: file not found: $DATA_TAR" >&2
    exit 1
fi

echo "About to restore:"
echo "  database   <- $DB_DUMP"
[ -n "$DATA_TAR" ] && echo "  moodledata <- $DATA_TAR"
echo "This OVERWRITES the current database${DATA_TAR:+ and all uploaded files}."
read -r -p "Type 'yes' to continue: " answer
[ "$answer" = "yes" ] || { echo "Aborted — nothing was changed."; exit 1; }

echo "Restoring database ..."
gunzip -c "$DB_DUMP" \
  | docker compose exec -T db mariadb -u"${DB_USER:-moodle}" -p"${DB_PASSWORD}" "${DB_NAME:-moodle}"

if [ -n "$DATA_TAR" ]; then
    echo "Restoring moodledata ..."
    docker compose exec -T moodle bash -c '
        rm -rf /var/www/moodledata/* /var/www/moodledata/.[!.]* 2>/dev/null || true
        tar -xzf - -C /var/www
        chown -R www-data:www-data /var/www/moodledata
    ' < "$DATA_TAR"
fi

echo "Clearing Moodle caches ..."
docker compose exec -u www-data moodle php /var/www/html/admin/cli/purge_caches.php || true

echo "Restore complete. Open your site and verify that content and logins work."
