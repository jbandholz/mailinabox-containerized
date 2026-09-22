# Chunk 09 — Supervision, Entrypoint & Probes

**Goal:** make the container actually run: supervisor as PID 1, mode-dispatching entrypoint,
daemon config routed to `config/current`, health probes.

**Depends on:** 07, 08
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Process Supervision; §Workload Shape; reconcile `startup` mode.

## Scope

### `container/supervisor/`

- One supervisor program per daemon, ordered groups per megaplan:
  1. logging (rsyslog) + recursive DNS (bind9);
  2. authoritative DNS (NSD) + mail policy/milters (postgrey, opendkim, opendmarc, spampd);
  3. Postfix, Dovecot, PHP-FPM, management gunicorn;
  4. nginx, Munin/munin-node, cron, fail2ban.
- All daemons foreground/non-daemon mode; stdout/stderr to supervisor for `kubectl logs`;
  file logs additionally per layout contract.
- Program defs carry user, state paths, dependencies — this is the decomposition inventory.

### `container/bin/entrypoint`

- Dispatch on mode arg: `fresh-install`, `offline-upgrade`, `startup`, `live-reconfigure`,
  `restore`, `validate` (Job commands) — implemented by calling reconcile/config machinery.
- `startup`: verify install + generation receipts match running image digests; create `/run`
  scratch; read-only config/DB checks; `exec supervisord`. Never renders config.
- Acquire `STATE_ROOT/locks/instance.lock` (flock) for serving mode; Jobs check it.
- SIGTERM → graceful supervisor stop honoring termination grace period.

### Daemon config routing

- Complete the image-baked fixed symlinks/flags so every daemon reads MIAB-managed config
  from `config/current/...`: mailinabox.conf, Postfix, Dovecot, nginx/PHP, bind/NSD,
  OpenDKIM/OpenDMARC, SpamAssassin/spampd/Postgrey, fail2ban, Munin, rsyslog/logrotate/cron,
  supervisor, Roundcube, Z-Push.
- Package/Kubernetes-owned `/etc` stays in the image/runtime layer — never persisted.

### Probes — `container/bin/probe-*`

- `startupProbe`: long window for ordered daemon bring-up.
- `readiness`: all critical listeners + config validity.
- `liveness`: PID 1/supervisor health only.

## Verification

- [ ] Pod starts from a promoted generation with `readOnlyRootFilesystem: true` and
      `emptyDir` `/run`,`/tmp`; no config writes during startup.
- [ ] Kill each child → supervisor restarts; SIGTERM → clean shutdown, no queue/DB corruption.
- [ ] Readiness fails until all critical listeners are up; liveness doesn't flap on a
      single degraded child.
- [ ] Startup with missing/incompatible generation fails closed with a clear error.
