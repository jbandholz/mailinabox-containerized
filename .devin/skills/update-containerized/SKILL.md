---
name: update-containerized
description: Synchronize trunk, review its integration into containerized, and publish after approval
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
10. Run `git diff --cached --check`. Show `git status --short`, `git diff --cached --stat`, and all commits that will be published with `git log --oneline origin/containerized..containerized`. If a merge is prepared, state that the proposed commit message is `Merge trunk into containerized`. If no merge is needed, state that approval will publish the existing local-only commits without creating a commit.
11. Pause with a structured single-choice question offering **Commit and push** and **Abort**. Do not commit or push until the user explicitly selects **Commit and push**.
12. If the user selects **Abort**, run `git merge --abort` only when a merge is in progress, then report that nothing was committed or pushed and stop. Treat a skipped or ambiguous response as **Abort**.
13. If approved and a merge is in progress, commit it with exactly:

    ```text
    Merge trunk into containerized

    Generated with [Devin](https://devin.ai)

    Co-Authored-By: Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>
    ```

14. Push with `git push origin containerized`. Never force-push. If the push fails, retain the local commit and report that publication is pending; do not reset or rewrite history.
15. Fetch `origin/containerized`, verify it resolves to the same commit as local `containerized`, verify the working tree is clean, and verify `containerized` remains checked out. Report whether trunk was synchronized, whether a merge commit was created, the published commit, and the final branch.
