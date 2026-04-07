# Makefile for claude-notify subproject (canonical build/test logic)

.PHONY: build test test-fast test-unit test-integration test-e2e \
	check-cases-unit check-cases-integration check-cases-e2e check-docstrings check-shell-path-casing \
	uninstall uninstall-hooks \
	all clean

all: build

SETTINGS_FILE ?= $(HOME)/.claude/settings.json
INSTALL_DIR ?= $(HOME)/.claude/hooks/claude-notify

DEVELOPER_DIR ?= $(if $(wildcard /Applications/Xcode.app/Contents/Developer),/Applications/Xcode.app/Contents/Developer,$(shell xcode-select -p))

SWIFT_ENV=CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/clang-module-cache \
	SWIFTPM_MODULECACHE_OVERRIDE=$(CURDIR)/.build/module-cache \
	XDG_CACHE_HOME=$(CURDIR)/.build/.cache \
	HOME=$(CURDIR)/.build/home \
	DEVELOPER_DIR=$(DEVELOPER_DIR)

APP_DIR := $(CURDIR)/claude-notify.app
APP_RESOURCES_DIR := $(APP_DIR)/Contents/Resources
APP_ICON_NAME := claude-code.icns
CLAUDE_ICON_SOURCE ?= /Applications/Claude.app/Contents/Resources/electron.icns

build:
	$(SWIFT_ENV) swift build --disable-sandbox -c release --product claude-notify
	mkdir -p $(APP_DIR)/Contents/MacOS
	cp .build/release/claude-notify $(APP_DIR)/Contents/MacOS/claude-notify
	mkdir -p $(APP_RESOURCES_DIR)
	if [ -f "$(CLAUDE_ICON_SOURCE)" ]; then \
		cp "$(CLAUDE_ICON_SOURCE)" "$(APP_RESOURCES_DIR)/$(APP_ICON_NAME)"; \
	else \
		printf '%s\n' "Warning: Claude icon not found at $(CLAUDE_ICON_SOURCE); using existing app icon assets"; \
	fi
	codesign -s - $(APP_DIR)

clean:
	rm -rf .build
	rm -rf $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/_CodeSignature

check-cases-unit:
	./scripts/check-required-cases.sh unit Sources/NotifyCore Tests/NotifyCoreTests Tests/shell/unit Tests/required-cases.txt

check-cases-integration:
	./scripts/check-required-cases.sh integration Sources/NotifyCore Tests/NotifyCoreTests Tests/shell/integration Tests/required-cases.txt

check-cases-e2e:
	./scripts/check-required-cases.sh e2e Tests/shell/e2e Tests/required-cases.txt

check-docstrings:
	./scripts/check-docstring-coverage.sh --min 80 Sources Tests

check-shell-path-casing:
	./scripts/check-shell-path-casing.sh

test-unit: check-docstrings check-cases-unit check-shell-path-casing
	$(SWIFT_ENV) swift test --disable-sandbox --filter Unit
	Tests/shell/unit/run.sh

test-integration: build check-cases-integration
	$(SWIFT_ENV) swift test --disable-sandbox --filter Integration
	Tests/shell/integration/run.sh

test-e2e: build check-cases-e2e
	Tests/shell/e2e/run.sh

test-fast: test-unit test-integration

test: test-fast test-e2e

uninstall: uninstall-hooks

uninstall-hooks:
	./scripts/uninstall-hooks.sh --all --remove-files \
		--settings "$(SETTINGS_FILE)" --install-dir "$(INSTALL_DIR)"

uninstall-hook-%:
	./scripts/uninstall-hooks.sh --hook "$*" \
		--settings "$(SETTINGS_FILE)" --install-dir "$(INSTALL_DIR)"
