#!/bin/bash
set -e

MW_HOME="${MW_HOME:-/var/www/html/w}"
MW_VOLUME="${MW_VOLUME:-/mediawiki}"

# Verify /mediawiki is a real mountpoint
if ! mountpoint -q -- "${MW_VOLUME}"; then
    echo "ERROR: ${MW_VOLUME} must be mounted to persistent storage."
    echo "Add a named volume in your compose file: volumes: - mw_data:/mediawiki"
    exit 1
fi

# Sync origin files to volume on first run
if [ ! -f "${MW_VOLUME}/.initialized" ]; then
    echo "First run — initializing ${MW_VOLUME}..."
    rsync -a --ignore-existing "${MW_HOME}/images/" "${MW_VOLUME}/images/" 2>/dev/null || true
    touch "${MW_VOLUME}/.initialized"
fi

exec "$@"
