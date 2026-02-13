# Docstring Standards

This repository enforces docstring coverage for Swift declarations in `Sources/` and `Tests/`.

## Coverage Rules

- Use `///` comments only. Other comment styles are ignored by coverage checks.
- Place the doc comment immediately above the declaration with no blank lines.
- A declaration counts as documented only if the previous non-empty line starts with `///`.

## Writing Guidelines

- Public APIs in `NotifyCore` should include:
  - a short summary,
  - `- Parameters` for each input,
  - `- Returns` when a value is produced,
  - `- Throws` when errors can be raised.
- Internal runtime and test declarations should use concise one-line intent comments.

## Enforcement

- Run `make check-docstrings` locally.
- CI runs docstring checks through `make test-unit`, so coverage failures block slower integration/e2e jobs.
