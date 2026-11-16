#!/bin/bash
# Tests for check_exim_queue with fake exim and sudo commands.
# Run: tests/test_check_exim_queue.sh

CHECK="$(cd "$(dirname "$0")/.." && pwd)/check_exim_queue"
FAKE_BIN=$(mktemp -d)
NO_EXIM=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN" "$NO_EXIM"' EXIT

# exim, controlled by FAKE_* variables; the listing is like exim -bp prints it
cat > "$FAKE_BIN/exim" <<'FAKE'
#!/bin/bash
echo "exim $*" >> "${FAKE_LOG:-/dev/null}"
[ -z "$FAKE_SLEEP" ] || sleep "$FAKE_SLEEP"
case "${FAKE_MODE:-ok}" in
	denied) echo "exim: permission denied" >&2; exit 1 ;;
	garbage) echo "LOG: something odd"; exit 0 ;;
esac
case "$1" in
	-bpc) echo "${FAKE_COUNT:-3}" ;;
	-bp) printf '%b' "${FAKE_LIST- 5m  2.9K 1tKxyz-000AbC-1X <alice@example.com>
          bob@example.org

 2h   12K 1tKabc-000DeF-2Y <> *** frozen ***
          postmaster@example.net

 4d  1.2M 1tKdef-000GhI-3Z <carol@example.com>
        D dave@example.org
          erin@example.org

}" ;;
esac
FAKE
# sudo -n runs the command, unless FAKE_SUDO_DENIED is set
cat > "$FAKE_BIN/sudo" <<'FAKE'
#!/bin/bash
echo "sudo $*" >> "${FAKE_LOG:-/dev/null}"
if [ -n "$FAKE_SUDO_DENIED" ]; then
	echo "sudo: a password is required" >&2
	exit 1
fi
[ "$1" == "-n" ] && shift
exec "$@"
FAKE
chmod +x "$FAKE_BIN"/*

# a PATH with the tools check_exim_queue needs, but without exim
for tool in bash timeout grep mktemp rm awk; do
	ln -s "$(command -v $tool)" "$NO_EXIM/$tool"
done

export PATH="$FAKE_BIN:$PATH"
LOG="$FAKE_BIN/log"

FAILURES=0
TESTS=0

# expect NAME EXIT_CODE OUTPUT_REGEX [ENV=VALUE ...] -- [ARGS ...]
expect(){
	local name=$1 code=$2 regex=$3 envs=() out rc
	shift 3
	while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
	shift
	rm -f "$LOG"
	out=$(env FAKE_LOG="$LOG" "${envs[@]}" "$CHECK" "$@" 2>&1)
	rc=$?
	TESTS=$((TESTS + 1))
	if [ $rc -ne "$code" ] || ! [[ "$out" =~ $regex ]] || [ "$(wc -l <<< "$out")" -ne 1 ]; then
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: exit %s (expected %s)\n     %s\n' "$name" $rc "$code" "$out"
	else
		printf 'ok   %s\n' "$name"
	fi
}

# expect_log NAME EXPECTED: the commands the last check ran
expect_log(){
	TESTS=$((TESTS + 1))
	if [ "$(cat "$LOG")" == "$2" ]; then
		printf 'ok   %s\n' "$1"
	else
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: expected\n%s\n     got\n%s\n' "$1" "$2" "$(cat "$LOG")"
	fi
}

expect "count only" 0 '^EXIM QUEUE OK - 3 message\(s\) in the queue\|queue=3;;;0$' --
expect_log "count with -bpc" "exim -bpc"
expect "below -w" 0 '^EXIM QUEUE OK - 3 message.*\|queue=3;4;10;0$' -- -w 4 -c 10
expect "at -w" 1 '^EXIM QUEUE WARNING - 3 message' -- -w 3 -c 10
expect "at -c" 2 '^EXIM QUEUE CRITICAL - 10 message' FAKE_COUNT=10 -- -w 3 -c 10
expect "only -c" 0 '^EXIM QUEUE OK - 3 message.*\|queue=3;;5;0$' -- -c 5
expect "empty queue" 0 '^EXIM QUEUE OK - 0 message' FAKE_COUNT=0 -- -w 1 -c 2

expect "details" 0 '^EXIM QUEUE OK - 3 message\(s\) in the queue, 1 frozen, the oldest 4d old\|queue=3;;;0 frozen=1;;;0 oldest=345600s;;;0$' -- -x
expect_log "details with -bp" "exim -bp"
expect "frozen at -f" 1 '^EXIM QUEUE WARNING - 3 message.*, 1 frozen,.*frozen=1;1;;0' -- -f 1
expect "frozen at -F" 2 '^EXIM QUEUE CRITICAL - .*frozen=1;;1;0' -- -F 1
expect "oldest at -a in days" 1 '^EXIM QUEUE WARNING - .*oldest=345600s;345600;;0$' -- -a 4d
expect "oldest below -A in hours" 0 '^EXIM QUEUE OK - .*oldest=345600s;;349200;0$' -- -A 97h
expect "oldest at -A in minutes" 2 '^EXIM QUEUE CRITICAL - .*oldest=345600s;;345600;0$' -- -A 5760
expect "worst state wins" 2 '^EXIM QUEUE CRITICAL - ' -- -w 100 -f 1 -A 1d
expect "hours and minutes" 0 '^EXIM QUEUE OK - 2 message\(s\) in the queue, 0 frozen, the oldest 3h old\|.* oldest=10800s' \
	"FAKE_LIST= 5m  2.9K 1tKxyz-000AbC-1X <a@example.com>\n          b@example.org\n\n 3h  1K 1tKabc-000DeF-2Y <c@example.com>\n          d@example.org\n\n" -- -x
expect "empty queue with details" 0 '^EXIM QUEUE OK - 0 message\(s\) in the queue, 0 frozen\|queue=0;;;0 frozen=0;;;0 oldest=0s;3600;;0$' FAKE_LIST= -- -x -a 1h

expect "permission denied" 3 '^EXIM QUEUE UNKNOWN - .*/exim failed with status 1: exim: permission denied \(only exim admin users may list the queue: use -S' FAKE_MODE=denied --
expect "sudo" 0 '^EXIM QUEUE OK - 3 message' -- -S
expect_log "exim through sudo -n" "$(printf 'sudo -n %s -bpc\nexim -bpc' "$FAKE_BIN/exim")"
expect "sudo needs a password" 3 '^EXIM QUEUE UNKNOWN - .*exim failed with status 1: sudo: a password is required$' FAKE_SUDO_DENIED=1 -- -S
expect "not a number" 3 "^EXIM QUEUE UNKNOWN - .*/exim -bpc printed 'LOG: something odd' instead of a number$" FAKE_MODE=garbage --
expect "timeout" 3 '^EXIM QUEUE UNKNOWN - .*/exim did not list the queue within 1s$' FAKE_SLEEP=3 -- -t 1
expect "exim missing" 3 '^EXIM QUEUE UNKNOWN - exim not found; give its path with -e$' PATH="$NO_EXIM" --
expect "exim given with -e" 0 '^EXIM QUEUE OK - 3 message' PATH="$NO_EXIM" -- -e "$FAKE_BIN/exim"
expect "-e not executable" 3 '^EXIM QUEUE UNKNOWN - /nonexistent/exim is not executable$' -- -e /nonexistent/exim

expect "-w above -c" 3 '^EXIM QUEUE UNKNOWN - the warning threshold of the queue \(-w, -c\) is above the critical one$' -- -w 10 -c 5
expect "-a above -A" 3 '^EXIM QUEUE UNKNOWN - the warning threshold of the age \(-a, -A\) is above the critical one$' -- -a 2d -A 1d
expect "bad count" 3 "^EXIM QUEUE UNKNOWN - -w must be a number of messages, not 'x'$" -- -w x
expect "bad age" 3 "^EXIM QUEUE UNKNOWN - -a must be minutes or a number with m, h or d, not '1w'$" -- -a 1w
expect "bad timeout" 3 "^EXIM QUEUE UNKNOWN - the timeout must be a positive number of seconds, not '0'$" -- -t 0
expect "missing option argument" 3 '^EXIM QUEUE UNKNOWN - option -w needs an argument$' -- -w
expect "unknown option" 3 '^EXIM QUEUE UNKNOWN - unknown option -q$' -- -q
expect "extra argument" 3 '^EXIM QUEUE UNKNOWN - unexpected argument foo$' -- foo
expect "version" 3 '^check_exim_queue 0\.1$' -- -V

TESTS=$((TESTS + 1))
if "$CHECK" -h | grep -q '^Usage: check_exim_queue'; then echo "ok   help"; else FAILURES=$((FAILURES + 1)); echo "FAIL help"; fi

echo "$((TESTS - FAILURES)) of $TESTS tests passed"
[ $FAILURES -eq 0 ]
