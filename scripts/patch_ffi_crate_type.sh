#!/usr/bin/env bash

set -Eeuo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/Cargo.toml" >&2
  exit 1
fi
MANIFEST="$1"
if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: Not found: $MANIFEST" >&2
  exit 1
fi
TMP="$(mktemp)"
perl -0777 -pe '
  if ($seen = /crate-type\s*=/s) {
    s/crate-type\s*=\s*\[[^\]]*\]/crate-type = ["staticlib"]/s;
  } else {
    s/(\[lib\][^\[]*)/$1\ncrate-type = ["staticlib"]\n/s;
  }
' "$MANIFEST" > "$TMP"
mv "$TMP" "$MANIFEST"
echo ">> Patched crate-type to staticlib: $MANIFEST"
