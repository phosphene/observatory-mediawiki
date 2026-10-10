# Observatory MediaWiki Image
# Registry: ghcr.io/phosphene/observatory-mediawiki
# Based faithfully on WikiTeq/Taqasta 1.43.8
# Source: https://github.com/WikiTeq/Taqasta

ARG GIT_SHA=unknown

FROM debian:12.5 AS base

LABEL org.opencontainers.image.title="Observatory MediaWiki" \
      org.opencontainers.image.source="https://github.com/phosphene/observatory-mediawiki" \
      org.opencontainers.image.vendor="Independent Media Institute" \
      org.opencontainers.image.licenses="GPL-2.0"

ENV MW_VERSION=REL1_43 \
	MW_CORE_VERSION=1.43.8 \
	WWW_ROOT=/var/www/mediawiki \
	MW_HOME=/var/www/mediawiki/w \
	MW_LOG=/var/log/mediawiki \
	MW_ORIGIN_FILES=/mw_origin_files \
	MW_VOLUME=/mediawiki \
	MW_IMPORT_VOLUME=/import \
	WWW_USER=www-data \
	WWW_GROUP=www-data \
	APACHE_LOG_DIR=/var/log/apache2

RUN set -eux; \
  rm -rf /var/lib/apt/lists/* && \
  apt-get clean && apt-get update && \
  apt-get install -y --no-install-recommends \
    wget lsb-release software-properties-common apt-transport-https ca-certificates && \
  wget -q -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && \
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
	git apache2 gpg imagemagick libvips-tools librsvg2-bin python3-pygments \
	msmtp msmtp-mta patch ffmpeg curl unzip gnupg \
	default-mysql-client rsync poppler-utils gettext-base \
	php8.3 php8.3-mysql php8.3-cli php8.3-gd php8.3-mbstring \
	php8.3-xml php8.3-intl php8.3-opcache php8.3-apcu \
	php8.3-redis php8.3-curl php8.3-tidy php8.3-zip \
	php-pear php8.3-dev liblua5.1-0 liblua5.1-0-dev lua5.1 \
	zip jq build-essential pkg-config && \
  pecl -d php_suffix=8.3 install luasandbox && \
  pecl -d php_suffix=8.3 install excimer && \
  apt-get -y remove php-pear php8.3-dev liblua5.1-0-dev build-essential pkg-config && \
  apt-get -y autoremove && \
  apt-get clean && rm -rf /var/lib/apt/lists/* && \
  update-alternatives --set php /usr/bin/php8.3 && \
  rm -f /etc/apache2/sites-enabled/000-default.conf && \
  rm -f /etc/apache2/sites-available/000-default.conf && \
  rm -rf /var/www/html && \
  a2enmod rewrite remoteip && \
  mkdir -p $MW_HOME $MW_LOG $MW_ORIGIN_FILES $MW_VOLUME


# -------------------------------------------------------------------------
# Document Export Binaries: Pandoc + wkhtmltopdf
# -------------------------------------------------------------------------
# WHAT: Install pandoc and wkhtmltopdf for PDF/EPUB/Markdown export.
# WHY: DownloadBook calls pandoc. PdfBook calls wkhtmltopdf.
#       Without these, "Download as PDF" fails.
# SECURITY BOUNDARY: Read-only converters, no escalation.
# -------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    pandoc \
    wkhtmltopdf \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
    composer self-update 2.10.1

FROM base AS core
RUN git clone --depth 1 -b 1.43.8 https://github.com/wikimedia/mediawiki.git $MW_HOME && \
    cd $MW_HOME && git submodule update --init --recursive && \
    find . \( -name ".git" -o -name ".gitignore" -o -name ".gitmodules" \) -exec rm -rf -- {} + 2>/dev/null || true

FROM base AS skins
RUN mkdir -p $MW_HOME/skins && cd $MW_HOME/skins
RUN cd $MW_HOME/skins && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-skins-CologneBlue CologneBlue \
	&& cd CologneBlue && git fetch --depth 1 origin d7c8d45093c82460fe80c98ce9fa775315fd3e30 && git checkout -q d7c8d45093c82460fe80c98ce9fa775315fd3e30 && cd ..

RUN cd $MW_HOME/skins && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-skins-Modern Modern \
	&& cd Modern && git fetch --depth 1 origin 5597681b7f0423a7e71cda64929c9d60dc999b8c && git checkout -q 5597681b7f0423a7e71cda64929c9d60dc999b8c && cd ..

RUN cd $MW_HOME/skins && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-skins-pivot pivot \
	&& cd pivot && git fetch --depth 1 origin f6b35ca2b8b07ced0e467d8b99421a41b0af3fa3 && git checkout -q f6b35ca2b8b07ced0e467d8b99421a41b0af3fa3 && cd ..

RUN cd $MW_HOME/skins && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-skins-Refreshed Refreshed \
	&& cd Refreshed && git fetch --depth 1 origin 2570c3ee3996cd8ca3f766131b301c33695f68e6 && git checkout -q 2570c3ee3996cd8ca3f766131b301c33695f68e6 && cd ..


# Strip .git directories to reduce image size and avoid leaking git history

RUN find $MW_HOME -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
FROM base AS extensions1-30
RUN mkdir -p $MW_HOME/extensions
RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-AdminLinks AdminLinks \
	&& cd AdminLinks && git fetch --depth 1 origin 60eda7201636218b80d83a637b70e5c753900e41 && git checkout -q 60eda7201636218b80d83a637b70e5c753900e41 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-AdvancedSearch AdvancedSearch \
	&& cd AdvancedSearch && git fetch --depth 1 origin fc7079d49fba845d786d97e4980c8d8fb522bd71 && git checkout -q fc7079d49fba845d786d97e4980c8d8fb522bd71 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-AJAXPoll AJAXPoll \
	&& cd AJAXPoll && git fetch --depth 1 origin fbfd07ef43063e806026d5bd3f95493e2b189378 && git checkout -q fbfd07ef43063e806026d5bd3f95493e2b189378 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-AntiSpoof AntiSpoof \
	&& cd AntiSpoof && git fetch --depth 1 origin 29d219c52f412d84182f979a202405664b9424e6 && git checkout -q 29d219c52f412d84182f979a202405664b9424e6 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-ApprovedRevs ApprovedRevs \
	&& cd ApprovedRevs && git fetch --depth 1 origin fad31826c0722700dfb7cc6c17c80d28b56a5a17 && git checkout -q fad31826c0722700dfb7cc6c17c80d28b56a5a17 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Arrays Arrays \
	&& cd Arrays && git fetch --depth 1 origin 96357a3708ec36ae4b6deebb63991c86268d0e2a && git checkout -q 96357a3708ec36ae4b6deebb63991c86268d0e2a && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/edwardspec/mediawiki-aws-s3.git AWS \
	&& cd AWS && git fetch --depth 1 origin 97c210475f82ed5bc86ea3cbf2726162ccbedbfe && git checkout -q 97c210475f82ed5bc86ea3cbf2726162ccbedbfe && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-BetaFeatures BetaFeatures \
	&& cd BetaFeatures && git fetch --depth 1 origin e2dc57ca67ca7d4188f3b921d5883ee532754724 && git checkout -q e2dc57ca67ca7d4188f3b921d5883ee532754724 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-BreadCrumbs2 BreadCrumbs2 \
	&& cd BreadCrumbs2 && git fetch --depth 1 origin 28e82570da8d7e9e8a422a9a3f55392cf6166e0f && git checkout -q 28e82570da8d7e9e8a422a9a3f55392cf6166e0f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-Cargo Cargo \
	&& cd Cargo && git fetch --depth 1 origin 7d92aee4a12e4eaefeff973eec6cafc838f845f0 && git checkout -q 7d92aee4a12e4eaefeff973eec6cafc838f845f0 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CharInsert CharInsert \
	&& cd CharInsert && git fetch --depth 1 origin ee7b17910ece1ebaf6ad53857926d797b0ff374d && git checkout -q ee7b17910ece1ebaf6ad53857926d797b0ff374d && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CheckUser CheckUser \
	&& cd CheckUser && git fetch --depth 1 origin 53f7c98d3fd003aef8faf95dd08ee05139079fab && git checkout -q 53f7c98d3fd003aef8faf95dd08ee05139079fab && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CirrusSearch CirrusSearch \
	&& cd CirrusSearch && git fetch --depth 1 origin 209efea8657680d855eb5495550af26ee60cea82 && git checkout -q 209efea8657680d855eb5495550af26ee60cea82 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CodeMirror CodeMirror \
	&& cd CodeMirror && git fetch --depth 1 origin 5b6096aaed463519b8f99aa79fadb4498b474905 && git checkout -q 5b6096aaed463519b8f99aa79fadb4498b474905 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Collection Collection

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CommentStreams CommentStreams \
	&& cd CommentStreams && git fetch --depth 1 origin 25340d9d06a7547ba31d9dc4ef0ac100a48f70ed && git checkout -q 25340d9d06a7547ba31d9dc4ef0ac100a48f70ed && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CommonsMetadata CommonsMetadata \
	&& cd CommonsMetadata && git fetch --depth 1 origin 133fd7511eff158456e194315e5f477166ef3206 && git checkout -q 133fd7511eff158456e194315e5f477166ef3206 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ConfirmAccount ConfirmAccount \
	&& cd ConfirmAccount && git fetch --depth 1 origin 852687aea8281b731d6193bab6477def06d9b31d && git checkout -q 852687aea8281b731d6193bab6477def06d9b31d && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ContactPage ContactPage \
	&& cd ContactPage && git fetch --depth 1 origin ad2cdd6a5bb1676dd42215f7585125a78140b121 && git checkout -q ad2cdd6a5bb1676dd42215f7585125a78140b121 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-ContributionScores ContributionScores \
	&& cd ContributionScores && git fetch --depth 1 origin 7934f5da8f642ddd75f17cd1d4041401106e8012 && git checkout -q 7934f5da8f642ddd75f17cd1d4041401106e8012 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-CookieWarning CookieWarning \
	&& cd CookieWarning && git fetch --depth 1 origin f697459d94ac1aa8c9d3e417a9b0e04f92640447 && git checkout -q f697459d94ac1aa8c9d3e417a9b0e04f92640447 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/harugon/mediawiki-extensions-cloudflare.git Cloudflare \
	&& cd Cloudflare && git fetch --depth 1 origin 9df89f3f5e0ace26b07d146167bab72540082fc8 && git checkout -q 9df89f3f5e0ace26b07d146167bab72540082fc8 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-DataTransfer DataTransfer \
	&& cd DataTransfer && git fetch --depth 1 origin 2693332aeb146681e54bb1131a3330235f14f742 && git checkout -q 2693332aeb146681e54bb1131a3330235f14f742 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-DeleteBatch DeleteBatch \
	&& cd DeleteBatch && git fetch --depth 1 origin 55ec7006ba073f16942ffa91620485b8f6cfc241 && git checkout -q 55ec7006ba073f16942ffa91620485b8f6cfc241 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Description2 Description2 \
	&& cd Description2 && git fetch --depth 1 origin 50e2aef88053be12a66b617657c414a665e2d38e && git checkout -q 50e2aef88053be12a66b617657c414a665e2d38e && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Disambiguator Disambiguator \
	&& cd Disambiguator && git fetch --depth 1 origin 56a4738b35d331fe3d3f985b9e3d1c084ab75ed9 && git checkout -q 56a4738b35d331fe3d3f985b9e3d1c084ab75ed9 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-DismissableSiteNotice DismissableSiteNotice \
	&& cd DismissableSiteNotice && git fetch --depth 1 origin caca5bf6baaf5b85487a5b822e42c6ee74aa0e9d && git checkout -q caca5bf6baaf5b85487a5b822e42c6ee74aa0e9d && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-DisplayTitle DisplayTitle \
	&& cd DisplayTitle && git fetch --depth 1 origin 920768a8efb9f316aed1f134fc07aa153d612eb7 && git checkout -q 920768a8efb9f316aed1f134fc07aa153d612eb7 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/Universal-Omega/DynamicPageList4.git DynamicPageList4 \
	&& cd DynamicPageList4 && git fetch --depth 1 origin ed0a71d544c768e02b44556b1caf7008dd50a279 && git checkout -q ed0a71d544c768e02b44556b1caf7008dd50a279 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Editcount Editcount \
	&& cd Editcount && git fetch --depth 1 origin a81f6e9e404da0e82801fc12d91567d1cc143181 && git checkout -q a81f6e9e404da0e82801fc12d91567d1cc143181 && cd ..


# Strip .git directories to reduce image size and avoid leaking git history

RUN find $MW_HOME -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
FROM base AS extensions31-60
RUN mkdir -p $MW_HOME/extensions
RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Elastica Elastica \
	&& cd Elastica && git fetch --depth 1 origin 3f2c3cad516c875091c3536d8d17b0297e8d2d87 && git checkout -q 3f2c3cad516c875091c3536d8d17b0297e8d2d87 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-EmailAuthorization EmailAuthorization \
	&& cd EmailAuthorization && git fetch --depth 1 origin d14a4bb04e2004bb13023dd8a044fc530d558bb8 && git checkout -q d14a4bb04e2004bb13023dd8a044fc530d558bb8 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/StarCitizenWiki/mediawiki-extensions-EmbedVideo.git EmbedVideo \
	&& cd EmbedVideo && git fetch --depth 1 origin 3d8124738d3f1696b42b6eba1d11e9aeae660551 && git checkout -q 3d8124738d3f1696b42b6eba1d11e9aeae660551 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-EventLogging EventLogging \
	&& cd EventLogging && git fetch --depth 1 origin 411fc0d6c8538b0064e0d75b5302534c7f28ac50 && git checkout -q 411fc0d6c8538b0064e0d75b5302534c7f28ac50 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-EventStreamConfig EventStreamConfig \
	&& cd EventStreamConfig && git fetch --depth 1 origin 38de67f43c8a1fb26115226fe17caf428b7ce381 && git checkout -q 38de67f43c8a1fb26115226fe17caf428b7ce381 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-ExternalData ExternalData \
	&& cd ExternalData && git fetch --depth 1 origin 76e95bbe462beab6218a8d6289e17c5da75aea67 && git checkout -q 76e95bbe462beab6218a8d6289e17c5da75aea67 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-FlexDiagrams FlexDiagrams \
	&& cd FlexDiagrams && git fetch --depth 1 origin 7e108c024e892b5dbecdada5dba7d62a93450d23 && git checkout -q 7e108c024e892b5dbecdada5dba7d62a93450d23 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-GlobalNotice GlobalNotice \
	&& cd GlobalNotice && git fetch --depth 1 origin 0cc66c56ebcfdebc0d407d82ae584a5426523d9f && git checkout -q 0cc66c56ebcfdebc0d407d82ae584a5426523d9f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-HeaderFooter HeaderFooter \
	&& cd HeaderFooter && git fetch --depth 1 origin a0d0f4e39f3069925815ca37320f72995aeb80c3 && git checkout -q a0d0f4e39f3069925815ca37320f72995aeb80c3 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-HeaderTabs HeaderTabs \
	&& cd HeaderTabs && git fetch --depth 1 origin 2fa424dd8adfb31a27613715ef523b918675ea42 && git checkout -q 2fa424dd8adfb31a27613715ef523b918675ea42 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-HTMLTags HTMLTags \
	&& cd HTMLTags && git fetch --depth 1 origin 3dc5caa3d586756f39abfef49053136267eb68ef && git checkout -q 3dc5caa3d586756f39abfef49053136267eb68ef && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-LabeledSectionTransclusion LabeledSectionTransclusion \
	&& cd LabeledSectionTransclusion && git fetch --depth 1 origin e7e5c6caf8faed52c8bdec9ee363511666405b20 && git checkout -q e7e5c6caf8faed52c8bdec9ee363511666405b20 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-LDAPAuthentication2 LDAPAuthentication2 \
	&& cd LDAPAuthentication2 && git fetch --depth 1 origin 808036a082e429c54799b0bbce89cba74a74157f && git checkout -q 808036a082e429c54799b0bbce89cba74a74157f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-LDAPAuthorization LDAPAuthorization \
	&& cd LDAPAuthorization && git fetch --depth 1 origin 05a9d007c24429cfee90337077c9d3276edc73ad && git checkout -q 05a9d007c24429cfee90337077c9d3276edc73ad && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-LDAPProvider LDAPProvider \
	&& cd LDAPProvider && git fetch --depth 1 origin c8a4cad128f7aa898c8660648a7da1aef571765d && git checkout -q c8a4cad128f7aa898c8660648a7da1aef571765d && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-Lingo Lingo \
	&& cd Lingo && git fetch --depth 1 origin f87ea047c6665c4c8d7435d23a3b454d127447a0 && git checkout -q f87ea047c6665c4c8d7435d23a3b454d127447a0 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-LinkSuggest LinkSuggest \
	&& cd LinkSuggest && git fetch --depth 1 origin 145247abb87a61b4c19523ce62de37161780bd14 && git checkout -q 145247abb87a61b4c19523ce62de37161780bd14 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-LinkTarget LinkTarget \
	&& cd LinkTarget && git fetch --depth 1 origin 8ef5df73988aa591cc5b73bbcfabd7fab9604fe7 && git checkout -q 8ef5df73988aa591cc5b73bbcfabd7fab9604fe7 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-LockAuthor LockAuthor \
	&& cd LockAuthor && git fetch --depth 1 origin 29fc3cad3e6b9c47c04161a03d758ff355ca5723 && git checkout -q 29fc3cad3e6b9c47c04161a03d758ff355ca5723 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Lockdown Lockdown \
	&& cd Lockdown && git fetch --depth 1 origin 977cfa553b8f40f731b9b86f7dcc18cf181bd854 && git checkout -q 977cfa553b8f40f731b9b86f7dcc18cf181bd854 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-LookupUser LookupUser \
	&& cd LookupUser && git fetch --depth 1 origin d0198361db26d3c6c69ce4cff52c85edae79bbe8 && git checkout -q d0198361db26d3c6c69ce4cff52c85edae79bbe8 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Loops Loops \
	&& cd Loops && git fetch --depth 1 origin dee5dd131110a73ebcb3c09cad9eec0e130f9315 && git checkout -q dee5dd131110a73ebcb3c09cad9eec0e130f9315 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/HydraWiki/LuaCache.git LuaCache \
	&& cd LuaCache && git fetch --depth 1 origin c654dacff3ae177d8ffc3dfd8c4f5e1e1ca7cb2f && git checkout -q c654dacff3ae177d8ffc3dfd8c4f5e1e1ca7cb2f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MagicNoCache MagicNoCache \
	&& cd MagicNoCache && git fetch --depth 1 origin 7315339c97c0eb7d528a8f6b14d055812a85fdb2 && git checkout -q 7315339c97c0eb7d528a8f6b14d055812a85fdb2 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MassMessage MassMessage \
	&& cd MassMessage && git fetch --depth 1 origin 27ad797faa94d0d43294609eb00b836d7ab2a08e && git checkout -q 27ad797faa94d0d43294609eb00b836d7ab2a08e && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MassMessageEmail MassMessageEmail \
	&& cd MassMessageEmail && git fetch --depth 1 origin b2d7a0441ce18e7d63532f4e46ac99a99c27718e && git checkout -q b2d7a0441ce18e7d63532f4e46ac99a99c27718e && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MediaUploader MediaUploader \
	&& cd MediaUploader && git fetch --depth 1 origin 77d2936cb635478c667d216fec3dcf8e0880e0c7 && git checkout -q 77d2936cb635478c667d216fec3dcf8e0880e0c7 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MobileFrontend MobileFrontend \
	&& cd MobileFrontend && git fetch --depth 1 origin a44f2808aa9e051f6a56215ce1320018db723808 && git checkout -q a44f2808aa9e051f6a56215ce1320018db723808 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MsUpload MsUpload \
	&& cd MsUpload && git fetch --depth 1 origin 039b6aece443d6d030e187c112ab2520a65915b2 && git checkout -q 039b6aece443d6d030e187c112ab2520a65915b2 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MyVariables MyVariables \
	&& cd MyVariables && git fetch --depth 1 origin 28e21be0ff6fdc1060f5e83a130faa8406d09b0f && git checkout -q 28e21be0ff6fdc1060f5e83a130faa8406d09b0f && cd ..


# Strip .git directories to reduce image size and avoid leaking git history

RUN find $MW_HOME -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
FROM base AS extensions61-90
RUN mkdir -p $MW_HOME/extensions
RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-NCBITaxonomyLookup NCBITaxonomyLookup \
	&& cd NCBITaxonomyLookup && git fetch --depth 1 origin 58727c6d1c62c3403a50e5e945b1a374701c3a93 && git checkout -q 58727c6d1c62c3403a50e5e945b1a374701c3a93 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-NewUserMessage NewUserMessage \
	&& cd NewUserMessage && git fetch --depth 1 origin 28641bc5780fa8023106b33f8647fc7bd954eb19 && git checkout -q 28641bc5780fa8023106b33f8647fc7bd954eb19 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-NumerAlpha NumerAlpha \
	&& cd NumerAlpha && git fetch --depth 1 origin 27660326ccaf44bbc2942e40a24e4433faaec1a7 && git checkout -q 27660326ccaf44bbc2942e40a24e4433faaec1a7 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-OpenGraphMeta OpenGraphMeta \
	&& cd OpenGraphMeta && git fetch --depth 1 origin cb990fcea3b7827f02bcc328e367a7b2387a32a3 && git checkout -q cb990fcea3b7827f02bcc328e367a7b2387a32a3 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-OpenIDConnect OpenIDConnect \
	&& cd OpenIDConnect && git fetch --depth 1 origin f68146b341213ded4552540eb29ede133c6ff0b5 && git checkout -q f68146b341213ded4552540eb29ede133c6ff0b5 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PageExchange PageExchange \
	&& cd PageExchange && git fetch --depth 1 origin afda8c1ebe6e870841df47f9abeba5ac590594d7 && git checkout -q afda8c1ebe6e870841df47f9abeba5ac590594d7 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-PageForms PageForms \
	&& cd PageForms && git fetch --depth 1 origin ffcfb416a4f18e17df5ff02eed6004c6933c0d8f && git checkout -q ffcfb416a4f18e17df5ff02eed6004c6933c0d8f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PluggableAuth PluggableAuth \
	&& cd PluggableAuth && git fetch --depth 1 origin 4ef6f74c067f9ff81b78fd64b9780a82ccce97f3 && git checkout -q 4ef6f74c067f9ff81b78fd64b9780a82ccce97f3 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Popups Popups \
	&& cd Popups && git fetch --depth 1 origin 3567c401b261076c68cb4872ec32a8eac47ff681 && git checkout -q 3567c401b261076c68cb4872ec32a8eac47ff681 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-PagePort PagePort \
	&& cd PagePort && git fetch --depth 1 origin bc7d6fc5e8e5c1ae7d29e24d309f89b202831c59 && git checkout -q bc7d6fc5e8e5c1ae7d29e24d309f89b202831c59 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-RegularTooltips RegularTooltips \
	&& cd RegularTooltips && git fetch --depth 1 origin e52d009f1a01575de2abebf802c6e97b24587d9a && git checkout -q e52d009f1a01575de2abebf802c6e97b24587d9a && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-RevisionSlider RevisionSlider \
	&& cd RevisionSlider && git fetch --depth 1 origin b10b2150133e77099a37b089003170c0111eb681 && git checkout -q b10b2150133e77099a37b089003170c0111eb681 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/miraheze/RottenLinks.git RottenLinks \
	&& cd RottenLinks && git fetch --depth 1 origin cb1d7376e7f900606b8f998e01280adf645d97c6 && git checkout -q cb1d7376e7f900606b8f998e01280adf645d97c6 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SandboxLink SandboxLink \
	&& cd SandboxLink && git fetch --depth 1 origin 3eae08b2f34e84399e154cc78973c69d4f5c7811 && git checkout -q 3eae08b2f34e84399e154cc78973c69d4f5c7811 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SaveSpinner SaveSpinner \
	&& cd SaveSpinner && git fetch --depth 1 origin 438ea79d4ba11cfe8a8c3599fba5c473b9760b91 && git checkout -q 438ea79d4ba11cfe8a8c3599fba5c473b9760b91 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b deletion-hook-support https://github.com/WikiTeq/SemanticDependencyUpdater.git SemanticDependencyUpdater \
	&& cd SemanticDependencyUpdater && git fetch --depth 1 origin cd0f50a31a21609636961ea2592ca12bbca9b651 && git checkout -q cd0f50a31a21609636961ea2592ca12bbca9b651 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SimpleChanges SimpleChanges

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/jmnote/SimpleMathJax.git SimpleMathJax \
	&& cd SimpleMathJax && git fetch --depth 1 origin fab35e6ac66e1f5abd3c91a57719f8180dd346ef && git checkout -q fab35e6ac66e1f5abd3c91a57719f8180dd346ef && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SkinPerPage SkinPerPage \
	&& cd SkinPerPage && git fetch --depth 1 origin cd94d4684782457f81517d6f2692f3af300d9242 && git checkout -q cd94d4684782457f81517d6f2692f3af300d9242 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SmiteSpam SmiteSpam \
	&& cd SmiteSpam && git fetch --depth 1 origin 529ad28e2953506c7216c90abb7bd17f320fb0b5 && git checkout -q 529ad28e2953506c7216c90abb7bd17f320fb0b5 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-TemplateStyles TemplateStyles \
	&& cd TemplateStyles && git fetch --depth 1 origin 31a4bd259a921e19b4857befa700e7fc0998b6d2 && git checkout -q 31a4bd259a921e19b4857befa700e7fc0998b6d2 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-TemplateWizard TemplateWizard \
	&& cd TemplateWizard && git fetch --depth 1 origin 4c3057f1bf55f686f044dce40b9e70e14ea8d8ec && git checkout -q 4c3057f1bf55f686f044dce40b9e70e14ea8d8ec && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-TinyMCE TinyMCE \
	&& cd TinyMCE && git fetch --depth 1 origin 70467c1b6bcfa7e2f5d415040b6a997741402b4a && git checkout -q 70467c1b6bcfa7e2f5d415040b6a997741402b4a && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-TitleIcon TitleIcon \
	&& cd TitleIcon && git fetch --depth 1 origin 892afc0abab4c76e2db13afab11dd82a8e09e8c8 && git checkout -q 892afc0abab4c76e2db13afab11dd82a8e09e8c8 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-UniversalLanguageSelector UniversalLanguageSelector \
	&& cd UniversalLanguageSelector && git fetch --depth 1 origin d74ff7c4b98d72dda6bfccc597d496ef93953bfb && git checkout -q d74ff7c4b98d72dda6bfccc597d496ef93953bfb && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-UploadWizard UploadWizard \
	&& cd UploadWizard && git fetch --depth 1 origin 858aa6c42ac1224c634c12123ed727734d41edad && git checkout -q 858aa6c42ac1224c634c12123ed727734d41edad && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-UrlGetParameters UrlGetParameters \
	&& cd UrlGetParameters && git fetch --depth 1 origin 013427509ca51a710879c8811b6f4ef04d7b2e12 && git checkout -q 013427509ca51a710879c8811b6f4ef04d7b2e12 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-UserFunctions UserFunctions \
	&& cd UserFunctions && git fetch --depth 1 origin fe610c0a243644789afd7837b7d19a896e216822 && git checkout -q fe610c0a243644789afd7837b7d19a896e216822 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-UserMerge UserMerge \
	&& cd UserMerge && git fetch --depth 1 origin 658fd7ac017cee7cd1ccd68a7431ffad31cf056c && git checkout -q 658fd7ac017cee7cd1ccd68a7431ffad31cf056c && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-UserPageViewTracker UserPageViewTracker \
	&& cd UserPageViewTracker && git fetch --depth 1 origin f375afc09cf381d662c75d405aa373cf6cb658cd && git checkout -q f375afc09cf381d662c75d405aa373cf6cb658cd && cd ..


# Strip .git directories to reduce image size and avoid leaking git history

RUN find $MW_HOME -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
FROM base AS extensions91-120
RUN mkdir -p $MW_HOME/extensions
RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Variables Variables \
	&& cd Variables && git fetch --depth 1 origin 81115fae09d0a219078d2a2511de83474fd2eb8f && git checkout -q 81115fae09d0a219078d2a2511de83474fd2eb8f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-VEForAll VEForAll \
	&& cd VEForAll && git fetch --depth 1 origin 33b5fa746af51e9c6c770950a197b1c17f5ee253 && git checkout -q 33b5fa746af51e9c6c770950a197b1c17f5ee253 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-VoteNY VoteNY \
	&& cd VoteNY && git fetch --depth 1 origin d1d57da0ba7418c9e7f98b659a5fa2832d790c2d && git checkout -q d1d57da0ba7418c9e7f98b659a5fa2832d790c2d && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-WatchAnalytics WatchAnalytics \
	&& cd WatchAnalytics && git fetch --depth 1 origin da4ab0f2455ef9ad2d1593143f638988f9aa1dec && git checkout -q da4ab0f2455ef9ad2d1593143f638988f9aa1dec && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-WhoIsWatching WhoIsWatching \
	&& cd WhoIsWatching && git fetch --depth 1 origin ad0d721ab588c77678a33db304a77bd684724a1a && git checkout -q ad0d721ab588c77678a33db304a77bd684724a1a && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Widgets Widgets \
	&& cd Widgets && git fetch --depth 1 origin 50da5c66923ec5169f5606cc1d76f38f0b759d71 && git checkout -q 50da5c66923ec5169f5606cc1d76f38f0b759d71 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-WikiForum WikiForum

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-WikiSEO WikiSEO \
	&& cd WikiSEO && git fetch --depth 1 origin 5d27adb6ec53e7b1076a485e93f0b0c272d08937 && git checkout -q 5d27adb6ec53e7b1076a485e93f0b0c272d08937 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-WSOAuth WSOAuth \
	&& cd WSOAuth && git fetch --depth 1 origin 9f25fade2bcd3fae44c3236072f5ea2eb068b75c && git checkout -q 9f25fade2bcd3fae44c3236072f5ea2eb068b75c && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-AddMessages AddMessages \
	&& cd AddMessages && git fetch --depth 1 origin a0af32f229d93016f3c3e80bcf2065e09f498064 && git checkout -q a0af32f229d93016f3c3e80bcf2065e09f498064 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Auth_remoteuser Auth_remoteuser \
	&& cd Auth_remoteuser && git fetch --depth 1 origin c985d520c7aea38092ee7208be31f07a7251210d && git checkout -q c985d520c7aea38092ee7208be31f07a7251210d && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Buggy.git Buggy \
	&& cd Buggy && git fetch --depth 1 origin 49dc8fd9ae01195127e0106b94fb01beb5022eb7 && git checkout -q 49dc8fd9ae01195127e0106b94fb01beb5022eb7 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ChangeAuthor ChangeAuthor \
	&& cd ChangeAuthor && git fetch --depth 1 origin 89105aebc39d85c15149391832376d6ea85702c1 && git checkout -q 89105aebc39d85c15149391832376d6ea85702c1 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Citoid Citoid \
	&& cd Citoid && git fetch --depth 1 origin ee1f920556ff245fd4366d8ceed15afb6aa1b0f8 && git checkout -q ee1f920556ff245fd4366d8ceed15afb6aa1b0f8 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-EditAccount EditAccount \
	&& cd EditAccount && git fetch --depth 1 origin e59561c56836a98bc5f5f3068bc81fd67a5d1c41 && git checkout -q e59561c56836a98bc5f5f3068bc81fd67a5d1c41 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-GoogleDocTag GoogleDocTag \
	&& cd GoogleDocTag && git fetch --depth 1 origin 50dfe68e36742b9c6ab24b734ab4401cf1d65178 && git checkout -q 50dfe68e36742b9c6ab24b734ab4401cf1d65178 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/SkizNet/mediawiki-GTag.git GTag \
	&& cd GTag && git fetch --depth 1 origin 570ceccdb7d6612ba37de0885c98a0b7fa95d341 && git checkout -q 570ceccdb7d6612ba37de0885c98a0b7fa95d341 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-HeadScript HeadScript \
	&& cd HeadScript && git fetch --depth 1 origin cc0fb94acd25a20292b0a4d5bbe74bac307b55fe && git checkout -q cc0fb94acd25a20292b0a4d5bbe74bac307b55fe && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-IframePage IframePage \
	&& cd IframePage && git fetch --depth 1 origin 31f27b2388c2032e121a062561924419ce2fe0e9 && git checkout -q 31f27b2388c2032e121a062561924419ce2fe0e9 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/nischayn22/MassPasswordReset.git MassPasswordReset \
	&& cd MassPasswordReset && git fetch --depth 1 origin 04b7e765db994d41f5ca3a910e18f77105218d94 && git checkout -q 04b7e765db994d41f5ca3a910e18f77105218d94 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-MobileDetect MobileDetect \
	&& cd MobileDetect && git fetch --depth 1 origin 1c783c4abc9849e1409f386583404762463f263f && git checkout -q 1c783c4abc9849e1409f386583404762463f263f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PageSchemas PageSchemas \
	&& cd PageSchemas && git fetch --depth 1 origin 25a55c1aa9c6600e9fd9b03f5d50ccad2a9e83fe && git checkout -q 25a55c1aa9c6600e9fd9b03f5d50ccad2a9e83fe && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/WolfgangFahl/PDFEmbed.git PDFEmbed \
	&& cd PDFEmbed && git fetch --depth 1 origin f38758156639b34317ffc6a9e8b5b2624aebae8b && git checkout -q f38758156639b34317ffc6a9e8b5b2624aebae8b && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/bovender/PubmedParser.git PubmedParser \
	&& cd PubmedParser && git fetch --depth 1 origin e8847b72f4e35b250e0aa80e1729e5f062c4ff91 && git checkout -q e8847b72f4e35b250e0aa80e1729e5f062c4ff91 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SelectCategory SelectCategory \
	&& cd SelectCategory && git fetch --depth 1 origin 1f351647af2e235e11139aa8f1b70c19a3556c61 && git checkout -q 1f351647af2e235e11139aa8f1b70c19a3556c61 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-ShowMe ShowMe \
	&& cd ShowMe && git fetch --depth 1 origin 44e3569219e804829e1ff770bb9bd02b7dd7ec2b && git checkout -q 44e3569219e804829e1ff770bb9bd02b7dd7ec2b && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/Universal-Omega/SimpleTooltip.git SimpleTooltip \
	&& cd SimpleTooltip && git fetch --depth 1 origin 3146514ecda810d6ce9feb79ac8e0e0015f242eb && git checkout -q 3146514ecda810d6ce9feb79ac8e0e0015f242eb && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/vedmaka/mediawiki-extension-SimpleTippy.git SimpleTippy \
	&& cd SimpleTippy && git fetch --depth 1 origin 6b4ddff802db21a4c3443d7ce9dcab5ac39d625a && git checkout -q 6b4ddff802db21a4c3443d7ce9dcab5ac39d625a && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SkinPerNamespace SkinPerNamespace \
	&& cd SkinPerNamespace && git fetch --depth 1 origin 33590b2659bf87274bb954f0d01377f5d679d94c && git checkout -q 33590b2659bf87274bb954f0d01377f5d679d94c && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Survey Survey \
	&& cd Survey && git fetch --depth 1 origin b0eb0fa7838827d2ce22be2fbd96ed9a6b182b7e && git checkout -q b0eb0fa7838827d2ce22be2fbd96ed9a6b182b7e && cd ..


# Strip .git directories to reduce image size and avoid leaking git history

RUN find $MW_HOME -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
FROM base AS extensions121-145
RUN mkdir -p $MW_HOME/extensions
RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://gitlab.com/hydrawiki/extensions/Tabber.git Tabber \
	&& cd Tabber && git fetch --depth 1 origin 6c67baf4d18518fa78e07add4c032d62dd384b06 && git checkout -q 6c67baf4d18518fa78e07add4c032d62dd384b06 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/StarCitizenTools/mediawiki-extensions-TabberNeue.git TabberNeue \
	&& cd TabberNeue && git fetch --depth 1 origin 799f86514b6b72bb6be1d615232a5c7cf7f6cfa3 && git checkout -q 799f86514b6b72bb6be1d615232a5c7cf7f6cfa3 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Tabs Tabs \
	&& cd Tabs && git fetch --depth 1 origin 505eac44a119ec3d804b8fd16d4c6b1f6abf7258 && git checkout -q 505eac44a119ec3d804b8fd16d4c6b1f6abf7258 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-TwitterTag TwitterTag \
	&& cd TwitterTag && git fetch --depth 1 origin 0ce9a66d1818eb7b77b91fb051957f99fc17351f && git checkout -q 0ce9a66d1818eb7b77b91fb051957f99fc17351f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-YouTube YouTube \
	&& cd YouTube && git fetch --depth 1 origin 01673ce5f560fabe09b0feb1e65b57cbf58aae39 && git checkout -q 01673ce5f560fabe09b0feb1e65b57cbf58aae39 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-GoogleLogin GoogleLogin

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/Liquipedia/VariablesLua.git VariablesLua \
	&& cd VariablesLua && git fetch --depth 1 origin 64a5776f055b33c38602e8a94f7237a6b8cb4c79 && git checkout -q 64a5776f055b33c38602e8a94f7237a6b8cb4c79 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/WikiTeq/WSSlots.git WSSlots \
	&& cd WSSlots && git fetch --depth 1 origin 9a39063a848130030c35944dea047386315051ae && git checkout -q 9a39063a848130030c35944dea047386315051ae && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/jeffw16/JWTAuth.git JWTAuth \
	&& cd JWTAuth && git fetch --depth 1 origin c7c0730160a84d6b60e3e1b6b108d790972f0f15 && git checkout -q c7c0730160a84d6b60e3e1b6b108d790972f0f15 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-WikiCategoryTagCloud.git WikiCategoryTagCloud \
	&& cd WikiCategoryTagCloud && git fetch --depth 1 origin c895cae34e8e13116a0921e2babf4b72ae53874f && git checkout -q c895cae34e8e13116a0921e2babf4b72ae53874f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-Share.git Share \
	&& cd Share && git fetch --depth 1 origin ffec5e3c4fad940320f3abeb7ea9104025f71612 && git checkout -q ffec5e3c4fad940320f3abeb7ea9104025f71612 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-OAuth OAuth \
	&& cd OAuth && git fetch --depth 1 origin b36cdf6963cbe8e2304ec3bdc63d476db008591b && git checkout -q b36cdf6963cbe8e2304ec3bdc63d476db008591b && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/WikiTeq/mediawiki-extension-SemanticReports.git SemanticReports \
	&& cd SemanticReports && git fetch --depth 1 origin 7548555e0c997a8b4feda38695c6f60977a81349 && git checkout -q 7548555e0c997a8b4feda38695c6f60977a81349 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/mywikis/CrawlerProtection.git CrawlerProtection \
	&& cd CrawlerProtection && git fetch --depth 1 origin 890492d17b4beb68042c88dce8d010c1a14225e7 && git checkout -q 890492d17b4beb68042c88dce8d010c1a14225e7 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-GoogleGeocode GoogleGeocode \
	&& cd GoogleGeocode && git fetch --depth 1 origin 2a8048c0f1fc6cb9d2ed52dbab6d3830bec9fd2a && git checkout -q 2a8048c0f1fc6cb9d2ed52dbab6d3830bec9fd2a && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/AlPha5130/mediawiki-extensions-EditCountNeue.git EditCountNeue \
	&& cd EditCountNeue && git fetch --depth 1 origin f4111b24a06e231c5a84a41755a8005378a50080 && git checkout -q f4111b24a06e231c5a84a41755a8005378a50080 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/WikiTeq/mediawiki-extension-MarkdownPages.git MarkdownPages \
	&& cd MarkdownPages && git fetch --depth 1 origin e7b4c1a320943797fcacfa94f2eef1d428419cea && git checkout -q e7b4c1a320943797fcacfa94f2eef1d428419cea && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-HoneyPot HoneyPot \
	&& cd HoneyPot && git fetch --depth 1 origin 1215c046042e589a7887f7456b65cf2fb168817e && git checkout -q 1215c046042e589a7887f7456b65cf2fb168817e && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-TemplateSandbox TemplateSandbox \
	&& cd TemplateSandbox && git fetch --depth 1 origin 2ba690210fe89175589156062f108f1f357f326f && git checkout -q 2ba690210fe89175589156062f108f1f357f326f && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/gvoss/php-mediawiki-jiki.git Jiki \
	&& cd Jiki && git fetch --depth 1 origin 058cc9a2469fb6c1e25e7d7ed94fad3ef6a10c87 && git checkout -q 058cc9a2469fb6c1e25e7d7ed94fad3ef6a10c87 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/WikiTeq/mediawiki-extension-StatusCheck.git StatusCheck \
	&& cd StatusCheck && git fetch --depth 1 origin 0d6cc4d3a759d81887491530d890a533eb7feed7 && git checkout -q 0d6cc4d3a759d81887491530d890a533eb7feed7 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/WikiTeq/mediawiki-extensions-SummaryToJiraComment.git SummaryToJiraComment \
	&& cd SummaryToJiraComment && git fetch --depth 1 origin 01515972ab6ce325c27b0ee33ff857b39f5b9c9e && git checkout -q 01515972ab6ce325c27b0ee33ff857b39f5b9c9e && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PageAuthors PageAuthors \
	&& cd PageAuthors && git fetch --depth 1 origin 26e15ce086e419d5837bd47ca986a605d52af0bf && git checkout -q 26e15ce086e419d5837bd47ca986a605d52af0bf && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/edwardspec/mediawiki-moderation.git Moderation \
	&& cd Moderation && git fetch --depth 1 origin 26c242887572d337c9db27711d154563639b9981 && git checkout -q 26c242887572d337c9db27711d154563639b9981 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SpamRegex SpamRegex \
	&& cd SpamRegex && git fetch --depth 1 origin 4303b01af935ef3edc6611f5038fb8052d1d61f9 && git checkout -q 4303b01af935ef3edc6611f5038fb8052d1d61f9 && cd ..


# Strip .git directories to reduce image size and avoid leaking git history

RUN find $MW_HOME -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# ─── T-386: Extensions required by wikivisor/LocalSettings.php but missing from image ───
FROM base AS extensions-observatory
RUN mkdir -p $MW_HOME/extensions

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-EditNotify EditNotify \
	&& cd EditNotify && git fetch --depth 1 origin e3a8453f13388e0840c7e54b160a55fd49775234 && git checkout -q e3a8453f13388e0840c7e54b160a55fd49775234 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/debtcompliance/EmailPage.git EmailPage \
	&& cd EmailPage && git fetch --depth 1 origin 7ec1d2fa56a8b3405d4c67ff8a3c5b96e4831223 && git checkout -q 7ec1d2fa56a8b3405d4c67ff8a3c5b96e4831223 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/wikimedia/mediawiki-extensions-JavascriptSlideshow JavascriptSlideshow \
	&& cd JavascriptSlideshow && git fetch --depth 1 origin 74a77c50814a647524bdbd10c7b59dfc5943e2b5 && git checkout -q 74a77c50814a647524bdbd10c7b59dfc5943e2b5 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/DaSchTour/matomo-mediawiki-extension.git Matomo \
	&& cd Matomo && git fetch --depth 1 origin 7cfd8167dd8527b39c3aa9ecb5fc7b3e2f90dc1c && git checkout -q 7cfd8167dd8527b39c3aa9ecb5fc7b3e2f90dc1c && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PageMagic PageMagic \
	&& cd PageMagic && git fetch --depth 1 origin a31c8bf8d04afd4487e7ef4479d55bcd3a9e714b && git checkout -q a31c8bf8d04afd4487e7ef4479d55bcd3a9e714b && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-PageNotice PageNotice \
	&& cd PageNotice && git fetch --depth 1 origin 862d30f4e544632e29adc219402715f6bbaf76ff && git checkout -q 862d30f4e544632e29adc219402715f6bbaf76ff && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b master https://github.com/WikiTeq/PdfBook.git PdfBook \
	&& cd PdfBook && git fetch --depth 1 origin 7492e435f3aa810334506e03f8d1a8010cb39037 && git checkout -q 7492e435f3aa810334506e03f8d1a8010cb39037 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-RSS RSS \
	&& cd RSS && git fetch --depth 1 origin aaf70e4f925c9a48855a9c84bbbffbfcce82e92e && git checkout -q aaf70e4f925c9a48855a9c84bbbffbfcce82e92e && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-SearchThumbs SearchThumbs \
	&& cd SearchThumbs && git fetch --depth 1 origin 3ff7c2b8c42646f43609a6495db5e29fa33db832 && git checkout -q 3ff7c2b8c42646f43609a6495db5e29fa33db832 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b main https://github.com/StarCitizenTools/mediawiki-extensions-ShortDescription.git ShortDescription \
	&& cd ShortDescription && git fetch --depth 1 origin a6ea44f8ec3c56e21878aead27784db20b151b48 && git checkout -q a6ea44f8ec3c56e21878aead27784db20b151b48 && cd ..

RUN cd $MW_HOME/extensions && \
	git clone --depth 1 -b REL1_43 https://github.com/wikimedia/mediawiki-extensions-VipsScaler VipsScaler \
	&& cd VipsScaler && git fetch --depth 1 origin afd1300bb90e46ec4de051c73bfc63d58e8539ff && git checkout -q afd1300bb90e46ec4de051c73bfc63d58e8539ff && cd ..

# Strip .git directories to reduce image size and avoid leaking git history
RUN find $MW_HOME -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

FROM base AS composer
COPY --from=core $MW_HOME $MW_HOME
COPY --from=skins $MW_HOME/skins $MW_HOME/skins
COPY --from=extensions1-30 $MW_HOME/extensions/ $MW_HOME/extensions/
COPY --from=extensions31-60 $MW_HOME/extensions/ $MW_HOME/extensions/
COPY --from=extensions61-90 $MW_HOME/extensions/ $MW_HOME/extensions/
COPY --from=extensions91-120 $MW_HOME/extensions/ $MW_HOME/extensions/
COPY --from=extensions121-145 $MW_HOME/extensions/ $MW_HOME/extensions/
COPY --from=extensions-observatory $MW_HOME/extensions/ $MW_HOME/extensions/

COPY composer.local.json $MW_HOME/composer.local.json
RUN set -eux; \
    cd $MW_HOME && \
    cp composer.json composer.json.bak && \
    cat composer.json.bak | jq '. + {"minimum-stability": "dev"}' > composer.json && \
    rm composer.json.bak && \
    cp composer.json composer.json.bak && \
    cat composer.json.bak | jq '. + {"prefer-stable": true}' > composer.json && \
    rm composer.json.bak && \
    composer clear-cache && \
    composer update --no-dev --optimize-autoloader --no-interaction && \
    composer clear-cache && \
    find $MW_HOME -maxdepth 5 -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find $MW_HOME -maxdepth 5 \( -name "docs" -o -name "doc" \) -type d -exec rm -rf {} + 2>/dev/null || true && \
    chown -R www-data:www-data $MW_HOME

FROM base AS final
ARG GIT_SHA
LABEL org.opencontainers.image.version="1.43.8" \
      org.opencontainers.image.revision="${GIT_SHA}"

COPY --from=composer $MW_HOME $MW_HOME
# mw_origin_files removed (T-386) — keep empty dir for entrypoint compatibility
RUN mkdir -p $MW_ORIGIN_FILES


COPY conf/mediawiki.conf /etc/apache2/sites-available/mediawiki.conf.template
COPY conf/mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf.template
COPY conf/msmtprc /etc/
# PHP configs — cli and apache2 (error reporting + common settings)
COPY conf/php_cli_error_reporting.ini conf/php_common_memory_limit.ini \
     conf/php_common_upload_max_filesize.ini conf/php_common_timeouts.ini \
     conf/php_common_luasandbox.ini conf/php_common_excimer.ini \
     /etc/php/8.3/cli/conf.d/
COPY conf/php_apache2_error_reporting.ini conf/php_common_memory_limit.ini \
     conf/php_common_upload_max_filesize.ini conf/php_common_timeouts.ini \
     conf/php_common_luasandbox.ini conf/php_common_excimer.ini \
     /etc/php/8.3/apache2/conf.d/
COPY conf/DockerSettings.php $MW_HOME/DockerSettings.php
COPY main/*.sh /
COPY main/getMediawikiSettings.php /

# Create a placeholder mediawiki.conf for a2ensite (runtime envsubst overwrites it)
RUN cp /etc/apache2/sites-available/mediawiki.conf.template /etc/apache2/sites-available/mediawiki.conf && \
    a2ensite mediawiki && \
    # Apache hardening (T-386) — suppress version info
    sed -i "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-available/security.conf && \
    sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-available/security.conf && \
    chmod +x /*.sh

ARG INSTALL_PHPUNIT=true
# Install PHPUnit for CI integration testing
RUN if [ "$INSTALL_PHPUNIT" = "true" ]; then \
    curl -sL https://phar.phpunit.de/phpunit-10.phar -o /usr/local/bin/phpunit \
    && chmod +x /usr/local/bin/phpunit \
    && phpunit --version; \
    fi

ENV MW_AUTOUPDATE=true \
    MW_MAINTENANCE_UPDATE=0 \
    MPM_PREFORK_START_SERVERS=5 \
    MPM_PREFORK_MIN_SPARE_SERVERS=5 \
    MPM_PREFORK_MAX_SPARE_SERVERS=10 \
    MPM_PREFORK_MAX_REQUEST_WORKERS=150 \
    MPM_PREFORK_MAX_REQUESTS_PER_CHILD=3000 \
    MW_ENABLE_EMAIL=0 \
    MW_ENABLE_USER_EMAIL=0 \
    MW_ENABLE_UPLOADS=0 \
    MW_USE_IMAGE_MAGIC=0 \
    MW_MAIN_CACHE_TYPE=CACHE_NONE \
    MW_DB_TYPE=mysql \
    MW_DB_SERVER=db \
    MW_DB_NAME=mediawiki \
    MW_DB_USER=root \
    MW_DB_INSTALLDB_USER=root \
    APACHE_REMOTE_IP_HEADER=X-Forwarded-For \
    MW_REDIS_SERVERS=redis:6379 \
    MW_CIRRUS_SEARCH_SERVERS=elasticsearch \
    MW_ENABLE_JOB_RUNNER=true \
    MW_JOB_RUNNER_PAUSE=2 \
    MW_ENABLE_TRANSCODER=true \
    MW_JOB_TRANSCODER_PAUSE=60 \
    PHP_UPLOAD_MAX_FILESIZE=50M \
    PHP_POST_MAX_SIZE=50M \
    PHP_MEMORY_LIMIT=256M \
    MW_SHOW_EXCEPTION_DETAILS=false

VOLUME ["/mediawiki"]
EXPOSE 80
WORKDIR $MW_HOME

HEALTHCHECK --interval=1m --timeout=10s --start-period=120s --retries=3 \
	CMD wget -q --method=HEAD localhost/w/api.php

CMD ["/run-apache.sh"]
