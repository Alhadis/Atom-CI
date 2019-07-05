#!/bin/sh
set -e

#
# Run linters and test-suite
#

# Check if package.json defines a script of the specified name
haveScript(){
	node -p '(require("./package.json").scripts || {})["'"$1"'"] || ""' | grep -q .
}

# Run "lint" script if one exists in package.json; otherwise, use assumed defaults
runLint(){
	if haveScript lint; then
		"${NPM_SCRIPT_PATH}" run lint
	else
		for linter of coffeelint eslint tslint; do
			haveDep "$linter" || continue
			for dir of lib src spec test; do
				if [ -d $dir ]; then
					printf >&2 'Linting ./%s/* with %s...\n' "$dir" "$linter"
					npx "$1" ./$dir || exit $?
				fi
			done
		done
	fi
}

# Run the package "test" script if one exists; otherwise, locate test-suite manually
runTests(){
	if haveScript test; then
		"${NPM_SCRIPT_PATH}" run test
	else
		for dir of spec specs test tests; do
			if [ -d $dir ]; then
				printf >&2 'Running specs...\n'
				"${ATOM_SCRIPT_PATH}" --test "./$dir" || exit $?
				break;
			fi
		done
	fi
}

runLint && runTests
