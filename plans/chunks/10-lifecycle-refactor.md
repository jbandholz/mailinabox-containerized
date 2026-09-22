# Chunk 10 — Service-Lifecycle Refactor (Management Callers)

**Goal:** route every dynamic service action through the `miab-service` abstraction so the
same code paths work under systemd (host) and supervisor (container).

**Depends on:** 02
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Process Supervision; Findings #2, #6; Impl. step 6.

## Scope

### Files to modify

- `management/dns_update.py` — nsd/bind reloads via `service_ctl`; zone writes target
  `STATE_ROOT/nsd/zones`; trigger `live-reconfigure` generation flow (chunk 08 API) instead
  of writing `/etc` directly.
- `management/web_update.py` — nginx config via generation + graceful reload.
- `management/ssl_certificates.py` — cert provisioning/reload through service controller;
  no request-killing restarts.
- `management/backup.py` — quiesce writers through `service_ctl` (Postfix, Dovecot,
  php-fpm apps, Postgrey, cron) before backup; restore order + readiness re-check.
- `management/daemon.py`, `management/cli.py`, `tools/dns_update`, `tools/web_update`,
  `tools/ssl_cleanup`, `management/daily_tasks.sh`, `management/munin_start.sh` —
  replace the six+ direct `/usr/sbin/service` calls and any `systemctl` usage.

### Interface contract

- `service_ctl(action, service)` where action ∈ start/stop/restart/reload/status/wait.
- Host impl → existing SysV behavior; container impl → `supervisorctl` (wired in chunk 09).
- Preserve graceful-reload semantics and dependency ordering; unknown service names fail
  loudly in tests.

## Out of scope

- The supervisor implementation details (chunk 09) — mock it in tests here.

## Verification

- [ ] `grep` shows zero remaining direct `service`/`systemctl` calls outside the adapter.
- [ ] Unit tests per caller with a fake service controller asserting action/order.
- [ ] Host-mode behavior unchanged (contract tests); container-mode calls hit the adapter.
- [ ] Backup quiesce/restart ordering test.
