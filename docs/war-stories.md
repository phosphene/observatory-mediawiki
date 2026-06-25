# WAR STORIES — Taqasta Gotchas in Production

A chronological record of real failures encountered during the Observatory V2
deploy, with the commits that fixed them and the Taqasta provisos they revealed.

Each story follows the same structure: **what happened → why it happened → what
Taqasta's design actually requires → the fix**.

This document is a primary source. The failures are real, the SHAs are real,
the pain was real. Read it before touching the compose file or config chain.

---

## Story 1 — The 503 That Wouldn't Die

**Date:** 2026-06-24
**PRs:** #22, #24, #25
**Commits:** `5580aed2`, `5cc587ce`, `c2f30f14`

### What happened

Deployed V2 to staging. Container started. Immediately returned 503 on every
request. Apache was up. Logs showed nothing. Tried restarting. Still 503.

### Why it happened

Taqasta's `run-maintenance-scripts.sh` runs maintenance tasks in the background
and touches a sentinel file (`$WWW_ROOT/.maintenance`) at the start. Apache
serves 503 while this file exists. The maintenance script removes it when done.

Our V2 deploy stub replaced `run-maintenance-scripts.sh` with a no-op script
that never ran — and never removed the sentinel file. Apache saw `.maintenance`
on every boot and served 503 indefinitely.

The same problem appeared in multiple forms:
- No-op stub didn't remove `.maintenance` (#24)
- Stage tier missing the stub entirely (#25)
- update.php firing before MySQL was ready, crashing the script mid-run,
  leaving `.maintenance` in place (#22)

### Taqasta proviso

> The `.maintenance` sentinel file is created by `run-apache.sh` before
> maintenance runs and deleted by `run-maintenance-scripts.sh` after. Any
> replacement or stub of that script **must** remove the sentinel or Apache
> will serve 503 forever.

### The fix

PR #22: Added 180-second wait for MW to be ready before running `update.php`.
PR #24: No-op stubs in all tiers explicitly remove the sentinel.
PR #25: Stage tier gets its own proper stub with sentinel removal.

---

## Story 2 — Varnish Couldn't Find Web

**Date:** 2026-06-24
**PR:** #27
**Commit:** `bd49f761`

### What happened

Stack started. Web was healthy. Varnish started. Every request through Varnish
returned connection refused. Direct hit to the web container worked fine.

### Why it happened

Our Varnish `depends_on` used the **container name** (`observatorywiki-web`)
instead of the **service name** (`web`). Docker Compose resolves `depends_on`
using service names from the compose file, not container names. Varnish started
before web was ready because the dependency wasn't registered.

### Taqasta proviso

> `depends_on` keys must match service names in the compose file, not container
> names set via `container_name:`. These are different things.

### The fix

PR #27: Changed `depends_on: observatorywiki-web` → `depends_on: web`.

---

## Story 3 — Chameleon Killed the Build

**Date:** 2026-06-25
**PR:** #30
**Commit:** `3c628b78`

### What happened

Added `MW_LOAD_SKINS: Vector,chameleon` to prod compose. Container failed to
start. Settings validation gate (`getMediawikiSettings.php`) exited non-zero.
Log: `Bootstrap extension required for chameleon skin`.

### Why it happened

The Chameleon skin requires the Bootstrap PHP extension as a dependency.
Bootstrap is in the Taqasta image, but it only loads when Chameleon is active.
DockerSettings.php explicitly gates Bootstrap loading on Chameleon being in
`$dockerLoadSkins`. However, our image build did not include Bootstrap's
compiled assets in a state compatible with our MediaWiki version.

### Taqasta proviso

> Chameleon is not a drop-in skin. It requires Bootstrap, which has its own
> asset compilation step baked into the image build. You cannot enable Chameleon
> at runtime without verifying Bootstrap is fully compiled for your MW version.
> When in doubt: use Vector.

### The fix

PR #30: Removed Chameleon from all tiers. Vector only for prod/stage.
Chameleon deferred to T-386 Phase 2 (image-level Bootstrap resolution).

---

## Story 4 — The Symlink That Wasn't There

**Date:** 2026-06-25
**PR:** #31
**Commit:** `8a32b29c`

### What happened

V2 deployed to staging with a pre-populated database. Container booted.
Settings validation passed. But the wiki loaded the setup wizard instead of
the real site. No content, wrong site name, no extensions.

### Why it happened

Taqasta's Path B routing depends on this decision tree in `run-maintenance-scripts.sh`:

```
Does /mediawiki/LocalSettings.php exist?
  NO:
    tables_count > 0?  → symlink to DockerSettings.php
    tables_count == 0? → run install.php → write generated LocalSettings.php
```

Our deploy stub used the wrong symlink target. It created:
```
/mediawiki/LocalSettings.php → /mediawiki/LocalSettings.php   (self-referential)
```
instead of:
```
/mediawiki/LocalSettings.php → /var/www/mediawiki/w/DockerSettings.php
```

The broken symlink caused MW to fall through to its own internal setup detection
and serve the installer.

### Taqasta proviso

> For an existing database, the one and only correct symlink is:
> `/mediawiki/LocalSettings.php → /var/www/mediawiki/w/DockerSettings.php`
>
> The second link (`/var/www/mediawiki/w/LocalSettings.php →
> /mediawiki/LocalSettings.php`) is created automatically by
> `run-maintenance-scripts.sh` if it doesn't exist. You do not need to
> create it manually.

### The fix

PR #31: Corrected the deploy stub symlink target to `DockerSettings.php`.

---

## Story 5 — install.php Destroyed Path B

**Date:** 2026-06-25
**Not a PR — a manual operation gone wrong**

### What happened

During initial V2 setup on Hetzner, `maintenance/install.php` was run manually
against the pre-populated prod database to "initialize" the container. The
container then returned 500 on every request for the next two hours.

Symptoms:
- Wrong site name ("Observatory" instead of "The Observatory")
- No extensions loaded — Scribunto, SMW, CirrusSearch all missing
- Raw `{{#invoke:Spotlight|featured}}` rendering in page source instead of content
- `MW_MAIN_CACHE_TYPE=CACHE_NONE` ignored — Redis connection errors in logs

### Why it happened

`install.php` writes a generated `LocalSettings.php` directly to
`/mediawiki/LocalSettings.php`, replacing the symlink with a real file.

That generated file:
- Does NOT include `DockerSettings.php`
- Does NOT read any `MW_*` env vars
- Sets `$wgMainCacheType = CACHE_ACCEL` (APCu) regardless of env
- Sets `$wgServer = "http://localhost"` regardless of env
- Loads no extensions

All env var evaluation was bypassed. The container was running on raw install
output with no Observatory config at all.

The cascade of symptoms all had the same root cause. We spent two hours chasing
individual symptoms (Scribunto missing, CACHE_NONE ignored, wrong site name)
before identifying that the volume was wrong.

### Taqasta proviso

> **Never run `maintenance/install.php` against a populated database.**
>
> For a pre-populated database, the correct boot path is:
> `run-maintenance-scripts.sh` detects tables > 0 → creates symlink to
> `DockerSettings.php` → update.php runs → Apache starts.
>
> `install.php` is for empty databases only. Running it against a populated
> database does not "reinitialize" the container — it silently destroys the
> config chain and produces a broken real file where a symlink should be.
>
> **Fix:** `docker run --rm -v <volume>:/mediawiki bash -c "rm /mediawiki/LocalSettings.php"`
> then restart the container.

---

## Story 6 — CACHE_NONE Was Always a Lie

**Date:** 2026-06-25
**Not a PR — config chain analysis**

### What happened

Set `MW_MAIN_CACHE_TYPE: CACHE_NONE` in compose.prod.yml. Redis container
removed. Container started, passed validation, then crashed on every page
request with `RedisBagOStuff connection refused`.

### Why it happened

`DockerSettings.php` reads `MW_MAIN_CACHE_TYPE` from env and sets
`$wgMainCacheType` accordingly. This is fine. But then the settings chain
continues:

```
DockerSettings.php  →  _settings/LocalSettings.php
                             →  extensions/wikivisor/LocalSettings.php
```

`wikivisor/LocalSettings.php` contains:
```php
$wgObjectCaches['redis'] = [ 'class' => 'RedisBagOStuff', 'servers' => ['redis'] ];
$wgMainCacheType = 'redis';
$wgSessionCacheType = CACHE_DB;
$wgJobTypeConf['default'] = [ 'class' => 'JobQueueRedis', ... ];
```

These lines are **unconditional**. They load after `DockerSettings.php` and
overwrite whatever `MW_MAIN_CACHE_TYPE` set. The env var had no effect.

### Taqasta proviso

> `DockerSettings.php` sets configuration from env vars. But the settings chain
> continues through `_settings/LocalSettings.php` into
> `extensions/wikivisor/LocalSettings.php`. Any file that loads later in the
> chain overwrites earlier settings unconditionally.
>
> `wikivisor/LocalSettings.php` IS the Observatory application layer. It
> hardcodes cache, job queue, namespaces, permissions, and extension loads.
> Env vars that conflict with wikivisor settings must be resolved in wikivisor,
> not in the compose file.
>
> **Rule:** When an env var isn't taking effect, find where in the settings
> chain it gets overwritten. The env var is not the end of the story.

**Fix required:** Guard the Redis block in `wikivisor/LocalSettings.php`
behind an env check. Not yet done — pending Phase 1 template work.

---

## Story 7 — Scribunto Was Never Missing

**Date:** 2026-06-25
**PR:** #32 (partial)
**Commit:** `969debf`

### What happened

Main page showed `{{#invoke:Spotlight|featured}}` as raw text — Lua templates
not executing. Added `Scribunto` to `MW_LOAD_EXTENSIONS`. Redeployed. Still raw.
Added `SemanticScribunto,LuaCache,VariablesLua`. Container crashed:
`SemanticScribunto requires SemanticMediaWiki`.

### Why it happened

Two compounding misunderstandings:

1. `MW_LOAD_EXTENSIONS` only affects what `DockerSettings.php` loads from its
   `DOCKER_EXTENSIONS` constant array. Scribunto is in that array — but
   `wikivisor/LocalSettings.php` already calls `wfLoadExtension('Scribunto')`
   directly, independently of `MW_LOAD_EXTENSIONS`.

2. The real reason Scribunto wasn't executing was not that it wasn't loaded.
   It was that `wikivisor/LocalSettings.php` wasn't mounted at all — so the
   entire Observatory config was absent, including the Scribunto load.

The `MW_LOAD_EXTENSIONS` fix was solving the wrong problem. The right fix is
mounting `_resources/observatory/` correctly as the wikivisor extension.

### Taqasta proviso

> `MW_LOAD_EXTENSIONS` controls what `DockerSettings.php` loads. It does not
> control what `wikivisor/LocalSettings.php` loads — those are unconditional
> `wfLoadExtension()` calls that run regardless.
>
> When an extension appears missing, check whether the wikivisor extension is
> mounted. If wikivisor isn't there, hundreds of extensions are missing — not
> just the one you're looking for.

---

## The Pattern

Every story above follows the same failure mode:

**We treated the compose env vars as the source of truth. They are not.**

The source of truth is the settings chain:

```
DockerSettings.php  (env vars → scaffolding)
  └── _settings/LocalSettings.php  (repo-mounted → Varnish + wikivisor require)
        └── wikivisor/LocalSettings.php  (the application — overrides everything)
```

Each layer can and does override the layer before it. An env var that
`DockerSettings.php` sets can be silently clobbered by wikivisor three lines
later. A service that's present in compose but missing from `depends_on` means
Varnish starts before web is ready. A stub that replaces a Taqasta script but
doesn't honour the sentinel contract leaves Apache in 503 forever.

The provisos are not edge cases. They are the architecture.

---

## Quick Reference — The Provisos

| Proviso | Story |
|---|---|
| No-op stubs must remove `.maintenance` sentinel or Apache 503s forever | 1 |
| `depends_on` uses service names, not container names | 2 |
| Chameleon requires Bootstrap compiled in the image — use Vector until resolved | 3 |
| Path B symlink target is `DockerSettings.php`, not `LocalSettings.php` | 4 |
| Never run `install.php` against a populated DB — it destroys Path B | 5 |
| wikivisor/LocalSettings.php loads after DockerSettings.php and overwrites it | 6 |
| `MW_LOAD_EXTENSIONS` does not control what wikivisor loads directly | 7 |
| When an extension is missing, check wikivisor is mounted before all else | 7 |
