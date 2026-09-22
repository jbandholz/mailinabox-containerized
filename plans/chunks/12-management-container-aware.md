# Chunk 12 — Container-Aware Management API & UI

**Goal:** replace host-mutating management behavior with immutable-lifecycle reporting and
container-aware status checks.

**Depends on:** 02, 09
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Container-Aware Management Behavior; Finding #7; Impl. step 8.

## Scope

### `management/daemon.py`, `management/status_checks.py`, `management/cli.py`, `management/auth.py`

- `/system/update-packages`: never mutates; returns read-only immutable-release info
  (installed MIAB version, container revision, source commit, image digest/build date,
  channel, last check, available release, compatibility/rollback class) loaded from image
  metadata + `STATE_ROOT/update/status.json`; response includes the exact host-side
  `sudo miab-update plan|apply` guidance.
- Reboot GET → false/not-applicable; POST → refuses without invoking `shutdown`.
- Latest-version check uses the configured trusted container release source, not the
  upstream host-installer git comparison (host runtime keeps existing behavior).
- Status checks: remove/mark-external host SSH config checks; replace UFW check with
  read-only `miab_host` baseline presence + `miab_dynamic` fail2ban status; cgroup-v2-aware
  memory; disk checks on `/home/miab`; Munin wording reflects container-scope metrics.
- API key at `STATE_ROOT/mailinabox/api.key`; status cache under
  `STATE_ROOT/mailinabox/status-cache`.
- DNS/web/cert runtime mutations go through the `live-reconfigure` generation flow
  (chunk 08) — never write the active config into the container overlay.

### `management/templates/system-status.html`

- Replace package-update/reboot actions with immutable-update status + host command guidance;
  honest stale/missing updater-status display.

## Verification

- [ ] Unit tests: update endpoint returns metadata + refuses mutation; reboot refused;
      stale updater status handled; cgroup/disk checks correct.
- [ ] Contract test diffs are the *intended* API changes only.
- [ ] Host runtime keeps current behavior (no regression in existing tests).
