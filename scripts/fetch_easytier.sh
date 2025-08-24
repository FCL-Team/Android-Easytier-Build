#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.."; pwd)"
REPO_URL="${REPO_URL:-https://github.com/EasyTier/EasyTier.git}"
REPO_DIR="$ROOT_DIR/third_party/easytier"
REF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      REF="$2"; shift 2;;
    --url)
      REPO_URL="$2"; shift 2;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1;;
  esac
done

mkdir -p "$ROOT_DIR/third_party"
if [[ -d "$REPO_DIR/.git" ]]; then
  echo ">> Updating EasyTier in $REPO_DIR"
  git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
  git -C "$REPO_DIR" fetch --tags --recurse-submodules origin
else
  echo ">> Cloning EasyTier from $REPO_URL"
  git clone --recursive "$REPO_URL" "$REPO_DIR"
fi

if [[ -n "$REF" ]]; then
  echo ">> Checking out ref: $REF"
  git -C "$REPO_DIR" checkout --recurse-submodules "$REF"
fi

echo ">> Current EasyTier HEAD: $(git -C "$REPO_DIR" rev-parse --short HEAD)"
