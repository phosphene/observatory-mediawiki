# Observatory MediaWiki Image
# Registry: ghcr.io/phosphene/observatory-mediawiki
#
# Pattern: extend official mediawiki:1.43.8, add extensions via composer.
# Community maintains base (PHP 8.3, Apache, MW core, GPG verification).
# We add Observatory extensions + config on top.

ARG MW_VERSION=1.43.8
ARG GIT_SHA=unknown

# ============================================================
# Stage 1: final — official MW image + Observatory layer
# ============================================================
FROM mediawiki:${MW_VERSION}

ARG MW_VERSION
ARG GIT_SHA

LABEL org.opencontainers.image.title="Observatory MediaWiki" \
      org.opencontainers.image.source="https://github.com/phosphene/observatory-mediawiki" \
      org.opencontainers.image.vendor="Independent Media Institute" \
      org.opencontainers.image.licenses="GPL-2.0" \
      org.opencontainers.image.version="${MW_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

# Additional system packages
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ghostscript \
        poppler-utils \
        msmtp \
        msmtp-mta \
        ffmpeg \
        liblua5.1-0 \
        libzip-dev \
    ; \
    # Additional PHP extensions via docker-php-ext-install (official pattern)
    docker-php-ext-install -j "$(nproc)" zip; \
    pecl install redis; \
    docker-php-ext-enable redis; \
    # Purge build deps — only runtime libs remain
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/* /tmp/pear

# Install Observatory extensions via composer (reproducible, versioned)
# composer.local.json declares the Observatory-specific extension set
COPY composer.local.json /var/www/html/composer.local.json
RUN set -eux; \
    cd /var/www/html; \
    # Use composer from official MW image
    composer update --no-dev --optimize-autoloader --no-interaction; \
    composer clear-cache; \
    chown -R www-data:www-data extensions vendor

# Observatory PHP config
COPY conf/observatory-php.ini /usr/local/etc/php/conf.d/observatory.ini

ENV MW_VERSION=${MW_VERSION}

# Inherit VOLUME ["/var/www/html/images"], EXPOSE 80, CMD ["apache2-foreground"]
# from official mediawiki base image
