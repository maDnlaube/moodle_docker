#!/bin/bash
# Entrypoint wrapper for the moodle service.
#
# On web-server start (CMD = apache2-foreground) it:
#   1. waits until the database container accepts connections,
#   2. installs the Moodle database tables on the very first run,
#   3. applies pending Moodle upgrades after an image rebuild,
# then hands over to the stock moodlehq image entrypoint.
#
# Any other command (the cron service overrides its entrypoint, and one-off
# `docker compose run moodle bash` sessions) skips straight to the stock
# entrypoint.

set -e

# Exit codes: 0 = Moodle installed, 1 = DB reachable but empty, 2 = no DB yet.
db_state() {
    php -d error_reporting=0 -d display_errors=0 -r '
        $conn = @mysqli_connect(
            getenv("MOODLE_DB_HOST") ?: "db",
            getenv("MOODLE_DB_USER"),
            getenv("MOODLE_DB_PASSWORD"),
            getenv("MOODLE_DB_NAME"),
            (int) (getenv("MOODLE_DB_PORT") ?: 3306)
        );
        if (!$conn) { exit(2); }
        $prefix = getenv("MOODLE_DB_PREFIX") ?: "mdl_";
        $result = mysqli_query($conn, "SHOW TABLES LIKE \"{$prefix}config\"");
        exit(($result && mysqli_num_rows($result) > 0) ? 0 : 1);
    '
}

if [ "$1" = "apache2-foreground" ]; then
    # The named volume must be writable by the web server user.
    mkdir -p /var/www/moodledata
    chown www-data:www-data /var/www/moodledata

    echo "[moodle-stack] Waiting for the database to come up..."
    state=0; db_state || state=$?
    while [ "$state" -eq 2 ]; do
        sleep 3
        state=0; db_state || state=$?
    done

    if [ "$state" -eq 1 ]; then
        echo "[moodle-stack] Empty database found — installing Moodle now."
        echo "[moodle-stack] This runs once and can take several minutes; do not stop the container."
        runuser -u www-data -- php /var/www/html/admin/cli/install_database.php \
            --agree-license \
            --fullname="${MOODLE_SITE_FULLNAME:-My Moodle Site}" \
            --shortname="${MOODLE_SITE_SHORTNAME:-Moodle}" \
            --adminuser="${MOODLE_ADMIN_USER:-admin}" \
            --adminpass="${MOODLE_ADMIN_PASSWORD:?MOODLE_ADMIN_PASSWORD is not set}" \
            --adminemail="${MOODLE_ADMIN_EMAIL:?MOODLE_ADMIN_EMAIL is not set}"
        echo "[moodle-stack] Moodle installed. Log in as '${MOODLE_ADMIN_USER:-admin}' with the password from your .env."
    else
        echo "[moodle-stack] Existing installation found — checking for pending upgrades..."
        runuser -u www-data -- php /var/www/html/admin/cli/upgrade.php --non-interactive \
            || echo "[moodle-stack] WARNING: upgrade.php failed; check the messages above." >&2
    fi
fi

exec moodle-docker-php-entrypoint "$@"
