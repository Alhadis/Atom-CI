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

# Load JSON data using curl(1)
loadJSON(){
	printf >&2 '\e[32m$ \e[1mcurl\e[22m -#fq \e[4m%s\e[0m\n' "$1"
	curl -#fq "$1"
}

# Retrieve the ID of the latest stable release
# - Arguments: [user/repo]
latestStableID(){
	printf >&2 'Getting ID of latest stable release\n'
	{ loadJSON "https://api.github.com/repos/$1/releases/latest" \
	| grep -oE '"id"\s*:\s*[0-9]+' \
	| head -n1 \
	| cut -f2 -d:; } \
	|| die 'Failed to load release ID' $?
}

# Retrieve the tag-name of the latest stable release
# - Arguments: [user/repo]
latestStableTag(){
	printf >&2 'Getting tag-name of latest stable release\n'
	{ loadJSON "https://api.github.com/repos/$1/releases/latest" \
	| grep -ioE '"tag_name"\s*:\s*"[^\"]+"' \
	| head -n1 \
	| cut -f2 -d: \
	| tr -d '"'; } \
	|| die 'Failed to load tag-name' $?
}

# Retrieve tag-name of latest beta release
# - Arguments: [user/repo]
latestBetaTag(){
	printf >&2 'Getting tag-name of latest beta release\n'
	{ loadJSON "https://api.github.com/repos/$1/releases" \
	| grep -ioE '"tag_name"\s*:\s*"[^\"]+-beta[0-9]*"' \
	| head -n1 \
	| cut -f2 -d: \
	| tr -d '"'; } \
	|| die 'Failed to load tag-name' $?
}

# Retrieve the ID of the latest beta release
# - Arguments: [user/repo]
latestBetaID(){
	getIDForTag "$1" "`latestStableTag "$1"`"
}

# Retrieve the ID of a tagged release
# - Arguments: [user/repo] [tag-name]
getIDForTag(){
	printf >&2 'Getting release ID for tag "%s"\n' "$2"
	{ loadJSON "https://api.github.com/repos/$1/releases/tags/$2" \
	| grep -m1 -oE '"id"\s*:\s*[0-9]+' \
	| head -n1 \
	| cut -f2 -d:; } \
	|| die 'Failed to load release ID' $?
}

# Retrieve the download URL of a release asset
# - Arguments: [user/repo] [release-id] [asset-filename]
getAssetURL(){
	printf >&2 'Getting URL for asset "%s"\n' "$3"
	{ loadJSON "https://api.github.com/repos/$1/releases/$2/assets" \
	| grep -oE '"browser_download_url"\s*:\s*"[^\"]+/'"$3"'"' \
	| cut -d: -f2,3 \
	| tr -d '"' \
 	| grep '^http'; } \
	|| die 'Unable to load asset URL' $?
}

# Download an asset file
# - Arguments: [source-url] [target-file]
downloadAsset(){
	printf >&2 'Downloading "%s" from \e[4m%s\e[0m\n' "$2" "$1"
	cmd curl -#fqL -H 'Accept: application/octet-stream' -o "$2" "$1" \
	|| die 'Failed to download file' $?
}

# Download the latest Atom release as a ZIP or Debian package
# - Arguments: [release-type] [saved-filename]
# - Example:   `downloadAtom beta atom-mac.zip`
downloadAtom(){
	case $1 in
		beta)   set -- "`latestBetaID atom/atom`"   "$2" ;;
		stable) set -- "`latestStableID atom/atom`" "$2" ;;
		*)      die "Unsupported release type: $1"       ;;
	esac
	downloadAsset "`getAssetURL atom/atom "$1" "$2"`" "$2" \
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
			cmd ln -s "./$2/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh" "${ATOM_SCRIPT_PATH}"
		else
			ATOM_APP_NAME='Atom.app'
			ATOM_SCRIPT_NAME='atom.sh'
			ATOM_SCRIPT_PATH="./$2/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh"
		fi
		
		ATOM_PATH="./$2"
		APM_SCRIPT_PATH="./$2/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/apm"
		NPM_SCRIPT_PATH="./$2/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${TRAVIS_BUILD_DIR}/$2/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin"
		export APM_SCRIPT_PATH ATOM_APP_NAME ATOM_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
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
		dpkg-deb -x "$1" "${HOME}/$2"
		
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
		PATH="${PATH}:${HOME}/$2/usr/bin"
		export APM_SCRIPT_NAME APM_SCRIPT_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
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
