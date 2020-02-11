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
	s/href=[[:blank:]]*\([^"'\''[:blank:]<>][^"'\''[:blank:]<>]*\)/href="\1"/g
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
	| sed -e 's|^/|https://github.com/|' \
	| grep . || die 'Failed to extract download link'
}

# Retrieve the URL to download the latest release
# - Arguments: [user/repo] [filename] [use-beta]?
getLatestRelease(){
	[ "$3" ] && set -- "$1" "$2" '' || set -- "$1" "$2" v
	curl -sSqL "https://github.com/$1/releases.atom" \
	| cleanHrefs \
	| grep -oe ' href="[^"]*/releases/tag/[^"]*"' \
	| grep -$3e '.-beta' \
	| head -n1 \
	| sed -e 's/ href="//; s/"$//' \
	| xargs curl -sSqL \
	| scrapeDownloadURL "$2"
}

# Retrieve the URL to download a specific release, specified by tag-name
# - Arguments: [user/repo] [tag] [filename]
# - Example:   `getReleaseByTag "atom/atom" "v1.25.0" "atom-mac.zip"`
getReleaseByTag(){
	set -- "https://github.com/$1/releases/tag/$2" "$3"
	set -- "$1" "$2" "`curl -sSqL $1`"
	if [ ! "$3" ]; then die "Release not found: `tput smul`$1`tput rmul`" 3; fi
	printf %s "$3" | scrapeDownloadURL "$2"
}

# Download a file.
# - Arguments: [url] [target-filename]
download(){
	printf >&2 'Downloading "%s" from %s%s%s\n' "$2" "`tput smul`" "$1" "`tput sgr0`"
	cmd curl -#fqL -H 'Accept: application/octet-stream' -o "$2" "$1" \
	|| die 'Failed to download file' $?
}

# Download the latest release from a beta or stable channel.
# - Arguments: [user/repo] [channel] [asset]
# - Example:   `downloadByChannel "atom/atom" "beta" "atom-mac.zip"`
downloadByChannel(){
	case $2 in
		beta)   set -- "`getLatestRelease "$1" "$3"`" 1 ;;
		stable) set -- "`getLatestRelease "$1" "$3"`" ;;
		*)      die "Unsupported release channel: $2" ;;
	esac
	download "$1" "$2"
}

# Download a specific release, specified by tag/version-string.
# - Arguments: [user/repo] [tag] [asset]
# - Example:   `downloadByTag "atom/atom" "v1.25.0" "atom-mac.zip"`
downloadByTag(){
	set -- "`getReleaseByTag "$1" "$2" "$3"`" "$3"
	download "$1" "$2"
}

# Download an Atom release
# - Arguments: [asset-file] [channel] [tag]
# - Examples:  `downloadAtom "atom-amd64.deb" "beta"`
#              `downloadAtom "atom-amd64.deb" "" "v1.25.0"`
downloadAtom(){
	[ -f "$1" ]     && cmd rm -rf "$1"
	[ -d .atom-ci ] && cmd rm -rf .atom-ci
	if [ "$3" ];
		then downloadByTag     atom/atom "$3" "$1" # Tag/version-string
		else downloadByChannel atom/atom "$2" "$1" # Beta/stable channel
	fi
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

# Building against a specific release
if [ "$ATOM_RELEASE" ]; then
	title "Installing Atom ($ATOM_RELEASE)"
	case $ATOM_RELEASE in
		*-beta*) ATOM_CHANNEL=beta   ;;
		*)       ATOM_CHANNEL=stable ;;
	esac
else
	# Verify that the requested channel is valid
	ATOM_CHANNEL=${ATOM_CHANNEL:=stable}
	case $ATOM_CHANNEL in
		beta)   title 'Installing Atom (Latest beta release)'   ;;
		stable) title 'Installing Atom (Latest stable release)' ;;
		*)      die   'Unsupported channel: '"$ATOM_CHANNEL"'"' ;;
	esac
fi

case `uname -s | tr A-Z a-z` in
	# macOS
	darwin)
		downloadAtom atom-mac.zip "$ATOM_CHANNEL" "$ATOM_RELEASE"
		cmd mkdir .atom-ci
		cmd unzip -q atom-mac.zip -d .atom-ci
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			ATOM_APP_NAME='Atom Beta.app'
		else
			ATOM_APP_NAME='Atom.app'
		fi
		ATOM_PATH="${PWD}/.atom-ci"
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
		DISPLAY=:99
		export DISPLAY
		
		downloadAtom atom-amd64.deb "$ATOM_CHANNEL" "$ATOM_RELEASE"
		ATOM_PATH="${PWD}/.atom-ci"
		cmd dpkg-deb -x atom-amd64.deb "$ATOM_PATH"
		
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
	if [ -f package-lock.json ] && apmHasCI; then
		printf >&2 'Installing from %s%s%s\n' "$2" package-lock.json "$3"
		cmd "${APM_SCRIPT_PATH}" ci $1
	else
		printf >&2 'Installing from %s%s%s\n' "$2" package.json "$3"
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
