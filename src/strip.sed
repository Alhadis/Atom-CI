/^#!/d
/^set -e$/d
/^\. .*\/0-shared\.sh$/d
/#[[:blank:]]DEBUG$/d
/# shellcheck/d
/^[[:blank:]]*##*[[:blank:]]*$/d
/^# [[:digit:]]\. [^[:blank:]].*$/d
s/ATOM_CI_DRY_RUN="" //g
