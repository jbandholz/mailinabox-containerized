# Chunk 08 — Persistent Configuration Generations

**Goal:** implement the versioned, atomically-promoted configuration store under
`/home/miab/config` that is the sole source of truth for MIAB-managed configuration.

**Depends on:** 03 (soft: 07 for image defaults path)
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Build-Time vs Run-Time Separation (generation rules); §Persistent Layout
Contract; §Configuration and First Boot.

## Scope

### New machinery — `container/bin/miab-config` (+ Python module, e.g. `management/config_gen.py`)

- `render <staging-dir>`: seed candidate generation from immutable image defaults
  (`/usr/share/mailinabox/config-defaults`), then apply `config/inputs` + `config/secrets`
  through the configure-phase pipeline (chunks 04–06 write into the staging dir).
- `validate <dir>`: run every daemon syntax check (`postfix check`, `doveconf`,
  `named-checkconf`, `nsd-checkconf`, `nginx -t`, PHP-FPM `-t`, supervisor/fail2ban config
  tests) plus manifest completeness.
- `promote <staging-dir>`: fsync + single atomic rename of `config/current` symlink
  (same filesystem); write promotion receipt.
- `rollback <generation-id>`: repoint `current` at a retained prior generation after
  validation.
- `gc`: bounded retention of prior generations.
- `manifest.json` per generation: image digest, source commit, config-defaults hash,
  input/secret hashes, module receipts, timestamp.

### Layout pieces

- `config/inputs/mailinabox.conf` (canonical identity/network inputs),
  `config/secrets/` (generated/supplied config secrets, service-specific modes),
  `config/generations/<id>/{etc,apps,supervisor,manifest.json}`, `config/receipts/`.
- Secrets: create-only-when-absent, atomic, least-privilege; referenced by generations,
  never embedded in them.

### Locking

- `STATE_ROOT/locks/config.lock` for live-reconfigure; `instance.lock` ownership rules per
  megaplan (Jobs hold it exclusively).

## Out of scope

- Daemon runtime wiring to `config/current` (chunk 09); host-side transactions that call
  this machinery (chunks 14/15).

## Verification

- [ ] Unit tests: seeding from defaults, input/secret carry-forward, manifest hashing,
      atomic promotion, failed-candidate leaves `current` untouched, retention GC,
      rollback to prior generation.
- [ ] All daemon syntax checks execute against a staged tree without root `/etc` writes.
- [ ] Concurrent render attempts serialize on the config lock.
