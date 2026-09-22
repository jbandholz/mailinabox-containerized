# Megaplan Chunks — Implementation Order

This directory decomposes `../megaplan-single-container.md` into self-contained work chunks.
Required reading per chunk: `../shared-context.md` (authoritative contract) + the chunk file
itself; megaplan citations in each chunk are optional deep-dives. To execute chunks 01–17
automatically via subagents, see `../ORCHESTRATOR.md`.

## Rules for every chunk

The full contract lives in `../shared-context.md` — read it before starting any chunk.
The non-negotiables in short:

- Host installer parity: `setup/start.sh` keeps working unchanged; container behavior is additive.
- Never modify `.devin/skills/update-containerized/SKILL.md` or `CONTRIBUTING.md`.
- No apt/downloads/daemon lifecycle at container runtime; no secrets in image layers.
- All durable writes under `/home/miab`; only `/run`/`/tmp` is ephemeral.
- `bash -n`, ShellCheck, Ruff, and pytest targets for everything touched.
- Minimal diffs: implement only what the chunk requires; report unrelated issues instead
  of folding them into the commit.

## Chunk order and dependencies

| # | Chunk | Depends on |
|---|-------|------------|
| 01 | Contract tests & fixtures | 02b (for golden capture only) |
| 02 | Platform/state abstractions | 01 |
| 02b | Synthetic test harness (podman `miab-test-host`) | — |
| 03 | Shared setup orchestrator & phase infra | 02 |
| 04 | Setup split: system/ssl/dns | 03 |
| 05 | Setup split: mail stack | 03 |
| 06 | Setup split: web/apps/migrate | 03 |
| 07 | OCI image build | 04, 05, 06 |
| 08 | Persistent config generations | 03 (07 soft) |
| 09 | Supervision, entrypoint, probes | 07, 08 |
| 10 | Service-lifecycle refactor (mgmt callers) | 02 |
| 11 | Split firewall/fail2ban + SSH lockdown | 02, 04 |
| 12 | Container-aware management API/UI | 02, 09 |
| 13 | k3s/Kustomize deployment assets | 07, 09 |
| 14 | `miab-install` host transaction | 08, 13 |
| 15 | `miab-update` host transaction | 08, 13, 14 |
| 16 | Backup expansion + restore Job | 10, 13 |
| 17 | CI pipeline & release metadata | 07, 13 (others as gates) |
| 18 | Production pilot + docs | all |

Chunks on the same tier may run in parallel if they touch disjoint files; 04/05/06 are the
main parallelizable set. 11 and 12 are also largely independent of each other.

## Verification gates

Each chunk lists its own checks. During development, all verification is **synthetic** and
runs **inside local podman containers only — no changes to the development host system**
(no host installs, no host firewall/fail2ban/sshd/k3s, no host `/home/miab`). Chunk 02b
builds the `miab-test-host` podman harness that simulates the Ubuntu host (systemd, sshd,
fail2ban, nftables, nested k3s) in its own namespaces; external DNS/ACME/SMTP peers are
stubbed and backups are fixtures. True kernel boot/reboot ordering is approximated by
container restart + service replay and re-verified in the pilot.

Chunk 18 alone requires real public infrastructure — it is the final acceptance gate and
must not be started until every synthetic gate passes. CI runs the same podman harness so
firewall/mail/DNS tests never touch shared runners.
