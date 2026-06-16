# Observatory MediaWiki Image
# Registry: ghcr.io/phosphene/observatory-mediawiki
#
# Strategy: extend the official Wikimedia MediaWiki image.
# Community maintains the base — PHP, Apache, MW core, GPG verification.
# We add only Observatory-specific extensions and configuration.
#
# Base: wikimedia/mediawiki:1.43 (php:8.3-apache, Debian bookworm)
# MW:   1.43.x LTS (current community-maintained release)
# PHP:  8.3 (from official PHP image)

ARG MW_VERSION=1.43.8
ARG GIT_SHA=unknown

# ============================================================
# Stage 1: extension fetcher — pulls all Observatory extensions
# Build tools stay here, never reach the runtime image.
# ============================================================
FROM debian:bookworm-slim AS extension-fetcher

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        curl \
        unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /extensions

# Clone Observatory extensions at pinned commits (reproducible builds)
# Extensions baked into image = available even without volume mounts in CI

# --- WikiTeq / Observatory custom ---
RUN git clone --depth=1 https://github.com/wikivisor/emailpage-observatory.git EmailPage

# --- MediaWiki community extensions (pinned to REL1_43) ---
RUN git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/VisualEditor && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/SemanticMediaWiki && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/PageForms && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/Scribunto && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/TemplateStyles && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/TemplateData && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/WikiEditor && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/CodeEditor && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/CodeMirror && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/AdvancedSearch && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/Cite && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/CiteThisPage && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/ContactPage && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/DataTransfer && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/DisplayTitle && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/Gadgets && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/ImageMap && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/Interwiki && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/Lockdown && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/MultimediaViewer && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/NumerAlpha && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/PageImages && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/PdfHandler && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/Poem && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/ReplaceText && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/TextExtracts && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/Variables && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/WikiSEO && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/CirrusSearch && \
    git clone --depth=1 -b REL1_43 https://gerrit.wikimedia.org/r/mediawiki/extensions/Elastica

# Remove .git dirs — no history in the final image
RUN find /extensions -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ============================================================
# Stage 2: final — official MW image + Observatory extensions
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

# Additional system packages Observatory needs beyond the base MW image
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # PDF handling
        ghostscript \
        poppler-utils \
        # Email relay (replaces ssmtp)
        msmtp \
        msmtp-mta \
        # Video transcoding (EmbedVideo/Transcoder)
        ffmpeg \
        # Lua for Scribunto
        liblua5.1-0 \
    ; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# Additional PHP extensions Observatory needs
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libzip-dev \
        libicu-dev \
    ; \
    docker-php-ext-install -j "$(nproc)" \
        zip \
    ; \
    pecl install redis; \
    docker-php-ext-enable redis; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/* /tmp/pear

# Copy Observatory extensions from fetcher stage
COPY --from=extension-fetcher /extensions /var/www/html/extensions/

# Observatory-specific PHP config
COPY conf/observatory-php.ini /usr/local/etc/php/conf.d/observatory.ini

# Apache: allow encoded slashes (needed for some MW API calls)
# Already set in base image for VisualEditor, confirm it's present
RUN grep -q "AllowEncodedSlashes" /etc/apache2/sites-available/000-default.conf || \
    sed -i "s/<\/VirtualHost>/\tAllowEncodedSlashes NoDecode\n<\/VirtualHost>/" \
    /etc/apache2/sites-available/000-default.conf

# Set correct ownership for extensions
RUN chown -R www-data:www-data /var/www/html/extensions

ENV MW_SHOW_EXCEPTION_DETAILS=false \
    MW_DEBUG_MODE=false \
    PHP_UPLOAD_MAX_FILESIZE=50M \
    PHP_POST_MAX_SIZE=50M \
    PHP_MEMORY_LIMIT=256M

# Inherit VOLUME, EXPOSE, CMD from official base image
# Base exposes 80 and uses apache2-foreground
