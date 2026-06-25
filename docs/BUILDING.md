# BUILDING.md — Observatory MediaWiki Image

How to build, test, and push `ghcr.io/phosphene/observatory-mediawiki`.

---

## Prerequisites

- Docker with Buildx
- GHCR access (`docker login ghcr.io -u <github-user>`)
- Go 1.22+ (for compliance test suite)

---

## Build

```bash
# Development build (default — includes PHPUnit)
docker build -t ghcr.io/phosphene/observatory-mediawiki:local .

# Production build (no PHPUnit, smaller image)
docker build --build-arg INSTALL_PHPUNIT=false \
  -t ghcr.io/phosphene/observatory-mediawiki:local .

# With explicit MW version
docker build \
  --build-arg MW_VERSION=1.43.8 \
  --build-arg GIT_SHA=$(git rev-parse --short HEAD) \
  -t ghcr.io/phosphene/observatory-mediawiki:local .
```

---

## Validate Before Pushing

### Settings gate (fast — catches broken config immediately)

```bash
docker run --rm \
  -e MW_SITE_NAME="Test" \
  -e MW_DB_TYPE=mysql \
  -e MW_DB_SERVER=localhost \
  -e MW_DB_NAME=test \
  -e MW_DB_USER=root \
  -e MW_DB_PASS=test \
  -e MW_ALLOW_UNMOUNTED_VOLUME=true \
  ghcr.io/phosphene/observatory-mediawiki:local \
  php /getMediawikiSettings.php --version MediaWiki
```

### Path B symlink assertions (catches Taqasta routing issues)

```bash
IMAGE=ghcr.io/phosphene/observatory-mediawiki:local

# LocalSettings.php must be a symlink (not a real file)
docker run --rm $IMAGE test -L /var/www/mediawiki/w/LocalSettings.php \
  && echo "✅ LocalSettings.php is a symlink" \
  || echo "❌ LocalSettings.php is NOT a symlink — Path B broken"

# DockerSettings.php must be a real file (never rm -f this)
docker run --rm $IMAGE test -f /var/www/mediawiki/w/DockerSettings.php \
  && echo "✅ DockerSettings.php exists" \
  || echo "❌ DockerSettings.php missing"
```

### Full compliance suite (boots MW + MySQL, runs BDD scenarios)

```bash
# Requires observatory-magazine-v2 checked out alongside this repo
cd ../observatory-magazine-v2/tests/compliance
MW_IMAGE=ghcr.io/phosphene/observatory-mediawiki:local make test
```

---

## Push

```bash
# Push to GHCR (requires login)
docker push ghcr.io/phosphene/observatory-mediawiki:main-dev

# Tag and push release
git tag v2.0.1
git push origin v2.0.1
# CI (build-push.yml) handles the rest
```

---

## CI Pipeline

`.github/workflows/build-push.yml` triggers on:
- Push to `main` → builds and pushes `main-dev` tag
- Tag `v*.*.*` → builds and pushes versioned + `latest` tags, runs Trivy CVE scan

---

## Composer Dependencies

`composer.local.json` — Composer packages baked into the image at build time.
Must match V1's running `composer.local.json` exactly for parity.

Current pinned versions (aligned to V1 as of 2026-06-25):
- `mediawiki/chameleon-skin`: `5.0.1`
- `mediawiki/bootstrap-components`: `5.2.1`
- `mediawiki/semantic-media-wiki`: `6.0.1`
- `mediawiki/simple-batch-upload`: `3.0.0`

To verify after a build:
```bash
docker run --rm ghcr.io/phosphene/observatory-mediawiki:local \
  cat /var/www/mediawiki/w/composer.local.json
```

---

## Layer Structure

```
base          — Debian 12.5 + PHP 8.3 + luasandbox + Composer
core          — MediaWiki 1.43.8 + submodules
skins         — CologneBlue, Modern, pivot, Refreshed
extensions1-30..N  — Extension groups (30 per stage for cache efficiency)
extensions-observatory  — 11 Observatory-specific extensions
composer      — Composer install (merges composer.local.json)
final         — Assembles all stages, copies conf/ + main/ scripts
```

See `docs/dockerfile-audit.md` for full layer analysis.
See `docs/taqasta-architecture.md` for the settings chain and Path B routing.
