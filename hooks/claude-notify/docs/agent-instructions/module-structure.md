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
├── docs/
│   └── agent-instructions/
│       ├── module-structure.md
│       ├── build-test-quality.md
│       └── conventions-maintenance.md
├── scripts/
└── claude-notify.app/
```

## Structure Rules

- Core logic belongs in `Sources/NotifyCore`.
- `Sources/ClaudeNotify/main.swift` must stay thin and focused on wiring/entrypoint behavior.
- Treat `claude-notify.app` as a committed skeleton only; binary and code-sign outputs are build artifacts.
