# Shared Context — MIAB Single-Container Kubernetes Milestone

Required reading for every chunk in `chunks/`. This file is the *authoritative contract*
for implementation; `megaplan-single-container.md` is the human-facing source of truth and
is only needed for deep dives (chunk files cite optional megaplan sections).

## Objective

One rootful-but-capability-scoped, stateless MIAB OCI container on single-node k3s,
`hostNetwork`, all durable state under `/home/miab`, on Ubuntu 22.04+ amd64. Preserve all
user-facing MIAB features except in-container OS package updates and host reboot, which
become immutable-image lifecycle operations. Fresh install is normal; migration = offline
restore of a same-release or one-release-earlier (v76/v75) backup.

## Hard invariants (violation = wrong implementation)

- **Host installer parity:** `setup/start.sh` on bare Ubuntu 22.04 keeps working with
  unchanged semantics; container behavior is additive/parameterized.
- **No runtime mutation of the image:** no apt/git/downloads, no daemon lifecycle, no
  hostname/swap/sysctl/systemd-resolved/systemctl/shutdown inside the container.
- **No secrets in the image:** no keys, passwords, hostnames, or instance state in any layer.
- **All durable writes under `/home/miab`;** only `/run`/`/tmp` scratch is ephemeral.
- **Never touch:** `CONTRIBUTING.md`, `.devin/skills/update-containerized/SKILL.md`.
- **Never commit from a subagent;** orchestrator reviews + commits per chunk.
- **Never push to GitHub** (or any remote). Local commits only; all publishing is a
  separate human-approved operation outside this plan.
- **Minimal diffs only:** each commit contains exactly what its chunk requires — no
  drive-by refactors, reformatting, unrelated cleanups, or speculative abstractions.
  If unrelated work is discovered, report it; don't fold it in.
- **Zero development-host changes:** all testing inside the podman `miab-test-host`
  harness; nothing installed/changed on the dev host.
- No `privileged: true`, no `SYS_ADMIN`, no service-account token, no Docker/containerd
  socket, no host PID/IPC, `readOnlyRootFilesystem: true`.

## Naming & environment contract

| Key/name | Value/meaning |
|---|---|
| `STORAGE_ROOT` | `/home/miab/data` (host default unchanged) |
| `STATE_ROOT` | `/home/miab/state` |
| `CONFIG_ROOT` | `/home/miab/config` |
| `MIAB_RUNTIME` | `host` (default) \| `container` |
| `MIAB_SETUP_PHASE` | `install` \| `configure` \| `all` |
| `MIAB_MODE` | `fresh-install` \| `offline-upgrade` \| `startup` \| `live-reconfigure` \| `host-install` |
| `miab-service` | service-control adapter: start/stop/restart/reload/status/wait (SysV on host, supervisorctl in container) |
| `miab-config` | generation tool: render/validate/promote/rollback/gc |
| `miab-install` / `miab-update` | root-only host commands (install & update transactions) |
| `miab-fw` | pod firewall helper, `miab_dynamic` table only |
| `lock-down-ssh` | optional host SSH hardening script (dry-run default, timed rollback) |
| `instance.lock` | `STATE_ROOT/locks/` — serving pod or Job holds it exclusively |
| `config.lock` | serializes live-reconfigure renders |
| nft tables | `inet miab_host` (host baseline), `inet miab_ssh_bans` (host fail2ban), `inet miab_dynamic` (pod app bans) |
| `miab-test-host` | podman harness image simulating the host |
| Immutable defaults | `/usr/share/mailinabox/config-defaults` (image-baked) |

## Persistent layout (`/home/miab`, versioned via `layout.version`)

```text
config/   inputs/mailinabox.conf + inputs/, secrets/,
          generations/<id>/{etc,apps,supervisor,manifest.json},
          current -> generations/<id> (atomic symlink), receipts/
data/     mail/ dns/dnssec/ ssl/ owncloud/ owncloud-backup/ www/ backup/
          settings.yaml mailinabox.version
state/    postfix/ nsd/zones/ z-push/ munin/{db,html,node}/ fail2ban/
          spamassassin/ mailinabox/{api.key,status-cache}/
          update/{status.json,history,receipts}/ backup-ssh/ logs/*/ locks/
restore/  offline staging only
```

Legacy→new path examples: `/var/spool/postfix`→`state/postfix`, `/etc/nsd/zones`→`state/nsd/zones`,
`/var/lib/z-push`→`state/z-push`, `/var/lib/munin`,`/var/cache/munin`→`state/munin`,
`/var/lib/fail2ban`→`state/fail2ban`, `/var/lib/mailinabox`→`state/mailinabox`,
`/root/.ssh/id_rsa_miab`→`state/backup-ssh`, `/etc/mailinabox.conf`→`config/inputs/mailinabox.conf`,
all MIAB-generated `/etc`+app config→`config/generations/<id>` (never in-place on `current`).

## Lifecycle modes

- `fresh-install` (Job): empty layout only, full configure pipeline, receipt last.
- `offline-upgrade` (Job): pod stopped + lock held; complete `setup/start.sh`-equivalent
  configure pipeline (numbered migrations + Nextcloud `occ` + Roundcube `updatedb` +
  permissions + full config render) → validate → atomically promote new generation.
- `startup` (serving pod): verify receipts/digests vs running image; `/run` scratch only;
  read-only config/DB checks; `exec supervisord`. Never renders config or mutates state.
- `live-reconfigure` (running pod): locked render → validate → atomic `current` switch →
  graceful reload; prior generation retained.

## Config generation rules

Seed candidates from **new image's** `/usr/share/mailinabox/config-defaults`; apply
`config/inputs` + `config/secrets` through the shared ordered pipeline; write manifest
(image/source/defaults/input hashes + validation receipt); promote = one same-filesystem
atomic symlink rename; failed candidates leave `current` untouched; bounded retention;
secrets are create-only-when-absent. Package/Kubernetes-owned `/etc` (passwd, hosts,
resolv.conf, CA trust) stays image/runtime-owned — never persisted.

## Service & port inventory

Daemons: rsyslog, bind9 (recursive, loopback), NSD (authoritative, public), Postfix,
Postgrey, Dovecot, spampd/SpamAssassin, OpenDKIM, OpenDMARC, php-fpm, nginx, management
gunicorn, fail2ban, cron, Munin + munin-node, Z-Push, Roundcube, Nextcloud.

Ports: public TCP 25/80/443/465/587/993/995/4190 + TCP/UDP 53; loopback-only
953/10023/10025/10026/8891/8893/10222. Supervisor order: logging+recursive DNS →
authoritative DNS+milters → mail/PHP/management → nginx/Munin/cron/fail2ban.

## Security & capability model

`capabilities.drop: [ALL]`; candidate adds: CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID,
KILL, NET_BIND_SERVICE, NET_ADMIN (fail2ban sets + NSD transparent bind), SYS_CHROOT;
NET_RAW only if syscall evidence proves need. Runtime-default seccomp.

## Firewall & admin access

- Host `miab_host`: boot-persistent default-deny; SSH from any source (password+key auth,
  host fail2ban `[sshd]`→`miab_ssh_bans`); loopback/internal k3s (6443 never public);
  MIAB public ports. Optional `lock-down-ssh` → CIDR/key-only with timed rollback.
- Pod `miab_dynamic`: application fail2ban sets only; no default policy, no port allows.
- No layer may `nft flush ruleset` or touch others'/k3s' tables; `nft -c` before atomic apply.
- Admin path: SSH→host→`sudo k3s kubectl`; no sshd in the MIAB image.

## Update & compatibility contract

Signed release manifest (schema ver, min updater, MIAB ver, commit, digest, arch,
supported source/layout versions, migration id, `rollback_class`=`image-only`|
`restore-required`, SBOM/provenance). `miab-update check|plan|apply|status|rollback`
+ `--image <digest>`. Pre-update verified backup mandatory. Rollback: config-candidate
fail→`current` untouched; pre-mutation→old digest; backward-compat→prior generation+
authorized image; else verified backup restore. Backups supported: same release or one
back (v76/v75, Nextcloud 26→27 assets bundled — no downloads).

## Testing rules

- Synthetic only during development, exclusively inside `miab-test-host` (podman,
  own netns; stubbed DNS/ACME/SMTP; fixture backups). Harness may be privileged — that
  privilege never applies to the MIAB workload image. No true kernel reboot: use
  container restart + `boot-replay.sh`; real boot/pilot is chunk 18 only.
- Per change: `bash -n`, ShellCheck, Ruff, pytest; daemon syntax checks
  (`postfix check`, `doveconf`, `named-checkconf`, `nsd-checkconf`, `nginx -t`,
  PHP-FPM `-t`, fail2ban test, `nft -c`) where relevant; IPv4-only AND dual-stack renders.
- Conventional-upgrade parity fixtures are release blockers; unclassified setup modules
  or unmapped config writes fail tests.
