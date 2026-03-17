---
name: commit-push
description: Commit staged/unstaged changes and push to origin with an Angular-style commit message. Use when the user says "commit and push", "commit this", "/commit-push", or after completing work that should be committed. Accepts optional file arguments to scope the commit, or interactive selection to pick files from the working tree. Also use when the user wants to choose, select, or pick which changed files to include in a commit.
---

# Commit and Push

## Workflow

1. Run `git status` (never use `-uall`), `git diff HEAD`, and `git log --oneline -5` in parallel.
2. Identify which files to stage:
   - If the user passed `--select` or `-i`: enter **interactive selection** (useful when many files are changed but only some belong in this commit):
     1. Run `git status --porcelain` to list all changed, staged, and untracked files.
     2. Present a numbered list via `AskUserQuestion` (use AskUserQuestion rather than a freeform text prompt to ensure structured, parseable input), showing each file with its git status indicator (M, A, D, ??), e.g.:
        ```
        Select files to include in this commit:
         1. M  src/auth/login.ts
         2. M  src/auth/session.ts
         3. ?? tests/new_test.py
        Type the numbers to include (e.g. 1,3,5 or 1-3,5):
        ```
     3. Parse the user's response (comma-separated numbers, dash ranges). If the selection is empty or all numbers are invalid, abort the commit and explain why. If some numbers are out of range, warn and use only the valid ones.
     4. Run `git reset HEAD` to clear any pre-existing staged files, then stage only the selected files. This ensures that only the user's chosen files end up in the commit.
   - If the user specified files (e.g., `@file1 @file2`), stage only those. (Note: if both `--select` and explicit files are passed, `--select` takes precedence — the interactive list will still show all changed files.)
   - Otherwise, stage all modified/new files relevant to the current work. Prefer `git add <file>...` over `git add -A`. Never stage files that likely contain secrets (`.env`, credentials, etc.).
3. Draft an Angular-style commit message:
   - **Format:** `type(scope): subject` with a body of bullet-point details.
   - **Types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `style`, `build`, `ci`.
   - **Subject:** lowercase, imperative, no trailing period.
   - **Body:** each bullet starts with `"- "`, describing a concrete change.
   - Match the style of recent commits in the repo.
   - Always pass the message via a HEREDOC.
4. Run `git add` and `git commit` (create a NEW commit, never amend).
5. If a pre-commit hook fails, run the appropriate fixer (e.g., formatter, linter), re-stage, and create a NEW commit.
6. Push to origin on the current branch: `git push`.
7. Report the commit SHA.
