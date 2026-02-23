# AGENTS.md

Instructions for `/hooks/claude-notify` only.

## Scope

- Apply these instructions only within `hooks/claude-notify/`.
- Do not treat them as repository-wide guidance.

## Quick Reference

- Build: `make build`
- Fast test pass: `make test-fast`
- Full test pass: `make test`
- Docstring gate: `>= 80%` Swift declaration coverage
- Case-ID gate: every scenario must be listed in `Tests/required-cases.txt`

## Critical Overrides

- Test execution order must be `unit -> integration -> e2e`.
- `notify.sh` is the hook entrypoint; it accepts stdin JSON payloads or message text via `$1`.
- Keep `README.md` synchronized with behavior, env var, and test changes.

## Detailed Instructions

- [Module Structure](docs/agent-instructions/module-structure.md)
- [Build, Tests, And Quality Gates](docs/agent-instructions/build-test-quality.md)
- [Conventions And Maintenance Rules](docs/agent-instructions/conventions-maintenance.md)
