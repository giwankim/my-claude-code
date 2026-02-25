# Build, Tests, And Quality Gates

## Scope

Run all commands from `hooks/claude-notify/`.

## Build And Test Commands

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

- Minimum coverage is `>= 80%` on Swift declarations in `Sources/` and `Tests/`.
- Enforced by `make check-docstrings` via `scripts/check-docstring-coverage.sh`.

### Required Case IDs

- Every scenario must be listed in `Tests/required-cases.txt`.
- Enforced by `make check-cases-*`.
- Active ranges:
  - Unit: `U001-U033`
  - Integration (Swift): `I001-I005`
  - Integration (shell): `I101-I131`
  - E2E (shell): `E001-E013`
- Keep `I006-I100` reserved.
