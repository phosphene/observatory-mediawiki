#!/bin/bash
set -e

# Configure PHP
PHP_INI="/etc/php/8.2/apache2/conf.d/99-mediawiki.ini"
cat > "$PHP_INI" << EOF
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-50M}
post_max_size = ${PHP_POST_MAX_SIZE:-50M}
memory_limit = ${PHP_MEMORY_LIMIT:-256M}
EOF

# Run MW auto-update if needed
if [ "${MW_AUTOUPDATE}" = "true" ] && [ -f "${MW_HOME}/LocalSettings.php" ]; then
    php "${MW_HOME}/maintenance/update.php" --quick 2>/dev/null || true
fi

# Start Apache in foreground
exec apache2ctl -D FOREGROUND
