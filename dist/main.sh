#!/bin/sh
set -e

# Emit an ANSI escape sequence to style console output.
# - Arguments: [sgr-id...]
# - Example:   `sgr 34 22`   => "\033[34;22m"
#              `sgr 38 5 10` => "\033[38;5;10m"
# Side-notes:
#   This function honours http://no-color.org/: if the `$NO_COLOR` environment
#   variable exists, this function becomes a no-op. Two extensions to the spec
#   are also provided:
#    1. The alternative spelling `$NO_COLOUR` is accepted if the US variant is
#       not defined. Similarly, the spelling `$FORCE_COLOUR` is also valid.
#    2. The variable `$FORCE_COLOR` (or `$FORCE_COLOUR`) overrides `$NO_COLOR`
#       if set to the numbers 1, 2, 3, the string "true", or the empty string.
#       All other values cause colours to be disabled, à la node(1).
sgr(){
	# Treat no arguments as shorthand for `sgr 0`
	[ $# -gt 0 ] || set -- 0

	# Resolve FORCE_COLOUR variable
	if   [ "${FORCE_COLOR+1}"  ]; then set -- FORCE_COLOR  "$@"
	elif [ "${FORCE_COLOUR+1}" ]; then set -- FORCE_COLOUR "$@"
	else                               set -- ""           "$@"
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
		if   [ "${NO_COLOR+1}"  ]; then set -- 1 "$@"
		elif [ "${NO_COLOUR+1}" ]; then set -- 1 "$@"
		else                            set -- 0 "$@"
		fi
	fi

	# Do nothing if colours are suppressed
	[ "$1" = 1 ] && return || shift

	# IDEA: Gatekeep colour resolution based on forced colour depth; i.e., 16-colour
	# mode causes `38;5;10` (bright green) to degrade into `32` (ordinary green).
	shift

	# Generate the final sequence, stripping any erroneous newlines added by older sed(1) versions
	printf '\033[%sm' "$*" | sed 's/  */;/g' | tr -d '\n'
}

# Print a colourful "==> $1"
title(){
	set -- "$1" "`sgr 34`" "`sgr 1`" "`sgr`"
	printf '%s==>%s %s%s%s\n' "$2" "$4" "$3" "$1" "$4"
}

# Quote command-line arguments for console display
argfmt(){
	while [ $# -gt 0 ]; do case $1 in *'
'*) printf \'; printf %s "$1" | sed s/\''/&\\&&/g'; printf \' ;;
	*) printf %s "$1" | sed ':x
	/^[]+:@^_[:alnum:][=[=]/.-][]~#+:@^_[:alnum:][=[=]/.-]*$/!{
		/^[]~#+:@^_[:alnum:][=[=]/.-]*[^]~#+:@^_[:alnum:][=[=]/.-][]~#+:@^_[:alnum:][=[=]/.-]*$/{
			/^--*.*=/!s/[^]~#+:@^_[:alnum:][=[=]/.-]/\\&/;;n;bx
		}; /'\''/! {s/^/'\''/;s/$/'\''/;n;bx
	}; s/[$"\\@]/\\&/g;s/^/"/;s/$/"/;}' | tr -d '\n' ;;
	esac; shift; [ $# -eq 0 ] || printf ' '; done
}

# Embellish and echo a command that's about to be executed
cmdfmt(){
	set -- "`argfmt "$@"`"
	if [ "$GITHUB_ACTIONS" ]; then
		printf '[command]%s\n' "$1"
	else
		printf '%s$ %s%s\n' "`sgr 32`" "$1" "`sgr`"
	fi
}

# Print a command before executing it
cmd(){
	cmdfmt "$@"
	"$@"
}

# Format a string with underlines
ul(){
	case $# in
		# Read from standard input
		0) [ -t 0 ] && return || sed "`printf 's/^/\033[4m/;s/$/\033[24m/'`" ;;
		
		# Read from parameters
		1) printf '\033[4m%s\033[24m' "$1" ;;
		*) set -- "$1" "`sh -c "
			format='\\\\033[4m'\\\"%s\\\"'\\\\033[24m'
			shift; [ \\\$# -eq 0 ] || printf  \\\"\\\$format\\\" \\\"\\\$1\\\"
			shift; [ \\\$# -eq 0 ] || printf \\\" \\\$format\\\" \\\"\\\$@\\\"
		" -- "$@"`"; printf "$@" ;;
	esac

	# Append a trailing newline if standard output is a terminal
	if [ -t 1 ]; then printf '\n'; fi
}

# Print a formatted error message to the console
err(){
	if [ $# -eq 0 ] && [ -t 0 ]; then return; fi
	[ "$GITHUB_ACTIONS" ] && printf '::error::' || {
		[ "$TRAVIS_JOB_ID" ] && sgr 1 31 || sgr 1 38 5 9
		printf 'ERROR: '
		sgr 22
	}
	[ $# -gt 0 ] && printf %s "`printf "$@"`" || sed ':x
		$!{N;/\n/{s// /g;n;bx
	};}'
	[ -n "$GITHUB_ACTIONS" ] || sgr 39
	if [ "$GITHUB_ACTIONS" ] || [ -t 1 ]; then printf '\n'; fi
}

# Print a formatted warning to the console
warn(){
	if [ $# -eq 0 ] && [ -t 0 ]; then return; fi
	[ "$GITHUB_ACTIONS" ] && printf '::warning::' || {
		[ "$TRAVIS_JOB_ID" ] && sgr 1 33 || sgr 1 38 5 11
		printf 'WARNING: '
		sgr 22
	}
	[ $# -gt 0 ] && printf %s "`printf "$@"`" || sed ':x
		$!{N;/\n/{s// /g;n;bx
	};}'
	[ -n "$GITHUB_ACTIONS" ] || sgr 39
	if [ "$GITHUB_ACTIONS" ] || [ -t 1 ]; then printf '\n'; fi
}

# Terminate execution with an error message
die(){
	err "${1:-Script terminated}"
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
		foldStack="$foldStack:$1"
		
		# FIXME: GitHub Actions doesn't support nested groups; degrade gracefully instead
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
		# Verify that the named fold exists, but don't return an error-code:
		# folding is a cosmetic feature that's worth breaking a build over.
		if [ $# -gt 0 ]; then
			case $foldStack in
				"$1"|"$1:"*|*":$1"|*":$1:"*) ;;
				*) warn 'No such fold: %s' "$1"; return ;;
			esac

		# If no name was passed, default to whatever fold was most recently opened
		else set -- "${foldStack##*:}"; fi

		while [ "$foldStack" ]; do
			set -- "$1" "${foldStack##*:}"
			foldStack=${foldStack%:$2}

			# FIXME: Same issue/limitation as `startFold()`
			case $foldStack in *:*) ;; *) printf '::endgroup::\n' ;; esac
			[ ! "$1" = "$2" ] || break
		done
	fi
}

# Switch working directory to that of the user's project
switchToProject(){
	set -- "`sgr 4`" "$ATOM_CI_PACKAGE_ROOT" "`sgr 24`"
	if [ "$2" ]; then
		if [ -s "$2/package.json" ]; then
			ATOM_CI_PACKAGE_ROOT=`cd "$2" && pwd`
			set -- "$2" "$1${ATOM_CI_PACKAGE_ROOT}$3"
			printf 'Switching to ATOM_CI_PACKAGE_ROOT: %s\n' "$2"
			# shellcheck disable=SC2164
			cd "$1"
		else
			set -- "$1$2$3"
			if [ "$GITHUB_ACTIONS" ]; then printf '::warning::'; fi
			warn 'Ignoring $ATOM_CI_PACKAGE_ROOT; "%s" is not a valid project directory' "$1"
			ATOM_CI_PACKAGE_ROOT=`pwd`
		fi
	else
		set -- "$1" "`pwd`" "$3"
		printf 'Working directory: %s\n' "$1$2$3"
		ATOM_CI_PACKAGE_ROOT=$2
	fi
	export ATOM_CI_PACKAGE_ROOT
	assertValidProject
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
	printf 'Downloading "%s" from %s%s%s\n' "$2" "`sgr 4`" "$1" "`sgr`"
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
# - Arguments: [source-file] [alias-name]
# - Example: mkalias ./usr/bin/atom-beta atom
mkalias(){
	set -- "${1##*/}" "${1%/*}/${2##*/}"
	printf '#!/bin/sh\n"${0%%/*}"/%s "$@"\n' "$1" > "$2"
	chmod +x "$2"
}

switchToProject

# Building against a specific release
if [ "$ATOM_RELEASE" ]; then
	title "Installing Atom ($ATOM_RELEASE)"
	case $ATOM_RELEASE in
		*-beta*) ATOM_CHANNEL=beta   ;;
		*)       ATOM_CHANNEL=stable ;;
	esac
else
	# Verify that the requested channel is valid
	ATOM_CHANNEL=${ATOM_CHANNEL:=stable}
	case $ATOM_CHANNEL in
		beta)   startFold 'install-atom' 'Installing Atom (Latest beta release)'   ;;
		stable) startFold 'install-atom' 'Installing Atom (Latest stable release)' ;;
		*)      die                      'Unsupported channel: '"$ATOM_CHANNEL"'"' ;;
	esac
fi

# Silence annoying deprecation messages from Electron, unless explicitly enabled
if [ ! "${NODE_NO_WARNINGS+1}" ]; then
	export NODE_NO_WARNINGS=1
fi

# GitHub Actions: Force 16-colour support unless explicitly disabled
if [ "$GITHUB_ACTIONS" ] && [ ! "${NO_COLOR+1}${NO_COLOUR+2}" ]; then
	export FORCE_COLOR=1
fi

case `uname -s | tr A-Z a-z` in
	# macOS
	darwin)
		downloadAtom atom-mac.zip "$ATOM_CHANNEL" "$ATOM_RELEASE"
		cmd mkdir .atom-ci
		cmd unzip -q atom-mac.zip -d .atom-ci
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			ATOM_APP_NAME='Atom Beta.app'
		else
			ATOM_APP_NAME='Atom.app'
		fi
		ATOM_PATH="${PWD}/.atom-ci"
		ATOM_SCRIPT_NAME='atom.sh'
		ATOM_SCRIPT_PATH="${ATOM_PATH}/${ATOM_APP_NAME}/Contents/Resources/app/atom.sh"
		APM_SCRIPT_PATH="${ATOM_PATH}/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/apm"
		NPM_SCRIPT_PATH="${ATOM_PATH}/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin/npm"
		PATH="${ATOM_PATH}/${ATOM_APP_NAME}/Contents/Resources/app/apm/node_modules/.bin:${PATH}"
		export APM_SCRIPT_PATH ATOM_APP_NAME ATOM_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
		cmd ln -fs "$ATOM_SCRIPT_PATH" "${APM_SCRIPT_PATH%/*}/atom"
	;;
	
	# Linux (Debian assumed)
	linux)
		cmd /sbin/start-stop-daemon \
			--start \
			--quiet \
			--oknodo \
			--pidfile /tmp/custom_xvfb_99.pid \
			--make-pidfile \
			--background \
			--exec /usr/bin/Xvfb \
			-- :99 -ac -screen 0 1280x1024x16 \
			|| die 'Unable to start Xvfb'
		DISPLAY=:99
		export DISPLAY
		
		downloadAtom atom-amd64.deb "$ATOM_CHANNEL" "$ATOM_RELEASE"
		ATOM_PATH="${PWD}/.atom-ci"
		cmd dpkg-deb -x atom-amd64.deb "$ATOM_PATH"
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			ATOM_SCRIPT_NAME='atom-beta'
			APM_SCRIPT_NAME='apm-beta'
		else
			ATOM_SCRIPT_NAME='atom'
			APM_SCRIPT_NAME='apm'
		fi
		ATOM_SCRIPT_PATH="${ATOM_PATH}/usr/bin/${ATOM_SCRIPT_NAME}"
		APM_SCRIPT_PATH="${ATOM_PATH}/usr/bin/${APM_SCRIPT_NAME}"
		NPM_SCRIPT_PATH="${ATOM_PATH}/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/node_modules/.bin/npm"
		PATH="${ATOM_PATH}/usr/bin:${NPM_SCRIPT_PATH%/*}:${PATH}"
		export APM_SCRIPT_NAME APM_SCRIPT_PATH ATOM_SCRIPT_NAME ATOM_SCRIPT_PATH NPM_SCRIPT_PATH PATH
		
		if [ "$ATOM_CHANNEL" = beta ]; then
			[ -f "${ATOM_PATH}/usr/bin/atom" ] || mkalias "${ATOM_PATH}/usr/bin/atom-beta" atom
			[ -f "${ATOM_PATH}/usr/bin/apm"  ] || mkalias "${ATOM_PATH}/usr/bin/apm-beta" apm
		fi
	;;
esac

# List environment variables if it's safe to do so
if [ "$TRAVIS_JOB_ID" ] || [ "$GITHUB_ACTIONS" ] || [ "$ATOM_CI_DUMP_ENV" ]; then
	startFold 'env-dump' 'Dumping environment variables'
	cmdfmt "env | sort"
	# Avoid using `env | sort`; some variables (i.e., $TRAVIS_COMMIT_MESSAGE) may contain newlines
	node -p 'Object.keys(process.env).sort().map(x => x + "=" + process.env[x]).join("\n")'
	endFold 'env-dump'
fi

endFold 'install-atom'

ATOM_SCRIPT_PATH=${ATOM_SCRIPT_PATH:=atom}
APM_SCRIPT_PATH=${APM_SCRIPT_PATH:=apm}

# Display version info for Atom/Node/?PM
showVersions(){
	printf 'Printing version info\n'
	cmd "${ATOM_SCRIPT_PATH}" --version
	cmd "${APM_SCRIPT_PATH}"  --version --no-color
	if [ $# -eq 0 ]; then return 0; fi
	cmd node --version
	cmd npm --version
}

# Install packages with `apm`
apmInstall(){
	endFold 'installers'
	startFold 'install-deps' 'Installing dependencies'
	set -- "$1" "`sgr 4`" "`sgr 24`" \
	/"`printf '\e'`"\\['[0-9][;0-9]*m[^[:cntrl:][:blank:]]\{1,\}$/{N;s/\n//;s/$/\n/;}'
	if [ -f package-lock.json ] && apmHasCI; then
		printf 'Installing from %s%s%s\n' "$2" package-lock.json "$3"
		cmd "${APM_SCRIPT_PATH}" ci $1 | sed "$4"
	else
		printf 'Installing from %s%s%s\n' "$2" package.json "$3"
		cmd "${APM_SCRIPT_PATH}" install $1 | sed "$4"
		cmd "${APM_SCRIPT_PATH}" clean      | sed "$4"
	fi
}

# Determine whether this version of APM supports the `ci`
# subcommand, which was added in atom/apm@2a6dc13 (v2.1.0).
apmHasCI(){
	# shellcheck disable=SC2046
	set -- `apm --version --no-color \
	| grep -i apm \
	| head -n1 \
	| sed -e '
		s/^[[:blank:]]*[Aa][Pp][Mm][[:blank:]]*[Vv]*//
		s/[[:blank:]]*$//
		s/+.*$//
		s/-[-A-Za-z0-9.].*$//
		s/$/.0.0.0.0/
		s/^\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\).*$/\1 \2 \3/'`
	[ "$1" -gt 2 ] || [ "$1" -eq 2 ] && [ "$2" -ge 1 ]
}

startFold 'installers' 'Resolving installers'

# Download using bundled version of Node
if [ "${ATOM_LINT_WITH_BUNDLED_NODE:=true}" = true ]; then
	printf 'Using bundled version of Node\n'
	showVersions
	apmInstall
	case `uname -s | tr A-Z a-z` in
		darwin) PATH="./.atom-ci/${ATOM_APP_NAME}/Contents/Resources/app/apm/bin:${PATH}" ;;
		*) PATH="${HOME}/.atom-ci/usr/share/${ATOM_SCRIPT_NAME}/resources/app/apm/bin:${PATH}" ;;
	esac
	export PATH

# Download using system's version of NPM
else
	printf 'Using system versions of Node/NPM\n'
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

endFold 'install-deps'

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
		printf 'Linting package with %s...\n' "$linter"
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
			printf 'Running specs...\n'
			cmd "${ATOM_SCRIPT_PATH}" --test "./$dir" || exit $?
			break;
		fi
	done
fi
