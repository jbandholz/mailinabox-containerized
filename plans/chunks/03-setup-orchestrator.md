# Chunk 03 — Shared Setup Orchestrator & Phase Infrastructure

**Goal:** extract one ordered reconciliation pipeline usable by both the conventional host
installer and container Jobs, with explicit phase/mode parameters.

**Depends on:** 02
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Build-Time vs Run-Time Separation; Impl. step 3; Finding #9.

## Scope

### Files to create

- `setup/reconcile.sh` — the single ordered orchestrator. It sources and runs each setup
  module in the same order as today's `setup/start.sh`, honoring:
  - `MIAB_SETUP_PHASE=install|configure|all`
  - `MIAB_RUNTIME=host|container`
  - `MIAB_MODE=fresh-install|offline-upgrade|startup|live-reconfigure|host-install`
- `setup/modules.manifest` (or in-script table) — per-module classification: which actions
  are install-phase, configure-phase, host-only, or container-allowed. This manifest is what
  the ordering/parity test asserts against.
- `container/bin/miab-reconcile` (thin entry shim; may live in `setup/` until image exists).

### Files to modify

- `setup/start.sh` — delegate module execution to `reconcile.sh` with
  `MIAB_SETUP_PHASE=all MIAB_RUNTIME=host`, preserving prompts/`firstuser.sh` flow.
- `setup/preflight.sh`, `setup/questions.sh` — accept validated noninteractive inputs
  (env/flag file) in addition to TTY prompts; identical defaults.
- `setup/functions.sh` — wire the phase guards from chunk 02 into shared helpers.

## Behavior requirements

- `fresh-install`/`offline-upgrade`/`live-reconfigure`: forbid apt, git, downloads, hostname,
  swap, sysctl, systemd-resolved, systemctl, shutdown, and daemon start/restart. Persistent
  mutations must be idempotent.
- `startup` mode is defined here but only performs read-only validation + scratch setup —
  it must *not* invoke configure modules (wired fully in chunk 09).
- Host path (`start.sh`) output/order must be byte-for-byte equivalent in module sequencing;
  the chunk-01 `test_setup_order` fixture is the gate.

## Verification

- [ ] `test_setup_order` passes; new upstream module missing from the manifest fails tests.
- [ ] `MIAB_SETUP_PHASE=configure bash setup/reconcile.sh` on a host fixture performs no
      apt/network/daemon actions (assert via stubbed `apt-get`/`service` on PATH).
- [ ] `bash -n` + ShellCheck on all touched scripts; conventional Vagrant/host install
      smoke path unchanged.
