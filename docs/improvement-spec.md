---
uri: platform/observatory-mediawiki-spec
owner: edphos
created: 2026-06-25
status: draft
---

# observatory-mediawiki — Improvement Spec

`phosphene/observatory-mediawiki` — the Observatory MediaWiki Docker image.
Gap analysis + proposed work, ordered by value.

---

## Current State

**What exists:**
- `Dockerfile` — multi-stage, Taqasta-derived, static (no gomplate)
- `conf/` — DockerSettings.php, Apache configs, PHP ini files, gomplate template
- `main/` — entrypoint scripts (run-apache.sh, functions.sh, etc.)
- `.github/workflows/build-push.yml` — build + push + Trivy CVE scan (tags only)
- `docs/` — changelog.md, dockerfile-audit.md
- `composer.local.json` — Composer deps (just aligned to V1 in fix/chameleon-v1-parity)

**What is missing:**
- Any CI validation before the image is pushed
- Any runtime testing after the image is built
- Documentation of the settings chain, Path B, known failure modes
- `conf/DockerSettings.php` divergence audit vs what's baked in the image
- Missing Observatory extensions in `DOCKER_EXTENSIONS`
- `conf/apache-mediawiki.conf` uses port 8080 + wrong DocumentRoot — diverged from V1

---

## Gap 1 — CI Validation Pipeline

**Current:** build-push.yml builds and pushes on every push to `main`.
No gate between commit and GHCR. A broken image ships immediately.

**What's missing:**

### 1a. Settings Validation Gate
Before pushing, verify that DockerSettings.php loads without errors against
a minimal MW environment. This is exactly what `run-apache.sh` does on boot:

```bash
php /getMediawikiSettings.php --version MediaWiki
```

If this fails → container exits on boot. Catch it in CI, not in prod.

**Implementation:** New job `validate` in build-push.yml — runs before `build`.
Boots the image with a minimal env, executes the settings gate, exits 1 on failure.

### 1b. Path B Symlink Assertions
After building, verify the Taqasta Path B symlink chain is intact in the image:

```bash
docker run --rm <image> test -L /var/www/mediawiki/w/LocalSettings.php
docker run --rm <image> test -f /var/www/mediawiki/w/DockerSettings.php
```

These have caught production failures twice. 100ms to run. Should be mandatory.

### 1c. Boot Smoke Test (testcontainers-go / Layer 3)
Full boot test using the pattern from `observatory-magazine-v2/tests/compliance`:
- Boot image + MySQL 8.4.0 via docker compose
- Wait for MW API 200
- Assert: sitename, extensions loaded, namespaces, no raw `{{#invoke}}`
- Assert Path B symlink chain via container exec
- Diff against `baseline.json` from V1

This is the same suite — it should live here AND in observatory-magazine-v2.
The image repo is the right place for the canonical compliance proof.

### 1d. Layer 2 — Compile Isolation (future: if gomplate adopted)
```bash
docker build --target compiler -t observatory-compiler:test .
```
Not applicable yet (static Dockerfile). File as future work if gomplate adopted.

---

## Gap 2 — Documentation

### 2a. Taqasta Architecture (PORT from observatory-magazine-v2)
`docs/taqasta-architecture.md` — settings chain, Path B routing, boot sequence,
known failure modes, practices. Already written in woodchipper. Port here.

### 2b. WAR STORIES (PORT from observatory-magazine-v2)
`docs/war-stories.md` — 7 real failure stories anchored to PRs/SHAs.
The image repo is the right canonical home. Already written. Port here.

### 2c. BUILDING.md
How to build, test, and push the image locally. Currently undocumented.

```
# Build
docker build -t ghcr.io/phosphene/observatory-mediawiki:local .

# Test locally (boots MW + MySQL)
cd tests/compliance && make test

# Push (requires GHCR login)
docker push ghcr.io/phosphene/observatory-mediawiki:main-dev
```

---

## Gap 3 — `conf/DockerSettings.php` Divergence

**Problem:** `conf/DockerSettings.php` is the source file, but the Dockerfile
does not COPY it from `conf/` — it copies it from upstream Taqasta via the
`core` stage. The `conf/` version may have diverged.

**Evidence:** `conf/DockerSettings.php` in this repo has `DOCKER_EXTENSIONS`
that includes our 11 Observatory-specific extensions (EditNotify, EmailPage,
Matomo, etc.) — but the Dockerfile's core stage pulls from upstream wikimedia
which won't have these.

**Required fix:** The Dockerfile must COPY `conf/DockerSettings.php` into the
final image, replacing whatever upstream installed. Currently it does not.

**Verification:** `docker run --rm <image> grep -c "EditNotify" /var/www/mediawiki/w/DockerSettings.php`
Should return > 0. If 0 — the conf/ file is not being used.

---

## Gap 4 — Missing Extensions in `DOCKER_EXTENSIONS`

The 11 Observatory extensions added in PR #1 (`extensions-observatory` stage)
are in the image filesystem but NOT in `DOCKER_EXTENSIONS` in DockerSettings.php.
This means they can never be loaded via `MW_LOAD_EXTENSIONS`.

Affected extensions (all added in PR #1 `extensions-observatory` stage):
- EditNotify, EmailPage, JavascriptSlideshow, Matomo, PageMagic, PageNotice,
  PdfBook, RSS, SearchThumbs, ShortDescription, VipsScaler

**Fix:** Add all 11 to `DOCKER_EXTENSIONS` array in `conf/DockerSettings.php`.

Note: In V1 these are loaded directly by `wikivisor/LocalSettings.php` via
hardcoded `wfLoadExtension()` calls — not via `MW_LOAD_EXTENSIONS`. So for
V2 with wikivisor mounted, they'll still load. But they should be in
`DOCKER_EXTENSIONS` so they can also be loaded by any deployment that
doesn't use the wikivisor overlay.

---

## Gap 5 — `conf/apache-mediawiki.conf` Diverged

`conf/apache-mediawiki.conf` listens on 8080 with DocumentRoot `/var/www/html`.
V1 uses port 80 and DocumentRoot `/var/www/mediawiki`.

The Dockerfile doesn't COPY this file anyway (copies from `main/` scripts).
The actual Apache config used at runtime is `conf/mediawiki.conf` (the Taqasta
upstream one) which is correct.

**Fix:** Either align `apache-mediawiki.conf` with the actual runtime config or
delete it (it's not used). It's a stale artefact that creates confusion.

---

## Gap 6 — Composer Alignment (IN PROGRESS)

`fix/chameleon-v1-parity` branch has the fix:
- `chameleon-skin: 5.0.1` (was 5.0.0)
- `bootstrap-components: 5.2.1` (was 5.2.4)
- `simple-batch-upload: 3.0.0` (was 2.0.1)
- Added: `mongodb`, `mwstake`, `modern-timeline`, `proofread-page`
- Removed: `semantic-watchlist`, `psysh`, `remote-wiki`

Needs PR + image rebuild.

---

## Gap 7 — `gomplate` / `values.yml` Adoption Decision

**Current:** Static Dockerfile. No `values.yml`. No `compile.sh`. No `validate.sh`.

**Option A — Keep static Dockerfile:**
- Simpler. Extensions added by hand.
- No gomplate toolchain dependency.
- Con: drift from upstream Taqasta makes rebasing harder.

**Option B — Adopt upstream Taqasta template pipeline:**
- Clone `values.yml` + `.tmpl` files from upstream.
- Run `compile.sh` to regenerate `Dockerfile`.
- Get snapshot testing (diff generated output against golden master).
- Con: gomplate toolchain, additional complexity, one-time migration cost.

**Recommendation:** Decision required from Ed Phil. Document the choice in
`docs/` either way.

---

## Proposed Work Order

| Priority | Item | Effort | Ticket |
|---|---|---|---
| 1 | Gap 1a+1b: CI validate + symlink assertions | S | new |
| 2 | Gap 3: COPY conf/DockerSettings.php in Dockerfile | S | new |
| 3 | Gap 4: Add 11 extensions to DOCKER_EXTENSIONS | S | new |
| 4 | Gap 2a+2b: Port architecture + war stories docs | S | new |
| 5 | Gap 6: Merge composer fix (fix/chameleon-v1-parity) | S | in-progress |
| 6 | Gap 1c: Boot smoke test suite (testcontainers) | M | new |
| 7 | Gap 5: Delete/align apache-mediawiki.conf | XS | new |
| 8 | Gap 7: gomplate decision | decision | T-386 Phase 2 |
| 9 | Gap 1c full: compliance suite ported from magazine-v2 | L | new |

---

## What We Don't Touch

- `main/run-apache.sh`, `main/functions.sh` — Taqasta upstream scripts.
  Don't modify unless there's a specific breaking bug. Override via bind mount.
- `main/mwjobrunner.sh` — already bind-mounted from `_resources/` in V1.
- Upstream extension SHAs — don't bump without testing.
