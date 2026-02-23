# AGENTS.md

Instructions for `/hooks/claude-notify` only.

## Scope

- This file governs work inside `hooks/claude-notify/`.
- Do not treat these instructions as repository-wide guidance for other components.

## Module Structure

```
hooks/claude-notify/
├── Makefile
├── Package.swift
├── README.md
├── notify.sh
├── tmux-redirect.sh
├── test-claude-notify.sh
├── Sources/
│   ├── ClaudeNotify/main.swift
│   └── NotifyCore/NotifyCore.swift
├── Tests/
│   ├── NotifyCoreTests/
│   └── required-cases.txt
├── tests/
│   └── shell/
│       ├── lib/
│       ├── unit/
│       ├── integration/
│       └── e2e/
├── scripts/
└── claude-notify.app/
```

## Build And Test Commands

Run from `hooks/claude-notify/`:

```bash
make build
make clean
make test-unit
make test-integration
make test-e2e
make test-fast
make test
make check-docstrings
make check-cases-unit
make check-cases-integration
make check-cases-e2e
```

## Quality Gates

### Docstring Coverage

- Minimum coverage: `>= 80%` on Swift declarations in `Sources/` and `Tests/`.
- Enforced by: `make check-docstrings` (`scripts/check-docstring-coverage.sh`).

### Required Case IDs

- Every scenario must be listed in `Tests/required-cases.txt`.
- Enforced by `make check-cases-*`.
- Active ranges:
  - Unit: `U001–U020`
  - Integration (Swift): `I001–I005`
  - Integration (shell): `I101–I129`
  - E2E (shell): `E001–E013`
- `I006–I100` remain reserved.

## Conventions

- `notify.sh` is the hook entrypoint and accepts either:
  - JSON on stdin (Claude hook payload), or
  - Message text as `$1`.
- Core logic belongs in `Sources/NotifyCore`; `Sources/ClaudeNotify/main.swift` should stay thin.
- Tests remain tiered and ordered: `unit -> integration -> e2e`.
- `claude-notify.app` skeleton is committed; binary and code-sign artifacts are build outputs.

## Maintenance Rules

- When adding or changing tests, update `Tests/required-cases.txt` with stable case IDs.
- Keep `README.md` in `hooks/claude-notify/` synchronized with behavior/env-var/test changes.
- Preserve deterministic test behavior; avoid introducing OS-state flakiness into integration/e2e suites.
