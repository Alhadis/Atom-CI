#!/bin/sh
set -e

# Print a colourful "==> $1"
title(){
	printf >&2 '\e[34m==>\e[0m \e[1m%s\e[0m\n' "$1"
}

# Print a command before executing it
cmd(){
	printf >&2 '\e[32m$ %s\e[0m\n' "$*"
	"$@"
}

# Terminate execution with an error message
die(){
	printf >&2 '\e[1;31mfatal:\e[22m %s\e[0m\n' "$1"
	shift
	exit ${1:-1}
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
	curl -qL "https://github.com/$1/releases/latest" | scrapeDownloadURL "$2"
}

# Retrieve the URL to download the latest beta release
# - Arguments: [user/repo] [filename]
getLatestBetaRelease(){
	curl -qL "https://github.com/$1/releases.atom" \
	| cleanHrefs \
	| grep -oe ' href="[^"]*/releases/tag/[^"]*"' \
	| grep -e '.-beta' \
	| head -n1 \
	| sed -e 's/ href="//; s/"$//' \
	| xargs curl -qL \
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
	printf >&2 'Downloading "%s" from \e[4m%s\e[0m\n' "$2" "$1"
	cmd curl -#fqL -H 'Accept: application/octet-stream' -o "$2" "$1" \
	|| die 'Failed to download Atom' $?
}

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
			ATOM_SCRIPT_NAME='atom-beta'
			ATOM_SCRIPT_PATH='./atom-beta'
			cmd ln -s "${PWD}/$2/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh" "${ATOM_SCRIPT_PATH}"
		else
			ATOM_APP_NAME='Atom.app'
			ATOM_SCRIPT_NAME='atom.sh'
			ATOM_SCRIPT_PATH="${PWD}/$2/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh"
		fi
		
		ATOM_PATH="${PWD}/$2"
		APM_SCRIPT_PATH="${PWD}/$2/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/apm"
		NPM_SCRIPT_PATH="${PWD}/$2/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${PWD}/$2/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin"
		export APM_SCRIPT_PATH ATOM_APP_NAME ATOM_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
		cmd ln -fs "${PWD}/${ATOM_SCRIPT_PATH#./}" "${APM_SCRIPT_PATH%/*}/atom"
		cmd env | sort
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
			--pidfile /tmp/custom_xvfb_99.pid \
			--make-pidfile \
			--background \
			--exec /usr/bin/Xvfb \
			-- :99 -ac -screen 0 1280x1024x16
		DISPLAY=:99; export DISPLAY
		cmd dpkg-deb -x "$1" "${HOME}/$2"
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			ATOM_SCRIPT_NAME='atom-beta'
			APM_SCRIPT_NAME='apm-beta'
		else
			ATOM_SCRIPT_NAME='atom'
			APM_SCRIPT_NAME='apm'
		fi
		ATOM_SCRIPT_PATH="${HOME}/$2/usr/bin/${ATOM_SCRIPT_NAME}"
		APM_SCRIPT_PATH="${HOME}/$2/usr/bin/${APM_SCRIPT_NAME}"
		NPM_SCRIPT_PATH="${HOME}/$2/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${HOME}/$2/usr/bin:${NPM_SCRIPT_PATH%/*}"
		export APM_SCRIPT_NAME APM_SCRIPT_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
		cmd ln -fs "${PWD}/${ATOM_SCRIPT_PATH#./}" "${APM_SCRIPT_PATH%/*}/atom"
		cmd env | sort
	;;
esac

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
	title 'Installing dependencies'
	if [ -f package-lock.json ]; then
		printf >&2 'Installing from \e[4m%s\e[24m\n' package-lock.json
		cmd "${APM_SCRIPT_PATH}" ci $1
	else
		printf >&2 'Installing from \e[4m%s\e[24m\n' package.json
		cmd "${APM_SCRIPT_PATH}" install $1
		cmd "${APM_SCRIPT_PATH}" clean
	fi
}

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
