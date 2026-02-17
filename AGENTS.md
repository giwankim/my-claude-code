# AGENTS.md

Project guidelines for AI agents working in this repository.

## Repository Structure

```
my-claude-code/
├── Makefile                              # Root orchestrator — delegates to component Makefiles
├── .github/workflows/tests.yml          # CI: unit → integration → e2e on macos-latest
├── hooks/
│   └── claude-notify/                   # macOS notification hook (Swift + shell)
│       ├── Makefile                     # build, test-*, check-* targets
│       ├── Package.swift                # Swift package: my-claude-code (macOS 13+, Swift 6.0)
│       ├── notify.sh                    # Hook entrypoint — reads JSON stdin or $1
│       ├── tmux-redirect.sh             # tmux click-redirect helper
│       ├── test-claude-notify.sh        # Local shell test runner
│       ├── README.md                    # Component docs + env vars reference
│       ├── claude-notify.app/           # App bundle skeleton (binary + codesign gitignored)
│       │   └── Contents/{Info.plist, PkgInfo, Resources/claude-code.icns}
│       ├── Sources/
│       │   ├── ClaudeNotify/main.swift  # Executable entry point
│       │   └── NotifyCore/NotifyCore.swift  # Library target (core logic)
│       ├── Tests/
│       │   ├── required-cases.txt       # Required case IDs per tier (U*, I*, E*)
│       │   ├── NotifyCoreTests/         # Swift XCTest (Unit* and Integration* files)
│       │   └── shell/                   # Shell test tiers
│       │       ├── lib/testlib.sh       # Shared test helpers
│       │       ├── integration/         # I101+ shell integration tests
│       │       └── e2e/                 # E001+ shell e2e tests
│       └── scripts/
│           ├── check-docstring-coverage.sh
│           └── check-required-cases.sh
└── skills/
    └── clippings-to-inbox/              # Web clipping processor (Python)
        ├── SKILL.md                     # Skill definition with frontmatter
        └── scripts/move_clippings.py
```

## Build and Test Commands

```bash
# Build and install
make build              # Compile Swift, assemble + codesign claude-notify.app
make install            # rsync hooks to ~/.claude/hooks/
make diff               # Diff installed hooks vs source
make clean              # Clean build artifacts

# Test tiers (sequential in CI; each gates the next)
make test-unit          # check-docstrings + check-cases-unit + swift test --filter Unit
make test-integration   # build + check-cases-integration + swift test --filter Integration + shell integration
make test-e2e           # build + check-cases-e2e + shell e2e
make test-fast          # test-unit + test-integration (skips e2e)
make test               # Full suite: test-fast + test-e2e

# Quality gate checks (also run inside test tier targets)
make check-docstrings        # Swift docstring coverage ≥ 80%
make check-cases-unit        # Verify U* IDs in required-cases.txt exist in sources
make check-cases-integration # Verify I* IDs exist in sources + shell integration tests
make check-cases-e2e         # Verify E* IDs exist in shell e2e tests
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

CI enforces these gates. Do not bypass them.

### Docstring coverage

- Threshold: **≥80%** on Swift sources in `Sources/` and `Tests/`.
- Checked by: `make check-docstrings` (runs `scripts/check-docstring-coverage.sh`).
- Applies to: `enum`, `struct`, `class`, `protocol`, `func`, `init` declarations — each must have a preceding `///` comment.

### Required test case IDs

All test scenarios must have a stable ID registered in `Tests/required-cases.txt`. Adding a test without a registered ID will fail CI.

| Prefix | Tier | Location |
|--------|------|----------|
| `U001–U016` | unit | Swift XCTest in `Tests/NotifyCoreTests/` |
| `I001–I005` | integration | Swift XCTest in `Tests/NotifyCoreTests/` |
| `I101–I128` | integration | Shell scripts in `Tests/shell/integration/` |
| `E001–E011` | e2e | Shell scripts in `Tests/shell/e2e/` |

`I006–I100` are reserved (gap between Swift and shell integration IDs).

## Conventions

- Hook entrypoints are shell scripts (`notify.sh`) that accept JSON on stdin per the Claude hook payload format, or a message as `$1`.
- Skill definitions use the `SKILL.md` format with YAML frontmatter (`name`, `description`).
- The root Makefile delegates to component Makefiles via `SUB_MAKE`. Add new hooks by extending the `HOOKS` variable.
- Tests are tiered: unit → integration → e2e. CI runs them sequentially with each tier gating the next.
- Swift package has two targets: `NotifyCore` (library — all core logic) and `ClaudeNotify` (executable — thin `main.swift` entry). Tests target `NotifyCore`.
- Integration tier has both Swift XCTest (`I001–I005`) and shell tests (`I101+`). Both are run by `make test-integration`.
- The `claude-notify.app/` bundle skeleton is committed. Binary (`Contents/MacOS/`) and code-sign (`Contents/_CodeSignature/`) dirs are gitignored, produced by `make build`.
- Hook behavior is configured via `NOTIFY_*` environment variables. See `hooks/claude-notify/README.md` for the full list.
