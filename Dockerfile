# Observatory MediaWiki Image
# Registry: ghcr.io/phosphene/observatory-mediawiki
#
# Strategy: follow WikiTeq/taqasta pattern exactly — git clone extensions
# in builder stage at pinned commits, copy to final image.
# Use GitHub mirrors (not Gerrit) for reliable CI pulls.
# Base: official mediawiki:1.43.8 (PHP 8.3, Apache, GPG-verified MW core).

ARG MW_VERSION=1.43.8
ARG GIT_SHA=unknown

# ============================================================
# Stage 1: extension builder
# Clone all extensions from GitHub mirrors at REL1_43 branch tips.
# Build tools and git history never reach the runtime image.
# ============================================================
FROM debian:bookworm-slim AS extension-builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# SMW family — own GitHub orgs, managed via composer in runtime stage
# Everything else — wikimedia GitHub mirrors at REL1_43

WORKDIR /extensions

RUN git config --global url."https://github.com/".insteadOf "git@github.com:" \
    && git config --global credential.helper ""

# --- Bundled in MW core (no clone needed, listed for documentation) ---
# Cite, CiteThisPage, CodeEditor, CategoryTree, ConfirmEdit, Echo,
# Gadgets, ImageMap, InputBox, Math, MultimediaViewer, Poem,
# ParserFunctions, SpamBlacklist, SyntaxHighlight_GeSHi, TemplateData,
# TemplateStyles, TextExtracts, TitleBlacklist, Vector, WikiEditor

# --- Clone from wikimedia GitHub mirrors ---
RUN git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-AdminLinks . && cd AdminLinks && rm -rf .git || true; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-AdvancedSearch AdvancedSearch && rm -rf AdvancedSearch/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-AJAXPoll AJAXPoll && rm -rf AJAXPoll/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-AntiSpoof AntiSpoof && rm -rf AntiSpoof/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ApprovedRevs ApprovedRevs && rm -rf ApprovedRevs/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Arrays Arrays && rm -rf Arrays/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-BetaFeatures BetaFeatures && rm -rf BetaFeatures/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CheckUser CheckUser && rm -rf CheckUser/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CirrusSearch CirrusSearch && rm -rf CirrusSearch/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CodeMirror CodeMirror && rm -rf CodeMirror/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CommonsMetadata CommonsMetadata && rm -rf CommonsMetadata/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ConfirmAccount ConfirmAccount && rm -rf ConfirmAccount/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ContactPage ContactPage && rm -rf ContactPage/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-DataTransfer DataTransfer && rm -rf DataTransfer/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Disambiguator Disambiguator && rm -rf Disambiguator/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-DismissableSiteNotice DismissableSiteNotice && rm -rf DismissableSiteNotice/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-DisplayTitle DisplayTitle && rm -rf DisplayTitle/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Elastica Elastica && rm -rf Elastica/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ExternalData ExternalData && rm -rf ExternalData/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-GlobalNotice GlobalNotice && rm -rf GlobalNotice/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-HTMLTags HTMLTags && rm -rf HTMLTags/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-IframePage IframePage && rm -rf IframePage/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Interwiki Interwiki && rm -rf Interwiki/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-LabeledSectionTransclusion LabeledSectionTransclusion && rm -rf LabeledSectionTransclusion/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Lingo Lingo && rm -rf Lingo/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Lockdown Lockdown && rm -rf Lockdown/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Loops Loops && rm -rf Loops/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MassMessage MassMessage && rm -rf MassMessage/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MobileFrontend MobileFrontend && rm -rf MobileFrontend/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MsUpload MsUpload && rm -rf MsUpload/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MultimediaViewer MultimediaViewer && rm -rf MultimediaViewer/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MyVariables MyVariables && rm -rf MyVariables/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Nuke Nuke && rm -rf Nuke/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-NumerAlpha NumerAlpha && rm -rf NumerAlpha/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-OATHAuth OATHAuth && rm -rf OATHAuth/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-OpenGraphMeta OpenGraphMeta && rm -rf OpenGraphMeta/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-OpenIDConnect OpenIDConnect && rm -rf OpenIDConnect/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PageForms PageForms && rm -rf PageForms/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PageImages PageImages && rm -rf PageImages/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PageSchemas PageSchemas && rm -rf PageSchemas/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PdfHandler PdfHandler && rm -rf PdfHandler/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PluggableAuth PluggableAuth && rm -rf PluggableAuth/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Popups Popups && rm -rf Popups/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ReplaceText ReplaceText && rm -rf ReplaceText/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-RevisionSlider RevisionSlider && rm -rf RevisionSlider/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Scribunto Scribunto && rm -rf Scribunto/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SecureLinkFixer SecureLinkFixer && rm -rf SecureLinkFixer/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SelectCategory SelectCategory && rm -rf SelectCategory/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SocialProfile SocialProfile && rm -rf SocialProfile/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SubPageList SubPageList && rm -rf SubPageList/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Thanks Thanks && rm -rf Thanks/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-TimedMediaHandler TimedMediaHandler && rm -rf TimedMediaHandler/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-UniversalLanguageSelector UniversalLanguageSelector && rm -rf UniversalLanguageSelector/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-UploadWizard UploadWizard && rm -rf UploadWizard/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-UserMerge UserMerge && rm -rf UserMerge/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Variables Variables && rm -rf Variables/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-VEForAll VEForAll && rm -rf VEForAll/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-VisualEditor VisualEditor && rm -rf VisualEditor/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-VoteNY VoteNY && rm -rf VoteNY/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Widgets Widgets && rm -rf Widgets/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-WhoIsWatching WhoIsWatching && rm -rf WhoIsWatching/.git

# --- SMW family — own GitHub orgs ---
RUN git clone --depth=1 -b 4.2.0 https://github.com/SemanticMediaWiki/SemanticMediaWiki SemanticMediaWiki && rm -rf SemanticMediaWiki/.git; \
    git clone --depth=1 -b 4.2.1 https://github.com/SemanticMediaWiki/SemanticResultFormats SemanticResultFormats && rm -rf SemanticResultFormats/.git; \
    git clone --depth=1 https://github.com/SemanticMediaWiki/SemanticScribunto SemanticScribunto && rm -rf SemanticScribunto/.git; \
    git clone --depth=1 https://github.com/SemanticMediaWiki/SemanticCompoundQueries SemanticCompoundQueries && rm -rf SemanticCompoundQueries/.git; \
    git clone --depth=1 https://github.com/SemanticMediaWiki/SemanticDrilldown SemanticDrilldown && rm -rf SemanticDrilldown/.git; \
    git clone --depth=1 https://github.com/SemanticMediaWiki/SemanticExtraSpecialProperties SemanticExtraSpecialProperties && rm -rf SemanticExtraSpecialProperties/.git

# --- WikiTeq custom / third-party ---
RUN git clone --depth=1 https://github.com/WikiTeq/mediawiki-extensions-EmbedVideo EmbedVideo && rm -rf EmbedVideo/.git; \
    git clone --depth=1 https://github.com/wikimedia/mediawiki-extensions-CommentStreams CommentStreams && rm -rf CommentStreams/.git

# ============================================================
# Stage 2: skins builder
# ============================================================
FROM debian:bookworm-slim AS skin-builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /skins

RUN git config --global url."https://github.com/".insteadOf "git@github.com:"

RUN git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-skins-MinervaNeue MinervaNeue && rm -rf MinervaNeue/.git; \
    git clone --depth=1 -b REL1_43 https://github.com/wikimedia/mediawiki-skins-Timeless Timeless && rm -rf Timeless/.git; \
    git clone --depth=1 https://github.com/ProfessionalWiki/chameleon chameleon && rm -rf chameleon/.git

# ============================================================
# Stage 3: final — official MW image + Observatory layer
# ============================================================
FROM mediawiki:${MW_VERSION}

ARG MW_VERSION
ARG GIT_SHA
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="Observatory MediaWiki" \
      org.opencontainers.image.source="https://github.com/phosphene/observatory-mediawiki" \
      org.opencontainers.image.vendor="Independent Media Institute" \
      org.opencontainers.image.licenses="GPL-2.0" \
      org.opencontainers.image.version="${MW_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

# Additional system packages + PHP extensions
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
    ; \
    pecl install redis; \
    docker-php-ext-enable redis; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/* /tmp/pear

# Copy extensions and skins from builder stages
COPY --from=extension-builder /extensions /var/www/html/extensions/
COPY --from=skin-builder /skins /var/www/html/skins/

# Install SMW family composer dependencies
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY composer.local.json /var/www/html/composer.local.json

RUN set -eux; \
    cd /var/www/html; \
    composer update --no-dev --optimize-autoloader --no-interaction; \
    composer clear-cache; \
    chown -R www-data:www-data extensions skins vendor

# Observatory PHP config
COPY conf/observatory-php.ini /usr/local/etc/php/conf.d/observatory.ini

# DockerSettings.php — WikiTeq pattern for MW_LOAD_EXTENSIONS env var
COPY conf/DockerSettings.php /var/www/html/DockerSettings.php

ENV MW_VERSION=${MW_VERSION} \
    MW_SHOW_EXCEPTION_DETAILS=false \
    MW_DEBUG_MODE=false \
    PHP_UPLOAD_MAX_FILESIZE=50M \
    PHP_POST_MAX_SIZE=50M \
    PHP_MEMORY_LIMIT=256M

# Inherit VOLUME, EXPOSE 80, CMD from official base image
