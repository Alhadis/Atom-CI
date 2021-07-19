all: lint dist


# Identify potential portability hassles in shell-scripts
lint: src/*.sh
	shellcheck --severity=warning --shell=sh $^
	checkbashisms $^
	$(ps-lint) -Path src

ps-lint = pwsh -NoLogo -Command Invoke-ScriptAnalyzer \
	-EnableExit \
	-Recurse \
	-Settings '@{Rules = @{PSAvoidUsingCmdletAliases = @{Whitelist = @("%")}}}' \
	-ExcludeRule '@("PSAvoidUsingWriteHost")' \
	-Severity '@("Error", "Warning", "ParseError")'

.PHONY: lint


# Concatenate source files into a single script for each implementation
dist: dist/main.ps1 dist/main.sh

dist/main.ps1: src/*.psm1 src/*.ps1
	printf  > $@ '#!/usr/bin/env pwsh\n'
	printf >> $@ 'Set-StrictMode -Version Latest\n'
	printf >> $@ '$$ErrorActionPreference = "Stop"\n\n'
	cat $^ | sed -f src/strip.sed | cat -s >> $@
	chmod +x $@
	test -n "$$WATCHMAN_ROOT" || $(ps-lint) -Path $@

dist/main.sh: src/*.sh
	printf '#!/bin/sh\n' > $@
	printf 'set -e\n'   >> $@
	cat $^ | sed -f src/strip.sed | cat -s >> $@
	chmod +x $@
	shellcheck -Swarning -ssh $@
	checkbashisms $@


# Nuke generated build targets
clean:
	rm -f dist/*
	git clean -fdx test

.PHONY: clean


# Install Debian packages needed to run Atom headlessly
apt-install:
	sudo apt-get install \
		build-essential \
		fakeroot \
		git \
		libgconf2-4 \
		libsecret-1-dev \
		xvfb \
		libxss1 \
		libnss3


# Regenerate concatenated script when source files are modified
watch:
	watchman watch .
	watchman -- trigger . join-sh 'src/*.sh' -- make dist/main.sh
	watchman -- trigger . join-pwsh 'src/*.psm1' 'src/*.ps1' -- make dist/main.ps1

.PHONY: watch


# Stop monitoring directory for changes
unwatch:
	watchman -- watch-del .

.PHONY: unwatch
