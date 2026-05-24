#!/usr/bin/env bash
set -euo pipefail

VOD_DIR="$(dirname "$0")/docker/.vod"

count=0
while IFS= read -r -d '' file; do
    if grep -q ':9193' "$file"; then
        sed -i 's/:9193/:9191/g' "$file"
        echo "Updated: $file"
        count=$((count + 1))
    fi
done < <(find "$VOD_DIR" -name '*.strm' -print0)

echo "Done. $count file(s) updated."
