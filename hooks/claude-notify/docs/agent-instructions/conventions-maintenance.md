# Conventions And Maintenance Rules

## Entrypoint And Execution

- `notify.sh` is the hook entrypoint and accepts either stdin JSON (Claude hook payload) or message text via `$1`.
- Keep tests tiered and ordered as `unit -> integration -> e2e`.

## Maintenance Expectations

- When adding or changing tests, update `Tests/required-cases.txt` with stable case IDs.
- Keep `README.md` synchronized with behavior, env var, and test changes.
- Preserve deterministic test behavior; avoid introducing OS-state flakiness in integration and e2e suites.
