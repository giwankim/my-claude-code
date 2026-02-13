# Makefile for syncing Claude Code hooks to ~/.claude/hooks/

.PHONY: install diff build test test-fast test-unit test-integration test-e2e \
	check-cases-unit check-cases-integration check-cases-e2e

SWIFT_ENV=CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/clang-module-cache \
	SWIFTPM_MODULECACHE_OVERRIDE=$(CURDIR)/.build/module-cache \
	XDG_CACHE_HOME=$(CURDIR)/.build/.cache \
	HOME=$(CURDIR)/.build/home \
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

install:
	rsync -a --delete hooks/ ~/.claude/hooks/

diff:
	diff -rq hooks/ ~/.claude/hooks/

build:
	$(SWIFT_ENV) swift build --disable-sandbox -c release --product claude-notify
	mkdir -p hooks/claude-notify.app/Contents/MacOS
	BIN_PATH=$$($(SWIFT_ENV) swift build --disable-sandbox -c release --show-bin-path); \
		cp "$$BIN_PATH/claude-notify" hooks/claude-notify.app/Contents/MacOS/claude-notify
	codesign -s - hooks/claude-notify.app

check-cases-unit:
	./scripts/check-required-cases.sh unit Sources/NotifyCore Tests/NotifyCoreTests tests/required-cases.txt

check-cases-integration:
	./scripts/check-required-cases.sh integration Sources/NotifyCore Tests/NotifyCoreTests hooks/tests/integration tests/required-cases.txt

check-cases-e2e:
	./scripts/check-required-cases.sh e2e hooks/tests/e2e tests/required-cases.txt

test-unit: check-cases-unit
	$(SWIFT_ENV) swift test --disable-sandbox --filter Unit

test-integration: build check-cases-integration
	$(SWIFT_ENV) swift test --disable-sandbox --filter Integration
	hooks/tests/integration/run.sh

test-e2e: build check-cases-e2e
	hooks/tests/e2e/run.sh

test-fast: test-unit test-integration

test: test-fast test-e2e
