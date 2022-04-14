export MAIN_BRANCH ?= main

.DEFAULT_GOAL := help
.PHONY: test build build/binary build/local clean test/coverage release/prepare release/tag .check_bump_type .check_git_clean help

GIT_BRANCH := $(shell git symbolic-ref --short HEAD)
WORKTREE_CLEAN := $(shell git status --porcelain 1>/dev/null 2>&1; echo $$?)
SCRIPTS_DIR := $(CURDIR)/scripts

versionFile = $(CURDIR)/.VERSION
curVersion := $(shell cat $(versionFile) | sed 's/^v//')

INJECTOR_NAME := onepassword-secrets-injector
INJECTOR_DOCKER_IMG_TAG ?= $(INJECTOR_NAME):v$(curVersion)

test:	## Run test suite
	go test ./...

test/coverage:	## Run test suite with coverage report
	go test -v ./... -cover

build/secret-injector:	## Build secret-injector Docker image
	@docker build -f secret-injector/Dockerfile --build-arg injector_version=$(curVersion) -t $(INJECTOR_DOCKER_IMG_TAG) .
	@echo "Successfully built and tagged image."
	@echo "Tag: $(INJECTOR_DOCKER_IMG_TAG)"

build/secret-injector/local:	## Build local version of the secret-injector Docker image 
	@docker build -f secret-injector/Dockerfile -t local/$(INJECTOR_DOCKER_IMG_TAG) .

build/secret-injector/binary: clean	## Build secret-injector binary
	@mkdir -p dist
	@go build -mod vendor -a -o manager ./secret-injector/cmd/manager/main.go
	@mv manager ./dist

clean:
	rm -rf ./dist

help:	## Prints this help message
	@grep -E '^[\/a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'


## Release functions =====================

release/prepare: .check_git_clean	## Updates changelog and creates release branch (call with 'release/prepare version=<new_version_number>')

	@test $(version) || (echo "[ERROR] version argument not set."; exit 1)
	@git fetch --quiet origin $(MAIN_BRANCH)

	@echo $(version) | tr -d '\n' | tee $(versionFile) &>/dev/null

	@NEW_VERSION=$(version) $(SCRIPTS_DIR)/prepare-release.sh

release/tag: .check_git_clean	## Creates git tag
	@git pull --ff-only
	@echo "Applying tag 'v$(curVersion)' to HEAD..."
	@git tag --sign "v$(curVersion)" -m "Release v$(curVersion)"
	@echo "[OK] Success!"
	@echo "Remember to call 'git push --tags' to persist the tag."

## Helper functions =====================

.check_git_clean:
ifneq ($(GIT_BRANCH), $(MAIN_BRANCH))
	@echo "[ERROR] Please checkout default branch '$(MAIN_BRANCH)' and re-run this command."; exit 1;
endif
ifneq ($(WORKTREE_CLEAN), 0)
	@echo "[ERROR] Uncommitted changes found in worktree. Address them and try again."; exit 1;
endif