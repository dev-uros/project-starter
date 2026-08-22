#!/usr/bin/env bash
#
# Double-clickable wrapper around new-project.sh.
#
# Finder has no "run" action for a .sh file, so double-clicking one opens an
# editor. It does run a .command in Terminal, which is the only reason this
# file exists -- there is no logic here, and nothing to keep in sync.
#
# From a shell, call new-project.sh directly; it takes the same arguments.

# Terminal starts a double-clicked script in the home directory, not next to
# the file, so the relative path below would otherwise miss.
cd "$(dirname "$0")" || exit 1

./new-project.sh "$@"
status=$?

# Terminal closes the window on exit when "close if the shell exited cleanly"
# is set, which would take the summary -- or the error -- with it.
printf '\n  press return to close this window '
read -r _

exit $status
