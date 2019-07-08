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
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
	cmd curl -#fqL -H 'Accept: application/octet-stream' -o "$2" "$1" \
	|| die 'Failed to download Atom' $?
}
