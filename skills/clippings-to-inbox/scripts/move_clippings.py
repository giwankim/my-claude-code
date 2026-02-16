#!/usr/bin/env python3
"""
Move Clippings to Inbox

Moves all .md files from Clippings/ to inbox/, converting filenames to kebab-case.

Kebab-case rules:
- Lowercase ASCII letters
- ASCII punctuation/spaces -> hyphens
- Non-ASCII punctuation (Unicode P*, Z*) -> hyphens
- Non-ASCII letters, digits, emoji (L*, N*, So) -> kept as-is
- Collapse consecutive hyphens, strip leading/trailing hyphens

Usage:
    python move_clippings.py [vault_path]
"""

import sys
import shutil
import unicodedata
from pathlib import Path


def to_kebab_case(name: str) -> str:
    """Convert a filename (without extension) to kebab-case."""
    result = []
    for ch in name:
        if ch.isascii():
            if ch.isalnum():
                result.append(ch.lower())
            else:
                # ASCII punctuation, spaces, etc. -> hyphen
                result.append('-')
        else:
            cat = unicodedata.category(ch)
            if cat.startswith('P') or cat.startswith('Z'):
                # Non-ASCII punctuation or separator -> hyphen
                result.append('-')
            else:
                # Non-ASCII letters (L*), digits (N*), symbols like emoji (So), etc. -> keep
                result.append(ch)

    # Collapse consecutive hyphens and strip leading/trailing
    collapsed = []
    for ch in result:
        if ch == '-' and (not collapsed or collapsed[-1] == '-'):
            if not collapsed:
                continue
            continue
        collapsed.append(ch)

    text = ''.join(collapsed).strip('-')
    return text


def resolve_conflict(dest_dir: Path, stem: str, suffix: str) -> Path:
    """Find a non-conflicting filename by appending -1, -2, etc."""
    candidate = dest_dir / f"{stem}{suffix}"
    if not candidate.exists():
        return candidate
    n = 1
    while True:
        candidate = dest_dir / f"{stem}-{n}{suffix}"
        if not candidate.exists():
            return candidate
        n += 1


def main():
    vault_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    vault_path = vault_path.resolve()

    clippings_dir = vault_path / 'Clippings'
    if not clippings_dir.is_dir():
        print(f"Error: Clippings directory not found: {clippings_dir}", file=sys.stderr)
        sys.exit(1)

    md_files = sorted(clippings_dir.glob('*.md'))
    if not md_files:
        print("Error: No .md files found in Clippings/", file=sys.stderr)
        sys.exit(1)

    inbox_dir = vault_path / 'inbox'
    inbox_dir.mkdir(exist_ok=True)

    moved = []
    for src in md_files:
        kebab = to_kebab_case(src.stem)
        if not kebab:
            kebab = 'untitled'
        dest = resolve_conflict(inbox_dir, kebab, '.md')
        shutil.move(str(src), str(dest))
        moved.append((src.name, dest.name))

    print(f"Moved {len(moved)} file(s) from Clippings/ to inbox/:\n")
    for old_name, new_name in moved:
        print(f"  {old_name}")
        print(f"    -> {new_name}")
        print()


if __name__ == '__main__':
    main()
