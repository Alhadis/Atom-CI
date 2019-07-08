#!/bin/sh
set -e

#
# 1. Download and install the latest Atom release.
#

# shellcheck source=./0-shared.sh
. "${0%/*}"/0-shared.sh

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
		cmd ln -fs "${PWD}/${ATOM_SCRIPT_PATH#./}" "${APM_SCRIPT_PATH%/*}/atom"
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
		cmd ln -fs "${PWD}/${ATOM_SCRIPT_PATH#./}" "${APM_SCRIPT_PATH%/*}/atom"
	;;
esac
