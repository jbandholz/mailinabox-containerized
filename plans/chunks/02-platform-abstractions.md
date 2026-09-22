# Chunk 02 — Platform & State Abstractions

**Goal:** introduce the runtime/path/service-control foundations every later chunk builds on,
with host defaults unchanged.

**Depends on:** 01
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Persistent Layout Contract; §Future Decomposition Seams; Impl. step 2.

## Scope

### Python side — `management/utils.py` (and a new `management/platform.py` if cleaner)

- Runtime detection: `MIAB_RUNTIME=host|container` (default `host`), plus helpers
  `is_container()`, `storage_root()`, `state_root()`, `config_root()`.
- Root env keys: `STORAGE_ROOT` (default unchanged for host), `STATE_ROOT`,
  `CONFIG_ROOT`; container defaults `/home/miab/{data,state,config}`.
- Atomic file helpers: `tempfile`+`fsync`+`rename` write, atomic symlink swap.
- Cgroup-aware memory/CPU helpers (v2 first, v1 fallback, host `/proc` fallback).
- Service-control interface `service_ctl(action, name)`; host implementation delegates to
  the existing SysV/systemd behavior. The supervisor-backed implementation lands in chunk 09;
  define the interface now.

### Shell side — `setup/functions.sh`

- Same env keys and helpers for setup scripts (`STORAGE_ROOT`, `STATE_ROOT`,
  `CONFIG_ROOT`, `MIAB_RUNTIME`, `MIAB_SETUP_PHASE`).
- `miab_service <action> <name>` wrapper that maps to existing `restart_service`/SysV on
  host; container mapping arrives with supervisor (chunk 09).
- Package-action guard: `require_install_phase` that no-ops/fails package & download calls
  when `MIAB_SETUP_PHASE=configure` or `MIAB_RUNTIME=container`.
- Layout initializer: `miab_layout_init` creating the `/home/miab` contract skeleton
  (no-op on host runtime).

## Out of scope

- No Dockerfile, supervisor, k3s manifests, or firewall changes yet.
- Do not rewire any daemon paths in this chunk — only provide the helpers.

## Verification

- [ ] Unit tests: path resolution under both runtimes, runtime detection, atomic write/swap,
      cgroup parsing with fixture files, layout init idempotency.
- [ ] Contract tests from chunk 01 still pass; host install path unchanged
      (`MIAB_RUNTIME` unset ⇒ identical behavior).
- [ ] ShellCheck clean on `setup/functions.sh`.
