#!/bin/bash
# Tests for the bash completion in completions/check_exim_queue.
# Run: tests/test_completion.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/check_exim_queue"
COMPLETION="$ROOT/completions/check_exim_queue"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
touch "$TMP/exim4" "$TMP/exim_tidydb"

FAILURES=0
TESTS=0

# the candidates, one per line, bash offers for the last argument, which may be empty
complete_words(){
	bash -c 'source "$1"; shift; COMP_WORDS=(check_exim_queue "$@"); COMP_CWORD=$#
		_check_exim_queue; printf "%s\n" "${COMPREPLY[@]}"' bash "$COMPLETION" "$@" | grep . | sort
}

# expect NAME EXPECTED ACTUAL
expect(){
	TESTS=$((TESTS + 1))
	if [ "$2" == "$3" ]; then
		printf 'ok   %s\n' "$1"
	else
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: expected\n%s\n     got\n%s\n' "$1" "$2" "$3"
	fi
}

TESTS=$((TESTS + 1))
if bash -n "$COMPLETION"; then echo "ok   syntax"; else FAILURES=$((FAILURES + 1)); echo "FAIL syntax"; fi

# the options -h lists
HELP_OPTIONS=$("$CHECK" -h | sed -n 's/^\(-[[:alnum:]]\) .*/\1/p' | sort)
expect "-h lists options" 12 "$(wc -l <<< "$HELP_OPTIONS")"
expect "exactly the options of -h" "$HELP_OPTIONS" "$(complete_words "")"
expect "option prefix" "-A" "$(complete_words -A)"
expect "files for -e" "$(printf '%s\n' "$TMP/exim4" "$TMP/exim_tidydb")" "$(complete_words -e "$TMP/exim")"
expect "no candidates for a count" "" "$(complete_words -w "")"
expect "options after a value" "-x" "$(complete_words -w 10 -x)"

echo "$((TESTS - FAILURES)) of $TESTS tests passed"
[ $FAILURES -eq 0 ]
