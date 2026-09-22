# Orchestrator Plan — MIAB Containerization (Chunks 01–17)

Execute every chunk in `plans/chunks/` **except chunk 18** (production pilot — requires a
real public node and human sign-off). One orchestrator session drives; work is delegated to
subagents per chunk; the orchestrator reviews, verifies, and commits.

## Operating rules

- Run in Normal mode (or `devin --sandbox` if configured). Stay in the repo workspace;
  the only sanctioned write outside it is the live plan file in `~/.devin/plans/`.
- **Never modify the host system** — no installs, no firewall/service changes. All
  synthetic testing runs inside the podman `miab-test-host` harness (chunk 02b).
- **Subagents never commit.** The orchestrator reviews each diff, runs the chunk's
  verification checklist itself, then commits.
- Commit per chunk on `containerized`. **Never push to GitHub or any remote** — local
  commits only. Never force-push, reset, rebase, or stash either; any of those requires
  stopping and asking the user (per `.devin/skills/update-containerized/SKILL.md`).
- Never touch `CONTRIBUTING.md` or `.devin/skills/update-containerized/SKILL.md`.
- The conventional host installer must keep working at every checkpoint — contract tests
  are the gate.
- Track progress in `plans/chunks/STATUS.md` (created at kickoff): one line per chunk —
  `pending | in-progress | done | blocked` + commit hash + notes. Update after every
  chunk so a crashed session can resume.

## Preflight (orchestrator, once)

- [ ] `podman --version` works; `podman run --rm ubuntu:22.04 true` succeeds; privileged
      nested containers allowed (`podman info` — check cgroup v2, userns).
- [ ] `git status` clean except pre-existing user changes (CONTRIBUTING.md, skill file)
      and the new `plans/` dir.
- [ ] `git worktree` available; disk headroom for several OCI image builds.
- [ ] Record baseline: `git rev-parse HEAD`, `pytest` baseline result.
- If podman is missing or nested containers can't run: **stop and ask the user** — do not
  install anything on the host.

## Standard subagent task template

```
Execute chunk NN of the MIAB containerization megaplan.

Read first: plans/shared-context.md (authoritative contract), plans/chunks/README.md
(process rules), plans/chunks/NN-*.md (your task). The megaplan is optional deep-dive
only. Work in <worktree path>.

Implement the chunk scope. Do NOT commit. Do NOT modify CONTRIBUTING.md or
.devin/skills/update-containerized/SKILL.md. All durable-path logic must honor the
/home/miab contract (CONFIG_ROOT/STORAGE_ROOT/STATE_ROOT). No apt/downloads/daemon
lifecycle at container runtime. Host installer semantics unchanged.

When done, report: files created/modified, each verification checklist item with
pass/fail evidence, deviations from the chunk spec, and open questions.
```

Use `subagent_general`. Foreground for sequential chunks; background only for parallel
tiers and only after the session has the tool approvals they need (or under `--sandbox`).

## Parallel-tier worktree strategy

```
git worktree add ../miab-wt-04 -b chunk-04
git worktree add ../miab-wt-05 -b chunk-05
git worktree add ../miab-wt-06 -b chunk-06
```

Each background subagent works only in its worktree. Orchestrator merges into
`containerized` one at a time, resolving conflicts in shared files (`setup/functions.sh`,
module manifest, test dirs). Re-run the merged tier's combined checklist after merging.

## Stage schedule

| Stage | Chunks | Mode | Gate to advance |
|-------|--------|------|-----------------|
| 0 | 02b harness | foreground | harness builds; zero-host-mutation check passes |
| 1 | 01 contracts | foreground | static contracts pass; golden capture runs in harness |
| 2 | 02 abstractions | foreground | unit tests green; host parity |
| 3 | 03 orchestrator | foreground | module-order parity; configure-phase guards proven |
| 4 | 04, 05, 06 | 3 background, worktrees | merged tree: all three checklists + suite green |
| 5 | 07 → 08 → 09 | sequential foreground | image builds clean; generations promote atomically; pod boots in harness |
| 6 | 10, 11 | 2 background, worktrees; then 12 foreground | adapter coverage; nft/fail2ban/lockdown checks in harness; API unit tests |
| 7 | 13 → 14 | sequential; 15, 16 parallel background worktrees | manifests validate; install/update/restore e2e in harness |
| 8 | 17 CI | foreground | pipeline definition valid; dry-run gates pass locally |

Chunk 12 depends on 09 (probes/entrypoint); chunk 15 depends on 14; chunk 16 needs 10+13.

## Per-chunk completion ritual

1. Read subagent's report; `git diff` review of every file.
2. Re-run the chunk's verification checklist personally (don't trust the report alone).
3. Run repo-wide `pytest tests/` + `bash -n` on touched scripts + ShellCheck/Ruff.
4. Keep the commit minimal: stage only files the chunk required; split or reject any
   unrelated changes the subagent included; report (don't commit) discovered side issues.
5. Update `STATUS.md`; commit with message `chunk NN: <title>` per repo commit style.

## Stop-and-ask triggers

- Any verification item fails after two fix attempts.
- A chunk requires real external infra (registry creds, public DNS, live CA) — mark it
  `blocked`, note what's stubbed, continue if a documented stub exists; else escalate.
- Ambiguity/conflict between chunk spec and megaplan, or a needed host change.
- Anything needing push, force-push, branch surgery, or upstream sync.
- Background subagent denied a required tool — resume it foreground or pre-approve.

## Definition of done (orchestrator scope)

- `STATUS.md` shows chunks 01–17 `done` with commit hashes.
- Full synthetic suite green inside the harness; host system provably untouched.
- `plans/` committed; handoff note for chunk 18 listing exactly which gates remain
  (real-node pilot checklist from megaplan §Production pilot).

## Kickoff prompt (for the user to start the orchestrator session)

```
Execute plans/ORCHESTRATOR.md. Begin with preflight, then Stage 0 (chunk 02b).
Use subagents per the plan; commit per chunk; stop-and-ask on the listed triggers.
Do not start chunk 18.
```
