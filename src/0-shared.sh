#!/bin/sh

# Print a colourful "==> $1"
title(){
	printf >&2 '\e[31m==>\e[0m \e[1m%s\e[0m\n' "$1"
}

# Print a command before executing it
cmd(){
	printf >&2 '\e[38;5;28m$\e[0m \e[32m%s\e[0m\n' "$*"
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
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
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
	curl -# -LH 'Accept: application/octet-stream' -o "$1" "$2" || {
		set -- "$1" "$2" "$?"
		printf >&2 'Failed to download \e[4m%s\e[0m from \e[4m%s\e[0m\n' "$1" "$2"
		exit $3
	}
}
