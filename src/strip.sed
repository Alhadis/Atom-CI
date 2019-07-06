/^#!/d
/^set -e$/d
/^\. .*\/0-shared\.sh$/d
/#[[:blank:]]DEBUG$/d
/# shellcheck/d
/^[[:blank:]]*##*[[:blank:]]*$/d
