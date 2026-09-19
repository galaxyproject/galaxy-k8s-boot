#!/bin/sh
# Print all Galaxy PVC UUIDs, one per line. An empty successful result means
# no matching data; an inaccessible export root is an error, not a fresh disk.
set -eu
export_root=${1:-/export}
ls "$export_root" >/dev/null
for dir in "$export_root"/pvc-*; do
    [ -d "$dir" ] || continue
    uuid=${dir##*/pvc-}
    # Exclude local-path volumes (RabbitMQ, etc.) and unexpected directory names.
    printf '%s\n' "$uuid" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || continue
    # Galaxy uses objects/ by default, but existing files/ takes precedence.
    # Charts that pre-created files/ therefore need to be recognized as well.
    if [ -d "$dir/objects" ] || [ -d "$dir/files" ]; then
        printf '%s\n' "$uuid"
    fi
done
