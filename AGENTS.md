# AGENTS.md

Project guidelines for AI agents working in this repository.

## Repository Structure

```
my-claude-code/
├── Makefile                    # Root orchestrator — delegates to component Makefiles
├── .github/workflows/tests.yml # CI: unit → integration → e2e on macos-latest
├── hooks/
│   └── claude-notify/          # macOS notification hook (Swift + shell)
│       ├── README.md           # Component docs
│       └── Makefile            # build, test-unit, test-integration, test-e2e, check-docstrings
└── skills/
    └── clippings-to-inbox/     # Web clipping processor (Python)
        └── SKILL.md            # Skill definition with frontmatter
```

## Build and Test Commands

```bash
make build              # Build all components
make test               # Run full test suite
make test-unit          # Swift unit tests + docstring gate
make test-integration   # Swift integration tests
make test-e2e           # Shell end-to-end tests
make install            # Install hooks to ~/.claude/hooks/
make diff               # Diff installed hooks vs source
make clean              # Clean build artifacts
```

## Keeping README.md in Sync

When hooks or skills are added, removed, or significantly changed, update `README.md`:

1. **Components section** — each component gets an entry under `### Hooks` or `### Skills` with:
   - Name linked to its docs file (`README.md` for hooks, `SKILL.md` for skills)
   - One-line description
   - 2–3 bullet points summarizing key features

2. **Quick Start section** — update prerequisites or install instructions if a new component introduces dependencies.

3. **Component metadata lives in**:
   - Hooks: `hooks/<name>/README.md`
   - Skills: `skills/<name>/SKILL.md` (YAML frontmatter has `name` and `description`)

## Quality Gates

- **Docstring coverage**: `≥80%` on Swift sources — checked by `make check-docstrings`
- **Required test cases**: IDs listed in `hooks/claude-notify/Tests/required-cases.txt` must all exist — checked by `make check-cases-unit`
- CI enforces these gates; do not bypass them.

## Conventions

- Hook entrypoints are shell scripts (`notify.sh`) that accept JSON on stdin per the Claude hook payload format.
- Skill definitions use the `SKILL.md` format with YAML frontmatter (`name`, `description`).
- The root Makefile delegates to component Makefiles — add new components by extending the delegation pattern.
- Tests are tiered: unit → integration → e2e. CI runs them sequentially with each tier gating the next.
