---
uri: specs/T-386-dockerfile-audit
ticket: T-386
status: implemented
author: Flow
date: 2026-06-23
revised: 2026-06-23T03:10Z
---

# Dockerfile Audit: `ghcr.io/phosphene/observatory-mediawiki`

Our image. Source: `github.com/phosphene/observatory-mediawiki`. GHCR access via
GitHub App (installation 141959311, phosphene org). Tags: `latest`, `main-dev`,
`wikivisor-base`.

## What's Already Good

The Dockerfile is already well-structured:

- **Multi-stage build** — 8 stages: `base` → `core` → `skins` → 5 parallel
  extension stages → `composer` → `final`. Extensions build in parallel.
- **`--depth 1` clones** — all extensions and skins use shallow clones
- **Pinned commits** — every extension pinned to a specific SHA, not just a branch
- **Composer in build stage** — `composer update` runs in `composer` stage,
  `final` only gets the output
- **`.dockerignore` present** — build context is controlled
- **Clean stage separation** — skins/extensions built independently, merged in composer

## Image Profile

| Metric | Value |
|---|---|
| Total size | **2.94 GB** |
| Base | `debian:12.5` |
| MW version | 1.43.8 |
| PHP | 8.3 (sury PPA) |
| Extensions | 192 (145 git-cloned + skins + SMW via composer) |
| Stages | 8 (parallel extension builds) |

## Findings

### 🔴 Critical

**F-01: `.git` directories not stripped from extension stages.**
The `core` stage strips `.git` (line 61), but the 5 extension stages and the
skins stage do NOT. All `.git` dirs survive `COPY --from=` into `composer` →
`final`. Result: 149 `.git` directories, 97 MB.

Fix — add to each extension/skins stage after all clones:
```dockerfile
RUN find $MW_HOME -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
```
Or add a single strip in the `composer` stage before the `COPY` to `final`.

**F-02: `mw_origin_files` is a full 1 GB duplicate.**
Composer stage line ~693: `cp -r $MW_HOME/. $MW_ORIGIN_FILES/`. The `final`
stage copies both `$MW_HOME` AND `$MW_ORIGIN_FILES`. This is a Taqasta
convention for restoring original files during `update.php` — we control our
own updates via image rebuilds, so we don't need this.

Fix — remove the `cp` in composer and the `COPY --from=composer $MW_ORIGIN_FILES`
in final. Keep the empty dir for entrypoint compatibility if needed.
```dockerfile
# In composer stage: remove the cp line
# In final stage: change to
RUN mkdir -p $MW_ORIGIN_FILES
# instead of COPY --from=composer $MW_ORIGIN_FILES $MW_ORIGIN_FILES
```

**F-03: Build tools left in `base` stage, inherited by `final`.**
`base` installs `build-essential`, `pkg-config`, `php8.3-dev`, `liblua5.1-0-dev`
for PECL compilation. It removes `php-pear php8.3-dev liblua5.1-0-dev` but NOT
`build-essential` or `pkg-config`. Since `final` inherits from `base`, `gcc`,
`g++`, `make` are in the prod image.

Fix — option A (minimal): add to the `base` RUN layer:
```
apt-get -y remove build-essential pkg-config && apt-get -y autoremove
```
Fix — option B (structural): separate build stage for PECL compilation,
copy `.so` files to a clean runtime base. More work but cleaner.

### 🟡 Important

**F-04: Container runs as root.**
The entrypoint scripts (`run-apache.sh`) likely need root for initial setup.
Apache worker processes run as `www-data`. But the container process is root.

Investigation needed: what does `run-apache.sh` require root for?

**F-05: `ServerTokens OS` and `ServerSignature On`.**
Apache default config leaks OS/version info. 2-line fix:
```dockerfile
RUN echo "ServerTokens Prod\nServerSignature Off" >> /etc/apache2/conf-available/security.conf
```

**F-06: PHPUnit baked into prod image.**
Line 730: `curl -sL phpunit-10.phar -o /usr/local/bin/phpunit`. Test framework
in prod. Fix: build arg `ARG INSTALL_PHPUNIT=false`, conditional install. Or
separate `main-dev` vs `latest` build targets.

**F-07: tests/ and docs/ directories not stripped.**
124 `tests/` dirs, 33 `docs/` dirs in extensions — not needed in prod.
Fix — add to `composer` stage before final copy:
```dockerfile
RUN find $MW_HOME -maxdepth 4 -name "tests" -type d -exec rm -rf {} + && \
    find $MW_HOME -maxdepth 4 \( -name "docs" -o -name "doc" \) -type d -exec rm -rf {} +
```

**F-08: No healthcheck `--start-period`.**
During cold starts (update.php, first boot), health checks can fail and
trigger container restarts.
```dockerfile
HEALTHCHECK --interval=1m --timeout=10s --start-period=120s --retries=3 \
    CMD wget -q --method=HEAD localhost/w/api.php
```

**F-09: Git, Composer still in final image.**
Both are in `base`, inherited by `final`. Neither needed at runtime.
Structural fix: split `base` into `build-base` (with git, composer, build tools)
and `runtime-base` (runtime deps only). `final` inherits from `runtime-base`.
This is a bigger refactor but the correct long-term answer.

### 🟢 Low Priority

**F-10: No pinned base image digest.**
`FROM debian:12.5` — no SHA256 pin. Minor reproducibility concern.

**F-11: Parallel extension stages share redundant `mkdir`.**
Each extension stage does `RUN mkdir -p $MW_HOME/extensions` — harmless but
could be in the base. Cosmetic.

**F-12: `composer.json` mutation via jq in composer stage.**
Uses `jq` to patch `minimum-stability` and `prefer-stable` at build time.
Works but fragile. Could use `composer config` commands instead.

## Size Projection

| Component | Current | After fixes |
|---|---|---|
| /mw_origin_files (F-02) | 1009 MB | 0 MB |
| .git directories (F-01) | 97 MB | 0 MB |
| Build tools (F-03) | ~200 MB | 0 MB |
| tests/ + docs/ (F-07) | ~100 MB | 0 MB |
| PHPUnit (F-06) | 5 MB | 0 MB (prod) |
| **Total savings** | | **~1.4 GB** |
| **Projected image** | 2.94 GB | **~1.5 GB** |

## Priority Order

1. **Strip .git from extension stages** (F-01) — 97 MB, 1 line per stage
2. **Remove mw_origin_files duplication** (F-02) — 1 GB, 2 line changes
3. **Remove build tools from base** (F-03) — 200 MB, add to existing RUN
4. **Apache hardening** (F-05) — 2 lines, zero cost
5. **Healthcheck start-period** (F-08) — 1 line
6. **Strip tests/docs** (F-07) — 100 MB, 2 lines in composer stage
7. **PHPUnit conditional** (F-06) — build arg
8. **Non-root investigation** (F-04) — needs entrypoint audit
9. **Split base into build/runtime** (F-09) — bigger refactor, long-term

## Missing Extensions for Prod

The image currently has 192 extensions. Prod's `wikivisor/LocalSettings.php`
loads 68 via `wfLoadExtension()`. Of those 68:

**52 present ✅** — already in our image
**16 missing:**
- 4 custom (bind-mounted in prod): `CategoryLockdown`, `CiteDrawer`, `DownloadBook`, `MixedNamespaceSearchSuggestions`
- 1 commented out: `AdvancedMeta` (skip)
- 11 in Taqasta but not ours: `EditNotify`, `EmailPage`, `JavascriptSlideshow`, `Matomo`, `PageMagic`, `PageNotice`, `PdfBook`, `RSS`, `SearchThumbs`, `ShortDescription`, `VipsScaler`

These 15 extensions need to be added to the Dockerfile for prod readiness.
