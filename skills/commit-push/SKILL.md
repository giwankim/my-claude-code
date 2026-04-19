---
name: commit-push
description: Commit staged/unstaged changes and push to origin with an Angular-style commit message. By default, auto-detects when changes span multiple cohesive scopes and proposes splitting them into multiple commits; user can override with `--single`/`-1` or natural-language phrases like "as one commit" or "single commit". File scoping (explicit `@file` args, `--select` interactive picker) and secret-file filtering apply on every path, including the override. Use when the user says "commit and push", "commit this", "/commit-push", or after completing work that should be committed. Accepts optional file arguments to scope the commit, or interactive selection to pick files from the working tree. Also use when the user wants to choose, select, or pick which changed files to include in a commit.
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

   **b) Secret filter** (applied to the candidate set on **every** path — including when `--single`, `-1`, `--select`, or explicit `@file` args are used; the filter cannot be bypassed by any flag):
   - Exclude files that likely contain secrets: `.env`/`.env.*`, private keys (`*.pem`, `*.key`, `*.p12`, `id_rsa*`, `id_dsa*`, `id_ecdsa*`, `id_ed25519*` — the `.pub` siblings are public and OK), credential files (`credentials*`, `*credentials.json`, `aws_credentials*`), and any file whose name contains `token` or `secret` unless it's clearly a safe fixture (e.g., a test data file the user obviously meant to commit).
   - When in doubt, exclude and tell the user.
   - List any excluded files explicitly in your reply so the user knows what was omitted. If the exclusion was a false positive (e.g., a genuine test fixture whose filename matches the secret pattern), the user's workarounds are (a) rename the file so it no longer matches, (b) adjust the filter rules above if the mis-match is structural, or (c) commit the file manually outside this skill (`git add` + `git commit` + `git push`). Re-invoking `/commit-push` with `--select` or explicit `@file` args will NOT re-include the filtered file — the filter is deliberately absolute as a safety invariant, and no flag overrides it.

   **c) Commit-count mode**:
   - **Single-commit mode** if any of the following:
     - Invocation contains `--single`, `-1`, or one of these unambiguous multi-word phrases — "single commit", "as one commit", "as a single commit", "commit this as one", "all together" — → acknowledge the override in your reply. Bare tokens like "as one" or "one commit" alone are **not** sufficient; they appear too often in unrelated prose ("commit this as one last sanity check", "this should be one commit per scope") and would false-positive. The phrases above all force the user to express override intent explicitly.
     - The user used `--select` or explicit `@file` args (manual scoping signals "this is one commit's worth of files"; preserves backward-compat with how the picker has always worked).
   - **Auto-detect mode** otherwise.

   In single-commit mode: skip steps 3–4 entirely; jump to step 5 with the secret-filtered candidate set as one group.

3. **Auto-detect cohesive groups** in the candidate set. Apply rules in order; first match wins per file:
   1. **Skill subdirectory**: files under `skills/<name>/...` group by `<name>` (e.g., `spring-init`, `commit-push`).
   2. **CI/infra directory**: files under `.github/...` group as scope `ci`. This rule fires *before* the generic top-level-directory rule below so `.github` doesn't end up as a literal directory scope; the `ci` mapping reflects what these files actually configure.
   3. **Top-level directory**: files under any other top-level `<dir>/...` group by `<dir>` (e.g., `hooks`, `docs`).
   4. **Root files** (no directory prefix): infer scope per file — `Makefile`/`Dockerfile`/`package.json`/`pyproject.toml`/`Cargo.toml`/build configs → `build`; `README*` and top-level `*.md` → `docs`; `LICENSE*` → `chore`; others → `chore`. Then group root files by inferred scope, so multiple root files sharing a scope form one group while files with different scopes form separate groups (e.g., changing `Makefile` and `Dockerfile` → one `build` group; changing `Makefile` and `README.md` → two groups: `build` and `docs`).

   **Cross-rule scope merging**: groups are keyed by their *resolved scope name*, not by the rule that produced them. So if rule 3.3 yields a `docs` group from `docs/README.md` and rule 3.4 yields a `docs` scope from a root-level `README.md`, those merge into a single `docs` group spanning both files (one `docs(docs): ...` commit — the outer `docs` is the Angular type, the inner `docs` is the resolved scope name). Same for `ci` (e.g., `.github/workflows/test.yml` from rule 3.2 plus a hypothetical root `.codecov.yml` mapped to `ci` → one `ci(ci): ...` commit). This keeps commit boundaries deterministic when scope names collide across rules.

   **Then refine for tests**: scan files matching `tests/...`, `test/...`, `__tests__/...`, or `test_*.{ext}` / `*_test.{ext}` patterns. Re-attribute each test file to a non-test scope when possible (impl + its tests should be one cohesive commit, not two):
   a. **Path-component match**: `tests/<scope>/...` (e.g., `tests/spring-init/...` → `spring-init`), or filename containing a scope keyword that exists in the candidate set (e.g., `tests/test_hooks.sh` when `hooks` is a non-test scope → `hooks`).
   b. **Sole non-test scope**: if exactly one non-test scope exists in the candidate set, attribute all unmatched test files to it.
   c. **Otherwise**: leave unmatched test files in their own `tests` group.

   **Trade-off note**: rule 3b ("sole non-test scope") means adding a *second* non-test scope to a previously-merged changeset can split test files off into their own group (because rule 3b no longer applies). This is intentional — arbitrary attachment to one of two impl scopes would be more surprising than a clean separation. If the user wants a particular test file to land with a particular impl group in a multi-scope changeset, they can pre-stage with `--select` or use `Adjust groupings` (step 4b) to define the grouping explicitly.

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
   1. Clear the index: `git restore --staged :/` (Git 2.23+ form, preferred over the legacy `git reset HEAD` to avoid confusion with `git reset --hard`; `git reset HEAD` still works on older Git). The `:/` magic pathspec anchors to the repo root so the entire index is cleared regardless of the caller's current working directory — do NOT use bare `git restore --staged .`, which is CWD-relative and would leave staged files outside the current subtree untouched. Then stage only this group's files via `git add <file>...`. Prefer explicit file args; never `git add -A` or `git add .`. The candidate set has already passed the secret filter (step 2b), so no further secret check is needed here.
   2. Draft an Angular-style commit message:
      - **Format:** `type(scope): subject` with a body of bullet-point details.
      - **Types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `style`, `build`, `ci`, `chore`.
      - **Subject:** lowercase, imperative, no trailing period.
      - **Body:** each bullet starts with `"- "`, describing a concrete change.
      - Match the style of recent commits in the repo.
      - Always pass the message via a HEREDOC.
   3. Run `git commit` (create a NEW commit, never `--amend`).
   4. **If a pre-commit hook fails** for this iteration, attempt a bounded recovery:
      a. **Determine a fixer** from the hook's stderr + the affected file types — e.g., `prettier --write` for JS/TS formatting, `ruff format` or `black` for Python, `gofmt -w` for Go, `markdownlint-cli --fix` for markdown, `shfmt -w` for shell. If the hook is a *spec check* with no auto-fix equivalent (e.g., `pytest`, `jsonschema`, integrity/hash checks, custom validators), skip directly to step 4c.
      b. **Retry up to twice** (initial attempt + at most 2 fixer-driven retries — total ≤3 `git commit` attempts per iteration). Each retry: run the fixer, re-stage **only this group's files** via `git add <file>...` (do NOT pull in files from already-committed earlier groups), run `git commit` again with the original message. Two retries absorbs the case where a fixer needs multiple passes (e.g., `eslint --fix` resolving cascading auto-fixes). Every retry creates a NEW commit — never use `--amend`, because earlier iterations' commits must be preserved exactly.
      c. **If no fixer can be determined OR all retries fail**: mark this group as FAILED and **abort the loop**. Do NOT attempt remaining groups. Do NOT run step 6 (reconciliation). Do NOT run step 7 (`git push`). Earlier successful per-group commits remain on the local branch; the user will resolve the hook error manually (reading the stderr output) and re-invoke `/commit-push` to handle the remaining work. Jump directly to step 8 with the failure context (failing group, hook stderr, unprocessed groups).

6. **Reconcile cross-group hook auto-fixes via a delta against the pre-loop snapshot.** **Skip step 6 entirely if step 5.4c fired** — the delta rule below assumes every candidate file was staged and committed during the loop, which isn't true after an abort. On abort, leave the working tree as-is for the user to inspect and jump to step 8. Otherwise, proceed: repo-wide pre-commit hooks (formatters, linters that touch every matching file in the tree, not just staged ones) sometimes auto-fix files that belong to *other* groups — those edits remain unstaged after their iteration ends because step 5.1 only stages the current group's files. Without reconciliation, those edits would either silently disappear from the run or pollute the next session. **However, the user may also have had unrelated unstaged changes in their working tree before invoking the skill — those must NOT be swept into a reconciliation commit.** To distinguish:
   - **Before** entering step 5's loop, snapshot the working-tree state via `git status --porcelain` (capture the output in memory or a temp file). **Normalize the snapshot** so it matches what post-loop `git status --porcelain` would show for the same pre-loop state *assuming no hooks ran* — step 5.1's index-clear `git restore --staged :/` unstages everything, which is what the normalized form represents. Apply these per-line rewrites:
     Porcelain v1 format is `XY<SP><path>` — X is the index status (position 1), Y is the worktree status (position 2), followed by one separator space before the path. So a staged-only modification renders as `M  <path>` (M, Y-space, separator-space, path), and a worktree-only modification as ` M <path>` (X-space, M, separator-space, path). The rules below preserve that two-column + separator spacing so the normalization can be applied mechanically to literal `git status --porcelain` output:
     - `M  <path>` → ` M <path>` (column swap; `<path>` kept). HEAD has `<path>`; working tree still has the modification.
     - `D  <path>` → ` D <path>` (column swap; `<path>` kept). HEAD has `<path>`; working tree is still missing it.
     - `A  <path>` → `?? <path>` (new classification). Staged new file; unstaging removes the index entry, and since HEAD has no entry either, the working-tree file becomes untracked — it does NOT become ` A` (which isn't a valid porcelain state for an uncommitted new file).
     - `R  <old> -> <new>` → two lines: ` D <old>` + `?? <new>` (one snapshot line expands to two). Staged renames decompose because the index operation is both "delete `<old>`" and "add `<new>`" relative to HEAD; unstaging leaves `<old>` present in the index at HEAD content (missing in working tree → ` D`) and removes `<new>` from the index entirely (present in working tree, absent from HEAD → `??`).
     - `C  <old> -> <new>` → `?? <new>` (one line, different path). Staged copies decompose; `<old>` stays clean because a copy doesn't modify the source, and `<new>` becomes untracked for the same reason as `A`.
     - **Combined index+worktree statuses** (both columns non-space — a user staged a file, then modified or deleted it in the worktree on top, before invoking the skill): treat by the same "what does `git restore --staged :/` produce?" rule applied to each column combo. The four practical cases:
       - `MM <path>` → ` M <path>` (unstaging drops the index modification; worktree still has both layers of change relative to HEAD, which surfaces as a single unstaged `M`).
       - `AM <path>` → `?? <path>` (same as `A ` — HEAD has no entry, so unstaging removes the index entry entirely and the worktree content becomes untracked; the extra worktree mod is absorbed into the untracked content).
       - `MD <path>` → ` D <path>` (unstaging drops the index mod; worktree is still missing the file, which becomes an unstaged deletion relative to HEAD).
       - `AD <path>` → **line dropped entirely** (HEAD has no entry, unstaging removes the index entry, worktree has no file — the path ceases to exist anywhere, so it disappears from post-loop porcelain).

     Treat each normalized line as part of the snapshot, matching by *both* path and indicator. Without this normalization a user who ran `git add fileA` (or `git mv`/`git add <new>`) before invoking `/commit-push --select fileB` would see the pre-loop entry transform into its unstaged form after step 5.1's index clear, get flagged as delta, and trigger a spurious warn branch — and the noise is worse for renames/copies where a single pre-loop entry fans out into two post-loop entries with entirely different path + indicator combinations.
   - **After** the loop completes, compute the *delta* against the snapshot using this two-part rule:
     - **Candidate-set files** (files from the post-filter candidate set — step 2a's file scoping intersected with step 2b's secret filter, i.e., what the per-commit loop actually committed): any file from the candidate set that shows an unstaged change in post-loop `git status --porcelain` is residue, regardless of its pre-loop status. Every candidate file was staged and committed during the loop, so any non-clean state afterward is necessarily hook-introduced — this catches the case where a file was `M` pre-loop, committed mid-loop (momentarily clean), and then re-dirtied by a repo-wide hook running on a *later* group's commit (both the pre-loop and post-loop `git status` lines look the same — ` M <path>` — but the content was committed in between).
     - **Non-candidate files**: only those whose status indicator *changed* from the snapshot or that *newly appeared* as unstaged count as delta. Files that were already dirty pre-loop and remain identically dirty post-loop are the user's pre-existing unrelated work and must not be touched.
   - If the delta is empty: skip — no extra commit.
   - If the delta contains only files that were also in the post-filter candidate set (step 2a's scoping ∩ step 2b's secret filter): stage just the delta files (`git add <delta-file>...`) and create one final commit, typically `chore(commit-push): reconcile hook auto-fixes` (use `style:` if purely formatting, or `fix:` if the hook actually fixed bugs — match the diff). Mention this commit explicitly in your reply so the user understands why an extra commit appeared and can keep/squash/split it.
   - If the delta contains files *outside* the original candidate set (a hook touched files the user wasn't trying to commit): warn the user and let them decide — do NOT auto-stage these. They may want to stash them, commit them separately under a different intent, or verify the hook's behavior. Auto-committing files the user didn't include in their candidate set would violate the principle that the skill only commits files the user opted in to.

7. After **all** commits (per-group + any reconciliation) succeed, push to origin on the current branch: `git push`. (Single push for the whole batch, regardless of how many commits were created.) **Skip the push if step 5.4c fired** — earlier successful commits stay local so the user can inspect, amend, or cherry-pick before deciding whether to push. Pushing a partial batch would surface the leading groups to origin while silently dropping the failed group, violating the atomic-batch invariant this skill otherwise enforces.

8. **Report** the outcome:
   - **On success**: list all commit SHAs created in this run, one per line (per-group commits in loop order, followed by the reconciliation commit if any).
   - **On abort from step 5.4c**: list the successful SHAs created before the abort (one per line), then a clear failure block: the failing group's scope name + files, the hook's stderr output (the last `git commit` stderr), the list of groups that never got their turn (unprocessed), and explicit guidance — *"Fix the hook error manually and re-invoke `/commit-push`. The earlier successful commits are still on your local branch but were not pushed; they'll be preserved and the remaining groups will be picked up fresh on re-invocation."*
