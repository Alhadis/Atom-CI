#!/bin/sh
set -e

#
# 2. Download and install dependencies
#

# shellcheck source=./0-shared.sh
. "${0%/*}"/0-shared.sh
assertValidProject # DEBUG

ATOM_SCRIPT_PATH=${ATOM_SCRIPT_PATH:=atom}
APM_SCRIPT_PATH=${APM_SCRIPT_PATH:=apm}


# Display version info for Atom/Node/?PM
showVersions(){
	printf 'Printing version info\n'
	ATOM_CI_DRY_RUN="" cmd "${ATOM_SCRIPT_PATH}" --version
	ATOM_CI_DRY_RUN="" cmd "${APM_SCRIPT_PATH}"  --version --no-color
	if [ $# -eq 0 ]; then return 0; fi
	ATOM_CI_DRY_RUN="" cmd node --version
	ATOM_CI_DRY_RUN="" cmd npm --version
}

# Install packages with `apm`
apmInstall(){
	endFold 'installers'
	startFold 'install-deps' 'Installing dependencies'
	set -- "$1" "`sgr 4`" "`sgr 24`"
	if [ -f package-lock.json ] && apmHasCI; then
		printf 'Installing from %s%s%s\n' "$2" package-lock.json "$3"
		cmd "${APM_SCRIPT_PATH}" ci $1
	else
		printf 'Installing from %s%s%s\n' "$2" package.json "$3"
		cmd "${APM_SCRIPT_PATH}" install $1
		cmd "${APM_SCRIPT_PATH}" clean
	fi
}

# Determine whether this version of APM supports the `ci`
# subcommand, which was added in atom/apm@2a6dc13 (v2.1.0).
apmHasCI(){
	# shellcheck disable=SC2046
	set -- `apm --version --no-color \
	| grep -i apm \
	| head -n1 \
	| sed -e '
		s/^[[:blank:]]*[Aa][Pp][Mm][[:blank:]]*[Vv]*//
		s/[[:blank:]]*$//
		s/+.*$//
		s/-[-A-Za-z0-9.].*$//
		s/$/.0.0.0.0/
		s/^\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\).*$/\1 \2 \3/'`
	[ "$1" -gt 2 ] || [ "$1" -eq 2 ] && [ "$2" -ge 1 ]
}

startFold 'installers' 'Resolving installers'

# Download using bundled version of Node
if [ "${ATOM_LINT_WITH_BUNDLED_NODE:=true}" = true ]; then
	printf 'Using bundled version of Node\n'
	showVersions
	apmInstall
	case `uname -s | tr A-Z a-z` in
		darwin) PATH="./.atom-ci/${ATOM_APP_NAME}/Contents/Resources/app/apm/bin:${PATH}" ;;
		*) PATH="${HOME}/.atom-ci/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/bin:${PATH}" ;;
	esac
	export PATH

# Download using system's version of NPM
else
	printf 'Using system versions of Node/NPM\n'
	NPM_SCRIPT_PATH='npm'; export NPM_SCRIPT_PATH
	showVersions --all
	apmInstall --production
	cmd npm install
fi

if [ "$APM_TEST_PACKAGES" ]; then
	for pkg in $APM_TEST_PACKAGES; do
		cmd "${APM_SCRIPT_PATH}" install "${pkg}"
	done
fi

endFold 'install-deps'
