#!/bin/sh
set -e

# Print a colourful "==> $1"
title(){
	printf >&2 '\e[31m==>\e[0m \e[1m%s\e[0m\n' "$1"
}

# Print a command before executing it
cmd(){
	printf >&2 '\e[38;5;28m$\e[0m \e[32m%s\e[0m\n' "$*"
	"$@"
}

# Check if a devDependency is listed in package.json
haveDep(){
	"${NPM_SCRIPT_PATH}" ls --parseable --dev --depth=0 "$1" 2>/dev/null | grep -q "$1$"
}

# Check if package.json defines a script of the specified name
haveScript(){
	node -p '(require("./package.json").scripts || {})["'"$1"'"] || ""' | grep -q .
}

# Retrieve the ID of the latest beta release
getBetaID(){
	printf >&2 'Getting tag of latest beta release... '
	set -- "`curl -s https://api.github.com/repos/atom/atom/releases \
	| grep -ioE '"tag_name"\s*:\s*"[^\"]+-beta[0-9]*"' \
	| head -n1 \
	| cut -f2 -d: \
	| tr -d '\"'`"
	printf >&2 '\e[4m%s\e[0m\n' "$1"
	
	printf >&2 'Getting release ID... '
	set -- "`curl -s https://api.github.com/repos/atom/atom/releases/tags/$1 \
	| grep -m1 -oE '"id"\s*:\s*[0-9]+' \
	| head -n1 \
	| cut -f2 -d:`"
	printf >&2 '\e[4m%s\e[0m\n' "$1"
	printf %s "$1"
}

# Retrieve the ID of the latest stable release
getStableID(){
	printf >&2 'Getting ID of latest stable release... '
	set -- "`curl -s https://api.github.com/repos/atom/atom/releases/latest \
	| grep -oE '"id"\s*:\s*[0-9]+' \
	| head -n1 \
	| cut -f2 -d:`"
	printf >&2 '\e[4m%s\e[0m\n' "$1"
	printf %s "$1"
}

# Retrieve the download URL of a release asset
# - getAssetURL [asset-filename] [release-id]
getAssetURL(){
	printf >&2 'Getting URL of asset "%s"... ' "$1"
	set -- "`curl -s https://api.github.com/repos/atom/atom/releases/$2/assets \
	| grep -oE '"browser_download_url"\s*:\s*"[^\"]+/'"$1"'"' \
	| cut -d: -f2,3 \
	| tr -d '\"'`"
	case $1 in
		http*)
			printf >&2 '\e[4m%s\e[0m\n' "$1"
			printf %s "$1"
		;;
		*)
			printf >&2 '\e[1m%s\e[0m\n' "Not found"
			return 1
		;;
	esac
}

# Download an asset file
# - download [save-as] [from-url]
downloadAsset(){
	printf >&2 'Downloading "%s" from \e[4m%s\e[0m...\n' "$1" "$2"
	curl -# -LH 'Accept: application/octet-stream' -o "$1" "$2" || {
		set -- "$1" "$2" "$?"
		printf >&2 'Failed to download \e[4m%s\e[0m from \e[4m%s\e[0m\n' "$1" "$2"
		exit $3
	}
}

# 1. Download and install the latest Atom release.


if [ "$ATOM_CHANNEL" = beta ]; then
	title 'Installing Atom (Latest beta release)'
	set -- "`getBetaID`"
else
	title 'Installing Atom (Latest stable release)'
	set -- "`getStableID`"
fi

case `uname -s | tr A-Z a-z` in
	# macOS
	darwin)
		set -- atom-mac.zip "$1" .atom-ci
		[ -f "$1" ] && cmd rm -rf "$1"
		[ -d "$3" ] && cmd rm -rf "$3"
		downloadAsset $1 "`getAssetURL $1 "$2"`"
		cmd mkdir .atom-ci
		cmd unzip -q $1 -d $3
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			ATOM_APP_NAME='Atom Beta.app'
			ATOM_SCRIPT_NAME='atom-beta'
			ATOM_SCRIPT_PATH='./atom-beta'
			cmd ln -s "./$3/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh" "${ATOM_SCRIPT_PATH}"
		else
			ATOM_APP_NAME='Atom.app'
			ATOM_SCRIPT_NAME='atom.sh'
			ATOM_SCRIPT_PATH="./$3/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh"
		fi
		
		ATOM_PATH="./$3"
		APM_SCRIPT_PATH="./$3/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/apm"
		NPM_SCRIPT_PATH="./$3/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${TRAVIS_BUILD_DIR}/$3/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin"
		export APM_SCRIPT_PATH ATOM_APP_NAME ATOM_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
	;;
	
	# Linux (Debian assumed)
	linux)
		set -- atom-amd64.deb "$1" .atom-ci
		[ -f "$1" ] && cmd rm -rf "$1"
		[ -d "$3" ] && cmd rm -rf "$3"
		downloadAsset $1 "`getAssetURL $1 "$2"`"
		
		cmd /sbin/start-stop-daemon \
			--start \
			--quiet \
			--pidfile /tmp/custom_xvfb_99.pid \
			--make-pidfile \
			--background \
			--exec /usr/bin/Xvfb \
			-- :99 -ac -screen 0 1280x1024x16
		DISPLAY=:99; export DISPLAY
		dpkg-deb -x $1 "${HOME}/$3"
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			ATOM_SCRIPT_NAME='atom-beta'
			APM_SCRIPT_NAME='apm-beta'
		else
			ATOM_SCRIPT_NAME='atom'
			APM_SCRIPT_NAME='apm'
		fi
		ATOM_SCRIPT_PATH="${HOME}/$3/usr/bin/${ATOM_SCRIPT_NAME}"
		APM_SCRIPT_PATH="${HOME}/$3/usr/bin/${APM_SCRIPT_NAME}"
		NPM_SCRIPT_PATH="${HOME}/$3/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${HOME}/$3/usr/bin"
		export APM_SCRIPT_NAME APM_SCRIPT_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
	;;
esac

# 2. Download and install dependencies


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

# 3. Run stuff that CI exists to run


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
