---
agent: devin-local
session: silk-offer
created: 2026-09-22T00:42:56Z
---
# MIAB Single-Container Kubernetes Megaplan

Refactor Mail-in-a-Box into one rootful-but-capability-scoped, stateless OCI container on single-node k3s, with every durable application artifact under `/home/miab`, production-grade restore/upgrade/rollback workflows, and explicit seams for later rootless multi-container decomposition.

## Summary

Create a production-pilot-quality first containerization milestone for the current `containerized` branch: one `linux/amd64` MIAB application container, managed by single-node k3s on an Ubuntu 22.04-or-newer host, using `hostNetwork`, a local persistent volume rooted at `/home/miab`, and UID 0 with a reviewed minimal capability set rather than `privileged: true`. Preserve all user-facing MIAB functionality except in-container OS package updates and host reboot. Both OS/package updates and MIAB source-code updates become an explicit, host-driven immutable-image lifecycle with trusted release discovery, compatibility planning, verified backup, digest deployment, health validation, and schema-aware rollback.

Fresh installation is the normal path. Migration is performed offline by restoring a backup from the same MIAB release or one release earlier (currently v76 or v75) through a one-shot Kubernetes Job using the same image. The milestone is complete only after production-pilot validation, including node reboot, pod recreation, queued-mail survival, backup/restore, firewall/fail2ban, rollback, public DNS, mail, web, and TLS tests.

## Confirmed Decisions and Boundaries

- **Kubernetes:** single-node **k3s**, with bundled Traefik and ServiceLB disabled so they cannot claim ports 80/443. Retain the normal k3s CNI for the future multi-container phase.
- **Host:** Ubuntu 22.04 or newer. The application image remains pinned to Ubuntu 22.04 initially because this MIAB release only supports Jammy and PHP 8.0; host and image OS versions are intentionally decoupled.
- **Networking:** `hostNetwork: true`; MIAB binds the host's public addresses directly and preserves client source IPs for SMTP, DNS, logs, and fail2ban.
- **Administrative access:** OpenSSH runs only on the Ubuntu host. By default it is reachable from any source permitted by upstream networking, accepts the host’s existing password and public-key authentication methods, and is protected by a host-level fail2ban SSH jail. Administrators SSH to the host and use local `sudo k3s kubectl`; the MIAB image contains no SSH server and the Kubernetes API is not public. An optional guarded script can later restrict SSH to approved CIDRs and key-only authentication.
- **Privilege:** container starts as UID 0, `privileged: false`, drops all capabilities, and adds only capabilities proven necessary. No Docker socket, host PID namespace, host root mount, systemd/cgroup mount, or Kubernetes API token.
- **Firewall:** use a split model. A boot-persistent host nftables baseline owns default-deny ingress, unrestricted-by-source host SSH allowance, internal k3s allowances, and MIAB’s fixed public ports. Host fail2ban owns SSH bans; pod fail2ban owns application-service bans. Neither fail2ban instance may change static baseline or k3s-owned policy.
- **Persistence:** all MIAB application state—including versioned MIAB-managed runtime configuration, user data, keys, SQLite databases, Postfix queue, logs, generated DNS zones, Z-Push state, Munin history, application fail2ban DB, API material, status cache, and backup SSH keys—lives beneath `/home/miab`. Host OpenSSH/fail2ban/firewall and k3s configuration are node-platform state. Only `/run`, `/tmp`, and process state are ephemeral; MIAB-generated `/etc`/application configuration is not.
- **Ownership:** `/home/miab` may be root-owned; service subtrees are assigned the package-defined numeric UIDs/GIDs required by Postfix, Dovecot, www-data, NSD, Munin, fail2ban, and other daemons.
- **Feature scope:** retain SMTP/submission, IMAP/POP/Sieve, Dovecot delivery, SpamAssassin/spampd, Postgrey, DKIM/DMARC, authoritative and recursive DNS, Roundcube, nginx/static sites, Nextcloud, Z-Push, TLS/Let's Encrypt, backups, fail2ban, Munin, admin UI/API/CLI, cron maintenance, and status reporting.
- **Immutable lifecycle:** initial installation and every OS/package or MIAB code update run from a verified image digest; never run `apt upgrade` in a live pod and never let the pod reboot the host. Host-side `miab-install` bootstraps empty persistent state through a one-shot fresh-install Job, while `miab-update` checks trusted release metadata, plans compatibility, verifies a pre-update backup, runs complete offline reconciliation, deploys the digest, validates service health, and performs image-only or restore-based rollback.
- **Image delivery:** registry-neutral local build and CI. Publish only when registry/repository/credentials are supplied; deployments consume immutable digests rather than mutable tags. CI emits signed release metadata tying together MIAB version, container revision, source commit, image digest, compatibility range, rollback class, SBOM, and provenance.
- **Architecture:** `linux/amd64` only for this milestone.
- **Testing tiers:** development-phase verification uses synthetic harnesses executed **inside local podman containers only — no changes to the development host system are permitted** (no host package installs, no host firewall/fail2ban/sshd changes, no host k3s, no `/home/miab` on the host). A purpose-built `miab-test-host` podman image simulates the Ubuntu host (systemd, sshd, fail2ban, nftables, nested k3s) in its own network/mount namespaces; external DNS/ACME/SMTP peers are stubbed and backups are fixtures. The sandbox container may be privileged for nested-container/kernel-namespace functionality — that privilege is test infrastructure only and never confers on the MIAB workload image, which remains non-privileged. Real public infrastructure (delegated DNS, unblocked TCP/25, live CA issuance, external mail round-trips) is required only for the final production-pilot acceptance phase.
- **Out of scope:** multi-node HA, multiple MIAB replicas, automatic failover to another node, ARM, rootless execution of the monolith, and direct migration of a live non-container filesystem.

## Current-Code Findings Driving the Design

1. `setup/start.sh` is a mutable host installer: it installs/upgrades packages, changes hostname/swap/journald/resolver/firewall settings, writes `/etc`, starts systemd services, generates secrets, and creates the first user. It cannot be used unchanged as a container entrypoint.
2. Service management is coupled to SysV/systemd through `restart_service`, direct `service` calls, `systemctl`, and six management-module calls to `/usr/sbin/service`.
3. MIAB currently assumes many cooperating daemons on loopback: bind9, NSD, Postfix, Postgrey, Dovecot, spampd, OpenDKIM, OpenDMARC, php-fpm, nginx, management gunicorn, fail2ban, rsyslog, cron, Munin, and munin-node.
4. Current `$STORAGE_ROOT` captures core user data but misses durable operational state such as `/var/spool/postfix`, `/etc/nsd/zones`, `/var/lib/z-push`, `/var/lib/munin`, `/var/cache/munin`, `/var/lib/fail2ban`, `/var/cache/mailinabox`, `/var/lib/mailinabox`, `/root/.ssh`, and service logs.
5. Dynamic management operations write `/etc/nginx/conf.d/local.conf`, `/etc/nsd/zones`, OpenDKIM tables, and restart/reload daemons. These MIAB-managed outputs must persist as versioned configuration generations (re-renderable on update from persisted inputs), while serial-bearing zone files and other non-regenerable data move to persistent state.
6. The backup coordinator stops selected system services through `/usr/sbin/service` and backs up only `$STORAGE_ROOT`; it must use a runtime-neutral service controller and cover the new state contract.
7. The control panel currently offers `apt update/upgrade` and host reboot endpoints, and status checks inspect host SSH/UFW/package state. Those are invalid or dangerous inside Kubernetes and require container-aware behavior.
8. Current source is based on v76; v75 used Nextcloud 26 and v76 uses Nextcloud 27. Supporting “same release or one back” therefore requires testing both data schemas and bundling the needed one-step Nextcloud upgrade assets in the image rather than downloading during startup.
9. A conventional MIAB code upgrade is not just `setup/migrate.py`: the administrator downloads the new source and reruns `setup/start.sh`, which executes numbered migrations and then the ordered system/SSL/DNS/mail/DKIM/spam/web/Roundcube/Nextcloud/Z-Push/management/Munin setup scripts. Those scripts mutate persistent databases/configuration, run Nextcloud and Roundcube schema upgrades, repair permissions, regenerate service configuration, and restart/reload services. The container update path must preserve this reconciliation contract without apt/download/host mutation.
10. MIAB’s current version check compares Git state with upstream setup metadata, but there is no container release channel, digest compatibility contract, host-side rollout coordinator, or schema-aware rollback mechanism. Source updates must therefore be coupled to OCI release metadata and k3s lifecycle tooling.
11. The branch has pre-existing uncommitted changes in `.devin/skills/update-containerized/SKILL.md` and `CONTRIBUTING.md`. Implementation must preserve them untouched unless the user resolves or explicitly includes them later.

## Target Architecture

### 1. Host and k3s Layer

- Install a pinned, tested k3s version through a checked script/configuration, with:
  - `traefik` and `servicelb` disabled;
  - default CNI retained;
  - node label `mailinabox.email/node=true`;
  - Kubernetes API access restricted to loopback and required internal interfaces, with no public port 6443 exposure;
  - root-owned kubeconfig used locally through `sudo k3s kubectl`, with permissions and recovery access documented;
  - host prerequisites checked: amd64, cgroup v2, required kernel modules, nftables support, free ports, static public addressing, reverse DNS, outbound TCP/25, disk space, and `fs.inotify.max_user_instances=1024`.
- Create `/home/miab` once, mode `0750`, before applying Kubernetes resources. Bootstrap creates directories and node prerequisites; the container assigns service-subtree ownership.
- Install a boot-persistent, host-owned nftables baseline before k3s/MIAB deployment. It defaults to deny unsolicited input; allows established/related, loopback, required ICMP/ICMPv6, the configured SSH port from any source by default, loopback/internal k3s traffic, and MIAB’s fixed public ports; and never flushes k3s-owned tables. Install host fail2ban with only the SSH jail enabled against host authentication logs. The baseline and SSH banning remain authoritative while the pod is absent or k3s is down.
- Use a manually defined `Retain` local PersistentVolume pointing to `/home/miab`, a bound RWO PVC, and node affinity to the labeled node. This gives a future extraction path from one directory/PV into per-service PVCs without embedding `hostPath` directly in the workload.
- Use a dedicated namespace. Explicitly label the namespace for the Pod Security level required by `hostNetwork` and added capabilities; do not weaken policy cluster-wide.

### 2. Workload Shape

- Use a one-replica `Deployment` with `strategy: Recreate` rather than a rolling strategy. A second host-network pod cannot bind the same ports, and concurrent writers must never share SQLite/queue state.
- The serving pod contains exactly one application container and no sidecars. Restore/validation are separate one-shot Jobs using the same image and command-specific entrypoints.
- Set `hostNetwork: true`, `dnsPolicy: None`, and pod DNS to `127.0.0.1` after the local recursive resolver starts. Startup checks use explicit bootstrap resolvers before bind9 is ready; normal runtime resolution uses the local DNSSEC-validating bind9 instance.
- Disable service-account token automounting. Do not grant RBAC permissions to mutate Deployments, nodes, or host configuration.
- Mount the single PVC at `/home/miab`. Point daemon state directly at service-specific paths and point daemon configuration at `/home/miab/config/current/...` through explicit command-line config roots or fixed image-baked symlinks from legacy `/etc`/application locations. These paths become clean extraction seams later.
- Mount ephemeral `emptyDir` volumes for `/run` and `/tmp` and any proven runtime-only scratch paths. Set `readOnlyRootFilesystem: true`: package/vendor defaults and binaries come from the image, while every MIAB-managed mutable configuration or state path resolves beneath `/home/miab`.
- Add:
  - a long `startupProbe` that tolerates ordered bring-up of all supervised daemons (key/schema work belongs to install/update Jobs, not serving startup);
  - a readiness probe covering all critical internal/public listeners and configuration validity;
  - a conservative liveness probe that checks PID 1/supervisor health only, avoiding restart loops for a single degraded child;
  - a termination grace period sufficient to stop listeners, flush queues/databases, and terminate children cleanly.

### 2A. Administrative Access and Recovery

- Keep the host's existing OpenSSH service as the sole SSH endpoint. Do not install, configure, expose, or supervise `sshd` inside the MIAB image.
- Use the normal administration path `administrator -> SSH to Ubuntu host -> sudo k3s kubectl -> MIAB pod`. Routine commands include `kubectl logs`, `kubectl exec`, Job creation, rollout status, and pod replacement; add noninteractive `miab-admin` wrappers for status, backup, queue, firewall, restore, and validation operations so routine work does not require an interactive shell.
- Keep k3s port 6443 off the public Internet. Bind/permit the API only on loopback and interfaces required by the local control plane. Remote Kubernetes administration is out of scope unless later added through a VPN or similarly constrained private path.
- Default host SSH policy allows the configured SSH port from all source addresses and preserves the host’s existing password and public-key authentication settings. Enable a host fail2ban `[sshd]` jail (initially matching MIAB’s existing `maxretry=7`, `bantime=3600`) against host authentication logs, with bans stored in a host-owned nftables timeout set.
- Provide an optional idempotent `lock-down-ssh` host script with repeatable `--admin-cidr` inputs and `--key-only`. Dry-run is the default. Before `--apply`, it must verify at least one usable authorized key for the invoking admin when key-only is requested, require the current `SSH_CONNECTION` source to fall within an approved CIDR, render an sshd drop-in rather than rewrite the vendor config, pass `sshd -t` and `nft -c`, and arm an automatic timed rollback.
- Applying hardening atomically changes only the host SSH allow rule and the dedicated sshd drop-in (`PubkeyAuthentication yes`, password and keyboard-interactive authentication disabled for key-only mode). The administrator must prove a second SSH session works and run an explicit confirmation command before the rollback timer is cancelled. Provide `status`, `confirm`, and `revert` operations and preserve prior files for deterministic rollback.
- Preserve host OpenSSH, host fail2ban, and the baseline independently of the MIAB pod. If the pod or k3s is unavailable, the administrator can still SSH to the host, inspect `/home/miab`, and repair/restart k3s.
- Document provider console/physical console access as the break-glass path for host firewall mistakes, SSH daemon failure, or loss of host credentials. Include commands to validate, inspect, reload, revert SSH hardening, and temporarily disable only the host MIAB-node baseline without touching k3s tables.
- On host reboot, the persistent baseline and host SSH jail are restored before application scheduling. The pod later restores application-service bans; host SSH protection does not depend on the pod.

### 3. Process Supervision Without systemd

- Install and use Ubuntu’s `supervisor` package as PID 1; do not mount cgroups or add `SYS_ADMIN` merely to run systemd.
- Run daemons in foreground/non-daemon mode under supervisor, with service users preserved where supported. Define ordered groups:
  1. logging and recursive DNS;
  2. authoritative DNS and mail policy/milter dependencies;
  3. Postfix, Dovecot, spam filtering, PHP, management API;
  4. nginx, Munin, cron, fail2ban.
- Add a `miab-service` adapter with `start`, `stop`, `restart`, `reload`, `status`, and `wait` operations backed by `supervisorctl`. Refactor management/setup callers to use this abstraction, while retaining the existing SysV behavior for non-container installations.
- Hold an exclusive lifetime lock beneath `/home/miab/state/locks/instance.lock` around the supervisor process. Restore/repair Jobs must obtain the same lock and fail closed if the serving pod is active.
- Forward service output to stdout/stderr for `kubectl logs` while retaining required file logs under `/home/miab/state/logs` for fail2ban, weekly mail reports, historical troubleshooting, and existing parsers. Keep logrotate running under cron with bounded retention.

### 4. Build-Time vs Run-Time Separation

Refactor setup into explicit phases while preserving the existing host installer as the default:

- **Install phase (image build only):** apt repositories/packages, Python virtualenv and locked dependencies, Roundcube/plugins, Nextcloud current and previous-release migration assets, Z-Push, management assets, compiled/static files, and deterministic service users/groups. Capture pristine package/repository configuration inputs and checksums under immutable `/usr/share/mailinabox/config-defaults`; bake only fixed links/launchers that direct MIAB-managed legacy `/etc` and application config paths to `/home/miab/config/current`.
- **Configure/reconcile phase (fresh-install, offline-upgrade, and live reconfigure only):** validate inputs, run data/layout compatibility actions, and build a complete candidate configuration generation under `/home/miab/config/generations/.staging-<id>`. Seed it from the **new image’s** immutable defaults, then apply persisted identity/settings/secrets and supported MIAB customizations through the same ordered service setup pipeline as conventional `setup/start.sh`. This includes user DB compatibility, Nextcloud `occ`, Roundcube `updatedb`, Postgrey/spam state, permissions, and DNS/web/service configuration—not only `setup/migrate.py`.
- **Host/default phase:** existing `setup/start.sh` continues running install+configure with current systemd/host behavior so upstream non-container compatibility is not accidentally broken.

Extract one shared ordered reconciliation orchestrator used by both host `setup/start.sh` and container Jobs so future upstream setup additions cannot silently bypass container upgrades. Parameterize `MIAB_SETUP_PHASE=install|configure|all`, `MIAB_RUNTIME=container|host`, and reconcile mode:

- `fresh-install`: require an empty/uninitialized layout, hold the lifetime lock, create persistent data/settings/secrets plus the first complete configuration generation, validate both, atomically promote the generation, and write `install.receipt`/the installed release marker last;
- `offline-upgrade`: serving pod stopped and lifetime lock held; run every persistent compatibility action and render the new image’s complete candidate generation, validate all databases/configs, then atomically promote `config/current` and emit the update receipt;
- `startup`: require valid installation/restore and configuration-generation receipts whose image/source/config-default digests match the running image; perform only runtime scratch setup and read-only configuration/database checks, then start supervisor using the persisted generation—do not regenerate `/etc` or mutate persistent configuration;
- `live-reconfigure`: under a configuration lock, render a new generation from immutable image defaults plus persistent inputs, validate it, atomically switch `config/current`, gracefully reload affected services, and retain the prior generation for rollback.

Configuration generation rules:

- persist canonical identity/settings in `config/inputs`, generated or supplied configuration secrets in `config/secrets`, complete service/app trees in `config/generations/<id>`, an atomic relative `config/current` symlink, and generation manifests/receipts with image/source/default/input hashes;
- launch each daemon with an explicit config root where supported; otherwise use image-baked fixed symlinks for known files/directories such as `/etc/mailinabox.conf`, Postfix, Dovecot, nginx/PHP, bind/NSD, OpenDKIM/OpenDMARC, SpamAssassin/spampd/Postgrey, fail2ban, Munin, rsyslog/logrotate/cron, supervisor, Roundcube, and Z-Push;
- never persist or replace package/Kubernetes-owned `/etc/passwd`, groups, CA trust, NSS/PAM, `/etc/hosts`, `/etc/resolv.conf`, or service-account/runtime mounts;
- never modify the active generation in place; failed rendering leaves `current` unchanged, and promotion is one same-filesystem atomic symlink rename after syntax/database validation;
- retain a bounded number of prior generations and include the active generation in backup/update/restore receipts.

In all container modes, prohibit apt, git, package/application downloads, host `hostname`, swap, sysctl, systemd-resolved, shutdown, and systemctl. Guard direct service actions and make persistent mutations idempotent/transactional. No private key, password, DNSSEC key, API key, certificate, backup key, or instance-specific hostname/IP may be created in an image layer.

### 5. Persistent Layout Contract

Use the following versioned layout and record its schema in `/home/miab/layout.version`:

```text
/home/miab/
  config/
    inputs/mailinabox.conf      # canonical persisted identity/network/runtime inputs
    inputs/                     # other supported non-secret configuration inputs
    secrets/                    # generated/supplied config secrets with service-specific ownership/modes
    generations/<id>/
      etc/                      # complete MIAB-managed service configuration tree
      apps/                     # Roundcube/Z-Push and other application config outside /etc
      supervisor/               # process definitions bound to this generation
      manifest.json             # image/source/default/input hashes and validation receipt
    current -> generations/<id> # atomically promoted active generation
    receipts/                   # install/reconfigure/promotion history
  data/                         # STORAGE_ROOT
    mail/                       # users.sqlite, mailboxes, sieve, DKIM, spam data, Roundcube DB, Postgrey DB
    dns/dnssec/                 # DNSSEC keys and custom DNS settings
    ssl/                        # private key, certs, ACME account, DH params
    owncloud/                   # Nextcloud DB/config/data
    owncloud-backup/
    www/
    backup/                     # duplicity settings/cache/encrypted target and secret
    settings.yaml
    mailinabox.version
  state/
    postfix/                    # queue_directory; survives pod replacement/reboot
    nsd/zones/                  # unsigned/signed zones, serials, DS outputs
    z-push/
    munin/{db,html,node}/
    fail2ban/
    spamassassin/               # package/runtime rule state not already under data
    mailinabox/{api.key,status-cache}/
    update/{status.json,history,receipts}/ # non-secret host-updater results visible read-only to MIAB
    backup-ssh/
    logs/{mail,syslog,nginx,roundcube,z-push,nsd,munin,fail2ban}/
    locks/
  restore/                      # offline staging only; empty in normal operation
```

Rules:

- `STORAGE_ROOT=/home/miab/data`; `STATE_ROOT=/home/miab/state`; `CONFIG_ROOT=/home/miab/config` become explicit environment keys.
- Assign deterministic image UID/GID ownership per subtree and verify IDs at startup before mutation. Refuse to start on incompatible ownership rather than recursively chowning large mail stores every boot.
- Every MIAB-generated or MIAB-mutated `/etc` and application configuration file is persisted in the active versioned generation. Immutable image defaults are inputs for creating a generation, never the runtime source of mutable configuration and never copied over the active generation in place.
- API and configuration secrets are created only when absent, atomically with least-privilege modes, and referenced from generations; they are not overwritten by service/pod restart.
- Move Postfix’s `queue_directory`, Dovecot’s Postfix auth socket path, NSD zone directory, Z-Push state, Munin DB/HTML state, fail2ban DB, backup SSH identity, logs, and status caches to the paths above.
- Back up canonical inputs/secrets, the active and bounded prior configuration generations, generation receipts, and data/state according to the backup contract.
- Add an automated “state escape” test: run representative install/reconfigure/service/update operations with a read-only image root, replace the container, and fail on any MIAB-managed write outside `/home/miab` or explicitly ephemeral `/run`/`/tmp` paths.

### 6. Configuration and First Boot

- Provide checked, non-secret inputs with a clear ownership split: application deployment values contain `PRIMARY_HOSTNAME`, `PUBLIC_IP`, optional `PUBLIC_IPV6`, private bind addresses derived/validated for `hostNetwork`, timezone, MTA-STS mode, resources, and image digest; node-bootstrap values contain the host SSH port and internal Kubernetes API/CNI allowances, with administration CIDRs and key-only mode supplied only to the optional SSH-lockdown command. Render the latter to root-owned host platform configuration (e.g. `/etc/mailinabox-node/firewall.conf`), not application state.
- Persist immutable instance identity on first successful configuration. On later starts, compare Kubernetes inputs with persisted values and fail with a precise migration instruction on unsafe drift instead of silently changing hostname/IP/key identity.
- Support a bootstrap Kubernetes Secret for the first admin email/password, consume it only if no users exist, never print it, and instruct operators to remove the bootstrap Secret after readiness. The durable password hash remains under `/home/miab/data`; the Secret is bootstrap input, not application state.
- Also retain an interactive `kubectl exec` first-user path so no plaintext password needs to be stored in manifests.
- Generate expensive DH parameters at image build because they are public/non-instance-specific; generate instance TLS/DNSSEC/DKIM/backup keys only at first runtime.
- Render complete candidate generations atomically (`tempfile + fsync + rename`), validate them before promotion, and switch `config/current` with one atomic symlink rename. Serving-pod startup treats the promoted generation as read-only and refuses a missing, incomplete, or image-incompatible manifest.

### 6A. Initial Installation Transaction

- Install a root-only host command, `miab-install`, as node-platform tooling. It supports guided TTY prompts and noninteractive flags/config, but never writes an administrator plaintext password to command history, manifests, receipts, or logs.
- `miab-install preflight` verifies amd64 Ubuntu support, host name/public IPv4 and optional IPv6, forward/reverse DNS expectations, outbound TCP/25, required public ports, host SSH continuity, k3s/CNI/API health, nftables/fail2ban baseline, free disk/RAM, `/home/miab` emptiness/layout status, and image signature/digest/embedded metadata.
- `miab-install apply` performs a resumable transaction:
  1. acquire a host install/update/restore lock and refuse an already initialized/non-empty application layout unless explicit recovery mode is selected;
  2. resolve/pull or locally import the exact trusted image digest before changing application state;
  3. create the dedicated namespace, node label, `Retain` local PV/PVC, non-secret ConfigMap, and a short-lived bootstrap Secret only when noninteractive first-admin credentials were supplied;
  4. run a one-shot, single-container `fresh-install` Job mounting the PVC, with no service-account token and the same scoped capabilities as needed for setup;
  5. execute the image’s complete configure/reconciliation pipeline against empty state: create layout/version markers, SQLite stores, mailbox/web defaults, self-signed TLS material, ACME account state, DNSSEC/DKIM keys, backup/API secrets, Nextcloud/Roundcube state, service permissions, and all generated service configuration, while prohibiting apt/git/downloads and daemon lifecycle actions;
  6. run database integrity and every daemon syntax/config check, record image/source/layout digests and per-module results, then write the installation receipt last;
  7. create/apply the one-replica serving Deployment at the same digest; require read-only startup validation of the promoted generation and supervisor readiness, with no independent config regeneration;
  8. create the first administrator through the live management API/CLI, either from a securely prompted password or the bootstrap Secret, then create required aliases and trigger a persistent `live-reconfigure` generation for DNS/web changes;
  9. delete the bootstrap Secret after successful account creation, run public/internal protocol postflight, and atomically mark installation complete.
- The fresh-install Job does not need a running management daemon and therefore skips `firstuser.sh`; first-user creation occurs only after the serving management service is healthy. If no bootstrap Secret exists, `miab-install` securely prompts at that point or prints the exact interactive `kubectl exec` command.
- Installation failure before the completion receipt leaves an explicitly incomplete, non-serving layout. Rerun resumes only proven-idempotent completed modules; `miab-install status` reports the failed module and `miab-install recover` requires an explicit resume or clean-reinitialize choice. Never automatically delete partially generated keys/data or an unknown non-empty `/home/miab`.
- Initial public certificates may remain self-signed until DNS delegation/reachability permits normal MIAB certificate provisioning; installation success requires valid self-signed service operation, not premature public CA issuance.

### 7. Networking, DNS, and Firewall

- Bind NSD only to the host’s selected public/private interface addresses on TCP/UDP 53; bind bind9 recursion/control only to loopback. Do not modify the host’s `/etc/resolv.conf` or systemd-resolved.
- Expose directly through host networking: TCP 25, 80, 443, 465, 587, 993, 995, 4190 and TCP/UDP 53. Keep management port 10222 and all internal mail/milter ports loopback-only.
- Replace UFW with three explicitly owned nftables layers:
  - **Host baseline (`inet miab_host`):** installed persistently by node bootstrap and restored at boot. Its input base chain owns default-deny policy; permits established/related, loopback, required ICMP/ICMPv6, the configured SSH port from any source by default, loopback/internal k3s traffic, and MIAB public ports. Optional hardening replaces only the unrestricted SSH allow with approved CIDRs.
  - **Host SSH bans (`inet miab_ssh_bans`):** an earlier-priority host fail2ban chain that drops SSH traffic from its timeout sets and otherwise falls through. It reads host authentication logs, persists its DB as node state, and is independent of the pod.
  - **Pod application bans (`inet miab_dynamic`):** an earlier-priority pod fail2ban chain that drops sources banned by MIAB application jails and otherwise falls through. It does not allow ports, set default policy, or own the SSH jail.
  - No layer may run `nft flush ruleset`, UFW, or generic iptables flushes. Every operation is table-name-scoped and preserves k3s and unrelated tables.
  - Validate transactions with `nft -c` before atomic application. Provide ownership-specific dry-run, status, reload, and emergency cleanup commands for all three tables.
- Split the existing `[sshd]` jail out of the container configuration into the host fail2ban configuration. Container fail2ban updates only `miab_dynamic`; its DB/logs remain under `/home/miab`. Host fail2ban updates only `miab_ssh_bans`; its DB/logs are Kubernetes-node state.
- Add `NET_ADMIN` to the pod only for application-ban sets and NSD transparent binding; retain `NET_RAW` only if testing proves a separate need. The pod must not expose a generic firewall-rule API or accept arbitrary nft input.
- Preserve password and public-key SSH authentication by default. The optional lockdown script alone introduces admin CIDRs and key-only authentication, using the guarded two-session/rollback workflow. Never create a public allow rule for k3s port 6443.
- Explicitly test IPv4-only and dual-stack configurations. Empty IPv6 values must not produce invalid bind/firewall rules.

### 8. Capability and Security Model

Start from `capabilities.drop: ["ALL"]` and an initial reviewed candidate set:

- `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID`, `KILL` for setup and service privilege transitions;
- `NET_BIND_SERVICE` for low ports;
- `NET_ADMIN` for the narrowly scoped fail2ban dynamic sets and NSD transparent binding; `NET_RAW` remains excluded unless capability testing demonstrates an independent required syscall;
- `SYS_CHROOT` for Postfix’s chrooted workers.

During implementation, run all service, backup, reload, certificate, DNS-update, fail2ban, and restore paths under this set with audit/strace evidence. Add a capability only with a recorded syscall/use case; remove unused candidates. Keep `privileged: false`, `hostPID: false`, `hostIPC: false`, runtime-default seccomp, no host root mount, and no service-account token. Set `allowPrivilegeEscalation` only where setuid/chroot service behavior proves it necessary; if Kubernetes cannot vary it per process in the monolith, record that as a decomposition target.

Other controls:

- Build as a noninteractive, minimal Ubuntu 22.04 image; clear apt caches and exclude build tools from the final stage where practical.
- Pin the base image by digest, all external application source revisions/checksums, Python dependency locks/hashes, CI actions, and build tooling. Record apt package versions and snapshot date in image metadata/SBOM.
- Produce OCI labels, SBOM, provenance, vulnerability scan results, and an immutable digest. Never place registry credentials or bootstrap secrets in layers/logs.
- Scan restored archives for absolute paths, traversal, device nodes, and symlinks escaping the staging root before promotion.

### 9. Container-Aware Management Behavior

Introduce a runtime/platform helper used by management modules rather than scattered environment checks.

- Route service reload/restart/stop/start through `miab-service` in container mode and `/usr/sbin/service` on hosts.
- Replace package-update endpoints and status checks with read-only immutable-release information loaded from image metadata and `/home/miab/state/update/status.json`:
  - installed MIAB version, container revision, source commit, image digest/build date, configured channel, last successful check, available trusted release, compatibility/rollback class, and last update result;
  - `/system/update-packages` never mutates the pod and returns the exact host-side `sudo miab-update plan|apply` workflow for the available digest;
  - latest-version checks use the configured trusted container release source rather than comparing only to upstream’s host installer;
  - stale/missing updater status is reported honestly without giving the pod registry credentials or Kubernetes RBAC;
  - reboot GET reports false/not-applicable and reboot POST refuses without calling `shutdown`.
- Remove host SSH configuration checks from the pod or mark them external/unavailable. Replace UFW status with read-only verification that the host `miab_host` baseline is active and required public ports are present, plus full status of the pod-owned `miab_dynamic` fail2ban sets.
- Make free-memory checks cgroup-v2-aware and disk checks target `/home/miab`; describe Munin metrics as container/application metrics rather than falsely claiming complete host metrics.
- Keep status checks for all MIAB service ports, public reachability, DNS, TLS, backups, disk, aliases, and fail2ban.
- Ensure DNS/web/certificate and other runtime config changes create/validate/promote a persistent `live-reconfigure` generation, then use graceful reloads without terminating the triggering API request; never write active configuration directly into the container overlay.

### 9A. MIAB Code and Image Update Mechanism

- Install a root-only host command, `miab-update`, as node-platform tooling. It owns update-source credentials and k3s authority; the application pod receives neither. Support `check`, `plan`, `apply`, `status`, and `rollback`, plus an explicit `--image <digest>` path for locally built/imported images.
- Configure a registry-neutral trusted update source (`UPDATE_SOURCE`) as either an OCI repository/release artifact or a signed HTTPS manifest. Pin a trust policy (public key or expected keyless identity/issuer); reject unsigned metadata, mutable tag-only targets, architecture mismatches, and digest/signature/provenance mismatches.
- Require each release manifest to contain: manifest schema version, minimum host-updater version, MIAB upstream version, container release, source commit, exact image digest, `linux/amd64`, build timestamp, supported source MIAB/layout versions, target layout version, migration identifier, reconciliation-contract version/hash, `rollback_class` (`image-only` or `restore-required`), release notes/security flag, and SBOM/provenance references.
- `miab-update check` fetches and verifies metadata without changing workloads, compares semantic MIAB/container versions and digests, verifies that its own version supports the manifest schema/minimum updater requirement, and atomically writes a non-secret status file under `/home/miab/state/update/` for the control panel. An optional host systemd timer may run **check only**; unattended apply is out of scope. If node tooling is too old, fail closed and direct the administrator to a separately signed, checksum-verified, atomic node-tooling upgrade with retained rollback copy; never let an application image overwrite host updater/firewall tooling.
- `miab-update plan` verifies node capacity, current/target versions, one-back migration support, PV/layout compatibility, registry reachability, image signature/provenance, current workload health, pending restore/update operations, and rollback requirements. It prints exact downtime and rollback steps and performs no mutation.
- `miab-update apply` executes a transaction with an update lock and durable receipt:
  1. resolve the trusted manifest to an immutable digest and pull/import it before downtime;
  2. run the new image’s non-mutating metadata, bundled-asset, source-version, and static configuration validation Job;
  3. run and verify a fresh pre-update backup, recording its collection/restore coordinates without exposing secrets;
  4. gracefully quiesce and scale the serving Deployment to zero, preserving Postfix queue and all PVC state;
  5. run the new digest’s `offline-upgrade` reconciliation Job under `instance.lock`: execute the complete container configure equivalent of the new release’s `setup/start.sh` against mounted state—including numbered/layout migrations, every ordered setup module, Nextcloud/Roundcube upgrades, permissions, and config/database validation—with package/download/service actions disabled;
  6. render/apply the Deployment with the exact digest; its `startup` path verifies and consumes the promoted persistent configuration generation read-only, then starts supervisor and waits through startup/readiness gates without regenerating configuration;
  7. run DNS, TLS, SMTP submission, IMAP, management API, database-integrity, Nextcloud/Roundcube, queue, and state-layout postflight checks;
  8. record installed digest/version, migration/backup receipts, verification results, and release history atomically.
- Failure handling is phase-aware: candidate-config failure leaves `config/current` untouched; before data mutation, restart the old digest/current generation; after a backward-compatible migration, atomically select the prior compatible generation and follow manifest-authorized image rollback; after a non-backward-compatible migration, restore the verified pre-update backup (including config generations/current pointer) and old digest. Never claim that changing the image field alone is safe when `rollback_class=restore-required`.
- Serialize update, restore, and backup operations with explicit locks. Refuse concurrent runs, dirty/unverified release metadata, unsupported version skips, an unverified backup, or an image whose embedded metadata does not match the release manifest.
- Couple upstream MIAB code updates to the existing `containerized` synchronization workflow: after semantic merge review, CI builds a candidate image, runs current and one-back migration/integration gates, and only then emits publishable signed release metadata. Thus updating MIAB code and updating OS packages use the same immutable rollout path.

### 10. Backups and Restore/Migration

#### Ongoing backups

- Change the backup source contract from only `$STORAGE_ROOT` to the versioned `/home/miab` application-state set, excluding the backup destination/cache itself, restore staging, and ephemeral locks.
- Acquire a maintenance lock, quiesce every writer through the service controller (Postfix, Dovecot, php-fpm/Nextcloud/Roundcube/Z-Push, Postgrey, management-triggered DNS/web writers, cron jobs as needed), back up, then restart in dependency order and re-run readiness checks.
- Preserve current file/rsync/S3/B2 support and move SSH key references from `/root/.ssh` to `/home/miab/state/backup-ssh`.
- Version backup metadata with MIAB release, image revision, layout version, source architecture, timestamp, and integrity hashes.

#### Migration restore Job

- Require the serving Deployment to be scaled to zero. The Job obtains `instance.lock` non-blocking and aborts if any serving process remains.
- Accept existing MIAB duplicity backup sources and separately supplied backup secret/remote credentials without embedding them in the image or committed YAML.
- Restore into `/home/miab/restore/staging`, never directly over live data.
- Validate:
  - backup release is the image’s release or exactly one MIAB release back;
  - expected `mailinabox.version`, SQLite databases, mailboxes, SSL/DNSSEC/DKIM material, and Nextcloud config are present;
  - SQLite `integrity_check` succeeds for users, Roundcube, and Nextcloud databases;
  - archive paths and symlinks stay inside staging;
  - sufficient disk space and expected architecture/layout are present.
- For legacy host backups, promote restored contents into `/home/miab/data`, initialize missing operational-state subtrees empty, normalize ownership, then run the target image’s complete `offline-upgrade` reconciliation pipeline (not only `setup/migrate.py`) so the restored system receives the same ordered setup, Nextcloud/Roundcube upgrades, permissions, and compatibility work as a conventional MIAB setup rerun, using only assets already in the image.
- For future container-layout backups, restore the complete versioned state contract.
- Write a restore receipt with source release, target release, hashes, timestamp, and completed migrations. Only after every check succeeds atomically rename staged directories into place.
- Start the Deployment, wait for readiness, and run post-restore DNS, TLS, mail-user, mailbox-count, and Nextcloud checks. Keep the restore Job logs and receipt for audit.
- Refuse unsupported older backups with instructions to upgrade them conventionally to the immediately previous release first.

### 11. Kubernetes Resources and Deployment Tooling

Create a Kustomize-based, registry-neutral deployment tree containing:

- namespace and Pod Security labels;
- labeled-node local PV, PVC, and `Retain` policy;
- ConfigMap generator inputs for non-secret settings;
- one-replica Recreate Deployment with host networking, probes, resources, security context, lifecycle hooks, and digest placeholder;
- bootstrap Secret example/instructions without real values;
- restore and validation Job templates using the same digest;
- no public Service/Ingress/LoadBalancer, because host-network listeners are the public endpoints;
- an optional headless internal Service only if future discovery needs it—do not add unused objects now.

Provide idempotent commands/scripts to:

1. preflight the host and ports;
2. install/configure pinned k3s;
3. label the node and create `/home/miab`;
4. build locally and import into k3s containerd, or render a registry image digest;
5. render/validate manifests without secrets;
6. run `miab-install preflight|apply|status|recover`, wait for readiness, securely create the first administrator, and remove bootstrap credentials;
7. inspect status/logs/firewall/queue;
8. check/plan/apply/status/rollback MIAB code and image releases by digest; run backup/restore; and perform explicit uninstall/firewall cleanup.

Uninstall must default to retaining the PV and `/home/miab`; deleting persistent data is a separate, explicitly confirmed operation and is not automated.

### 12. CI, Image Publication, and Supply Chain

Add registry-neutral CI stages:

1. shell/Python lint and unit tests;
2. configuration rendering tests for IPv4-only and dual-stack inputs;
3. OCI image build for `linux/amd64` with no push;
4. image inspection ensuring no secrets/instance state and correct package/application versions;
5. vulnerability scan with a documented severity policy and exceptions process;
6. SBOM/provenance generation;
7. container smoke tests inside a podman test-harness container with firewall application disabled so CI cannot alter the runner host;
8. Kustomize render plus schema validation;
9. generate and verify the release compatibility manifest against embedded image labels and current/one-back migration results;
10. optionally sign and publish the digest, release manifest, SBOM, and provenance when registry/update-source credentials are supplied. Refuse publication when required compatibility, restore, integration, vulnerability, or signature gates fail.

Pin all CI actions/tools by immutable revision. Never weaken package-manager minimum-age/security policies to make a build pass. Treat a published signed release manifest—not an image tag—as the update channel’s source of truth.

### 13. Future Decomposition Seams

Make milestone-one choices that reduce—not deepen—monolith coupling:

- Define `DATA_ROOT`, `STATE_ROOT`, service-specific state directories, and internal endpoint settings centrally instead of introducing new hard-coded localhost/storage paths.
- Keep supervisor program definitions one per daemon, with explicit dependencies, health checks, ports, users, and state paths; these definitions become the inventory for later Deployments/StatefulSets.
- Replace direct `service` calls with a service-control interface now so it can later target Kubernetes rollouts/APIs or no-op across service boundaries.
- Keep generated configuration templates per service and avoid one script mutating unrelated services.
- Preserve one SQLite writer and one pod in milestone one; do not imply horizontal scalability while shared SQLite, maildir, and Postfix queues remain local.
- Suggested later extraction order:
  1. scheduled maintenance/backup Jobs and monitoring;
  2. nginx/web assets and management API (rootless candidates);
  3. Roundcube, Nextcloud, and Z-Push with explicit storage/database contracts (rootless candidates);
  4. authoritative and recursive DNS;
  5. spam/policy/milter pipeline;
  6. Postfix and Dovecot/mail storage, after queue, auth, LMTP, and mailbox consistency contracts are redesigned.
- Before moving to a distinct node, replace the local PV with a storage class appropriate to workload semantics, move config/secrets to a managed secret system, add NetworkPolicies, and choose stable service DNS names. Do not attempt multi-replica mail components until databases, queues, locking, and mailbox storage support it.

## Implementation Steps

1. **Add contract tests before behavior changes.** Capture current host install defaults, generated config expectations, service/port inventory, current `$STORAGE_ROOT` schema, v75/v76 migration fixtures, and existing management API behavior that must intentionally change.
2. **Introduce platform/state abstractions.** Add runtime detection, root-path helpers, cgroup-aware resource helpers, service control, atomic file helpers, and layout initialization. Update hard-coded durable paths and add compatibility defaults so host installs still use their current locations.
3. **Split setup into install/configure phases.** Refactor each setup script without changing default host semantics; guard host-only operations and eliminate package/network activity from container startup.
4. **Build the OCI image.** Add the pinned Ubuntu 22.04 amd64 build, package/dependency locks, verified third-party assets, supervisor, immutable application sources, labels, non-secret DH params, and no runtime state.
5. **Implement persistent configuration generations and supervision.** Capture immutable image defaults, persist inputs/secrets, render/validate/atomically promote complete generations, route every daemon to `config/current`, enforce a read-only root filesystem, initialize runtime scratch only at serving startup, start foreground services, handle signals, and expose probes.
6. **Refactor dynamic lifecycle calls.** Route backup, DNS, web, SSL, and setup service actions through the service controller; preserve graceful reload semantics and deterministic dependency ordering.
7. **Implement split nftables/fail2ban policy.** Add boot-persistent `miab_host`, host fail2ban plus `miab_ssh_bans`, pod fail2ban plus `miab_dynamic`, guarded atomic transactions, ownership-specific ban restoration/status/recovery, default password-and-key SSH from any source, and the optional rollback-protected CIDR/key-only lockdown script. Audit host-network capabilities.
8. **Make management container-aware.** Remove live apt/reboot behavior, expose installed/available image and MIAB-code release status read-only, adapt system checks, preserve API compatibility where safe, and update UI text/actions.
9. **Implement the host initial-install transaction.** Add `miab-install` preflight/apply/status/recover, empty-layout safeguards, trusted digest resolution, PV/config/bootstrap-secret creation, one-shot full fresh-install reconciliation, receipts, serving-pod startup, secure first-admin creation, secret removal, and postflight validation.
10. **Implement the host update transaction.** Add trusted release discovery/signature verification, compatibility planning, image pull/import, complete offline data reconciliation plus staged persistent config-generation promotion, verified pre-update backup, exact-digest rollout with read-only startup validation, postflight checks, durable receipts/history, and rollback-class enforcement without granting pod RBAC or registry secrets.
11. **Expand backup scope and implement restore Job command.** Add version metadata, quiescing, staging validation, same/one-back migration, ownership normalization, receipts, and rollback-safe promotion shared by update recovery.
12. **Add k3s/Kustomize deployment assets.** Implement PV/PVC, namespace, ConfigMap, Deployment, probes/security context/resources, fresh-install/restore/validation/reconciliation Jobs, and local-import/registry-digest workflows.
13. **Add CI and verification harnesses.** Build/lint/scan/render in ordinary CI; generate signed compatibility release metadata; run full k3s integration inside the podman `miab-test-host` harness so firewall/DNS/mail tests cannot affect shared runners or the development host.
14. **Run production-pilot qualification.** Execute fresh install, interrupted-install recovery, v76 restore, v75 restore, code/image update, every rollback class, node reboot, pod recreation, queued-mail durability, backup/restore, public protocol, fail2ban/firewall, and state-escape tests. Record exact host OS, k3s/image/source digests, release manifest, and receipts.
15. **Update existing operator/developer documentation surfaces.** Extend `README.md`, command `--help`, manifest examples, and existing API/UI text with prerequisites, initial setup, first user, update channels, code/image updates, restore, rollback, firewall recovery, limitations, and the future decomposition contract. Avoid touching the user-modified `CONTRIBUTING.md` unless separately resolved.

## Files to Modify

### Existing setup and configuration

- `setup/functions.sh` — setup phases, runtime detection, service abstraction, package guards, atomic helpers.
- `setup/start.sh`, new shared `setup/reconcile.sh`, `setup/preflight.sh`, `setup/questions.sh`, `setup/firstuser.sh` — one ordered host/container reconciliation pipeline, runtime modes, noninteractive validated inputs, and safe bootstrap handling.
- `setup/system.sh` — separate host mutation from container-local resolver/logging/fail2ban configuration; remove container apt/hostname/swap/resolver/UFW/systemd behavior.
- `setup/{ssl,dns,mail-postfix,mail-dovecot,mail-users,dkim,spamassassin,web,webmail,nextcloud,zpush,management,munin}.sh` — install/configure phase separation, generation-targeted config writes via `CONFIG_ROOT`, persistent state paths, deferred lifecycle, offline assets, and container-safe ownership.
- `setup/migrate.py` — layout-aware migration preconditions/receipts while preserving data migration numbering.
- `conf/fail2ban/jails.conf` and relevant nginx/service templates — new log/state paths and container lifecycle assumptions.

### Existing management/runtime code

- `management/utils.py` — platform/root/service-control helpers and atomic configuration utilities.
- `management/{backup,dns_update,web_update,ssl_certificates}.py` — supervisor-backed lifecycle and new state/backup contract.
- `management/{daemon,status_checks,auth,cli,mail_log}.py` — immutable update/reboot behavior, nft/cgroup checks, persistent API key/cache/log paths, container-aware messages.
- `management/templates/system-status.html` — replace package-update/reboot actions with immutable image guidance/status.
- `management/daily_tasks.sh`, `management/munin_start.sh` — locking and supervisor/container behavior.
- `tools/{dns_update,web_update,ssl_cleanup}` and backup/restore helpers — state-root and lifecycle consistency.
- `README.md`, `security.md`, API schema where behavior is exposed — operator/security/API contract updates.

### New implementation assets

- `container/Dockerfile` and `.dockerignore` — pinned multi-stage OCI build.
- `container/packages.lock`, Python lock/constraints, and verified asset manifest — auditable build inputs.
- `container/release-manifest.schema.json` and embedded build metadata — signed update compatibility, provenance, migration, and rollback contract.
- `container/bin/` — entrypoint, layout initializer, config renderer/validator, service adapter, probes, firewall, backup/restore/validation/migration commands.
- `container/supervisor/` and container-specific daemon/logrotate/rsyslog/fail2ban templates.
- `deploy/k3s/` — host preflight/install scripts; persistent firewall/SSH security assets; guarded SSH lockdown; root-only `miab-install` initial-setup and `miab-update` transaction commands, update-source/trust-policy and release-manifest schema, status/history handling, deployment renderer, and rollback recovery; plus Kustomize resources for namespace, PV/PVC, Deployment, configuration, restore, validation, and migration Jobs.
- `tests/container/` — layout, render, lifecycle, capability, firewall, migration, backup/restore, and state-escape tests; `tests/container/harness/` — the `miab-test-host` podman image, stubbed external peers, and boot-replay scripts providing the zero-host-mutation synthetic environment.
- `.github/workflows/container.yml` (or the repository’s selected CI equivalent) — registry-neutral build/test/scan/SBOM/provenance and optional publication.

Do not modify `.devin/skills/update-containerized/SKILL.md` or `CONTRIBUTING.md` while their current user changes are unresolved.

## Verification

Tiers: the static/unit, functional, backup/restore/upgrade/rollback, and firewall/security
checklists all run **synthetically** during development — exclusively inside local podman
containers, with **zero changes to the development host system**. The `miab-test-host`
harness (a podman image with systemd, sshd, fail2ban, nftables, and nested k3s in its own
network/mount namespaces) simulates the Ubuntu host; external DNS/ACME/SMTP peers are
stubbed and backups are fixtures. Known simulation gaps — a real kernel boot ordering,
true host reboot, genuine public DNS/routing — are approximated by container restarts and
service re-runs and are explicitly re-verified in the pilot. Nothing outside the
“Production pilot” subsection requires real public infrastructure; that subsection alone
is the final acceptance gate.

### Static and unit verification

- [ ] `bash -n` all changed/new shell scripts; run pinned ShellCheck with no unreviewed suppressions.
- [ ] Run Ruff and existing Python tests, plus unit tests for path resolution, runtime detection, service control, cgroup metrics, image-version API behavior, and restore validation.
- [ ] Render both IPv4-only and dual-stack configs and run `postfix check`, `doveconf`, `named-checkconf`, `nsd-checkconf`, `nginx -t`, PHP-FPM config test, supervisor config test, fail2ban config test, and `nft -c`.
- [ ] Assert that host `setup/start.sh`, container `fresh-install`, `offline-upgrade`, and `live-reconfigure` classify/invoke shared configure modules in the documented order, while `startup` is read-only validation only. Fail when a new upstream setup module or config write is not classified.
- [ ] Inventory every MIAB mutation of `/etc`, `/usr/local` application config, `/var/lib`, `/var/cache`, `/var/spool`, `/var/log`, and root home paths; assert each maps to a persisted `/home/miab` path or an explicitly ephemeral runtime path, while package/Kubernetes-owned `/etc` remains image/runtime-owned.
- [ ] Unit-test candidate-generation seeding from the target image defaults, secret/input carry-forward, manifest hashing, same-filesystem atomic promotion, failed-candidate isolation, bounded retention, and prior-generation rollback.
- [ ] Build twice from locked inputs where infrastructure permits and compare package/assets/SBOM; explain any unavoidable apt metadata variance.
- [ ] Scan image history and filesystem for bootstrap values, private keys, credentials, machine identity, package caches, and unexpected writable state.
- [ ] Render Kustomize and validate against the targeted Kubernetes API schema; server-side dry-run on the pinned k3s version.

### Functional container verification

- [ ] Run `miab-install preflight` against valid and invalid hosts/configurations; reject occupied ports, unsupported architecture, broken k3s/firewall, insufficient storage, untrusted image metadata, and unknown non-empty `/home/miab` before application mutation.
- [ ] From empty `/home/miab`, exercise interactive and noninteractive `miab-install apply`; prove the one-shot Job runs every fresh-install setup module without apt/git/application downloads or daemons, writes its receipt last, and creates all secrets/data only beneath the persistent contract.
- [ ] Inject failure at multiple fresh-install modules; verify no serving Deployment starts, `status` identifies the module, retry resumes idempotently, recovery never silently deletes generated state, and explicit clean reinitialization is guarded.
- [ ] Start the serving pod at the identical digest with `readOnlyRootFilesystem: true`; verify it validates and consumes the promoted configuration generation without rewriting it, securely create the first administrator without logging/persisting plaintext, remove the bootstrap Secret, promote a new persistent DNS/web generation, and reach Ready.
- [ ] Validate TCP/UDP DNS, SMTP 25/465/587, IMAP 993, POP 995, Sieve 4190, HTTP redirect, HTTPS/admin, Roundcube, Nextcloud DAV, Z-Push, Munin, API, cron, and local resolver/DNSSEC behavior.
- [ ] Add users/aliases/custom DNS/web content, provision/reload TLS, send and receive mail, train spam, and verify DKIM/DMARC/DANE/MTA-STS outputs.
- [ ] Kill each child process and verify supervisor behavior; test graceful reloads and SIGTERM shutdown without queue/database corruption.
- [ ] Recreate the pod and reboot the node; verify identities, keys, messages, contacts/calendars, queue, DNS serials, bans, metrics, logs, and settings survive.
- [ ] Queue mail while delivery is unavailable, recreate the pod/reboot the node, restore delivery, and prove the exact queued message is delivered once.
- [ ] Run `podman diff`/nested-containerd snapshot inspection after representative use and fail on non-allowlisted durable writes outside `/home/miab`.

### Backup, restore, upgrade, and rollback verification

- [ ] Complete and verify backups to each supported target class (file, rsync, S3-compatible, B2 as practical), including expanded state metadata.
- [ ] Restore a sanitized v76 host backup into an empty volume, validate data, start services, and run protocol/application checks.
- [ ] Restore a sanitized v75 host backup, execute v75→v76 MIAB/Nextcloud/Roundcube migrations offline, and run the same checks.
- [ ] Corrupt/truncate a staged SQLite DB, use an unsupported backup version, add an escaping symlink, and attempt restore while the pod holds the lock; each must fail before promotion.
- [ ] Verify `miab-update check` detects newer MIAB source and OS/package image releases from a configured signed channel, ignores mutable-tag drift, writes only non-secret status, and gives the control panel accurate installed/available digest and compatibility information.
- [ ] Reject unsigned/tampered or unsupported-schema manifests, unmet minimum-updater versions, wrong signer/issuer, digest-label mismatch, wrong architecture, unsupported skipped releases, incompatible layout ranges, missing provenance, concurrent restore/update, and unavailable or unverified pre-update backup before workload/data mutation; verify the separate signed node-tooling upgrade and rollback path.
- [ ] Apply a code-only `image-only` update with queued mail/data present; prove the image is pulled before downtime, the old pod is quiesced, the exact digest is deployed, postflight succeeds, queue/data survive, and receipts/history identify source and target commits.
- [ ] Apply a current-to-next release requiring compatibility work; verify the offline Job runs the complete new-release setup reconciliation in conventional order—not only numbered migrations—including Nextcloud/Roundcube and permissions/configuration steps, while package/download/start actions remain disabled.
- [ ] Start the new pod and prove read-only startup validates/uses the exact promoted generation without rewriting configuration or persistent databases/state; compare promoted schemas/config semantics with a conventional same-release `setup/start.sh` upgrade fixture.
- [ ] Verify update locking, embedded-versus-manifest metadata, database integrity, current/one-back compatibility, module-by-module receipts, and control-panel update status.
- [ ] Inject failures before reconciliation, after numbered migrations, at representative later setup modules (including Nextcloud/Roundcube), during rollout, and during postflight. Prove automatic old-digest restart only before persistent mutation, manifest-authorized image rollback for proven backward-compatible changes, and verified backup restore plus old digest for partial/non-backward-compatible reconciliation.
- [ ] Exercise explicit local `--image <digest>` update/import with the same validation/backup/receipt gates, without requiring a particular registry.

### Firewall and security verification

- [ ] Validate and atomically install the host `miab_host` baseline, then reboot before deploying MIAB; verify default-deny policy, required public ports, unrestricted-by-source SSH on the configured port, local `sudo k3s kubectl`, CNI/DNS/control-plane operation, and no changes to non-owned tables.
- [ ] Verify host SSH accepts both a valid password and a valid public key by default; repeated invalid authentication triggers only `miab_ssh_bans`, expires after the configured timeout, and survives host fail2ban restart according to its persisted DB.
- [ ] Verify no SSH daemon/package/listener or authorized-key store exists in the application container, public TCP/6443 is blocked, and pod administration succeeds through SSH-to-host plus local kubectl.
- [ ] Stop the MIAB pod and k3s separately and reboot the node; verify `miab_host`, host fail2ban/`miab_ssh_bans`, and host SSH remain available before the pod starts.
- [ ] Exercise application fail2ban against SMTP submission, IMAP/POP/Sieve, Roundcube, Nextcloud, and admin login; verify only `miab_dynamic` changes, bans expire correctly, and persisted active bans are restored after pod/node restart.
- [ ] Exercise `lock-down-ssh` dry-run, rejected unsafe inputs, timed automatic rollback, explicit confirmation from a second key-authenticated session, approved-versus-unapproved CIDRs, password rejection in key-only mode, idempotent reapplication, and `revert` restoring unrestricted password-and-key defaults.
- [ ] Validate separate emergency removal/recreation of `miab_dynamic` and `miab_ssh_bans`, plus host-baseline recovery; no operation may flush k3s or unrelated nftables state.
- [ ] Run all operations under the final capability list and runtime-default seccomp; document evidence for every retained capability.
- [ ] Confirm no Kubernetes API token, host root, Docker/containerd socket, PID namespace, cgroup mount, or `privileged` flag is present.
- [ ] Confirm service files and secrets have least-privilege UID/GID/modes and restore does not broaden them.

### Production pilot — final acceptance phase only

Deferred until every synthetic gate passes; this is the sole checklist requiring real
public infrastructure.

- [ ] Use a disposable public Ubuntu node with correct forward/reverse DNS and unblocked TCP/25.
- [ ] Run the existing remote DNS, SMTP, mail round-trip, TLS, and fail2ban tests plus new Kubernetes lifecycle tests.
- [ ] Observe at least one certificate cycle/dry-run, DNSSEC re-sign, nightly backup/status cycle, Nextcloud cron cycle, log rotation, and queued delivery retry.
- [ ] Record the exact host OS, k3s version, image digest, SBOM/provenance, manifest digest, test results, known warnings, and rollback point before declaring the milestone releasable.

## Acceptance Criteria

1. On a fresh Ubuntu 22.04+ amd64 host, `miab-install` preflights the node, initializes an empty `/home/miab` through a one-shot full setup-reconciliation Job, securely creates the first administrator, removes bootstrap credentials, and reaches Ready using one non-privileged-but-root serving container and no sidecars.
2. Every MIAB feature listed in scope works; package and MIAB source-code updates use the trusted host-side immutable-image transaction, while host reboot remains external.
3. Deleting/recreating the pod and rebooting the node loses no application state, queued mail, keys, logs, operational history, or configuration; all such state is demonstrably under `/home/miab`.
4. No first-boot package download or apt mutation occurs, and no instance secret exists in the image or source repository.
5. The final pod is `privileged: false`, has no `SYS_ADMIN`, uses a documented minimal capability list, and does not mount host root/runtime sockets or a Kubernetes token.
6. From boot, `miab_host` exposes SSH from any source by default while host fail2ban maintains only `miab_ssh_bans`; the pod maintains only `miab_dynamic` application bans. All layers preserve k3s/unrelated tables, and the optional guarded script demonstrably converts SSH to approved-CIDR/key-only mode and safely reverts.
7. Same-release and immediately previous-release backups restore through the offline Job and pass integrity/application checks; unsupported versions fail before changing live state.
8. `miab-update check|plan|apply|status|rollback` handles MIAB code and OS/package releases by trusted digest, requires verified backup, runs the new release’s complete setup/configure reconciliation against persistent state with parity to conventional `setup/start.sh`, leaves module-level receipts, and demonstrates image-only and restore-required rollback.
9. Backup, restore, explicit uninstall-with-data-retention, and local-image update paths are exercised successfully.
10. CI builds/scans/validates a registry-neutral amd64 image and can optionally publish a signed digest plus compatibility manifest, SBOM, and provenance; deployment and update history are pinned by digest.
11. Host administration is proven through host OpenSSH plus local `sudo k3s kubectl`; default password and key authentication work with host fail2ban, optional CIDR/key-only hardening and rollback work, the application container has no SSH service, public Kubernetes API access is blocked, and SSH remains usable during pod/k3s failure.
12. Production-pilot public DNS, mail, TLS, web/groupware, firewall, update, rollback, restart, reboot, and state-escape gates all pass.

## Risks and Considerations

- **Host baseline lifecycle:** the persistent host nftables configuration is node/platform state outside `/home/miab` and must be upgraded, validated, and rolled back with k3s node bootstrap. A provider or physical console remains a production prerequisite for baseline mistakes or lost host credentials.
- **Default SSH exposure:** password-capable SSH from unrestricted source addresses is intentionally less restrictive than CIDR/key-only access. Host fail2ban reduces online guessing but does not replace strong passwords, timely OpenSSH updates, MFA/bastion controls, or the optional lockdown script.
- **Dynamic-ban restoration windows:** host SSH bans restore with host fail2ban independently of k3s; application bans restore only after the pod starts. Static default-deny policy is continuous throughout.
- **Host-network blast radius:** `NET_ADMIN` in a host-network pod can technically alter host networking even though code is designed to touch only `miab_dynamic`. Strict command construction, table-name assertions, atomic validation, no arbitrary rule API, and tests proving `miab_host`, `miab_ssh_bans`, and k3s tables remain unchanged are mandatory until application banning is extracted to a node security component.
- **No HA/scaling yet:** local PV, SQLite, Maildir, Postfix queue, fixed host ports, and one recursive/authoritative DNS stack require exactly one pod on one node. Kubernetes supplies lifecycle management, not horizontal scalability in milestone one.
- **Node failure:** `/home/miab` on local disk does not fail over. External encrypted backups remain mandatory; later node separation needs an explicit storage design.
- **Persistent configuration completeness:** enforcing `readOnlyRootFilesystem: true` will expose undocumented writes by Debian services or bundled applications. Every required write must be classified as persistent under `/home/miab` or runtime-only under `/run`/`/tmp`; weakening the read-only root is not an accepted workaround.
- **Monitoring semantics:** Munin inside the pod sees a mixture of host-network, cgroup, and container filesystem data. UI wording and plugins must not misrepresent container metrics as complete host observability.
- **Version compatibility:** this plan deliberately guarantees only current and one-back restore/update. Every future release must update and test the compatibility matrix before signed release publication; skipping releases is refused unless a future manifest explicitly proves a tested path.
- **Update trust and authority:** `miab-update` holds registry/update-source access and root/k3s authority on the node. Root-only files, pinned signer policy, immutable digests, no pod RBAC, minimal logged secrets, and strict manifest/image cross-checking are required.
- **Update downtime and rollback:** the monolith must stop during stateful reconciliation. Queue persistence limits mail loss, but service interruption remains. Non-backward-compatible or partially completed setup rollback depends on a fresh verified backup and is slower than changing an image digest.
- **Initial-install partial state:** key generation and database/application initialization span many modules and cannot be globally atomic. The completion marker must be written last; failed installs remain non-serving, preserve evidence/state, and require explicit idempotent resume or guarded clean reinitialization.
- **Reconciliation breadth/idempotency:** current setup scripts mix package installation, persistent migrations, generated configuration, and service restarts. Splitting phases incorrectly could omit compatibility work or repeat destructive steps. Shared ordering, per-module classification, fresh-install/offline-upgrade/live-reconfigure idempotency tests, read-only startup validation, generation receipts, and conventional-upgrade parity fixtures are release blockers.
- **Upstream merge cost:** phase-splitting many setup scripts creates a broad integration surface. Keep host defaults unchanged, centralize container branches, and extend the existing semantic upstream-merge review to package, path, service, port, permission, startup, migration, and release-manifest changes.
- **External mail constraints:** Kubernetes does not solve PTR records, port-25 blocking, IP reputation, provider filtering, or public DNS delegation. Production-pilot qualification requires real infrastructure satisfying these prerequisites.
- **Pre-existing worktree changes:** implementation must not overwrite the user’s current modifications to the update skill and contributing guide.
