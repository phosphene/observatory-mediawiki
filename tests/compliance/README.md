# Observatory MediaWiki — Compliance Tests

BDD compliance suite for the `observatory-mediawiki` baked image.
Architecture follows [phosphene/go_bdd_reference](https://github.com/phosphene/go_bdd_reference).

## Philosophy

**Gherkin feature files are the contract. Go step definitions are the proof.**

- `features/` — human-readable behavioral specifications
- `test/bdd_test.go` — step definitions + hermetic stack lifecycle
- `internal/mediawiki/` — MW API client (HTTP only, no domain logic)
- `internal/db/` — direct MySQL client for data invariant verification
- `test/testdata/baseline.json` — V1 ground truth oracle

V1 works. The baked image must match it. The features describe the observable behavior.
The steps prove it against a live hermetic container + direct DB connection.

## Structure

```
compliance/
├── features/
│   ├── taqasta_boot.feature    Boot contract: API, Main_Page, robots, favicon
│   ├── v1_parity.feature       V1 parity: extensions, namespaces, skin
│   └── db_invariants.feature   Data layer: schema tables, page count
├── test/
│   ├── bdd_test.go             TestMain + TestFeatures + step definitions
│   └── testdata/
│       ├── docker-compose.yml  Ephemeral test stack (MW + MySQL 8.4.0)
│       └── baseline.json       V1 ground truth oracle
├── internal/
│   ├── mediawiki/client.go     MW API client
│   └── db/mysql.go             MySQL client for data invariants
├── Makefile
├── go.mod
└── README.md
```

## TDD Loop

```
1. Write a Gherkin scenario in features/
2. make test             →  step not implemented (pending/yellow)
3. Implement the step in test/bdd_test.go
4. make test             →  fails (red)
5. Fix Dockerfile / compose / settings
6. make test             →  passes (green)
7. Commit
```

## Usage

```bash
cd tests/compliance

# Full suite — boots ephemeral stack (~5min cold, ~2min warm)
make test

# Skip boot — use already-running container
MW_BASE_URL=http://10.x.x.x:80 go test -v ./test/... -timeout 5m

# Specific image
MW_IMAGE=ghcr.io/phosphene/observatory-mediawiki:v2.0.0-observatory make test
```

## Known Divergences

Intentional V1→V2 differences are registered in `KnownDivergences` in
`test/bdd_test.go`. They log as `KNOWN DIVERGENCE` — not failures.
Any unlisted divergence fails the test.

Current:
- `default_skin:chameleon→vector` — T-386 Phase 2 Bootstrap dep pending
- `redis:removed` — CACHE_NONE confirmed from V1 env; removed deliberately
