# Root orchestrator Makefile for local hook projects.

.PHONY: install install-hooks install-skills diff build test test-fast test-unit \
	test-integration test-e2e \
	check-cases-unit check-cases-integration check-cases-e2e check-docstrings \
	all clean

HOOKS_DIR := hooks
HOOKS := claude-notify
CLAUDE_NOTIFY_DIR := $(HOOKS_DIR)/$(firstword $(HOOKS))
SUB_MAKE := $(MAKE) -C $(CLAUDE_NOTIFY_DIR)
INSTALL_HOOK_DIR := $(HOME)/.claude/hooks/claude-notify

SKILLS_DIR := skills
SKILLS := $(notdir $(patsubst %/,%,$(wildcard $(SKILLS_DIR)/*/)))
AGENTS_SKILLS_DIR := $(HOME)/.agents/skills

all: build

install: install-hooks install-skills

install-hooks:
	@mkdir -p "$(INSTALL_HOOK_DIR)"
	rsync -a --delete \
		--exclude='.build/' \
		"$(CLAUDE_NOTIFY_DIR)/" "$(INSTALL_HOOK_DIR)/"

install-skills:
	@mkdir -p "$(AGENTS_SKILLS_DIR)"
	@for skill in $(SKILLS); do \
		rm -rf "$(AGENTS_SKILLS_DIR)/$$skill"; \
		ln -sfn "$(CURDIR)/$(SKILLS_DIR)/$$skill" "$(AGENTS_SKILLS_DIR)/$$skill"; \
	done

diff:
	diff -rq --exclude='.build' "$(CLAUDE_NOTIFY_DIR)" "$(INSTALL_HOOK_DIR)"

build:
	$(SUB_MAKE) build

clean:
	$(SUB_MAKE) clean

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
