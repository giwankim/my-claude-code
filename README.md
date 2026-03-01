# my-claude-code

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) extensions for macOS — hooks and skills that extend the CLI agent.

## Components

### Hooks

- **[claude-notify](hooks/claude-notify/README.md)** — macOS notification hook with tmux integration
  - Posts native macOS notifications via a Swift binary with sender spoofing (custom app icon)
  - Click-to-redirect: clicking a notification switches your tmux client back to the originating pane
  - Configurable via environment variables; falls back to AppleScript when native delivery is unavailable

### Skills

- **[clippings-to-inbox](skills/clippings-to-inbox/SKILL.md)** — Move web clippings to inbox with kebab-case filenames
  - Converts Obsidian `Clippings/*.md` filenames to kebab-case with Unicode-aware normalization
  - Optionally generates and inserts summary callouts before moving
  - Handles filename conflicts with auto-incrementing suffixes

## Quick Start

### Prerequisites

- macOS
- Swift toolchain (`swift build`, `swift test`)
- Python 3
- `perl` with `Time::HiRes` (bundled by default on standard macOS Perl builds)
- `jq`

### Build and Test

```bash
make build          # Build all components
make test           # Run all tests (unit + integration + e2e)
make test-unit      # Swift + shell unit tests with docstring/case-ID/shell-path gates
make test-integration  # Swift integration tests
make test-e2e       # Shell end-to-end tests
```

### Install

**Hooks** — copy into the Claude hooks directory:

```bash
make install        # rsync to ~/.claude/hooks/claude-notify/
make diff           # compare installed vs source
```

**Skills** — symlink the skill directory into your Obsidian vault:

```bash
ln -s /path/to/my-claude-code/skills/clippings-to-inbox /path/to/vault/.agents/skills/clippings-to-inbox
```

## Development

- CI runs on `macos-latest` via [GitHub Actions](.github/workflows/tests.yml) — unit, integration, and e2e jobs with Swift build caching
- Quality gates: docstring coverage (`≥80%`), required test case IDs
- Component docs: [claude-notify README](hooks/claude-notify/README.md), [clippings-to-inbox SKILL.md](skills/clippings-to-inbox/SKILL.md)

## License

MIT
