# AGENTS.md — coffee-clang.github.io

## Project Overview

The **coffee-clang.github.io** repository serves two distinct subsystems:

1. **Website** — the [Cup of Coffee](https://coffee-clang.github.io/) 
   project homepage, hosted on GitHub Pages and built with mdbook
2. **Toolchain build system** — bash scripts that build and package C/C++ toolchains (GCC, Clang, GDB, Valgrind, etc.) for distribution via GitHub Releases

"Cup of Coffee" is a modern C toolchain manager (inspired by Rustup/Cargo). Cup = toolchain installer, Coffee = build system, Recipes = package registry.

## Directory Layout

```
.
├── header.html          # HTML head, logo, nav menu
├── content.html         # Install instructions (Linux curl, Windows PS)
├── footer.html          # Footer + copy-to-clipboard JS
├── downloads.html       # Auto-generated download tables (not committed)
├── index.html           # Final site (concatenated at deploy time)
├── brand.css            # Shared brand identity (coffee color palette)
├── cup.css              # Project-specific styles
├── normalize.css        # CSS reset
├── mdbook.css           # mdBook layout
├── logo.svg             # Animated coffee cup with </> code brackets
├── copy-icon.svg        # Copy button icon
├── config/
│   └── packages.cfg     # Package inventory: versions, formats, URLs per tool/platform
├── scripts/
│   ├── package-common.sh          # **Shared library** for all builds
│   ├── build-gcc.sh               # Build self-contained GCC (+Binutils +MinGW-w64 for Windows)
│   ├── build-gdb.sh               # Build GDB
│   ├── build-llvm-tool.sh         # Build any LLVM tool (clang, lld, lldb, clangd, clang-format, clang-tidy)
│   ├── build-valgrind.sh          # Build Valgrind
│   ├── build-gnu-package.sh       # Dispatcher: routes to build-gcc.sh or build-gdb.sh
│   ├── generate-downloads.sh      # Reads packages.cfg → generates downloads.html
│   ├── install-cup.sh             # Bootstrap installer (POSIX sh)
│   ├── install-cup-windows.ps1    # Bootstrap installer (PowerShell)
│   ├── uninstall-cup.sh           # Uninstaller (POSIX sh)
│   ├── uninstall-cup-windows.ps1  # Uninstaller (PowerShell)
├── .github/workflows/
│   ├── deploy.yml                 # Deploy site to GitHub Pages (on push to main)
│   └── build-valgrind.yml         # Build Valgrind via Docker, publish release (on tag valgrind-*)
├── docker/
│   └── toolchain-builder.Dockerfile  # Ubuntu 24.04 with all build deps
├── fonts/fira-code/               # Fira Code TTF fonts
└── docs/design/                   # Empty placeholder
```

### Shared Library: `scripts/package-common.sh`
Every build script must `source` this. It provides all infrastructure:

**Platform abstraction functions:**
- `platform_triple()` — maps `linux-x64` → `x86_64-linux-gnu`, `windows-x64` → `x86_64-w64-mingw32`
- `platform_family()`, `platform_runtime()`, `platform_thread_model()` — per-platform metadata
- `is_windows_platform()` / `is_cross_build()` — boolean checks

**Version management:**
- `resolve_version(tool, requested)` — resolves "latest"/"stable" to concrete versions. Defaults maintained at top of file.
- `package_version_name()` / `package_base_name()` — construct package names with revision logic (GCC always gets `-revN`, cross-builds always get `-revN`)

**Source management:**
- `fetch(url, output)` — curl with caching (skips if file exists)
- `extract_archive(archive, destination)` — handles .tar.xz, .tar.gz, .tar.bz2, .zip
- `prepare_source_tree(name, version, url, fallback_archive)` — download + extract in one call
- `source_url_*()` functions — return source download URLs for each tool

**Packaging:**
- `create_packages()` — copies staged prefix into `dist/`, creates archives in all formats, writes `release.env`
- `create_archive()` — creates tar.xz, tar.gz, or zip
- `package_formats_for_host()` — preferred format order per platform
- `write_info_file()` — writes `info.txt` metadata into the package

**Directory conventions:**
- `CUP_WORK_DIR=.cup-build/` — build artifacts
- `CUP_SRC_DIR`, `CUP_BUILD_DIR`, `CUP_STAGE_DIR` — under work dir
- `CUP_OUT_DIR=dist/` — final packages land here

### Build script patterns
All build scripts follow this structure:
1. Source `package-common.sh`
2. Parse arguments: `<version|stable|latest> <host_platform> <target_platform> [revision]`
3. Resolve version, compute platform triples
4. Call `make_dirs()` and `need_*()` for required tools
5. Download and extract sources via `prepare_source_tree()`
6. Configure with `./configure` flags, build with `make -j$CUP_JOBS`, install with `make install`
7. Write `info.txt` metadata via `write_info_file()`
8. Package via `create_packages()`

### Build script specifics

**`build-gcc.sh`** — Most complex. Key behaviors:
- **Native Linux** (linux-x64→linux-x64): builds GCC with bootstrap, bundles Binutils
- **Windows** (any→windows-x64): cross-compiles GCC, bundles Binutils + MinGW-w64 (headers, CRT, winpthreads)
- Uses a 2-stage GCC build for Windows targets (stage1 builds minimal GCC, then builds CRT with it, then final GCC)
- PATH is modified in subshells during build — SC2030/SC2031 shellcheck warnings are known
- Target tool aliasing: creates prefixed tool names (e.g., `x86_64-w64-mingw32-gcc`), handles symlink materialization

**`build-llvm-tool.sh`** — Handles 6 tools from a single llvm-project source:
- 5th arg selects tool: `clang`, `lld`, `lldb`, `clangd`, `clang-format`, `clang-tidy`
- Uses CMake (set `-DLLVM_ENABLE_PROJECTS=...`)
- For Windows cross-builds: uses `CMAKE_TOOLCHAIN_FILE`

**`build-gdb.sh`** — Standard autotools build, supports Linux native and Windows cross (with MinGW)

**`build-valgrind.sh`** — Standard autotools build, Linux native only. Tested in CI with actual leak detection.

**`build-gnu-package.sh`** — Thin dispatcher:
- Routes `gcc` → `build-gcc.sh`, `gdb` → `build-gdb.sh`
- Same arg format but with tool name as first arg

### CI workflows

**`build-valgrind.yml`**:
- Trigger: tag matching `valgrind-*`
- Builds inside `toolchain-builder.Dockerfile` container
- Extensive testing after build: version check, tool help, leak detection (`definitely lost: 4 bytes in 1 blocks`), MPI wrapper presence, relocation test
- Publishes to GitHub Releases via `gh release`

### Build environment defaults (in `package-common.sh`)

```
DEFAULT_GCC_VERSION=16.1.0
DEFAULT_GDB_VERSION=17.1
DEFAULT_BINUTILS_VERSION=2.46.0
DEFAULT_MINGW_VERSION=14.0.0
DEFAULT_LLVM_VERSION=22.1.5
DEFAULT_VALGRIND_VERSION=3.27.0
```

## The `config/packages.cfg` Format

INI-like flat key-value file. Key format:
```
{category}.{tool}.{host_platform}.{target_platform}.{property}=value
```

Categories: `compiler`, `debugger`, `linker`, `language-server`, `formatter`, `linter`, `analyzer`

Tools: `gcc`, `clang`, `gdb`, `lldb`, `lld`, `clangd`, `clang-format`, `clang-tidy`, `valgrind`

Platforms: `linux-x64`, `windows-x64`

Properties: `stable_version`, `available_versions`, `default_format`, `formats`, `url_template`

`url_template` supports placeholders: `{version}`, `{host_platform}`, `{target_platform}`, `{format}`

## Gotchas & Non-obvious Patterns

1. **All scripts use `set -euo pipefail`** — strict error handling throughout
2. **`package-common.sh` uses global variables** (CUP_ROOT, CUP_WORK_DIR, etc.) — sourced, not executed. Changing them affects all subsequent build operations.
3. **GCC revision logic**: GCC always gets `-revN` in the version string (`14.2.0-rev1`). Cross-builds also always get `-revN`. Native non-GCC tools don't.
4. **Windows GCC builds are always cross-compiles** — even native Windows builds (windows-x64→windows-x64) are done via cross-compilation techniques (using `--target`).
5. **`configure_script_for_build()` in build-gcc.sh** uses relative paths for Windows (to avoid path separator issues) and absolute paths for Linux.
6. **Test in CI uses exact string matching** for valgrind leak detection: `grep "definitely lost: 4 bytes in 1 blocks"` — brittle if output format changes.
7. **Website has no package.json, no build tool** — it's raw HTML+CSS with `cat` assembly.
8. **The `docs/design/` directory is empty** — intended for design documents but not yet populated.
9. **Shellcheck warnings are present** — SC2129 (multiple redirects), SC2030/SC2031 (PATH modified in subshell). Known and mostly benign.
10. **All GitHub artifacts go to the `coffee-clang/cup` repo** — not this repo. Download URLs point to `github.com/coffee-clang/cup/releases/`.
