# Module Structure

## Scope

This file documents the expected structure inside `hooks/claude-notify/`.

## Layout

```text
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
│   ├── required-cases.txt
│   └── shell/
│       ├── lib/
│       ├── unit/
│       ├── integration/
│       └── e2e/
├── scripts/
└── claude-notify.app/
```

## Structure Rules

- Keep core logic in `Sources/NotifyCore`.
- Keep `Sources/ClaudeNotify/main.swift` thin and focused on wiring/entrypoint behavior.
- Keep `claude-notify.app` as a committed skeleton only; binary and code-sign outputs are build artifacts.
