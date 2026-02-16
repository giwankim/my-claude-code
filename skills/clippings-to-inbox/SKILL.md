---
name: clippings-to-inbox
description: Move web clippings from Clippings/ to inbox/ with kebab-case filenames. Use when the user says "move clippings", "process clippings", "clippings to inbox", or "clean up clippings".
---

# Clippings To Inbox

Move all `.md` files from `Clippings/` to `inbox/`, converting filenames to kebab-case.

## Workflow

1. List all `.md` files in `Clippings/`. If there are none, inform the user and stop.
2. Ask the user whether to add summaries to the clippings before moving them.
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

4. Run the move script from the vault root:

   ```bash
   python3 .agents/skills/clippings-to-inbox/scripts/move_clippings.py
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
