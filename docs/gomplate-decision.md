# Gomplate Adoption Decision — Gap 7

**Date:** 2026-06-25
**Author:** Flow (platform team)
**Status:** DECIDED — Path A (adopt gomplate)
**Context:** observatory-mediawiki improvement run, feat/improvement-run-2026-06-25

---

## The Problem

The observatory-mediawiki Dockerfile manages 161 extensions across 7 staged
`RUN` blocks (extensions1-30 through extensions-observatory). Adding a new
extension requires edits in two places:

1. **Dockerfile** — a new `RUN git clone` block in the correct stage
2. **conf/DockerSettings.php** — the extension name added to `DOCKER_EXTENSIONS`

These two files have no structural coupling. There is no mechanism that
enforces they stay in sync. When they drift, the failure mode is silent:
the extension exists on disk but is never loaded (missing from
`DOCKER_EXTENSIONS`), or `DOCKER_EXTENSIONS` references an extension that
was never cloned. Neither failure produces a build error.

**Evidence this is not hypothetical:** Step 1 of this improvement run added
14 extensions to `DOCKER_EXTENSIONS` that were missing — cloned in the
Dockerfile but never registered for loading. These extensions were absent
for months. The drift was discovered only by systematic audit.

## The Two Paths

### Path A — Adopt Gomplate

Use gomplate templates to generate the Dockerfile and composer.wikiteq.json
from a single `values.yml` source of truth. Extension metadata lives in one
place; generated artifacts are deterministic outputs.

### Path B — Stay Static

Keep the hand-maintained Dockerfile and DockerSettings.php. Add compensating
controls (linting, CI checks) to catch drift between them.

## Reasoning

### 1. Gomplate infrastructure is already half-started

`conf/composer.wikiteq.json.tmpl` exists in this repository. It is a gomplate
template that generates `composer.wikiteq.json` from a `values` datasource.
The template references `(ds "values").packages`, `(ds "values").extensions`,
and `(ds "values").repositories` — the same structure used by the upstream
wikiteq/taqasta project.

Choosing Path B means leaving this template in the repo with no purpose. It
becomes a dangling artifact that confuses anyone reading the codebase: "why
is there a `.tmpl` file if we don't use gomplate?" Either we commit to the
template system or we delete the template. Leaving it half-finished is the
worst option.

### 2. The scale of the Dockerfile demands structured generation

The Dockerfile is 848 lines. It contains 161 `git clone` operations across
7 parallel build stages. The `DOCKER_EXTENSIONS` array in DockerSettings.php
is 198 lines. These are not small files amenable to careful hand-editing —
they are large, repetitive, structurally regular data expressed as
imperative build instructions.

This is exactly the pattern that template generation solves: repetitive
structure with per-item variation (repo URL, branch, commit hash, extension
name). A `values.yml` entry like:

```yaml
- EditNotify:
    repository: https://github.com/wikimedia/mediawiki-extensions-EditNotify
    branch: REL1_43
    commit: e3a8453f13388e0840c7e54b160a55fd49775234
```

replaces a 3-line RUN block in the Dockerfile AND the corresponding entry
in DOCKER_EXTENSIONS. One source of truth, two generated outputs.

### 3. Schema validation is free once values.yml exists

The upstream wikiteq/taqasta project provides `values.schema.json` — a JSON
Schema that validates the structure of `values.yml`. With `ajv` (or any JSON
Schema validator), CI can reject malformed extension entries before the
Dockerfile is even generated. Path B has no equivalent — there's no schema
for "is this RUN block correctly formatted?"

### 4. The sync problem is structural, not procedural

Path B's compensating controls would need to:
- Parse git clone commands from the Dockerfile to extract extension names
- Parse the PHP DOCKER_EXTENSIONS array to extract registered names
- Diff the two sets and fail CI on mismatch

This is a lint script that reverse-engineers structured data from two
different file formats. It solves the symptom (detecting drift) without
solving the cause (having two independent sources of truth). Every future
maintainer must understand both the Dockerfile conventions AND the lint
script. With gomplate, the lint script is unnecessary — there's nothing
to drift.

### 5. The migration cost is bounded and estimable

The one-time cost is extracting `values.yml` from the current Dockerfile:
reading each of the 161 `git clone` blocks and translating them to YAML
entries. The upstream `values.yml` from wikiteq/taqasta provides the exact
schema to follow. Estimated effort: ~2 hours of mechanical translation,
plus verification that `compile.sh` regenerates a Dockerfile matching the
current one.

The ongoing cost is near-zero: `compile.sh` is a single `docker run`
command. No local toolchain installation required.

### 6. Snapshot testing becomes possible

Template testing (golden master / snapshot diffing) requires templates to
exist. With gomplate:
- Render templates → generated files
- Compare generated files against committed golden masters
- Any unexpected diff fails CI

This is Layer 2 of the template testing approach. Without gomplate, there
are no templates, so there is nothing to snapshot-test. The Dockerfile
itself cannot be meaningfully snapshot-tested because it IS the artifact.

### 7. Upstream alignment reduces maintenance burden

The Observatory fork diverges from wikiteq/taqasta in extensions and
configuration, but the build system structure is the same. Adopting gomplate
aligns the build tooling with upstream, which means:
- Upstream improvements to `compile.sh` or `Dockerfile.tmpl` can be merged
- The values.yml diff between Observatory and upstream makes the fork's
  divergence explicit and reviewable
- Contributors familiar with Taqasta can work on Observatory without
  learning a different build system

## Decision

**Path A — Adopt gomplate.**

The evidence is unambiguous:
- The template infrastructure is already partially present (composer.wikiteq.json.tmpl)
- The sync problem that triggered this analysis (14 missing DOCKER_EXTENSIONS entries) is exactly the class of bug gomplate eliminates structurally
- The migration cost is bounded (~2h mechanical work)
- The ongoing benefit compounds: schema validation, snapshot testing, upstream alignment, single source of truth

## Bootstrap Plan

| Step | Description | Depends on |
|------|-------------|------------|
| A1 | Copy `values.schema.json` from wikiteq/taqasta | — |
| A2 | Copy `Dockerfile.tmpl` structure from wikiteq/taqasta, adapt for Observatory's 7-stage layout | — |
| A3 | Extract current Dockerfile extension stages → `values.yml` extension list (161 extensions) | — |
| A4 | Run `compile.sh`, verify generated Dockerfile matches current Dockerfile (diff must be empty or whitespace-only) | A1, A2, A3 |
| A5 | Add `validate.sh` (ajv schema check on values.yml) to CI | A1, A3 |
| A6 | Add `compile.sh` to CI pipeline before Docker build step | A4 |
| A7 | Golden master snapshot: commit generated `composer.wikiteq.json` as reference artifact | A4 |

**A3 is the critical path item.** Everything else is copying upstream tooling
and wiring it into CI. The 161-extension extraction is the real work.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| values.yml extraction errors (wrong commit hash, wrong branch) | A4 verification: generated Dockerfile must match current byte-for-byte |
| gomplate version drift from upstream | Pin gomplate version in compile.sh; update deliberately |
| Contributors unfamiliar with gomplate | values.yml is plain YAML — no gomplate knowledge needed to add an extension |
| compile.sh requires Docker | Already a Docker-based build; no new dependency |
