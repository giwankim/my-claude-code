# Makefile for syncing Claude Code hooks to ~/.claude/hooks/

.PHONY: install diff build test

install:
	rsync -a --delete hooks/ ~/.claude/hooks/

diff:
	diff -rq hooks/ ~/.claude/hooks/

build:
	swiftc hooks/claude-notify.swift -o hooks/claude-notify.app/Contents/MacOS/claude-notify -framework Cocoa -framework UserNotifications
	codesign -s - hooks/claude-notify.app

test:
	hooks/test-claude-notify.sh
