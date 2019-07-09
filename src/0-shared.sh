#!/bin/sh

# Print a colourful "==> $1"
title(){
	set -- "$1" "`tput setaf 4`" "`tput bold`" "`tput sgr0`"
	printf >&2 '%s==>%s %s%s%s\n' "$2" "$4" "$3" "$1" "$4"
}

# Print a command before executing it
cmd(){
	printf >&2 '%s$ %s%s\n' "`tput setaf 2`" "$*" "`tput sgr0`"
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
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
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
	cmd curl -#fqL -H 'Accept: application/octet-stream' -o "$2" "$1" \
	|| die 'Failed to download Atom' $?
}

# Create an "alias" of an executable that simply calls the source file
# with the same arguments. Necessary because `atom.sh` tries to be smart
# about resolving symlinks and using $0 to determine the $CHANNEL (making
# it impossible to symlink `atom-beta` as `atom` so scripts don't break).
#
# - Arguments: [source-file] [alias-name]
# - Example: mkalias ./usr/bin/atom-beta atom
mkalias(){
	set -- "${1##*/}" "${1%/*}/${2##*/}"
	printf '#!/bin/sh\n"${0%%/*}"/%s "$@"\n' "$1" > "$2"
	chmod +x "$2"
}
