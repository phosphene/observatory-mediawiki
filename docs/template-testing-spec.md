# Template Testing Spec

Observatory MediaWiki image — `phosphene/observatory-mediawiki`

Three-layer verification strategy for the image build pipeline.
Each layer catches a different failure class. Run in order. Fail fast.

---

## Context: What This Repo Produces

This repo produces a Docker image. The "template" in this context is the
build process itself: the `Dockerfile`, `conf/DockerSettings.php`, and
`conf/composer.wikiteq.json.tmpl` are the source artifacts that get compiled
into a running container. Testing them means proving that:

1. The source artifacts are structurally valid (static)
2. The compiled output matches what we expect (snapshot)
3. The running container behaves correctly (runtime)

---

## Layer 1 — Static Validation

**When:** Before any Docker build. Runs in seconds.
**Purpose:** Catch broken source files before spending 20 minutes building.

### 1a. PHP syntax check — `conf/DockerSettings.php`

```bash
php -l conf/DockerSettings.php
```

DockerSettings.php is the central config file copied into the image.
A syntax error here means every container boot fails at the settings
validation gate. Catch it here in <1s.

### 1b. YAML/Dockerfile lint

```bash
# Dockerfile linting (hadolint config already exists at hadolint.yaml)
docker run --rm -i hadolint/hadolint < Dockerfile

# composer.local.json is valid JSON
python3 -m json.tool composer.local.json > /dev/null && echo "✅ valid JSON"
```

### 1c. DOCKER_EXTENSIONS completeness check

`conf/DockerSettings.php` declares `DOCKER_EXTENSIONS` — the list of extensions
that can be loaded via `MW_LOAD_EXTENSIONS`. The 11 Observatory-specific extensions
added in `extensions-observatory` stage are not in this list. This is a known gap
(improvement-spec.md Gap 4).

Static assertion: every extension directory present in the image must appear in
`DOCKER_EXTENSIONS` or have a documented reason why it doesn't.

```bash
# Run after building the image — list extensions in image vs DOCKER_EXTENSIONS
docker run --rm ghcr.io/phosphene/observatory-mediawiki:local \
  ls /var/www/mediawiki/w/extensions/ | sort > /tmp/image-extensions.txt

grep -oP "'\K[A-Za-z0-9_/]+(?=')" conf/DockerSettings.php \
  | sort > /tmp/declared-extensions.txt

comm -23 /tmp/image-extensions.txt /tmp/declared-extensions.txt
# Output = extensions in image but NOT declared in DOCKER_EXTENSIONS
```

---

## Layer 2 — Snapshot Testing (Compiled Output)

**When:** After any change to `conf/DockerSettings.php`, `composer.local.json`,
or the Dockerfile extension stages.
**Purpose:** Prove the compiled output matches a verified golden master.
Catches silent drift between source and baked artifact.

### 2a. DockerSettings.php snapshot

`conf/DockerSettings.php` is COPYd into the image verbatim. The snapshot test
proves what's in the image exactly matches the source file:

```bash
IMAGE=ghcr.io/phosphene/observatory-mediawiki:local

# Extract baked DockerSettings.php from the image
docker run --rm $IMAGE cat /var/www/mediawiki/w/DockerSettings.php \
  > /tmp/baked-dockersettings.php

# Diff against source
diff conf/DockerSettings.php /tmp/baked-dockersettings.php
# Any output = divergence between source and image
```

If this diff is non-empty, the Dockerfile's COPY step is wrong or an earlier
stage is overwriting DockerSettings.php.

### 2b. composer.local.json snapshot

V1 ground truth is documented. The image's baked `composer.local.json` must
match `conf/` source exactly:

```bash
docker run --rm $IMAGE cat /var/www/mediawiki/w/composer.local.json \
  > /tmp/baked-composer.json

diff <(python3 -m json.tool composer.local.json) \
     <(python3 -m json.tool /tmp/baked-composer.json)
```

### 2c. gomplate dry-run (for `conf/composer.wikiteq.json.tmpl`)

`conf/composer.wikiteq.json.tmpl` is a gomplate template. It is NOT currently
used in the build — the Dockerfile uses `composer.local.json` directly. But if
the gomplate pipeline is adopted (see improvement-spec.md Gap 7), this template
becomes the source of truth for Composer deps.

Dry-run produces the template output without building a Docker layer:

```bash
# Render composer.wikiteq.json.tmpl against a values file
docker run --rm \
  -v $(pwd):/app -w /app \
  hairyhenderson/gomplate:v3.11.5-alpine \
  -d config=values.yml \
  -f conf/composer.wikiteq.json.tmpl
```

Golden master snapshot pattern:
```bash
docker run --rm -v $(pwd):/app -w /app \
  hairyhenderson/gomplate:v3.11.5-alpine \
  -d config=values.yml \
  -f conf/composer.wikiteq.json.tmpl > /tmp/rendered-composer.json

diff tests/snapshots/expected-composer.json /tmp/rendered-composer.json
# Non-empty diff = template change had unintended effects
```

**Note:** This layer is PENDING the gomplate adoption decision. It is specced
here so the work is ready to implement when the decision is made. Until then,
Layer 2b (composer.local.json direct snapshot) is the substitute.

---

## Layer 3 — Runtime Compliance Testing

**When:** After building the image. Before pushing to GHCR.
**Purpose:** Prove the running container behaves correctly against V1 baseline.

This layer uses testcontainers-go + godog following the
`phosphene/go_bdd_reference` methodology.

The compliance suite lives in `observatory-magazine-v2/tests/compliance/`.
It is designed to run against any image tag via `MW_IMAGE` env var.

### 3a. Settings Validation Gate

The fastest runtime check. Proves DockerSettings.php loads without fatal errors:

```bash
docker run --rm \
  -e MW_SITE_NAME="Observatory" \
  -e MW_DB_TYPE=mysql \
  -e MW_DB_SERVER=localhost \
  -e MW_DB_NAME=test \
  -e MW_DB_USER=root \
  -e MW_DB_PASS=test \
  -e MW_ALLOW_UNMOUNTED_VOLUME=true \
  ghcr.io/phosphene/observatory-mediawiki:local \
  php /getMediawikiSettings.php --version MediaWiki
```

If this exits non-zero → the container will die on every boot. Do not push.

### 3b. Path B Symlink Assertions

```bash
IMAGE=ghcr.io/phosphene/observatory-mediawiki:local

docker run --rm $IMAGE test -L /var/www/mediawiki/w/LocalSettings.php \
  && echo "✅ LocalSettings.php is symlink" || echo "❌ FAIL"

docker run --rm $IMAGE test -f /var/www/mediawiki/w/DockerSettings.php \
  && echo "✅ DockerSettings.php is real file" || echo "❌ FAIL"
```

These have caught production failures twice. 100ms. Mandatory before every push.

### 3c. BDD Compliance Suite

Full boot test against V1 baseline (`../observatory-magazine-v2/tests/compliance`):

```bash
# Boot image + MySQL 8.4.0 via testcontainers-go
# Runs all Gherkin scenarios against live container + direct DB connection
MW_IMAGE=ghcr.io/phosphene/observatory-mediawiki:local \
  cd ../observatory-magazine-v2/tests/compliance && make test
```

Gherkin contracts proved:
- `features/taqasta_boot.feature` — API health, Main_Page, robots.txt, favicon
- `features/v1_parity.feature` — sitename, dbversion, all 75 extensions, all 38 namespaces
- `features/db_invariants.feature` — schema tables exist, page count

---

## CI Pipeline Implementation

Current `build-push.yml` has no validation gate. Proposed additions:

```yaml
jobs:
  validate:                          # Layer 1 — runs in <1min, no Docker pull
    steps:
      - php -l conf/DockerSettings.php
      - python3 -m json.tool composer.local.json
      - docker run hadolint/hadolint < Dockerfile

  build:                             # existing
    needs: validate

  snapshot-test:                     # Layer 2 — runs after build
    needs: build
    steps:
      - pull image
      - diff conf/DockerSettings.php vs baked
      - diff composer.local.json vs baked

  compliance:                        # Layer 3 — full BDD suite
    needs: build
    steps:
      - checkout observatory-magazine-v2
      - MW_IMAGE=<built-tag> make test

  push:                              # only after all layers pass
    needs: [validate, snapshot-test, compliance]
    steps:
      - docker push
```

**Key principle:** push is gated. Image only reaches GHCR after all three
layers pass. Currently push happens immediately on build with no gate.

---

## File Locations

```
conf/DockerSettings.php          Source → baked into image via COPY
conf/composer.wikiteq.json.tmpl  gomplate template (not yet used in build)
composer.local.json              Composer deps → baked into image
tests/                           (to be created) Layer 1+2 scripts
.github/workflows/build-push.yml CI pipeline (to be extended)
```

---

## Work Required (from improvement-spec.md)

| Item | Layer | Status |
|---|---|---|
| `php -l conf/DockerSettings.php` in CI | 1 | not implemented |
| hadolint already in repo | 1 | config exists, not wired to CI |
| `composer.local.json` JSON lint | 1 | not implemented |
| DOCKER_EXTENSIONS completeness | 1+2 | not implemented |
| DockerSettings.php snapshot diff | 2 | not implemented |
| composer.local.json snapshot diff | 2 | not implemented |
| gomplate dry-run | 2 | pending Gap 7 decision |
| Settings validation gate | 3 | not in CI |
| Path B symlink assertions | 3 | not in CI |
| BDD compliance suite | 3 | lives in observatory-magazine-v2 |
| Push gated on all layers | CI | not implemented |
