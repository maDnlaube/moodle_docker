# Multi-stage Dockerfile for the Moodle 5.3 LTS stack.
#
# Two final images built from a single source tree:
#   - target=moodle  -> Apache + mod_php + Moodle source + config.php
#   - target=proxy   -> Caddy with the Caddyfile baked in
#
# Uses moodlehq/moodle-php-apache as base — the publicly maintained Moodle HQ
# image with all required PHP extensions pre-installed (gd, intl, zip,
# mbstring, soap, exif, sodium, opcache, ...).
#
# Build everything:
#   docker compose build
# Single target:
#   docker build --target=moodle -t moodle-stack:5.3 .

ARG PHP_VERSION=8.3

# ============================================================================
# Stage 1: Download the Moodle source tree.
# This stage is only a layer source for the final image; never run as-is.
# ============================================================================
FROM moodlehq/moodle-php-apache:${PHP_VERSION} AS moodle-source

ARG MOODLE_BRANCH=503
# Default pulls the newest 5.3.x release (includes security fixes).
# To pin an exact version for reproducible builds, set in .env e.g.:
#   MOODLE_TARBALL=moodle-5.3.tgz      (the first 5.3 release has no ".0")
#   MOODLE_TARBALL=moodle-5.3.1.tgz    (later patch releases)
ARG MOODLE_TARBALL=moodle-latest-503.tgz

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    rm -rf /var/www/html/*; \
    curl -fsSL --retry 5 --retry-delay 10 \
        "https://download.moodle.org/download.php/direct/stable${MOODLE_BRANCH}/${MOODLE_TARBALL}" \
        -o /tmp/moodle.tgz; \
    tar -xzf /tmp/moodle.tgz -C /var/www/html --strip-components=1; \
    rm /tmp/moodle.tgz; \
    if [ ! -f /var/www/html/public/r.php ]; then \
        echo "ERROR: ${MOODLE_TARBALL} is older than Moodle 5.1. This stack serves Moodle's public/ folder, which only exists from 5.1 on." >&2; \
        echo "ERROR: Coming from the Moodle 4.5 version of this repository? Update MOODLE_BRANCH, MOODLE_TARBALL and IMAGE_TAG in .env - see 'Upgrading from Moodle 4.5' in README.md." >&2; \
        exit 1; \
    fi

# The download does not include vendor/. Moodle runs without it, but its
# REST API, OAuth 2 server and the bin/moodle command-line tool depend on
# packages that only Composer installs (exact versions from composer.lock).
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
RUN set -eux; \
    cd /var/www/html; \
    COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-dev --optimize-autoloader --no-interaction --no-progress; \
    chown -R www-data:www-data /var/www/html

# --- Optional: bake plugins into the image ---------------------------------
# Treat plugins as infrastructure-as-code: add them here instead of installing
# through the admin UI, so every fresh deploy ships the same plugin set.
# Since Moodle 5.1, plugins live inside the public/ folder.
# Example (uncomment and adapt):
#
# RUN apt-get update && apt-get install -y --no-install-recommends git && \
#     git clone --depth 1 --branch MOODLE_503_STABLE \
#         https://github.com/<owner>/<plugin-repo>.git \
#         /var/www/html/public/<plugin-type>/<plugin-name> && \
#     rm -rf /var/www/html/public/<plugin-type>/<plugin-name>/.git && \
#     chown -R www-data:www-data /var/www/html/public/<plugin-type>/<plugin-name>

# ============================================================================
# Stage 2: Final Moodle image (target=moodle). Used by `moodle` and `cron`.
# Apache serves only /var/www/html/public (the webroot since Moodle 5.1);
# config.php sits one level up in /var/www/html, outside the webroot.
# ============================================================================
FROM moodlehq/moodle-php-apache:${PHP_VERSION} AS moodle

LABEL org.opencontainers.image.title="moodle-stack" \
      org.opencontainers.image.description="Moodle 5.3 LTS on Apache + mod_php"

COPY --from=moodle-source --chown=www-data:www-data /var/www/html /var/www/html
COPY --chown=www-data:www-data moodle/config.php /var/www/html/config.php
COPY moodle/apache-vhost.conf /etc/apache2/sites-available/000-default.conf
COPY moodle/php-overrides.ini /usr/local/etc/php/conf.d/zz-moodle-overrides.ini
COPY moodle/entrypoint.sh /usr/local/bin/moodle-stack-entrypoint

RUN chmod +x /usr/local/bin/moodle-stack-entrypoint && \
    mkdir -p /var/www/moodledata && \
    chown www-data:www-data /var/www/moodledata

EXPOSE 80

# Wrapper waits for the DB, installs Moodle on first run, applies pending
# upgrades after a rebuild, then hands over to the stock image entrypoint.
ENTRYPOINT ["moodle-stack-entrypoint"]
CMD ["apache2-foreground"]

# ============================================================================
# Stage 3: Caddy image (target=proxy). Used by the `caddy` service.
# Caddy terminates HTTPS and reverse-proxies to the moodle service on port 80.
# ============================================================================
FROM caddy:2-alpine AS proxy

LABEL org.opencontainers.image.title="moodle-stack-caddy" \
      org.opencontainers.image.description="Caddy reverse proxy with automatic HTTPS for Moodle"

COPY caddy/Caddyfile /etc/caddy/Caddyfile
