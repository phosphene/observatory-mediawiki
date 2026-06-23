# Changelog

## 2026-06-23 — T-386: Image hardening + 11 missing Observatory extensions

**PR #1** — `fix/T-386-image-hardening` → merged to `main`
**Build:** `dc13560` — ✅ `main-dev` tag updated on GHCR

### Image Hardening (~1.4 GB savings, 2.94 GB → ~1.5 GB projected)

| Fix | What | Savings |
|-----|------|---------|
| F-01 | Strip `.git` dirs from all extension/skin stages | 97 MB |
| F-02 | Remove `mw_origin_files` 1 GB duplication | ~1 GB |
| F-03 | Remove `build-essential`, `pkg-config` after PECL compile | ~200 MB |
| F-05 | Apache `ServerTokens Prod`, `ServerSignature Off` | security |
| F-06 | PHPUnit conditional via `--build-arg INSTALL_PHPUNIT=false` | 5 MB |
| F-07 | Strip `tests/` and `docs/` directories from final image | ~100 MB |
| F-08 | Healthcheck `--start-period=120s --retries=3` | reliability |

**Context:** `.git` dirs were not stripped from extension stages (only `core`
stripped them). `mw_origin_files` was a Taqasta convention for in-place MW
updates — we control updates via image rebuilds, so it was 1 GB of pure waste.
`build-essential` and `pkg-config` were installed for PECL compilation but not
cleaned up, leaving `gcc`/`g++`/`make` in a web-facing container.

### Missing Extensions (11 added)

New stage `extensions-observatory` — extensions required by
`_resources/observatory/LocalSettings.php` (`wfLoadExtension()`) but absent
from our image. These were present in the Taqasta prod image but had never been
added to ours.

| Extension | Source | Branch | Pinned SHA |
|-----------|--------|--------|------------|
| EditNotify | wikimedia/mediawiki-extensions-EditNotify | REL1_43 | e3a8453f |
| EmailPage | debtcompliance/EmailPage | master | 7ec1d2fa |
| JavascriptSlideshow | wikimedia/mediawiki-extensions-JavascriptSlideshow | master | 74a77c50 |
| Matomo | DaSchTour/matomo-mediawiki-extension | master | 7cfd8167 |
| PageMagic | wikimedia/mediawiki-extensions-PageMagic | REL1_43 | a31c8bf8 |
| PageNotice | wikimedia/mediawiki-extensions-PageNotice | REL1_43 | 862d30f4 |
| PdfBook | WikiTeq/PdfBook | master | 7492e435 |
| RSS | wikimedia/mediawiki-extensions-RSS | REL1_43 | aaf70e4f |
| SearchThumbs | wikimedia/mediawiki-extensions-SearchThumbs | REL1_43 | 3ff7c2b8 |
| ShortDescription | StarCitizenTools/mediawiki-extensions-ShortDescription | main | a6ea44f8 |
| VipsScaler | wikimedia/mediawiki-extensions-VipsScaler | REL1_43 | afd1300b |

**Context:** Discovered when T-385 fix added the `extensions/wikivisor` bind
mount to `compose.test.yml` in `observatory-magazine-v2` CI. The mount makes
`wikivisor/LocalSettings.php` load in CI for the first time, which then calls
`wfLoadExtension('VipsScaler')` — missing from our image. All 11 were in the
Taqasta image but had never been added to ours.

### Usage

```bash
# CI/dev build (default — includes PHPUnit):
docker build -t ghcr.io/phosphene/observatory-mediawiki:main-dev .

# Prod build (no PHPUnit):
docker build --build-arg INSTALL_PHPUNIT=false \
  -t ghcr.io/phosphene/observatory-mediawiki:latest .
```

---

## Prior history

Image was created as a fork of WikiTeq/Taqasta 1.43.8, maintained by
Independent Media Institute / phosphene platform team.
