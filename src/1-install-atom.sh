#!/bin/sh
set -e

#
# Download and install Atom.
#

# Retrieve the ID of the latest beta release
getBetaID(){
	printf >&2 'Getting tag of latest beta release... '
	set -- "`curl -s https://api.github.com/repos/atom/atom/releases \
	| grep -ioE '"tag_name"\s*:\s*"[^"]+-beta[0-9]*"' \
	| head -n1 \
	| cut -f2 -d: \
	| tr -d '"'`"
	printf >&2 '\e[4m%s\e[0m\n' "$1"
	
	printf >&2 'Getting release ID... '
	set -- `curl -s https://api.github.com/repos/atom/atom/releases/tags/$1 \
	| grep -m1 -oE '"id"\s*:\s*[0-9]+' \
	| head -n1 \
	| cut -f2 -d: \
	| tr -d '"'`
	printf >&2 '\e[4m%s\e[0m\n' "$1"
	printf %s "$1"
}

# Retrieve the ID of the latest stable release
getStableID(){
	printf >&2 'Getting ID of latest stable release... '
	set -- `curl -s https://api.github.com/repos/atom/atom/releases/latest \
	| grep -oE '"id"\s*:\s*[0-9]+' \
	| head -n1 \
	| cut -f2 -d: \
	| tr -d '"'`
	printf >&2 '\e[4m%s\e[0m\n' "$1"
	printf %s "$1"
}

# Retrieve the download URL of a release asset
# - getAssetURL [asset-filename] [release-id]
getAssetURL(){
	printf >&2 'Getting URL of asset "%s"... ' "$1"
	set -- "`curl -s https://api.github.com/repos/atom/atom/releases/$2/assets \
	| grep -oE '"browser_download_url"\s*:\s*"[^"]+/'"$1"'"' \
	| cut -d: -f2,3 \
	| tr -d '"'`"
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
	echo $@
	return
	curl -sLH 'Accept: application/octet-stream' -o "$1" "$2" || {
		set -- "$1" "$2" "$?"
		printf >&2 'Failed to download \e[4m%s\e[0m from \e[4m%s\e[0m\n' "$1" "$2"
		exit $3
	}
}


case "$ATOM_CHANNEL" in
	beta) set -- "`getBetaID`"   ;;
	*)    set -- "`getStableID`" ;;
esac

case `uname -s | tr A-Z a-z` in
	# macOS
	darwin)
		set -- atom-mac.zip "$1"
		downloadAsset $1 "`getAssetURL $1 "$2"`"
		mkdir atom
		unzip -q atom.zip -d atom
		
		if [ "$ATOM_CHANNEL" = 'beta' ]; then
			ATOM_APP_NAME='Atom Beta.app'
			ATOM_SCRIPT_NAME='atom-beta'
			ATOM_SCRIPT_PATH='./atom-beta'
			ln -s "./atom/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh" "${ATOM_SCRIPT_PATH}"
		else
			ATOM_APP_NAME='Atom.app'
			ATOM_SCRIPT_NAME='atom.sh'
			ATOM_SCRIPT_PATH="./atom/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh"
		fi
		
		ATOM_PATH='./atom'
		APM_SCRIPT_PATH="./atom/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/apm"
		NPM_SCRIPT_PATH="./atom/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${TRAVIS_BUILD_DIR}/atom/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin"
		export APM_SCRIPT_PATH ATOM_APP_NAME ATOM_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
	;;
	
	# Linux (Debian assumed)
	linux)
		set -- atom-amd64.deb "$1"
		downloadAsset $1 "`getAssetURL $1 "$2"`"
		
		/sbin/start-stop-daemon \
			--start \
			--quiet \
			--pidfile /tmp/custom_xvfb_99.pid \
			--make-pidfile \
			--background \
			--exec /usr/bin/Xvfb \
			-- :99 -ac -screen 0 1280x1024x16
		DISPLAY=:99; export DISPLAY
		dpkg-deb -x atom-amd64.deb "${HOME}/atom"
		
		if [ "$ATOM_CHANNEL" = 'beta' ]; then
			ATOM_SCRIPT_NAME='atom-beta'
			APM_SCRIPT_NAME='apm-beta'
		else
			ATOM_SCRIPT_NAME='atom'
			APM_SCRIPT_NAME='apm'
		fi
		ATOM_SCRIPT_PATH="${HOME}/atom/usr/bin/${ATOM_SCRIPT_NAME}"
		APM_SCRIPT_PATH="${HOME}/atom/usr/bin/${APM_SCRIPT_NAME}"
		NPM_SCRIPT_PATH="${HOME}/atom/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/node_modules/.bin/npm"
		PATH="${PATH}:${HOME}/atom/usr/bin"
		export APM_SCRIPT_NAME APM_SCRIPT_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
	;;
esac
