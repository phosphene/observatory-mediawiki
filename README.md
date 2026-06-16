# observatory-mediawiki

Observatory MediaWiki Docker image. Replaces `wikivisor/taqasta-1.43.8-observatory:latest`.

**Registry:** `ghcr.io/phosphene/observatory-mediawiki`

## What changed from wikivisor base

| Before | After | Why |
|--------|-------|-----|
| CentOS 7 (EOL Jun 2024) | Debian bookworm-slim | Security patches, active support |
| MW 1.35.6 | MW 1.43.x LTS | Current supported release |
| PHP 7.4 | PHP 8.2 | Performance, security |
| ssmtp (dead since 2011) | msmtp | Maintained SMTP relay |
| clamav (installed, unused) | removed | 200MB saved |
| vim + mc | removed | No debug tools in prod |
| monit | removed | Use infra monitoring |
| Non-deterministic builds | Locked deps | Reproducible |
| No init process | tini as PID 1 | Signal handling, zombie reaping |
| Single RUN layer | Multi-stage build | Layer caching |

## Tags

| Tag | Description |
|-----|-------------|
| `latest` | Current stable release |
| `1.43.x` | Versioned release |
| `wikivisor-base` | Frozen mirror of original wikivisor image |
| `main-dev` | Latest build from main branch |

## Usage

```yaml
# compose.yml
services:
  web:
    image: ghcr.io/phosphene/observatory-mediawiki:latest
    volumes:
      - mw_data:/mediawiki   # required — image enforces this mountpoint
    environment:
      MW_DB_SERVER: db
      MW_DB_NAME: my_wiki
      MW_DB_USER: mediawiki
      MW_DB_PASS: secret

volumes:
  mw_data:
```

## Building locally

```bash
docker build --build-arg MW_VERSION=1.43.2 -t observatory-mediawiki:local .
```

## Releasing

Tag a commit to trigger the build workflow:

```bash
git tag v1.43.2
git push origin v1.43.2
```

GitHub Actions builds, scans for CVEs, and pushes to GHCR automatically.

## Observatory-specific extensions

Custom extensions (CollabPads, Push, CategoryLockdown, etc.) are volume-mounted
at runtime from the observatory-magazine / observatory-editorial repos — not baked
into this image. This keeps the base image generic and reusable.
