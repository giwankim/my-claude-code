---
name: commit-push
description: Commit staged/unstaged changes and push to origin with an Angular-style commit message. By default, auto-detects when changes span multiple cohesive scopes and proposes splitting them into multiple commits; user can override with `--single`/`-1` or natural-language phrases like "commit as one". File scoping (explicit `@file` args, `--select` interactive picker) and secret-file filtering apply on every path, including the override. Use when the user says "commit and push", "commit this", "/commit-push", or after completing work that should be committed. Accepts optional file arguments to scope the commit, or interactive selection to pick files from the working tree. Also use when the user wants to choose, select, or pick which changed files to include in a commit.
---

# Commit and Push

## Workflow

1. Run `git status` (never use `-uall`), `git diff HEAD`, and `git log --oneline -5` in parallel.

2. **Pre-flight**: determine the candidate file set, apply the secret filter, and pick a commit-count mode. These three concerns are independent: file scoping decides *which files are eligible*; the secret filter removes risky files regardless of scoping; commit-count mode decides *how many commits* to produce. Keeping them separate prevents the override from accidentally bypassing protections.

   **a) Candidate file set** (files eligible for committing):
   - **Explicit file args** (e.g., `@file1 @file2`): candidate set = those files.
   - **`--select` / `-i`**: interactive picker. Run `git status --porcelain`, then present a numbered list via `AskUserQuestion` with each file's M/A/D/?? indicator, e.g.:
     ```text
     Select files to include:
      1. M  src/auth/login.ts
      2. M  src/auth/session.ts
      3. ?? tests/new_test.py
     Type the numbers to include (e.g. 1,3,5 or 1-3,5):
     ```
     Parse comma-separated numbers and dash ranges. Empty/all-invalid selection → abort and explain. Out-of-range numbers → warn and use only the valid ones. Picked files = candidate set.
   - **Otherwise**: candidate set = all changed files in the working tree (modified, staged, untracked).
   - **Conflict warning + precedence**: if both `--select` and explicit files are passed, warn and use the explicit files. When multiple file-scoping signals are present, precedence is: explicit `@file` args > `--select`/`-i` > the default "all changed files" path.
   - **Pre-existing staging warning**: if `git status` shows files already staged (e.g., from `git add -p`), warn before proceeding — the per-commit loop in step 5 resets the index before staging each group, which discards any partial staging.

   **b) Secret filter** (applied to the candidate set on **every** path, including when `--single` or explicit `@file` args are used):
   - Exclude files that likely contain secrets: `.env`/`.env.*`, private keys (`*.pem`, `*.key`, `*.p12`, `id_rsa*`, `id_dsa*`, `id_ecdsa*`, `id_ed25519*` — the `.pub` siblings are public and OK), credential files (`credentials*`, `*credentials.json`, `aws_credentials*`), and any file whose name contains `token` or `secret` unless it's clearly a safe fixture (e.g., a test data file the user obviously meant to commit).
   - When in doubt, exclude and tell the user.
   - List any excluded files explicitly in your reply so the user can re-include them with `--select` or explicit args if the exclusion was a false positive.

   **c) Commit-count mode**:
   - **Single-commit mode** if any of the following:
     - Invocation contains `--single`, `-1`, or one of "single commit", "one commit", "as one", "all together", "commit this as one", "as a single commit" → acknowledge the override in your reply.
     - The user used `--select` or explicit `@file` args (manual scoping signals "this is one commit's worth of files"; preserves backward-compat with how the picker has always worked).
   - **Auto-detect mode** otherwise.

   In single-commit mode: skip steps 3–4 entirely; jump to step 5 with the secret-filtered candidate set as one group.

3. **Auto-detect cohesive groups** in the candidate set. Apply rules in order; first match wins per file:
   1. **Skill subdirectory**: files under `skills/<name>/...` group by `<name>` (e.g., `spring-init`, `commit-push`).
   2. **Top-level directory**: files under any other top-level `<dir>/...` group by `<dir>` (e.g., `hooks`, `docs`).
   3. **Root files** (no directory prefix, or under `.github/`): one group; infer scope from filename — `Makefile` → `build`, `README.md` → `docs`, files under `.github/...` → `ci`, others → `chore`.

   **Then refine for tests**: scan files matching `tests/...`, `test/...`, `__tests__/...`, or `test_*.{ext}` / `*_test.{ext}` patterns. Re-attribute each test file to a non-test scope when possible (impl + its tests should be one cohesive commit, not two):
   a. **Path-component match**: `tests/<scope>/...` (e.g., `tests/spring-init/...` → `spring-init`), or filename containing a scope keyword that exists in the candidate set (e.g., `tests/test_hooks.sh` when `hooks` is a non-test scope → `hooks`).
   b. **Sole non-test scope**: if exactly one non-test scope exists in the candidate set, attribute all unmatched test files to it.
   c. **Otherwise**: leave unmatched test files in their own `tests` group.

   - If only 1 group → silently jump to step 5.
   - If 2+ groups → continue to step 4.

4. **Propose the split** via `AskUserQuestion`. The prompt must:
   - Preview each proposed commit with: scope, files (M/A/D/?? indicators), and a draft `type(scope): subject` (infer `type` from the diff: new behavior → `feat`, bugfix → `fix`, tests-only → `test`, docs-only → `docs`, config/build/CI → `chore`/`build`/`ci`; if mixed within a group, pick the dominant type — do **not** subdivide further).
   - Include a **cap warning** if there are >5 groups: "This change spans N groups, which is unusually scattered. Consider combining or adjusting groupings." Surface the Combine and Adjust options prominently.
   - Offer exactly these 3 options:
     1. `Yes — create N commits as proposed`
     2. `Combine into a single commit`
     3. `Adjust groupings (custom)`
   - Routing:
     - **Yes** → step 5 with the proposed groups in order.
     - **Combine** → step 5 with all candidate files as one group.
     - **Adjust groupings** → step 4b.

   **4b. Custom groupings sub-flow** (only entered from "Adjust groupings"). Iteratively let the user define groups until every candidate file is assigned — this differs from `--select`, which only produces a single set:
   - Maintain a list of unassigned files (initially: the entire candidate set).
   - Loop:
     1. Use `AskUserQuestion` to present unassigned files (numbered, with M/A/D/?? indicators). Offer:
        - Numeric input (e.g., `1,3,5` or `1-3,5`) → those files form the next group; mark them assigned.
        - `All remaining files in one final commit` → all unassigned become the last group; exit loop.
        - `Cancel and return to the proposal` → discard any in-progress custom groupings and return to step 4's 3-option proposal.
     2. Continue until unassigned is empty.
   - Once every candidate file is assigned → step 5 with the user-defined groups in creation order.

5. **Per-commit loop**. For each group (in order). Each iteration creates a NEW commit:
   1. Clear the index: `git reset HEAD`. Then stage only this group's files via `git add <file>...`. Prefer explicit file args; never `git add -A` or `git add .`. The candidate set has already passed the secret filter (step 2b), so no further secret check is needed here.
   2. Draft an Angular-style commit message:
      - **Format:** `type(scope): subject` with a body of bullet-point details.
      - **Types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `style`, `build`, `ci`, `chore`.
      - **Subject:** lowercase, imperative, no trailing period.
      - **Body:** each bullet starts with `"- "`, describing a concrete change.
      - Match the style of recent commits in the repo.
      - Always pass the message via a HEREDOC.
   3. Run `git commit` (create a NEW commit, never `--amend`).
   4. **If a pre-commit hook fails** for this iteration: run the appropriate fixer (formatter, linter), re-stage **only this group's files** (do not pull in files from already-committed earlier groups), and create a NEW commit. Never use `--amend` here — earlier iterations' commits must be preserved exactly.

6. After **all** commits in the loop succeed, push to origin on the current branch: `git push`. (Single push for the whole batch, regardless of how many commits were created.)

7. Report **all** commit SHAs created in this run, one per line.
