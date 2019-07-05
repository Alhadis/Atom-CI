#!/bin/sh
set -e

#
# Download and install dependencies
#

# Print version statistics for debugging
printf '\e[1mAtom version:\e[0m\n'; "${ATOM_SCRIPT_PATH}" -v | sed -e 's/^/    /g'
printf '\e[1mAPM version:\e[0m\n';  "${APM_SCRIPT_PATH}"  -v | sed -e 's/^/    /g'

# Download using bundled version of Node
if [ "${ATOM_LINT_WITH_BUNDLED_NODE:=true}" = true ]; then
	if [ -f package-lock.json ]; then
		"${APM_SCRIPT_PATH}" ci
	else
		"${APM_SCRIPT_PATH}" install
		"${APM_SCRIPT_PATH}" clean
	fi
	case `uname -s | tr A-Z a-z` in
		darwin) PATH="./atom/${ATOM_APP_NAME}/Contents/Resources/app/apm/bin:${PATH}" ;;
		*) PATH="${HOME}/atom/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/bin:${PATH}" ;;
	esac
	export PATH
	
# Download using system's version of NPM
else
	NPM_SCRIPT_PATH='npm'; export NPM_SCRIPT_PATH
	printf '\e[1mNode version:\e[0m\n'; node --version | sed -e 's/^/    /g'
	printf '\e[1mNPM version:\e[0m\n';  npm --version  | sed -e 's/^/    /g'
	if [ -f package-lock.json ]; then
		"${APM_SCRIPT_PATH}" ci --production
	else
		"${APM_SCRIPT_PATH}" install --production
		"${APM_SCRIPT_PATH}" clean
	fi
	npm install
fi

if [ "$APM_TEST_PACKAGES" ]; then
	for pkg in $APM_TEST_PACKAGES; do
		"${APM_SCRIPT_PATH}" install "${pkg}"
	done
fi
