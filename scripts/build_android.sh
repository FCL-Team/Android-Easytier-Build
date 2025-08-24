#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.."; pwd)"
DIST_DIR="$ROOT_DIR/dist"
REPO_DIR="$ROOT_DIR/third_party/easytier"

# Allow overrides via env
REF="${ET_REF:-${1:-}}"
ABIS="${ABIS:-arm64-v8a,armeabi-v7a,x86,x86_64}"
CARGO_PROFILE="${CARGO_PROFILE:-release}"
PROFILE_FLAG="--release"
if [[ "$CARGO_PROFILE" != "release" ]]; then
  PROFILE_FLAG="--profile ${CARGO_PROFILE}"
fi

# 1) Ensure deps
command -v rustup >/dev/null || { echo "ERROR: rustup not found"; exit 1; }
command -v cargo  >/dev/null || { echo "ERROR: cargo not found";  exit 1; }

if ! command -v cargo-ndk >/dev/null; then
  echo ">> Installing cargo-ndk ..."
  cargo install cargo-ndk
fi

# 2) Locate NDK (prefer pre-set env from CI)
if [[ -z "${ANDROID_NDK_HOME:-}" && -z "${ANDROID_NDK_ROOT:-}" ]]; then
  if [[ -n "${ANDROID_NDK:-}" ]]; then
    export ANDROID_NDK_HOME="$ANDROID_NDK"
  fi
fi
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  if [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME/ndk" ]]; then
    CANDIDATE="$(ls -1d "$ANDROID_HOME/ndk"/* 2>/dev/null | sort -V | tail -n1 || true)"
    if [[ -n "$CANDIDATE" ]]; then
      export ANDROID_NDK_HOME="$CANDIDATE"
    fi
  fi
fi
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  echo "ERROR: ANDROID_NDK_HOME not set and cannot auto-detect from ANDROID_HOME/ndk/*" >&2
  exit 1
else
  echo ">> ANDROID_NDK_HOME = $ANDROID_NDK_HOME"
fi

# 3) Fetch upstream if needed / switch ref
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo ">> Upstream not found, fetching..."
  "$ROOT_DIR/scripts/fetch_easytier.sh" ${REF:+--ref "$REF"}
elif [[ -n "$REF" ]]; then
  echo ">> Switching upstream to ref: $REF"
  git -C "$REPO_DIR" fetch --tags --recurse-submodules origin
  git -C "$REPO_DIR" checkout --recurse-submodules "$REF"
fi

# 4) Ensure Rust android targets
rustup target add \
  aarch64-linux-android \
  armv7-linux-androideabi \
  i686-linux-android \
  x86_64-linux-android

# 5) Detect FFI crate manifest (robust)
FFI_MANIFEST="${FFI_MANIFEST:-}"

# If user provided but path does not exist, fall back to auto-detect
if [[ -n "$FFI_MANIFEST" && ! -f "$FFI_MANIFEST" ]]; then
  echo ">> WARNING: FFI_MANIFEST is set but not found: $FFI_MANIFEST"
  echo ">> Falling back to auto-detection"
  FFI_MANIFEST=""
fi

if [[ -z "$FFI_MANIFEST" ]]; then
  # search up to depth 6 for Cargo.toml whose crate name is easytier-ffi / easytier_ffi
  FFI_MANIFEST="$(find "$REPO_DIR" -maxdepth 6 -type f -name Cargo.toml -print0 2>/dev/null \
    | xargs -0 -r grep -IlE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"(easytier_ffi|easytier-ffi)"' \
    | head -n1 || true)"
fi

# Common fallbacks (case variants)
if [[ -z "$FFI_MANIFEST" && -f "$REPO_DIR/easytier-contrib/easytier-ffi/Cargo.toml" ]]; then
  FFI_MANIFEST="$REPO_DIR/easytier-contrib/easytier-ffi/Cargo.toml"
fi
if [[ -z "$FFI_MANIFEST" && -f "$REPO_DIR/Easytier/easytier-contrib/easytier-ffi/Cargo.toml" ]]; then
  FFI_MANIFEST="$REPO_DIR/Easytier/easytier-contrib/easytier-ffi/Cargo.toml"
fi
if [[ -z "$FFI_MANIFEST" && -f "$REPO_DIR/EasyTier/easytier-contrib/easytier-ffi/Cargo.toml" ]]; then
  FFI_MANIFEST="$REPO_DIR/EasyTier/easytier-contrib/easytier-ffi/Cargo.toml"
fi

if [[ -z "$FFI_MANIFEST" ]]; then
  echo "ERROR: Cannot locate Cargo.toml for FFI crate." >&2
  echo "Searched under: $REPO_DIR" >&2
  echo "Hints:" >&2
  echo "  - Ensure clone step completed and 'easytier-contrib/easytier-ffi' exists." >&2
  echo "  - You may set FFI_MANIFEST=third_party/easytier/easytier-contrib/easytier-ffi/Cargo.toml" >&2
  echo "  - Cargo.toml found nearby:" >&2
  find "$REPO_DIR" -maxdepth 3 -type f -name Cargo.toml -print >&2 || true
  exit 1
fi

# 5.x) Normalize manifest path to absolute (so it survives directory changes)
if [[ "${FFI_MANIFEST:0:1}" != "/" ]]; then
  FFI_MANIFEST="$ROOT_DIR/${FFI_MANIFEST#./}"
fi
if [[ ! -f "$FFI_MANIFEST" ]]; then
  echo "ERROR: FFI_MANIFEST resolved to '$FFI_MANIFEST' but not found" >&2
  exit 1
fi

echo ">> Using FFI MANIFEST: $FFI_MANIFEST"

# Patch crate-type to staticlib (so we get .a instead of .so)
"$ROOT_DIR/scripts/patch_ffi_crate_type.sh" "$FFI_MANIFEST"

# 6) Build all ABIs in one go
mkdir -p "$DIST_DIR"
pushd "$REPO_DIR" >/dev/null

echo ">> Building libeasytier_ffi.a for ABIs: $ABIS"
cargo ndk -o "$DIST_DIR" -t "$ABIS" -- build $PROFILE_FLAG --manifest-path "$FFI_MANIFEST"

popd >/dev/null

echo ">> Build complete. Outputs:"
find "$DIST_DIR" -maxdepth 2 -name 'libeasytier_ffi.a' -print
