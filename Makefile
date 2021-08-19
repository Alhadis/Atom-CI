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
	-ExcludeRule '@("PSAvoidUsingWriteHost", "PSAvoidUsingInvokeExpression")' \
	-Severity '@("Error", "Warning", "ParseError")'

.PHONY: lint


# Concatenate source files into a single script for each implementation
dist: dist/main.ps1 dist/main.sh

dist/main.ps1: src/*.psm1 src/*.ps1
	printf  > $@ '#!/usr/bin/env pwsh\n'
	printf >> $@ 'Set-StrictMode -Version Latest\n'
	printf >> $@ '$$ErrorActionPreference = "Stop"\n\n'
	cat $^ | sed -f src/strip.sed | sed -f src/pwsh-prod.sed | cat -s >> $@
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
	sudo apt-get update
	sudo apt-get install -y \
		build-essential \
		ca-certificates \
		fakeroot \
		fonts-liberation \
		gconf-service \
		git \
		libappindicator1 \
		libasound2 \
		libatk-bridge2.0-0 \
		libatk1.0-0 \
		libc6 \
		libcairo2 \
		libcups2 \
		libdbus-1-3 \
		libexpat1 \
		libfontconfig1 \
		libgbm-dev \
		libgcc1 \
		libgconf-2-4 \
		libgconf2-4 \
		libgdk-pixbuf2.0-0 \
		libglib2.0-0 \
		libgtk-3-0 \
		libgtk2.0-0 \
		libnotify-dev \
		libnspr4 \
		libnss3 \
		libnss3 \
		libpango-1.0-0 \
		libpangocairo-1.0-0 \
		libsecret-1-dev \
		libstdc++6 \
		libx11-6 \
		libx11-xcb1 \
		libxcb1 \
		libxcomposite1 \
		libxcursor1 \
		libxdamage1 \
		libxext6 \
		libxfixes3 \
		libxi6 \
		libxrandr2 \
		libxrender1 \
		libxss1 \
		libxtst6 \
		lsb-release \
		wget \
		xauth \
		xdg-utils \
		xvfb
	@ command -v node >/dev/null 2>&1 || "$(MAKE)" apt-install-node
	@ command -v pwsh >/dev/null 2>&1 || "$(MAKE)" apt-install-powershell


# Install Node.js for Ubuntu
# - Source: https://github.com/nodesource/distributions/blob/master/README.md#deb
apt-install-node:
	curl -fsSL 'https://deb.nodesource.com/setup_current.x' | sudo -E bash -
	sudo apt-get install -y nodejs


# Install PowerShell for Ubuntu
# - Source: https://docs.microsoft.com/powershell/scripting/install/installing-powershell-core-on-linux
apt-install-powershell:
	sudo apt-get install -y wget apt-transport-https software-properties-common
	wget "https://packages.microsoft.com/config/ubuntu/`lsb_release -sr`/packages-microsoft-prod.deb"
	sudo dpkg -i packages-microsoft-prod.deb
	rm -f packages-microsoft-prod.deb
	sudo apt-get update
	sudo apt-get install -y powershell


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
