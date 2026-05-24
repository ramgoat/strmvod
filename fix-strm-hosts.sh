#!/usr/bin/env bash
set -euo pipefail

VOD_DIR="$(dirname "$0")/docker/.vod"

count=0
while IFS= read -r -d '' file; do
    if grep -q 'localhost' "$file"; then
        sed -i 's/localhost/dispatcharr/g' "$file"
        echo "Updated: $file"
        count=$((count + 1))
    fi
done < <(find "$VOD_DIR" -name '*.strm' -print0)

echo "Done. $count file(s) updated."
