---
name: update-containerized
description: Synchronize trunk, semantically review its integration into containerized, and publish after approval
triggers:
  - user
---

Follow this workflow exactly. Never force-push, reset, rebase, stash, discard changes, auto-resolve conflicts, or publish before explicit approval.

1. As the first repository operation, run `git status --porcelain --untracked-files=normal`. Do not fetch, switch branches, invoke another skill, merge, commit, or push before this check.
2. If the output is non-empty, run `git status --short`, report that the working tree contains changes that must be committed or otherwise resolved first, and stop. Do not alter the changes.
3. After the clean-tree gate passes, verify that HEAD is attached, Git author identity is configured, the `origin` and `upstream` remotes exist, and local `trunk` and `containerized` branches exist. Stop without mutations if a prerequisite is missing.
4. Switch to `containerized` if it is not already checked out.
5. Fetch `origin/trunk`, `origin/containerized`, and `upstream/main` into their remote-tracking references without merging.
6. Compare local `trunk`, `origin/trunk`, and `upstream/main`. If all three do not resolve to the same commit, invoke the `/sync-upstream` project skill. Stop if it fails. Then verify that all three references resolve to the same commit before continuing.
7. Require `origin/containerized` to be an ancestor of local `containerized`. If it is not, report that GitHub is ahead or divergent and stop without pulling, resetting, rebasing, committing, or pushing.
8. Record the current local and remote `containerized` commits. Show commits in `containerized..trunk` and `origin/containerized..containerized`.
9. If `trunk` is not already an ancestor of `containerized`, run `git merge --no-commit --no-ff trunk`. If the merge conflicts, immediately run `git merge --abort`, report the conflict, and stop without committing or pushing. If `trunk` is already an ancestor, do not create an empty merge.
10. Run `git diff --cached --check`. Show `git status --short`, `git diff --cached --stat`, and all commits that will be published with `git log --oneline origin/containerized..containerized`.
11. If a merge is prepared, perform a semantic review before offering commit approval:
    - Read every incoming commit in `containerized..trunk` and inspect the complete staged merge with `git diff --cached`.
    - For each changed interface, function signature, file path, service, command, package, port, permission, environment variable, storage path, or startup assumption, trace affected callers, references, configuration, and containerization-specific behavior.
    - Look specifically for changes that merge cleanly as text but conflict logically with Podman, Kubernetes, container builds, manifests, mounted storage, networking, health checks, or service lifecycle handling.
    - Discover and run the narrowest relevant syntax checks, tests, linters, or configuration validation supported by the affected files. Do not run a check expected to rewrite tracked files.
    - Report blocking problems, recommended fixups, unresolved risks, and every verification command with its result. Do not claim the merge is semantically safe merely because Git merged it without conflicts.
12. If the semantic review finds a blocking problem or required fixup, pause with a structured single-choice question offering **Apply fixups**, **Abort merge**, and **Leave prepared**. Do not edit, commit, or push before this choice.
13. Handle the review choice as follows:
    - **Apply fixups** — make only the approved fixes in the still-uncommitted merge, stage them, and repeat steps 10–12 until no blocking findings remain. Include the fixups in the semantic review and final staged diff.
    - **Abort merge** — run `git merge --abort`, report that nothing was committed or pushed, and stop.
    - **Leave prepared** — stop with the uncommitted merge intact for manual work and report that the working tree is intentionally not clean. Do not commit or push.
    Treat a skipped or ambiguous response as **Leave prepared**.
14. When no blocking findings remain, show the final staged diff statistics, review findings, unresolved risks, verification results, and the proposed commit message `Merge trunk into containerized`. If no merge was needed, state that approval will publish the existing local-only commits without creating a commit.
15. Pause with a structured single-choice question offering **Commit and push**, **Abort**, and, when a merge is prepared, **Leave prepared**. Do not commit or push until the user explicitly selects **Commit and push**.
16. If the user selects **Abort**, run `git merge --abort` only when a merge is in progress, then report that nothing was committed or pushed and stop. If the user selects **Leave prepared**, stop with the merge intact and do not commit or push. Treat a skipped or ambiguous response as **Abort** when no merge is prepared and as **Leave prepared** when a merge is prepared.
17. If approved and a merge is in progress, commit it with exactly:

    ```text
    Merge trunk into containerized

    Generated with [Devin](https://devin.ai)

    Co-Authored-By: Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>
    ```

18. Push with `git push origin containerized`. Never force-push. If the push fails, retain the local commit and report that publication is pending; do not reset or rewrite history.
19. Fetch `origin/containerized`, verify it resolves to the same commit as local `containerized`, verify the working tree is clean, and verify `containerized` remains checked out. Report whether trunk was synchronized, whether a merge commit was created, whether semantic fixups were included, the published commit, and the final branch.
