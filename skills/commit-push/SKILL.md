---
name: commit-push
description: Commit staged/unstaged changes and push to origin with an Angular-style commit message. By default, auto-detects when changes span multiple cohesive scopes and proposes splitting them into multiple commits; user can override with `--single`/`-1` or natural-language phrases like "commit as one". Use when the user says "commit and push", "commit this", "/commit-push", or after completing work that should be committed. Accepts optional file arguments to scope the commit, or interactive selection to pick files from the working tree. Also use when the user wants to choose, select, or pick which changed files to include in a commit.
---

# Commit and Push

## Workflow

1. Run `git status` (never use `-uall`), `git diff HEAD`, and `git log --oneline -5` in parallel.

2. Determine scoping mode by inspecting the invocation in this order; first match wins:
   - **Single-commit override**: if the invocation contains `--single`, `-1`, or any of these phrases — "single commit", "one commit", "as one", "all together", "commit this as one", "as a single commit" — treat **all** changed files as one group and skip auto-detect (jump to step 5 with a single group). Acknowledge the override in your reply so the user sees it was honored.
   - **`--select` / `-i`**: enter **interactive selection** (useful when many files are changed but only some belong in this commit):
     1. Run `git status --porcelain` to list all changed, staged, and untracked files.
     2. Present a numbered list via `AskUserQuestion` (use AskUserQuestion rather than a freeform text prompt to ensure structured, parseable input), showing each file with its git status indicator (M, A, D, ??), e.g.:
        ```text
        Select files to include in this commit:
         1. M  src/auth/login.ts
         2. M  src/auth/session.ts
         3. ?? tests/new_test.py
        Type the numbers to include (e.g. 1,3,5 or 1-3,5):
        ```
     3. Parse the user's response (comma-separated numbers, dash ranges). If the selection is empty or all numbers are invalid, abort the commit and explain why. If some numbers are out of range, warn and use only the valid ones.
     4. Run `git reset HEAD` to clear any pre-existing staged files, then stage only the selected files. This ensures that only the user's chosen files end up in the commit. Note: this discards any partial staging (e.g., from `git add -p`) — warn the user if the index already has staged changes before resetting.
     5. Skip auto-detect; jump to step 5 with the selected files as a single group.
   - **Explicit file args** (e.g., `@file1 @file2`): stage only those files. (If both `--select` and explicit files are passed, treat them as mutually exclusive: warn the user about the conflict and use the explicit files, skipping interactive selection.) Skip auto-detect; jump to step 5 with those files as a single group.
   - **Default — none of the above**: continue to step 3 (auto-detect).

3. **Auto-detect cohesive groups**. Group all changed files (staged, unstaged, untracked) by inferred Angular scope. Apply rules in order; first match wins per file:
   1. **Skill subdirectory**: files under `skills/<name>/...` group by `<name>` (e.g., `spring-init`, `commit-push`). Each skill is its own scope.
   2. **Top-level directory**: files under any other top-level `<dir>/...` group by `<dir>` (e.g., `hooks`, `tests`, `docs`).
   3. **Root files** (no directory prefix, or under `.github/`): one group; infer scope from filename — `Makefile` → `build`, `README.md` → `docs`, files under `.github/...` → `ci`, others → `chore`.
   - Never stage files that likely contain secrets (`.env`, credentials, etc.) — exclude them from groups before counting.
   - If only **1 group** results → silently proceed to step 5 with that group as the single commit. Do **not** show a split proposal.
   - If **2+ groups** → continue to step 4 (proposal).

4. **Propose the split** via `AskUserQuestion`. The prompt must:
   - Preview each proposed commit with: its scope, the files it contains (with M/A/D/?? indicators, mirroring the `--select` idiom in step 2), and a draft `type(scope): subject` line (infer `type` from the diff: new behavior → `feat`, bugfix → `fix`, tests-only → `test`, docs-only → `docs`, config/build/CI → `chore`/`build`/`ci`; if mixed, pick the dominant type — do **not** subdivide further).
   - Include a **cap warning** if there are >5 groups: "This change spans N groups, which is unusually scattered. Consider combining into a single commit, or adjusting the groupings." Surface "Combine" and "Adjust groupings" prominently in this case.
   - Offer exactly these 3 options:
     1. `Yes — create N commits as proposed`
     2. `Combine into a single commit`
     3. `Adjust groupings (switch to interactive --select)`
   - Routing:
     - **Yes** → continue to step 5 with the proposed groups in proposal order.
     - **Combine** → continue to step 5 with all changes as one group.
     - **Adjust groupings** → restart at step 2's `--select` sub-bullet (full interactive picker).

5. **Per-commit loop**. For each group (in order), do the following — each iteration is independent and creates a NEW commit:
   1. Clear the index of any prior-iteration staging: `git reset HEAD`. Then stage only this group's files via `git add <file>...`. Prefer explicit file args; never `git add -A` or `git add .`.
   2. Draft an Angular-style commit message:
      - **Format:** `type(scope): subject` with a body of bullet-point details.
      - **Types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `style`, `build`, `ci`, `chore`.
      - **Subject:** lowercase, imperative, no trailing period.
      - **Body:** each bullet starts with `"- "`, describing a concrete change.
      - Match the style of recent commits in the repo.
      - Always pass the message via a HEREDOC.
   3. Run `git commit` (create a NEW commit, never `--amend`).
   4. **If a pre-commit hook fails** for this iteration: run the appropriate fixer (e.g., formatter, linter), re-stage **the same group's files** (do not pull in files from already-committed earlier groups), and create a NEW commit. Never use `--amend` here — earlier iterations' commits must be preserved exactly.

6. After **all** commits in the loop succeed, push to origin on the current branch: `git push`. (Single push for the whole batch, regardless of how many commits were created.)

7. Report **all** commit SHAs created in this run, one per line.
