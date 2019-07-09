#!/bin/sh
set -e

# Print a colourful "==> $1"
title(){
	set -- "$1" "`tput setaf 4`" "`tput bold`" "`tput sgr0`"
	printf >&2 '%s==>%s %s%s%s\n' "$2" "$4" "$3" "$1" "$4"
}

# Print a colourful shell-command prefixed by a "$ "
cmdfmt(){
	printf >&2 '%s$ %s%s\n' "`tput setaf 2`" "$*" "`tput sgr0`"
}

# Print a command before executing it
cmd(){
	cmdfmt "$*"
	"$@"
}

# Terminate execution with an error message
die(){
	set -- "$1" "$2" "`tput bold`" "`tput setaf 1`" "`tput sgr0`"
	printf >&2 '%s%sfatal:%s%s %s%s\n' "$3" "$4" "$5" "$4" "$1" "$5"
	exit ${2:-1}
}

# Emit an arbitrary byte-sequence to standard output
putBytes(){
	printf %b "`printf \\\\%03o "$@"`"
}

# Output a control-sequence introducer for an ANSI escape code
csi(){
	putBytes 27 91
}

# TravisCI: Begin a named folding region
startFold(){
	if [ ! "$TRAVIS_JOB_ID" ]; then return; fi
	set -- "$1" "`csi`"
	printf 'travis_fold:start:%s\r%s0K' "$1" "$2"
}

# TravisCI: Close a named folding region
endFold(){
	if [ ! "$TRAVIS_JOB_ID" ]; then return; fi
	set -- "$1" "`csi`"
	printf 'travis_fold:end:%s\r%s0K' "$1" "$2"
}

# Abort script if current directory lacks a test directory and package.json file
assertValidProject(){
	[ -f package.json ] || die 'No package.json file found'
	[ -s package.json ] || die 'package.json appears to be empty'
	[ -d spec ] || [ -d specs ] || [ -d test ] || [ -d tests ] \
		|| die 'Project must contain a test directory'
}

# Check if a devDependency is listed in package.json
haveDep(){
	"${NPM_SCRIPT_PATH}" ls --parseable --dev --depth=0 "$1" 2>/dev/null | grep -q "$1$"
}

# Check if package.json defines a script of the specified name
haveScript(){
	node -p '(require("./package.json").scripts || {})["'"$1"'"] || ""' | grep -q .
}

# Normalise formatting of `href` attributes for more reliable matching
# - E.g: HREF=value or href = 'value' become href="value"
cleanHrefs(){
	sed -e ':x
	/[Hh][Rr][Ee][Ff][[:blank:]]*$/,/=/ {
		N
		s/\n//g
		bx
	}
	s/[Hh][Rr][Ee][Ff][[:blank:]]*=/href=/g
	/href=[[:blank:]]*$/ {
		N
		s/\n//g
		bx
	}
	s/href=[[:blank:]]*'\''\([^'\'']*\)'\''/href="\1"/g
	s/href=\([^"'\''[:blank:]][^"'\''[:blank:]]*\)/href="\1"/g
	s/href[[:blank:]]*=[[:blank:]]*"/href="/g
	s/^href=/ href=/g
	s/[[:blank:]]href=/ href=/g'
}

# Extract a download link from a release page
# - Arguments: [filename] (default: "atom-mac.zip")
scrapeDownloadURL(){
	if [ ! "$1" ]; then set -- atom-mac.zip; fi
	set -- "`printf %s "$1" | sed -e 's/\\./\\\\./g'`"
	cleanHrefs \
	| grep -oe ' href="[^"]*'"$1"'"' \
	| sed -e 's/^ href="//; s/"$//' \
	| sed -e 's|^/|https://github.com/|'
}

# Retrieve the URL to download the latest stable release
# - Arguments: [user/repo] [filename]
getLatestStableRelease(){
	curl -sSqL "https://github.com/$1/releases/latest" | scrapeDownloadURL "$2"
}

# Retrieve the URL to download the latest beta release
# - Arguments: [user/repo] [filename]
getLatestBetaRelease(){
	curl -sSqL "https://github.com/$1/releases.atom" \
	| cleanHrefs \
	| grep -oe ' href="[^"]*/releases/tag/[^"]*"' \
	| grep -e '.-beta' \
	| head -n1 \
	| sed -e 's/ href="//; s/"$//' \
	| xargs curl -sSqL \
	| scrapeDownloadURL "$2"
}

# Download the latest Atom release as a ZIP or Debian package
# - Arguments: [release-type] [saved-filename]
# - Example:   `downloadAtom beta atom-mac.zip`
downloadAtom(){
	case $1 in
		beta)   set -- "`getLatestBetaRelease   atom/atom "$2"`" "$2" ;;
		stable) set -- "`getLatestStableRelease atom/atom "$2"`" "$2" ;;
		*)      die "Unsupported release type: $1"       ;;
	esac
	printf >&2 'Downloading "%s" from %s%s%s\n' "$2" "`tput smul`" "$1" "`tput sgr0`"
	cmd curl -#fqL -H 'Accept: application/octet-stream' -o "$2" "$1" \
	|| die 'Failed to download Atom' $?
}

# Create an "alias" of an executable that simply calls the source file
# with the same arguments. Necessary because `atom.sh` tries to be smart
# about resolving symlinks and using $0 to determine the $CHANNEL (making
# it impossible to symlink `atom-beta` as `atom` so scripts don't break).
# - Arguments: [source-file] [alias-name]
# - Example: mkalias ./usr/bin/atom-beta atom
mkalias(){
	set -- "${1##*/}" "${1%/*}/${2##*/}"
	printf '#!/bin/sh\n"${0%%/*}"/%s "$@"\n' "$1" > "$2"
	chmod +x "$2"
}

assertValidProject
startFold 'install-atom'

# Verify that the requested channel is valid
ATOM_CHANNEL=${ATOM_CHANNEL:=stable}
case $ATOM_CHANNEL in
	beta)   title 'Installing Atom (Latest beta release)'   ;;
	stable) title 'Installing Atom (Latest stable release)' ;;
	*)      die   'Unsupported channel: '"$ATOM_CHANNEL"'"' ;;
esac

case `uname -s | tr A-Z a-z` in
	# macOS
	darwin)
		set -- atom-mac.zip .atom-ci
		[ -f "$1" ] && cmd rm -rf "$1"
		[ -d "$2" ] && cmd rm -rf "$2"
		downloadAtom "$ATOM_CHANNEL" "$1"
		cmd mkdir .atom-ci
		cmd unzip -q "$1" -d "$2"
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			ATOM_APP_NAME='Atom Beta.app'
		else
			ATOM_APP_NAME='Atom.app'
		fi
		
		ATOM_PATH="${PWD}/$2"
		ATOM_SCRIPT_NAME='atom.sh'
		ATOM_SCRIPT_PATH="${ATOM_PATH}/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh"
		APM_SCRIPT_PATH="${ATOM_PATH}/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/apm"
		NPM_SCRIPT_PATH="${ATOM_PATH}/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${ATOM_PATH}/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin"
		export APM_SCRIPT_PATH ATOM_APP_NAME ATOM_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
		cmd ln -fs "$ATOM_SCRIPT_PATH" "${APM_SCRIPT_PATH%/*}/atom"
	;;
	
	# Linux (Debian assumed)
	linux)
		set -- atom-amd64.deb .atom-ci
		[ -f "$1" ] && cmd rm -rf "$1"
		[ -d "$2" ] && cmd rm -rf "$2"
		downloadAtom "$ATOM_CHANNEL" "$1"
		
		cmd /sbin/start-stop-daemon \
			--start \
			--quiet \
			--oknodo \
			--pidfile /tmp/custom_xvfb_99.pid \
			--make-pidfile \
			--background \
			--exec /usr/bin/Xvfb \
			-- :99 -ac -screen 0 1280x1024x16 \
			|| die 'Unable to start Xvfb'
		DISPLAY=:99; export DISPLAY
		
		ATOM_PATH="${PWD}/$2"
		cmd dpkg-deb -x "$1" "$ATOM_PATH"
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			ATOM_SCRIPT_NAME='atom-beta'
			APM_SCRIPT_NAME='apm-beta'
		else
			ATOM_SCRIPT_NAME='atom'
			APM_SCRIPT_NAME='apm'
		fi
		ATOM_SCRIPT_PATH="${ATOM_PATH}/usr/bin/${ATOM_SCRIPT_NAME}"
		APM_SCRIPT_PATH="${ATOM_PATH}/usr/bin/${APM_SCRIPT_NAME}"
		NPM_SCRIPT_PATH="${ATOM_PATH}/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${ATOM_PATH}/usr/bin:${NPM_SCRIPT_PATH%/*}"
		export APM_SCRIPT_NAME APM_SCRIPT_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			[ -f "${ATOM_PATH}/usr/bin/atom" ] || mkalias "${ATOM_PATH}/usr/bin/atom-beta" atom
			[ -f "${ATOM_PATH}/usr/bin/apm"  ] || mkalias "${ATOM_PATH}/usr/bin/apm-beta" apm
		fi
	;;
esac

startFold 'env-dump'
cmdfmt 'env | sort'
env | sort
endFold 'env-dump'

endFold 'install-atom'

ATOM_SCRIPT_PATH=${ATOM_SCRIPT_PATH:=atom}
APM_SCRIPT_PATH=${APM_SCRIPT_PATH:=apm}

# Display version info for Atom/Node/?PM
showVersions(){
	printf >&2 'Printing version info\n'
	cmd "${ATOM_SCRIPT_PATH}" --version
	cmd "${APM_SCRIPT_PATH}"  --version --no-color
	if [ $# -eq 0 ]; then return 0; fi
	cmd node --version
	cmd npm --version
}

# Install packages with `apm`
apmInstall(){
	endFold 'installers'
	startFold 'install-deps'
	title 'Installing dependencies'
	set -- "$1" "`tput smul`" "`tput rmul`"
	if [ -f package-lock.json ]; then
		printf >&2 'Installing from %s%s%s\n' "$2" package-lock.json "$3"
		cmd "${APM_SCRIPT_PATH}" ci $1
	else
		printf >&2 'Installing from %s%s%s\n' "$2" package.json "$3"
		cmd "${APM_SCRIPT_PATH}" install $1
		cmd "${APM_SCRIPT_PATH}" clean
	fi
}

startFold 'installers'
title 'Resolving installers'

# Download using bundled version of Node
if [ "${ATOM_LINT_WITH_BUNDLED_NODE:=true}" = true ]; then
	printf >&2 'Using bundled version of Node\n'
	showVersions
	apmInstall
	case `uname -s | tr A-Z a-z` in
		darwin) PATH="./.atom-ci/${ATOM_APP_NAME}/Contents/Resources/app/apm/bin:${PATH}" ;;
		*) PATH="${HOME}/.atom-ci/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/bin:${PATH}" ;;
	esac
	export PATH

# Download using system's version of NPM
else
	printf >&2 'Using system versions of Node/NPM\n'
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

title 'Running tasks'

ATOM_SCRIPT_PATH=${ATOM_SCRIPT_PATH:=atom}
APM_SCRIPT_PATH=${APM_SCRIPT_PATH:=apm}
NPM_SCRIPT_PATH=${NPM_SCRIPT_PATH:=npm}

# Run "lint" script if one exists in package.json; otherwise, use assumed defaults
if haveScript lint; then
	cmd "${NPM_SCRIPT_PATH}" run lint
else
	for linter in coffeelint eslint tslint; do
		haveDep $linter || continue
		printf >&2 'Linting package with %s...\n' "$linter"
		for dir in lib src spec test; do
			if [ -d $dir ]; then
				cmd npx $linter ./$dir || exit $?
			fi
		done
	done
fi

# Run the package "test" script if one exists; otherwise, locate test-suite manually
if haveScript test; then
	cmd "${NPM_SCRIPT_PATH}" run test
else
	for dir in spec specs test tests; do
		if [ -d $dir ]; then
			printf >&2 'Running specs...\n'
			cmd "${ATOM_SCRIPT_PATH}" --test "./$dir" || exit $?
			break;
		fi
	done
fi
