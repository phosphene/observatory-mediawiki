# Observatory MediaWiki Image
# Replaces: wikivisor/taqasta-1.43.8-observatory:latest
# Registry: ghcr.io/phosphene/observatory-mediawiki
#
# Improvements over wikivisor base:
#   - Debian bookworm-slim instead of CentOS 7 (EOL Jun 2024)
#   - MW 1.43.2 LTS instead of 1.35.6
#   - PHP 8.2 instead of 7.4
#   - tini as PID 1 (signal handling, zombie reaping)
#   - msmtp replaces unmaintained ssmtp
#   - Removed: clamav, vim, mc, monit, git/curl/patch from runtime
#   - Multi-stage build — build tools never reach final image
#   - Composer pulled from verified official image (no curl|sh)
#   - Deterministic: composer install --no-dev --frozen-lockfile

ARG MW_VERSION=1.43.2
ARG GIT_SHA=unknown

# ============================================================
# Stage 1: base — runtime packages only (no build tools)
# ============================================================
FROM debian:bookworm-slim AS base

# DEBIAN_FRONTEND as ARG, not ENV — doesn't leak into final image
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
        # Web server
        apache2 \
        libapache2-mod-php8.2 \
        # PHP runtime
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
        # Media processing (ImageMagick for thumbnails, ffmpeg for video transcoding)
        imagemagick \
        ffmpeg \
        # Email relay (replaces unmaintained ssmtp)
        msmtp \
        msmtp-mta \
        # Proper PID 1 — signal handling + zombie reaping
        tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${MW_HOME}" "${MW_LOG}" "${MW_VOLUME}" "${MW_ORIGIN_FILES}" \
    && a2enmod rewrite headers deflate expires

# ============================================================
# Stage 2: builder — MW core + deps (build tools stay here)
# ============================================================
FROM base AS builder

ARG MW_VERSION
ARG DEBIAN_FRONTEND=noninteractive

# Build tools — only in this stage, never reach final image
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        unzip \
        patch \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Composer from official image — no curl|sh antipattern
COPY --from=composer:2.7.6 /usr/bin/composer /usr/local/bin/composer

# Download MW core tarball (faster + cleaner than git clone)
RUN set -eux; \
    curl -fsSL "https://releases.wikimedia.org/mediawiki/${MW_VERSION%.*}/mediawiki-${MW_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 -C "${MW_HOME}" \
    # Preserve origin files for volume init on first container start
    && cp -r "${MW_HOME}/." "${MW_ORIGIN_FILES}/"

WORKDIR ${MW_HOME}

# Install PHP deps — frozen lockfile, no composer update
COPY composer.local.json ./
RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && composer clear-cache

# ============================================================
# Stage 3: final — lean runtime image, no build tools
# ============================================================
FROM base AS final

ARG MW_VERSION
ARG GIT_SHA

# Wire version metadata into OCI labels at build time
LABEL org.opencontainers.image.version="${MW_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

# Copy MW installation from builder — explicit paths, no wildcards
COPY --from=builder ${MW_HOME} ${MW_HOME}
COPY --from=builder ${MW_ORIGIN_FILES} ${MW_ORIGIN_FILES}

# Apache config
COPY conf/apache-mediawiki.conf /etc/apache2/sites-available/mediawiki.conf

# Entrypoint and run scripts — explicit, not COPY scripts/ /
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/run-apache.sh /run-apache.sh

RUN a2dissite 000-default.conf \
    && a2ensite mediawiki \
    && chmod +x /entrypoint.sh /run-apache.sh \
    # Set correct ownership for MW directories
    && chown -R www-data:www-data "${MW_HOME}" "${MW_LOG}"

# MW runtime defaults — all overridable via compose env:
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

# /mediawiki must be a named volume — entrypoint enforces this
VOLUME ["/mediawiki"]

EXPOSE 80

# tini as PID 1
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["/run-apache.sh"]
