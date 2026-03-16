---
name: commit-push
description: Commit staged/unstaged changes and push to origin with an Angular-style commit message. Use when the user says "commit and push", "commit this", "/commit-push", or after completing work that should be committed. Accepts optional file arguments to scope the commit.
---

# Commit and Push

## Workflow

1. Run `git status` (never use `-uall`), `git diff HEAD`, and `git log --oneline -5` in parallel.
2. Identify which files to stage:
   - If the user specified files (e.g., `@file1 @file2`), stage only those.
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
