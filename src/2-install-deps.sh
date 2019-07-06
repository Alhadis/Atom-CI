#!/bin/sh
set -e

#
# 2. Download and install dependencies
#

# shellcheck source=./0-shared.sh
. "${0%/*}"/0-shared.sh

ATOM_SCRIPT_PATH=${ATOM_SCRIPT_PATH:=atom}
APM_SCRIPT_PATH=${APM_SCRIPT_PATH:=apm}

# Print title and version statistics
title 'Installing dependencies'

printf >&2 '\e[1mAtom version:\e[0m\n'
"${ATOM_SCRIPT_PATH}" -v \
| sed -e 's/^/    /g'

printf >&2 '\e[1mAPM version:\e[0m\n'
"${APM_SCRIPT_PATH}"  -v --no-color \
| sed -E 's/ +/: /' \
| sort \
| sed -e 's/^/    /g'

# Download using bundled version of Node
if [ "${ATOM_LINT_WITH_BUNDLED_NODE:=true}" = true ]; then
	printf >&2 'Using bundled version of Node\n'
	if [ -f package-lock.json ]; then
		cmd "${APM_SCRIPT_PATH}" ci
	else
		cmd "${APM_SCRIPT_PATH}" install
		cmd "${APM_SCRIPT_PATH}" clean
	fi
	case `uname -s | tr A-Z a-z` in
		darwin) PATH="./.atom-ci/${ATOM_APP_NAME}/Contents/Resources/app/apm/bin:${PATH}" ;;
		*) PATH="${HOME}/.atom-ci/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/bin:${PATH}" ;;
	esac
	export PATH

# Download using system's version of NPM
else
	printf >&2 'Using system versions of Node/NPM'
	NPM_SCRIPT_PATH='npm'; export NPM_SCRIPT_PATH
	printf >&2 '\e[1mNode version:\e[0m\n'; node --version | sed -e 's/^/    /g'
	printf >&2 '\e[1mNPM version:\e[0m\n';  npm --version  | sed -e 's/^/    /g'
	if [ -f package-lock.json ]; then
		cmd "${APM_SCRIPT_PATH}" ci --production
	else
		cmd "${APM_SCRIPT_PATH}" install --production
		cmd "${APM_SCRIPT_PATH}" clean
	fi
	cmd npm install
fi

if [ "$APM_TEST_PACKAGES" ]; then
	for pkg in $APM_TEST_PACKAGES; do
		cmd "${APM_SCRIPT_PATH}" install "${pkg}"
	done
fi
