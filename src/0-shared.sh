#!/bin/sh

# Print a colourful "==> $1"
title(){
	printf >&2 '\e[34m==>\e[0m \e[1m%s\e[0m\n' "$1"
}

# Print a command before executing it
cmd(){
	printf >&2 '\e[32m$ %s\e[0m\n' "$*"
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
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
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
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
