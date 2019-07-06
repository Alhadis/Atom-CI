all: lint run.sh


# Identify potential portability hassles in shell-scripts
lint: src/*.sh
	shellcheck --severity=warning --shell=sh $^
	checkbashisms $^

.PHONY: lint


# Concatenate each source file into a single shell-script
run.sh: src/*.sh
	printf '#!/bin/sh\n' > $@
	printf 'set -e\n'   >> $@
	cat $^ | sed '/^#!/d; /^set -e$$/d; s/^# RUN: //' >> $@
	chmod +x $@


# Nuke generated build targets
clean:
	rm -f run.sh

.PHONY: clean
