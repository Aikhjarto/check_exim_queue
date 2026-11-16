# check_exim_queue

A Nagios/Icinga plugin that checks the exim mail queue: the number of
messages, and optionally frozen messages and the age of the oldest message.

```sh
check_exim_queue -w 50 -c 200
check_exim_queue -S -w 50 -c 200 -f 1 -a 4h -A 2d
```

```
EXIM QUEUE WARNING - 3 message(s) in the queue, 1 frozen, the oldest 4d old|queue=3;50;200;0 frozen=1;1;;0 oldest=345600s;14400;172800;0
```

| Option | Meaning |
|---|---|
| `-w`, `-c` | WARNING or CRITICAL when this many messages or more are in the queue |
| `-f`, `-F` | WARNING or CRITICAL when this many frozen messages or more are in the queue |
| `-a`, `-A` | WARNING or CRITICAL when the oldest message is this old or older: minutes, or a number with `m`, `h` or `d` (`30m`, `4h`, `2d`) |
| `-x` | Report frozen messages and the oldest message without thresholds for them |
| `-S` | Run exim with `sudo -n` (see below) |
| `-e` | The exim binary; by default `exim` or `exim4` from `PATH`, or `/usr/sbin/exim` or `/usr/sbin/exim4` |
| `-t` | Give up after this many seconds (default: 10) |
| `-V` | Show the version |
| `-h` | Show the help |

Without `-f`, `-F`, `-a`, `-A` and `-x`, the plugin only counts the messages
with `exim -bpc`, which stays fast on a large queue. With them, it reads the
whole listing with `exim -bp`. exim shows the age of a message in minutes up to
90 minutes, then in hours, and above 72 hours in days, so the age is that
precise.

The counts and the age go into the performance data. Thresholds are optional:
without any, the check is always OK and only collects the performance data.
If exim fails, the check is UNKNOWN with exim's error message.

## Permissions

exim lets only admin users list the queue: root, the exim user and members of
the groups in exim's `admin_groups`. Either add the monitoring user to such a
group, or let it run the two commands with sudo and use `-S`:

```
# /etc/sudoers.d/check_exim_queue
nagios ALL=(root) NOPASSWD: /usr/sbin/exim -bpc, /usr/sbin/exim -bp
```

Use the user your monitoring runs as (nagios, icinga, ...), and the path of
exim on your system (`/usr/sbin/exim4` on Debian also works).

## Requirements

bash, coreutils (`timeout`, `mktemp`), grep, awk and exim. sudo for `-S`.

## Tests

```sh
tests/test_check_exim_queue.sh
tests/test_completion.sh
```

The tests use fake `exim` and `sudo` commands, so no mail server is needed.

## License

GPL-2.0-or-later
