---
uri: platform/observatory-v2/taqasta-architecture
owner: edphos
created: 2026-06-25
status: authoritative
---

# Taqasta Architecture — Observatory V2

Complete operational knowledge of the Taqasta stack as deployed at observatory.wiki.
Written from primary source inspection of running V1 container + upstream wikiteq/taqasta repo.

---

## 1. What Taqasta Is

Taqasta is an enterprise-focused, production-ready MediaWiki distribution maintained
by WikiTeq. It is a downstream fork of the Canasta project. It re-engineers MediaWiki
into an Infrastructure-as-Code, non-interactive, environment-driven container platform.

**Key properties:**
- 130+ extensions bundled in image layers
- Extensions enabled via `MW_LOAD_EXTENSIONS` env var (not hardcoded PHP)
- Headless, non-interactive installer — reads env vars on first boot
- Declarative build engine via gomplate templates + `values.yml` manifest
- State-separated symlink routing (Path B Logic) — see §4

**Upstream:** https://github.com/wikiteq/taqasta
**Our fork:** `ghcr.io/phosphene/observatory-mediawiki`
**Base image:** `wikivisor/taqasta-1.43.8-observatory:latest` (V1)

---

## 2. Boot Sequence

```
docker compose up
  └── run-apache.sh
        ├── Mount check ($MW_VOLUME must be mounted, or MW_ALLOW_UNMOUNTED_VOLUME=true)
        ├── rsync $MW_ORIGIN_FILES → $MW_VOLUME (soft sync, ignore-existing)
        ├── php /getMediawikiSettings.php --version  ← SETTINGS VALIDATION GATE
        │     If this fails → exit 1 (container dies here)
        ├── /update-docker-gateway.sh
        ├── Log dir setup
        └── run-maintenance-scripts.sh (background)
              ├── Symlink routing (Path B) — see §4
              ├── waitdatabase() — blocks on MySQL port + admin ping
              ├── waitelastic() — blocks on ES health=green
              ├── run_autoupdate() — update.php, CirrusSearch index, SMW tasks
              ├── run_import() — PagePort import if MW_AUTO_IMPORT
              ├── jobrunner() — mwjobrunner.sh if MW_ENABLE_JOB_RUNNER
              └── sitemapgen() — if MW_ENABLE_SITEMAP_GENERATOR
        └── exec apachectl -DFOREGROUND
```

---

## 3. Settings Chain (V1 — authoritative)

```
DockerSettings.php                          ← baked into image at /var/www/mediawiki/w/
  ├── reads MW_LOAD_EXTENSIONS env var
  ├── reads MW_LOAD_SKINS env var
  ├── reads MW_MAIN_CACHE_TYPE env var       ← sets cache type from env
  └── includes: glob($MW_CONFIG_DIR/settings/*.php)
        └── _settings/LocalSettings.php     ← bind-mounted from repo
              ├── $wgMemoryLimit = '256M'
              ├── $wgUseCdn = true + Varnish config
              ├── wfLoadExtension('MultiPurge') + Varnish purge config
              ├── require_once "extensions/wikivisor/LocalSettings.php"  ← THE APP LAYER
              │     ├── Chameleon skin layout + theme config
              │     ├── $wgMainCacheType = 'redis'    ← OVERRIDES DockerSettings cache!
              │     ├── Redis job queue config
              │     ├── Custom namespaces (NS_DRAFTS, NS_INTERACTIVE, NS_BRIEF,
              │     │   NS_NEWS/Commentary, NS_CLASSICS, NS_RECIPE, NS_INFO,
              │     │   NS_EVENT, NS_QUERIES, NS_SEO, NS_CAMPAIGN, NS_BOOK)
              │     ├── wfLoadExtension('SemanticMediaWiki') + enableSemantics()
              │     ├── All extension loads (100+ explicit wfLoadExtension calls)
              │     ├── ExternalData fundraiser_db config (reads FUNDRAISER_DB_PASS env)
              │     ├── Permissions/Lockdown (Namespace + Special page)
              │     ├── FundraiseUp + Google Analytics JS injection
              │     └── ContactPage, EmailPage, IframePage, VipsScaler configs
              └── require_once "extensions/wikivisor/Permissions.php"
              └── wfLoadExtension('UserMerge')
              └── $wgScribuntoDefaultEngine = 'luasandbox'   ← engine override
```

### Critical insight: wikivisor/LocalSettings.php overrides DockerSettings.php

`$wgMainCacheType = 'redis'` is hardcoded in wikivisor/LocalSettings.php.
`MW_MAIN_CACHE_TYPE=CACHE_NONE` in the env var is SET by DockerSettings.php,
but wikivisor/LocalSettings.php loads AFTER and overwrites it.

**For V2 with no Redis:** must patch wikivisor/LocalSettings.php to remove the
`$wgMainCacheType = 'redis'` and Redis job queue config lines, or add an
override after the require_once.

### Scribunto loading chain

Scribunto is NOT loaded via `MW_LOAD_EXTENSIONS`. It is loaded by:
1. `wikivisor/LocalSettings.php` → `wfLoadExtension('Scribunto')` (line ~717)
2. `_settings/LocalSettings.php` → `$wgScribuntoDefaultEngine = 'luasandbox'`

`MW_LOAD_EXTENSIONS=...,Scribunto,...` is therefore redundant but harmless
(DockerSettings.php guards with `file_exists()` before loading).

---

## 4. Path B Symlink Routing

Taqasta's state separation model:

```
Immutable (in image):
  /var/www/mediawiki/w/          ← MW core + all extensions
  /var/www/mediawiki/w/DockerSettings.php   ← env-driven config

Stateful (persistent volume):
  /mediawiki/                    ← $MW_VOLUME

Symlink chain (created by run-maintenance-scripts.sh on first boot):
  /mediawiki/LocalSettings.php  →  /var/www/mediawiki/w/DockerSettings.php
  /var/www/mediawiki/w/LocalSettings.php  →  /mediawiki/LocalSettings.php
```

**Decision tree in run-maintenance-scripts.sh:**

```
Does /mediawiki/LocalSettings.php exist?
  NO:
    Is DB empty (tables_count == 0)?
      YES → run install.php → write LocalSettings.php to /mediawiki/ → append @include('DockerSettings.php')
      NO  → ln -s /var/www/mediawiki/w/DockerSettings.php /mediawiki/LocalSettings.php
  YES:
    Does /var/www/mediawiki/w/LocalSettings.php exist?
      NO → ln -s /mediawiki/LocalSettings.php /var/www/mediawiki/w/LocalSettings.php
```

**Our prod DB is pre-populated (tables_count > 0), so the correct Path B is:**
`/mediawiki/LocalSettings.php → /var/www/mediawiki/w/DockerSettings.php`

**What goes wrong:** If install.php is run manually, it writes a full generated
`LocalSettings.php` to `/mediawiki/`, replacing the symlink with a real file.
That file does NOT include DockerSettings.php, so all env var evaluation
(MW_LOAD_EXTENSIONS, MW_MAIN_CACHE_TYPE, etc.) is bypassed entirely.
Result: 500 errors, raw `{{#invoke:}}` templates, wrong site name.

**Fix:** Delete `/mediawiki/LocalSettings.php` and let the container recreate
the correct symlink on next boot (it detects tables > 0 → symlink path).

---

## 5. The wikivisor Extension / Application Layer

`_resources/observatory/` in the repo is mounted as the `wikivisor` extension:
```
./_resources/observatory  →  /var/www/mediawiki/w/extensions/wikivisor
```

This is not a standard MW extension. It IS the entire Observatory application layer:
- `LocalSettings.php` — 800+ line master config (namespaces, extensions, permissions)
- `Permissions.php` — user group and namespace permission matrix
- `SemanticSettings.php` — SMW property definitions
- `skins/` — Chameleon layout + theme files
- `images/` — Observatory logo
- `fonts/` — Georgia.ttf for mpdf/PDF export

All Observatory-specific extension loads, namespace definitions, and permissions
live in this one file. It must be present for the wiki to function.

---

## 6. Extension Mounts (V1 Bind-Mount Overrides)

V1 mounts individual files to override baked-in extension files:

| Mount source | Target | Purpose |
|---|---|---|
| `_resources/extensions/MixedNamespaceSearchSuggestions/` | `extensions/MixedNamespaceSearchSuggestions/` | Custom extension not in image |
| `_resources/extensions/CategoryLockdown/` | `extensions/CategoryLockdown/` | Custom extension not in image |
| `_resources/extensions/CiteDrawer/` | `extensions/CiteDrawer/` | Custom extension not in image |
| `_resources/extensions/DownloadBook/` | `extensions/DownloadBook/` | Custom extension not in image |
| `_resources/extensions/SpecialContact.php` | `extensions/ContactPage/includes/SpecialContact.php` | Observatory-specific ContactPage override |
| `_resources/extensions/BookRenderingTask.php` | `extensions/DownloadBook/includes/BookRenderingTask.php` | Observatory-specific DownloadBook override |
| `_resources/extensions/EditNotifyHooks.php` | `extensions/EditNotify/includes/EditNotifyHooks.php` | Observatory-specific EditNotify override |
| `_resources/downloadbook.css` | `extensions/DownloadBook/downloadbook.css` | Custom CSS |
| `_resources/downloadbook-epub.css` | `extensions/DownloadBook/downloadbook-epub.css` | Custom CSS |
| `_resources/observatory/images/remove.png` | `extensions/Collection/images/remove.png` | Observatory branding |
| `_resources/observatory/images/show.png` | `extensions/Collection/images/show.png` | Observatory branding |
| `_resources/mwjobrunner.sh` | `/mwjobrunner.sh` | Job runner script |
| `_resources/observatory/fonts/Georgia.ttf` | `vendor/mpdf/mpdf/ttfonts/Georgia.ttf` | PDF font |

**Note:** MixedNamespaceSearchSuggestions, CategoryLockdown, CiteDrawer are custom
extensions that do not exist in the Taqasta image — they must be bind-mounted in.

---

## 7. V1 Services (Authoritative)

| Service | Image | Profile | Notes |
|---|---|---|---|
| db | mysql:8.4.0 | always | `--log-bin --binlog_expire_logs_seconds=259200`, cap_add SYS_NICE, __initdb mount |
| web | wikivisor/taqasta-1.43.8-observatory:latest | always | |
| redis | redis:7.4.0-alpine3.20 | always | maxmemory 500mb, allkeys-lru |
| varnish | pastakhov/varnish:7.0 | always | Traefik-routed |
| elasticsearch | docker.elastic.co/elasticsearch:7.10.2 | always | single-node, 512m heap |
| restic | ghcr.io/wikiteq/restic-backup-docker:stream | production | daily mysqldump + images backup |
| matomo | matomo:5.1.1 | production | matomo.observatory.wiki, Traefik-routed |
| cron | ghcr.io/wikiteq/cron | always | docker.sock mount, fundraiser cron, TZ=America/New_York |

---

## 8. V1 → V2 Divergence (Summary)

Full detail: `drafts/platform/T-386-image-independence/v1-v2-divergence-matrix.md`

| Item | Status | Fix |
|---|---|---|
| MySQL 8.0 vs 8.4 | FATAL | Change to mysql:8.4.0 in compose template |
| Namespace 100 collision | FATAL | Audit prod DB; fix ObservatorySetup |
| wikivisor/LocalSettings.php redis override | FATAL | Patch to remove redis cache/queue config |
| Scribunto loading | RESOLVED | Loaded by wikivisor/LocalSettings.php directly |
| Restic backup missing | CRITICAL | Add service to compose template |
| Matomo missing | CRITICAL | Add service to compose template |
| Cron missing | CRITICAL | Add service to compose template |
| 12 webroot bind mounts missing | CRITICAL | Add to compose template |
| Extension bind mounts missing | CRITICAL | Add to compose template |
| Fundraiser DB (__initdb) missing | CRITICAL | Add mount + env var |
| MW_SECRET_KEY placeholder | CRITICAL | Set real value |
| DB credential placeholders | FIXED | Patched on server; needs template fix |

---

## 9. Known Failure Modes We Hit

### INC-001: install.php volume clobber (2026-06-25)
Manual install.php run wrote generated LocalSettings.php to /mediawiki/ volume.
Severed Path B symlink. All env var evaluation bypassed. Site returned 500 on
every request with wrong site name, no extensions loaded.
**Fix:** Delete /mediawiki/LocalSettings.php, restart container (tables_count > 0
triggers correct symlink creation).

### INC-002: MW_MAIN_CACHE_TYPE=CACHE_NONE ignored (2026-06-25)
Set CACHE_NONE in compose env. Site still crashed on Redis connection.
**Root cause:** wikivisor/LocalSettings.php loads after DockerSettings.php and
hardcodes `$wgMainCacheType = 'redis'`. Env var is overwritten.
**Fix required:** Patch wikivisor/LocalSettings.php to conditionally set cache type.

### INC-003: Scribunto not loading (2026-06-25)
Added Scribunto to MW_LOAD_EXTENSIONS. Still not loaded.
**Root cause:** Scribunto is loaded by wikivisor/LocalSettings.php directly, not
via MW_LOAD_EXTENSIONS. MW_LOAD_EXTENSIONS is only read by DockerSettings.php.
**Fix:** Mount wikivisor correctly — Scribunto load comes for free.

---

## 10. Practices

### Before any compose change
1. Read `run-maintenance-scripts.sh` decision tree — understand what the container
   will do on boot with the new config.
2. Check if the setting is controlled by DockerSettings.php (env var) or by
   wikivisor/LocalSettings.php (hardcoded). wikivisor always wins.
3. Never run `maintenance/install.php` against a pre-populated DB — it writes
   a new LocalSettings.php to the volume and breaks Path B.

### Before any image change
1. Changes must go through `values.yml` + `compile.sh` — never edit Dockerfile
   directly (it is generated from Dockerfile.tmpl).
2. After compile.sh, run `validate.sh` before building.
3. Extension additions require a new image build. You cannot add an extension
   at runtime by dropping files — the composer dependencies are baked in.
   Exception: extensions with no composer deps can be bind-mounted.

### The wikivisor extension is the application
Every Observatory-specific setting lives in `_resources/observatory/LocalSettings.php`.
When debugging any config issue, this file is the first place to look.
DockerSettings.php controls the runtime scaffolding. wikivisor controls the app.

