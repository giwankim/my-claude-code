# Makefile for claude-notify subproject (canonical build/test logic)

.PHONY: build test test-fast test-unit test-integration test-e2e \
	check-cases-unit check-cases-integration check-cases-e2e check-docstrings

SWIFT_ENV=CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/clang-module-cache \
	SWIFTPM_MODULECACHE_OVERRIDE=$(CURDIR)/.build/module-cache \
	XDG_CACHE_HOME=$(CURDIR)/.build/.cache \
	HOME=$(CURDIR)/.build/home \
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

HOOKS_DIR := $(abspath ..)

build:
	$(SWIFT_ENV) swift build --disable-sandbox -c release --product claude-notify
	mkdir -p $(HOOKS_DIR)/claude-notify.app/Contents/MacOS
	BIN_PATH=$$($(SWIFT_ENV) swift build --disable-sandbox -c release --show-bin-path); \
		cp "$$BIN_PATH/claude-notify" $(HOOKS_DIR)/claude-notify.app/Contents/MacOS/claude-notify
	codesign -s - $(HOOKS_DIR)/claude-notify.app

check-cases-unit:
	./scripts/check-required-cases.sh unit Sources/NotifyCore Tests/NotifyCoreTests Tests/required-cases.txt

check-cases-integration:
	./scripts/check-required-cases.sh integration Sources/NotifyCore Tests/NotifyCoreTests tests/shell/integration Tests/required-cases.txt

check-cases-e2e:
	./scripts/check-required-cases.sh e2e tests/shell/e2e Tests/required-cases.txt

check-docstrings:
	./scripts/check-docstring-coverage.sh --min 80 Sources Tests

test-unit: check-docstrings check-cases-unit
	$(SWIFT_ENV) swift test --disable-sandbox --filter Unit

test-integration: build check-cases-integration
	$(SWIFT_ENV) swift test --disable-sandbox --filter Integration
	tests/shell/integration/run.sh

test-e2e: build check-cases-e2e
	tests/shell/e2e/run.sh

test-fast: test-unit test-integration

test: test-fast test-e2e
