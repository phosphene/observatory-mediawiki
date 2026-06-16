# Observatory MediaWiki Image
# Replaces: wikivisor/taqasta-1.43.8-observatory:latest
# Registry: ghcr.io/phosphene/observatory-mediawiki
#
# Architecture: Apache on 8080 (internal) — Varnish/Traefik handles 80/443
# Runs as www-data (non-root) — no port 80 binding needed

ARG MW_VERSION=1.43.2
ARG GIT_SHA=unknown

# ============================================================
# Stage 1: base — runtime packages only (no build tools)
# ============================================================
FROM debian:bookworm-slim AS base

ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="Observatory MediaWiki" \
      org.opencontainers.image.source="https://github.com/phosphene/observatory-mediawiki" \
      org.opencontainers.image.vendor="Independent Media Institute" \
      org.opencontainers.image.licenses="GPL-2.0"

ENV MW_HOME=/var/www/html/w \
    MW_LOG=/var/log/mediawiki \
    MW_VOLUME=/mediawiki \
    MW_ORIGIN_FILES=/mw_origin_files \
    WWW_USER=www-data \
    WWW_GROUP=www-data \
    APACHE_LOG_DIR=/var/log/apache2

RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends \
        apache2 \
        libapache2-mod-php8.2 \
        php8.2 \
        php8.2-cli \
        php8.2-mysql \
        php8.2-gd \
        php8.2-mbstring \
        php8.2-xml \
        php8.2-intl \
        php8.2-opcache \
        php8.2-apcu \
        php8.2-redis \
        php8.2-curl \
        php8.2-zip \
        imagemagick \
        ffmpeg \
        msmtp \
        msmtp-mta \
        tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${MW_HOME}" "${MW_LOG}" "${MW_VOLUME}" "${MW_ORIGIN_FILES}" \
    # Disable default site — our config replaces it
    && a2dissite 000-default.conf 2>/dev/null || true \
    && a2enmod rewrite headers deflate expires \
    # Allow www-data to write logs
    && chown -R www-data:www-data "${MW_LOG}" /var/log/apache2 /var/run/apache2 \
    # Apache: run on 8080, no root binding needed
    && sed -i 's/Listen 80$//' /etc/apache2/ports.conf \
    && sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' \
        /etc/apache2/sites-available/*.conf 2>/dev/null || true

# ============================================================
# Stage 2: builder — MW core + deps (build tools stay here)
# ============================================================
FROM base AS builder

ARG MW_VERSION
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git curl unzip patch \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Composer from verified official image — no curl|sh
COPY --from=composer:2.7.6 /usr/bin/composer /usr/local/bin/composer

RUN set -eux; \
    curl -fsSL "https://releases.wikimedia.org/mediawiki/${MW_VERSION%.*}/mediawiki-${MW_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 -C "${MW_HOME}" \
    && cp -r "${MW_HOME}/." "${MW_ORIGIN_FILES}/"

WORKDIR ${MW_HOME}

COPY composer.local.json ./
RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && composer clear-cache

# ============================================================
# Stage 3: final — lean runtime, non-root
# ============================================================
FROM base AS final

ARG MW_VERSION
ARG GIT_SHA

LABEL org.opencontainers.image.version="${MW_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

COPY --from=builder ${MW_HOME} ${MW_HOME}
COPY --from=builder ${MW_ORIGIN_FILES} ${MW_ORIGIN_FILES}

COPY conf/apache-mediawiki.conf /etc/apache2/sites-available/mediawiki.conf
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/run-apache.sh /run-apache.sh

RUN a2ensite mediawiki \
    && chmod +x /entrypoint.sh /run-apache.sh \
    && chown -R www-data:www-data "${MW_HOME}" "${MW_LOG}" "${MW_VOLUME}"

ENV MW_VERSION=${MW_VERSION} \
    MW_AUTOUPDATE=true \
    MW_MAINTENANCE_UPDATE=0 \
    MW_ENABLE_EMAIL=0 \
    MW_ENABLE_USER_EMAIL=0 \
    MW_ENABLE_UPLOADS=0 \
    MW_USE_IMAGE_MAGIC=1 \
    MW_MAIN_CACHE_TYPE=CACHE_NONE \
    MW_DB_TYPE=mysql \
    MW_DB_SERVER=db \
    MW_DB_USER=mediawiki \
    MW_CIRRUS_SEARCH_SERVERS=elasticsearch \
    MW_ENABLE_JOB_RUNNER=true \
    MW_JOB_RUNNER_PAUSE=2 \
    PHP_UPLOAD_MAX_FILESIZE=50M \
    PHP_POST_MAX_SIZE=50M \
    PHP_MEMORY_LIMIT=256M \
    MW_SHOW_EXCEPTION_DETAILS=false \
    MW_DEBUG_MODE=false

VOLUME ["/mediawiki"]

# 8080 internally — Varnish/Traefik handles 80/443
EXPOSE 8080

# Non-root: www-data
USER www-data

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["/run-apache.sh"]
