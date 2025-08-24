# EasyTier Android FFI Builder

This repository fetches a specific **EasyTier** revision and builds a **static** library `libeasytier_ffi.a` for **Android**. It is **CI-only**: builds run on GitHub Actions (no local/Windows entry points). All build parameters live in `BUILD_CONFIG.env`.

---

## What this repo does

- Clones EasyTier into `third_party/easytier` at the revision you choose.
- Locates the **FFI crate** (`easytier-contrib/easytier-ffi`) automatically, or via `FFI_MANIFEST`.
- Patches its `Cargo.toml` to `crate-type = ["staticlib"]` (so you get a `.a`, not a `.so`).
- Builds `libeasytier_ffi.a` for these ABIs:
  - `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`
- Runs the four ABI builds **in parallel** via a matrix workflow.
- Normalizes outputs into `dist/<abi>/libeasytier_ffi.a`, then packages them as a single zip artifact.

---

## Quick start

1) Edit **`BUILD_CONFIG.env`** at repo root:

```ini
REPO_URL=https://github.com/EasyTier/EasyTier.git
ET_REF=releases/v2.4.2         # tag/branch/commit, e.g. v2.4.2 or main
NDK_VERSION=r26d               # NDK version used on CI
RUST_TARGETS=aarch64-linux-android,armv7-linux-androideabi,i686-linux-android,x86_64-linux-android
CARGO_PROFILE=release          # or a custom named profile defined in your workspace
# Optional: only set if auto-detection fails (use relative paths, no quotes)
FFI_MANIFEST=third_party/easytier/easytier-contrib/easytier-ffi/Cargo.toml
```

> Tip: Do **not** use `${{ github.workspace }}` or shell variables in `BUILD_CONFIG.env`. The file is imported as literal `KEY=VALUE`.

2) Commit and push your changes.

3) In GitHub → **Actions** → run the workflow defined at `.github/workflows/android.yml`.

4) After it finishes, download the artifact named `libeasytier_ffi-android-libs` (a zip).

---

## Outputs

The artifact zip contains:

```
dist/
  arm64-v8a/libeasytier_ffi.a
  armeabi-v7a/libeasytier_ffi.a
  x86/libeasytier_ffi.a
  x86_64/libeasytier_ffi.a
```

The zip filename includes your `ET_REF` (slashes sanitized) and `NDK_VERSION`.

---

## How it works (CI)

- **Workflow**: `.github/workflows/android.yml`
  - Loads `BUILD_CONFIG.env`.
  - Installs NDK via `nttld/setup-ndk@v1` (version from `NDK_VERSION`).
  - Installs Rust toolchains (targets from `RUST_TARGETS`).
  - Installs `protoc` (required by EasyTier’s build script) and verifies it.
  - **Matrix build**: four parallel jobs, one ABI each, calling `scripts/build_android.sh`.
  - Normalizes outputs so each ABI has `dist/<abi>/libeasytier_ffi.a`.
  - A final packaging job downloads the four ABI artifacts and zips `dist/`.

- **Scripts**:
  - `scripts/fetch_easytier.sh`: clone/switch EasyTier to `ET_REF`.
  - `scripts/build_android.sh`:
    - Ensures toolchains and NDK.
    - Auto-detects the FFI crate. If `FFI_MANIFEST` is set but invalid, it falls back to auto detection and common paths.
    - Patches `crate-type` to `["staticlib"]`.
    - Runs `cargo ndk ... build` with your `CARGO_PROFILE`.

---

## Configuration details (BUILD_CONFIG.env)

| Key            | Description                                                                                  | Example                                                        |
|----------------|----------------------------------------------------------------------------------------------|----------------------------------------------------------------|
| `REPO_URL`     | EasyTier upstream repository                                                                 | `https://github.com/EasyTier/EasyTier.git`                     |
| `ET_REF`       | Tag/branch/commit to build                                                                   | `v2.4.2` or `releases/v2.4.2` or `main`                        |
| `NDK_VERSION`  | Android NDK version installed on CI                                                          | `r26d`                                                         |
| `RUST_TARGETS` | Rust targets to install with the toolchain                                                   | `aarch64-linux-android,armv7-linux-androideabi,i686-linux-android,x86_64-linux-android` |
| `CARGO_PROFILE`| Cargo profile passed to the build (`release` by default; custom names supported)             | `release`                                                      |
| `FFI_MANIFEST` | **Optional.** Path to the FFI `Cargo.toml` if auto-detection fails (use **relative** path).  | `third_party/easytier/easytier-contrib/easytier-ffi/Cargo.toml` |

Notes:
- If `ET_REF` contains `/` (e.g., `releases/v2.4.2`), the workflow sanitizes it for file names.
- `FFI_MANIFEST` is resolved to an absolute path inside the script so directory changes don’t break it.
- The matrix defines the ABI list; `ABIS` from env is not used in the matrix setup.

---

## License

- Scripts in this repo: **MIT** (see `LICENSE`).
- Upstream **EasyTier** retains its original license and copyrights.
