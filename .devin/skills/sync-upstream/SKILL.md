---
name: sync-upstream
description: Synchronize upstream Mail-in-a-Box changes through local trunk and publish origin/trunk
allowed-tools:
  - exec
triggers:
  - user
---

Execute `tools/sync-upstream.sh` from the repository root.

Do not bypass or weaken the script's clean-tree, ancestry, fast-forward, branch-restoration, or non-force-push safeguards. Do not substitute a different sequence of Git commands if the script refuses to continue.

Report whether local `trunk` changed, whether publication to `origin/trunk` succeeded, and which branch is checked out when the command finishes. If the script fails, report its error and stop without attempting corrective Git mutations.
