---
name: clippings-to-inbox
description: Move web clippings from Clippings/ to inbox/ with kebab-case filenames. Use when the user says "move clippings", "process clippings", "clippings to inbox", or "clean up clippings".
---

# Clippings To Inbox

Move all `.md` files from `Clippings/` to `inbox/`, converting filenames to kebab-case.

## Claude Code and Codex

This skill requires Python 3 and works in both hosts. Resolve `scripts/move_clippings.py` relative to the directory containing this loaded `SKILL.md`, using its absolute path. The skill may be installed globally or in a project, including through a symlink; its directory is independent of the vault root.

For questions, use the input mechanism available in the current host:

- **Claude Code:** use `AskUserQuestion` when available.
- **Codex:** prefer `request_user_input_async` when available; use `request_user_input` only when the current mode and tool instructions allow it. Do not switch modes just to ask a question.
- **Fallback:** ask in chat and end the turn to wait for the reply.

Follow the selected tool's schema. Reuse answers already given by the user. Wait for an actual answer before editing or moving files when the workflow depends on it; an asynchronous tool returning or a preselected option is not an answer.

## Workflow

1. Use the vault path supplied by the user, or the current working directory if it contains `Clippings/`. If the vault is unclear, ask for its path. Resolve the vault to an absolute path and list its `Clippings/*.md` files. If there are none, inform the user and stop.
2. Ask whether to add summaries before moving, unless the user has already specified a preference. Use the host's input mechanism above and wait for the answer.
3. If yes: for each file, read its content, generate a concise 2-3 sentence summary, and insert a `> [!summary]` callout block immediately after the frontmatter closing `---`. If the file has no frontmatter, insert the callout at the very top.

   The summary callout format:

   ```markdown
   ---
   (frontmatter)
   ---

   > [!summary]
   > 2-3 sentence summary of the article content.

   (rest of content)
   ```

4. Run the bundled move script with the explicit vault path. Replace both paths below with the resolved absolute paths and quote them so spaces are preserved:

   ```bash
   python3 "/absolute/path/to/clippings-to-inbox/scripts/move_clippings.py" "/absolute/path/to/vault"
   ```

   The script:
   1. Finds all `.md` files in `Clippings/`
   2. Converts each filename to kebab-case
   3. Creates `inbox/` if it does not exist
   4. Moves each file, appending `-1`, `-2`, etc. on name conflicts
   5. Prints a summary of moved files

## Kebab-Case Rules

- ASCII letters and digits: lowercased and kept
- ASCII punctuation and spaces: replaced with hyphens
- Non-ASCII punctuation and separators (Unicode `P*`, `Z*`) replaced with hyphens
- Non-ASCII letters, digits, and symbols like emoji (`L*`, `N*`, `So`): kept as-is
- Consecutive hyphens collapsed; leading/trailing hyphens stripped

## Examples

| Before | After |
|--------|-------|
| `21 Lessons From 14 Years at Google.md` | `21-lessons-from-14-years-at-google.md` |
| `A Complete Guide To AGENTS.md` | `a-complete-guide-to-agents.md` |
| `리눅스 비동기 IO 톺아보기 - All.md` | `리눅스-비동기-io-톺아보기-all.md` |
| `🪙내 월급, CMA로 받으면 이자가 30배?.md` | `🪙내-월급-cma로-받으면-이자가-30배.md` |
