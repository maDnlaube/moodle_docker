#!/usr/bin/env bash
# Create a timestamped backup of the Moodle database and uploaded files.
#
# Usage (from anywhere):
#   ./scripts/backup.sh
#
# Output lands in ./backups/ next to docker-compose.yml:
#   backups/db-<timestamp>.sql.gz          full database dump
#   backups/moodledata-<timestamp>.tar.gz  uploaded files, course content, etc.
#
# Restore with ./scripts/restore.sh. Copy the backups OFF the server
# regularly (scp/rsync/cloud storage) — a backup on the same disk does not
# protect you from a failed disk or a deleted server.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "ERROR: .env not found. Run this on a configured deployment (where docker compose runs)." >&2
    exit 1
fi
set -a; source ./.env; set +a

STAMP="$(date +%Y-%m-%d_%H%M%S)"
mkdir -p backups

echo "Dumping database '${DB_NAME:-moodle}' ..."
docker compose exec -T db mariadb-dump \
    -u"${DB_USER:-moodle}" -p"${DB_PASSWORD}" \
    --single-transaction --quick \
    --routines --triggers --events \
    "${DB_NAME:-moodle}" \
  | gzip > "backups/db-${STAMP}.sql.gz"

echo "Archiving moodledata (uploaded files) ..."
docker compose exec -T moodle tar -czf - -C /var/www moodledata \
  > "backups/moodledata-${STAMP}.tar.gz"

echo "Backup complete:"
ls -lh "backups/db-${STAMP}.sql.gz" "backups/moodledata-${STAMP}.tar.gz"
