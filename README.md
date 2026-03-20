# my-claude-code

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) extensions for macOS — hooks and skills that extend the CLI agent.

## Components

### Hooks

- **[claude-notify](hooks/claude-notify/README.md)** — macOS notification hook with tmux integration
  - Posts native macOS notifications via a Swift binary with sender spoofing (custom app icon)
  - Click-to-redirect: clicking a notification switches your tmux client back to the originating pane
  - Configurable via environment variables; falls back to AppleScript when native delivery is unavailable

### Skills

- **[commit-push](skills/commit-push/SKILL.md)** — Commit and push with Angular-style messages
  - Stages relevant files, drafts an Angular-style `type(scope): subject` commit message, and pushes
  - Interactive file selection with `--select` / `-i`: numbered list of changed/untracked files to pick from
  - Handles pre-commit hook failures with automatic fix-and-retry

- **[spring-init](skills/spring-init/SKILL.md)** — Initialize Spring Boot projects via Spring Initializr
  - Interactive configuration with sensible defaults (Gradle-Kotlin, Kotlin, Java 25)
  - Dependency selection by category from the full Spring Initializr catalog
  - Uses the `spring` CLI (sdkman) for project generation

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
make clean          # Remove build artifacts
make test           # Run all tests (unit + integration + e2e)
make test-fast      # Unit + integration (skip e2e)
make test-unit      # Swift + shell unit tests with docstring/case-ID/shell-path gates
make test-integration  # Swift integration tests
make test-e2e       # Shell end-to-end tests
```

### Install

```bash
make install        # install hooks + skills
make install-hooks  # rsync hooks to ~/.claude/hooks/claude-notify/
make install-skills # copy skills to ~/.agents/skills/, symlink from ~/.claude and ~/.codex
make diff           # compare installed hooks vs source
```

`make install-skills` auto-discovers all directories under `skills/`, copies them to `~/.agents/skills/`, and creates symlinks in `~/.claude/skills/` and `~/.codex/skills/`. The copy in `~/.agents/skills/` is standalone — the source repo can be relocated without breaking installed skills.

## Development

- CI runs on `macos-latest` via [GitHub Actions](.github/workflows/tests.yml) — unit, integration, and e2e jobs with Swift build caching
- Quality gates: docstring coverage (`≥80%`), required test case IDs, shell-path casing
- Component docs: [claude-notify README](hooks/claude-notify/README.md), [commit-push SKILL.md](skills/commit-push/SKILL.md), [spring-init SKILL.md](skills/spring-init/SKILL.md), [clippings-to-inbox SKILL.md](skills/clippings-to-inbox/SKILL.md)

## License

MIT
