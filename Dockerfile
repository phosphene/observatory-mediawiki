# Observatory MediaWiki Image
# Replaces: wikivisor/taqasta-1.43.8-observatory:latest
# Registry: ghcr.io/phosphene/observatory-mediawiki
#
# Improvements over wikivisor base:
#   - Debian bookworm-slim instead of CentOS 7 (EOL Jun 2024)
#   - MW 1.43.x LTS instead of 1.35.6
#   - PHP 8.2 instead of 7.4
#   - tini as PID 1 (signal handling, zombie reaping)
#   - msmtp replaces unmaintained ssmtp
#   - Removed: clamav, vim, mc, monit
#   - Multi-stage build with deterministic composer install

ARG MW_VERSION=1.43.2

# ============================================================
# Stage 1: base — OS + runtime packages
# ============================================================
FROM debian:bookworm-slim AS base

ARG MW_VERSION

LABEL org.opencontainers.image.title="Observatory MediaWiki" \
      org.opencontainers.image.source="https://github.com/phosphene/observatory-mediawiki" \
      org.opencontainers.image.vendor="Independent Media Institute" \
      org.opencontainers.image.licenses="GPL-2.0"

ENV MW_VERSION=${MW_VERSION} \
    MW_HOME=/var/www/html/w \
    MW_LOG=/var/log/mediawiki \
    MW_VOLUME=/mediawiki \
    MW_ORIGIN_FILES=/mw_origin_files \
    WWW_USER=www-data \
    WWW_GROUP=www-data \
    APACHE_LOG_DIR=/var/log/apache2 \
    DEBIAN_FRONTEND=noninteractive

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
        git \
        curl \
        unzip \
        patch \
        msmtp \
        msmtp-mta \
        tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${MW_HOME}" "${MW_LOG}" "${MW_VOLUME}" "${MW_ORIGIN_FILES}" \
    && a2enmod rewrite headers deflate expires

# ============================================================
# Stage 2: builder — MW core + composer deps
# ============================================================
FROM base AS builder

ARG MW_VERSION

RUN curl -sS https://getcomposer.org/installer \
    | php -- --install-dir=/usr/local/bin --filename=composer --version=2.7.6

RUN set -eux; \
    curl -fsSL "https://releases.wikimedia.org/mediawiki/${MW_VERSION%.*}/mediawiki-${MW_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 -C "${MW_HOME}" \
    && cp -r "${MW_HOME}/." "${MW_ORIGIN_FILES}/"

WORKDIR ${MW_HOME}

COPY composer.local.json ./
RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && composer clear-cache

# ============================================================
# Stage 3: final — lean runtime image
# ============================================================
FROM base AS final

ARG MW_VERSION

COPY --from=builder ${MW_HOME} ${MW_HOME}
COPY --from=builder ${MW_ORIGIN_FILES} ${MW_ORIGIN_FILES}

COPY conf/apache-mediawiki.conf /etc/apache2/sites-available/mediawiki.conf
COPY scripts/ /

RUN a2dissite 000-default.conf && a2ensite mediawiki \
    && chmod +x /entrypoint.sh /run-apache.sh

ENV MW_AUTOUPDATE=true \
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
EXPOSE 80

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/run-apache.sh"]
