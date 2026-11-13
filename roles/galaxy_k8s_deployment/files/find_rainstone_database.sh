#!/bin/sh
# Ignore symlink aliases from earlier restores; only real directories count.
set -eu
root=$1
namespace=$2
claim=$3
ls "$root" >/dev/null
candidate=
count=0
aliases=false
for directory in "$root"/pvc-*_${namespace}_${claim}; do
    if [ -L "$directory" ]; then
        if [ ! -s "$directory/pgdata/PG_VERSION" ]; then
            echo "Broken Rainstone volume alias: $directory" >&2
            exit 1
        fi
        aliases=true
        continue
    fi
    [ -d "$directory" ] || continue
    count=$((count + 1))
    if [ "$count" -gt 1 ]; then
        echo "Multiple Rainstone volume directories; refusing ambiguous reuse" >&2
        exit 1
    fi
    [ -n "$(ls -A "$directory")" ] || continue
    if [ ! -s "$directory/pgdata/PG_VERSION" ]; then
        echo "Incomplete Rainstone database: $directory" >&2
        exit 1
    fi
    candidate=$directory
done
if [ "$aliases" = true ] && [ -z "$candidate" ]; then
    echo "Rainstone volume aliases have no matching retained directory" >&2
    exit 1
fi
if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
fi
