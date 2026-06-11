# Multi-stage Dockerfile for the Moodle 4.5 LTS stack.
#
# Two final images built from a single source tree:
#   - target=moodle  -> Apache + mod_php + Moodle source + config.php
#   - target=proxy   -> Caddy with the Caddyfile baked in
#
# Uses moodlehq/moodle-php-apache as base — the publicly maintained Moodle HQ
# image with all required PHP extensions pre-installed (gd, intl, zip,
# mbstring, soap, exif, opcache, ...).
#
# Build everything:
#   docker compose build
# Single target:
#   docker build --target=moodle -t moodle-stack:4.5 .

ARG PHP_VERSION=8.3

# ============================================================================
# Stage 1: Download the Moodle source tree.
# This stage is only a layer source for the final image; never run as-is.
# ============================================================================
FROM moodlehq/moodle-php-apache:${PHP_VERSION} AS moodle-source

ARG MOODLE_BRANCH=405
# Default pulls the newest 4.5.x patch release (includes security fixes).
# To pin an exact version for reproducible builds, set in .env e.g.:
#   MOODLE_TARBALL=moodle-4.5.12.tgz
ARG MOODLE_TARBALL=moodle-latest-405.tgz

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    rm -rf /var/www/html/*; \
    curl -fsSL "https://download.moodle.org/download.php/direct/stable${MOODLE_BRANCH}/${MOODLE_TARBALL}" \
        -o /tmp/moodle.tgz; \
    tar -xzf /tmp/moodle.tgz -C /var/www/html --strip-components=1; \
    rm /tmp/moodle.tgz; \
    chown -R www-data:www-data /var/www/html

# --- Optional: bake plugins into the image ---------------------------------
# Treat plugins as infrastructure-as-code: add them here instead of installing
# through the admin UI, so every fresh deploy ships the same plugin set.
# Example (uncomment and adapt):
#
# RUN apt-get update && apt-get install -y --no-install-recommends git && \
#     git clone --depth 1 --branch MOODLE_405_STABLE \
#         https://github.com/<owner>/<plugin-repo>.git \
#         /var/www/html/<plugin-type>/<plugin-name> && \
#     rm -rf /var/www/html/<plugin-type>/<plugin-name>/.git && \
#     chown -R www-data:www-data /var/www/html/<plugin-type>/<plugin-name>

# ============================================================================
# Stage 2: Final Moodle image (target=moodle). Used by `moodle` and `cron`.
# Apache + mod_php serve both static and PHP files from /var/www/html.
# ============================================================================
FROM moodlehq/moodle-php-apache:${PHP_VERSION} AS moodle

LABEL org.opencontainers.image.title="moodle-stack" \
      org.opencontainers.image.description="Moodle 4.5 LTS on Apache + mod_php"

COPY --from=moodle-source --chown=www-data:www-data /var/www/html /var/www/html
COPY --chown=www-data:www-data moodle/config.php /var/www/html/config.php
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
