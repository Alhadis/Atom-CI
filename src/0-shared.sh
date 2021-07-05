#!/bin/sh

# Print a colourful "==> $1"
title(){
	set -- "$1" "`sgr 34`" "`sgr 1`" "`sgr`"
	printf >&2 '%s==>%s %s%s%s\n' "$2" "$4" "$3" "$1" "$4"
}

# Print a colourful shell-command prefixed by a "$ "
cmdfmt(){
	printf >&2 '%s$ %s%s\n' "`sgr 32`" "$*" "`sgr`"
}

# Print a command before executing it
cmd(){
	cmdfmt "$*"
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
	"$@"
}

# Terminate execution with an error message
die(){
	set -- "$1" "$2" "`sgr 1`" "`sgr 31`" "`sgr`"
	printf >&2 '%s%sfatal:%s%s %s%s\n' "$3" "$4" "$5" "$4" "$1" "$5"
	exit ${2:-1}
}

# Emit an arbitrary byte-sequence to standard output
putBytes(){
	printf %b "`printf \\\\%03o "$@"`"
}

# Colon-delimited list of currently-open folds
foldStack=

# Begin a collapsible folding region
# - Arguments: [id] [label]?
startFold(){
	if [ "$TRAVIS_JOB_ID" ]; then
		printf 'travis_fold:start:%s\r\033[0K' "$1"
	elif [ "$GITHUB_ACTIONS" ]; then
		set -- "$1" "${2:-$1}"
		set -- "`printf %s "$1" | sed s/:/꞉/g`" "$2"
		foldStack="$1:$foldStack"
		
		# FIXME: GitHub Actions don't support nested groups. Degrade gracefully.
		case $foldStack in *:*:*) title "$2" ;; *) printf '::group::%s\n' "$2" ;; esac
		
		return
	fi
	[ -z "$2" ] || title "$2"
}

# Close a named folding region
# - Arguments: [id]?
endFold(){
	if [ "$TRAVIS_JOB_ID" ]; then
		printf 'travis_fold:end:%s\r\033[0K' "$1"
	elif [ "$GITHUB_ACTIONS" ]; then
		[ $# -gt 0 ] || set -- "${foldStack%%:*}"
		while [ "$foldStack" ] && [ ! "$1" = "${foldStack%%:*}" ]; do
			set -- "${foldStack%%:*}"
			foldStack="${foldStack#*:}"
			# FIXME: Same issue/limitation as `startFold()`
			case $foldStack in *:*) ;; *) printf '::endgroup::\n' ;; esac
		done
	fi
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
	if [ ! "$3" ]; then die "Release not found: `sgr 4`$1`sgr 24`" 3; fi
	printf %s "$3" | scrapeDownloadURL "$2"
}

# Download a file.
# - Arguments: [url] [target-filename]
download(){
	printf >&2 'Downloading "%s" from %s%s%s\n' "$2" "`sgr 4`" "$1" "`sgr`"
	if [ "$ATOM_CI_DRY_RUN" ]; then return 0; fi # DEBUG
	cmd curl -#fqL -H 'Accept: application/octet-stream' -o "$2" "$1" \
	|| die 'Failed to download file' $?
}

# Download the latest release from a beta or stable channel.
# - Arguments: [user/repo] [channel] [asset]
# - Example:   `downloadByChannel "atom/atom" "beta" "atom-mac.zip"`
downloadByChannel(){
	case $2 in
		beta)   set -- "`getLatestRelease "$1" "$3" 1`" "$3" ;;
		stable) set -- "`getLatestRelease "$1" "$3"`"   "$3" ;;
		*)      die "Unsupported release channel: $2" ;;
	esac
	[ "$1" ] || die 'Failed to retrieve URL'
	[ "$2" ] || die 'Missing filename'
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
#
# - Arguments: [source-file] [alias-name]
# - Example: mkalias ./usr/bin/atom-beta atom
mkalias(){
	set -- "${1##*/}" "${1%/*}/${2##*/}"
	printf '#!/bin/sh\n"${0%%/*}"/%s "$@"\n' "$1" > "$2"
	chmod +x "$2"
}

# Emit an ANSI escape sequence to style console output.
# - Arguments: [sgr-id...]
# - Example:   `sgr 34 22`   => "\033[34;22m"
#              `sgr 38 5 10` => "\033[38;5;10m"
# Side-notes:
#   This function honours http://no-color.org/: if the `$NO_COLOR` environment
#   variable exists, this function becomes a no-op. Two extensions to the spec
#   are also provided by the function:
#
#    1. The alternative spelling `$NO_COLOUR` is accepted if the US variant
#       is not defined in the environment.
#
#    2. The variable `$FORCE_COLOR` (or `$FORCE_COLOUR`) overrides `$NO_COLOR`
#       if set to the numbers 1, 2, 3, the string "true", or the empty string.
#       Any other value causes colours to be disabled. This logic matches that
#       of Node.js (sans `NODE_DISABLE_COLORS` support); see node(1).
sgr(){
	# Treat no arguments as shorthand for `sgr 0`
	[ $# -gt 0 ] || set -- 0

	# Resolve FORCE_COLOUR variable
	if   [ ! -z "${FORCE_COLOR+1}"  ]; then set -- FORCE_COLOR  "$@"
	elif [ ! -z "${FORCE_COLOUR+1}" ]; then set -- FORCE_COLOUR "$@"
	else                                    set -- ""           "$@"
	fi

	# Resolve colour depth, if forced
	if [ "$1" ]; then
		case `eval "echo \"\\$$1\""` in
			''|1|true) shift; set -- 0 16       "$@" ;; # 16-colour support
			2)         shift; set -- 0 256      "$@" ;; # 256-colour support
			3)         shift; set -- 0 16000000 "$@" ;; # 16-million (“true colour”) support
			*)         shift; set -- 1 0        "$@" ;; # Invalid value; disable colours
		esac
	else
		# Resolve NO_COLOUR variable
		if   [ ! -z "${NO_COLOR+1}"  ]; then set -- 1 "$@"
		elif [ ! -z "${NO_COLOUR+1}" ]; then set -- 1 "$@"
		else                                 set -- 0 "$@"
		fi
	fi

	# Do nothing if colours are suppressed
	[ "$1" = 1 ] && return || shift

	# IDEA: Gatekeep colour resolution based on forced colour depth; i.e., 16-colour
	# mode causes `38;5;10` (bright green) to degrade into `32` (ordinary green).
	shift

	# Generate the final sequence
	printf '\033[%sm' "$*" | sed 's/  */;/g'
}
