# Root compatibility Makefile delegating claude-notify operations to hooks/claude-notify.

.PHONY: install diff build test test-fast test-unit test-integration test-e2e \
	check-cases-unit check-cases-integration check-cases-e2e check-docstrings

PROJECT_DIR := hooks/claude-notify
SUB_MAKE := $(MAKE) -C $(PROJECT_DIR)

install:
	rsync -a --delete \
		--include='claude-notify.app/' \
		--include='claude-notify.app/**' \
		--include='notify.sh' \
		--include='test-claude-notify.sh' \
		--exclude='*' \
		hooks/ ~/.claude/hooks/

diff:
	diff -q hooks/notify.sh ~/.claude/hooks/notify.sh
	diff -q hooks/test-claude-notify.sh ~/.claude/hooks/test-claude-notify.sh
	diff -rq hooks/claude-notify.app ~/.claude/hooks/claude-notify.app

build:
	$(SUB_MAKE) build

check-cases-unit:
	$(SUB_MAKE) check-cases-unit

check-cases-integration:
	$(SUB_MAKE) check-cases-integration

check-cases-e2e:
	$(SUB_MAKE) check-cases-e2e

check-docstrings:
	$(SUB_MAKE) check-docstrings

test-unit:
	$(SUB_MAKE) test-unit

test-integration:
	$(SUB_MAKE) test-integration

test-e2e:
	$(SUB_MAKE) test-e2e

test-fast:
	$(SUB_MAKE) test-fast

test:
	$(SUB_MAKE) test
