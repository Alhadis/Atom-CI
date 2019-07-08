all: lint dist/main.sh


# Identify potential portability hassles in shell-scripts
lint: src/*.sh
	shellcheck --severity=warning --shell=sh $^
	checkbashisms $^

.PHONY: lint


# Concatenate each source file into a single shell-script
dist/main.sh: src/*.sh
	printf '#!/bin/sh\n' > $@
	printf 'set -e\n'   >> $@
	cat $^ | sed -f src/strip.sed | cat -s >> $@
	chmod +x $@
	shellcheck -Swarning -ssh $@
	checkbashisms $@


# Nuke generated build targets
clean:
	rm -f dist/*

.PHONY: clean
