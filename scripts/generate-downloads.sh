#!/usr/bin/env bash
#
# generate-downloads.sh — Generate the Cup downloads page from packages.cfg
#
# Reads config/packages.cfg and produces downloads.html
# with per-category download tables for all tools.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_DIR/config/packages.cfg"
OUTPUT_FILE="$PROJECT_DIR/downloads.html"

# --- Helper: get a value from the config file ---
get_cfg() {
  local key="$1"
  grep "^${key}=" "$CONFIG_FILE" | head -1 | sed 's/^[^=]*=//'
}

# --- Category display names and order ---
CATEGORY_ORDER=(
  "compiler"
  "debugger"
  "linker"
  "language-server"
  "formatter"
  "linter"
  "analyzer"
)

declare -A CATEGORY_LABELS
CATEGORY_LABELS[compiler]="Compilers"
CATEGORY_LABELS[debugger]="Debuggers"
CATEGORY_LABELS[linker]="Linkers"
CATEGORY_LABELS[language-server]="Language Servers"
CATEGORY_LABELS[formatter]="Formatters"
CATEGORY_LABELS[linter]="Linters"
CATEGORY_LABELS[analyzer]="Analyzers"

# --- Website URLs for each tool ---
declare -A TOOL_WEBSITES
TOOL_WEBSITES[compiler.gcc]="https://gcc.gnu.org/"
TOOL_WEBSITES[compiler.clang]="https://llvm.org/"
TOOL_WEBSITES[debugger.gdb]="https://sourceware.org/gdb/"
TOOL_WEBSITES[debugger.lldb]="https://llvm.org/"
TOOL_WEBSITES[linker.lld]="https://llvm.org/"
TOOL_WEBSITES[language-server.clangd]="https://clangd.llvm.org/"
TOOL_WEBSITES[formatter.clang-format]="https://clang.llvm.org/docs/ClangFormat.html"
TOOL_WEBSITES[linter.clang-tidy]="https://clang.llvm.org/extra/clang-tidy/"
TOOL_WEBSITES[analyzer.valgrind]="https://valgrind.org/"

# --- Human-readable platform names ---
platform_label() {
  local plat="$1"
  local os="${plat%%-*}"
  local arch="${plat#*-}"
  local os_label=""
  case "$os" in
    linux)   os_label="Linux" ;;
    windows) os_label="Windows" ;;
    macos|darwin) os_label="macOS" ;;
    freebsd) os_label="FreeBSD" ;;
    *)       os_label="$os" ;;
  esac
  local arch_label=""
  case "$arch" in
    x64|x86_64) arch_label="x64" ;;
    aarch64|arm64) arch_label="ARM64" ;;
    x86)     arch_label="x86" ;;
    *)       arch_label="$arch" ;;
  esac
  echo "$os_label ($arch_label)"
}

# --- HTML-escape a string ---
html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  echo "$s"
}

# =============================================================
# 1. Verify config file
# =============================================================

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

# =============================================================
# 2. Discover tools and platform combinations
# =============================================================

declare -A CATEGORY_TOOLS  # "compiler→gcc" = 1
declare -A TOOL_COMBOS     # "compiler→gcc→linux-x64→windows-x64" = 1

while IFS='=' read -r line; do
  key="${line%%=*}"
  key="$(echo "$key" | xargs)"
  case "$key" in
    *.stable_version)
      prefix="${key%.stable_version}"
      IFS='.' read -r category tool host_platform target_platform <<< "$prefix" || true
      CATEGORY_TOOLS["$category→$tool"]=1
      TOOL_COMBOS["$category→$tool→$host_platform→$target_platform"]=1
      ;;
  esac
done < <(grep -v '^\s*#' "$CONFIG_FILE")

# =============================================================
# 3. Generate the HTML
# =============================================================

cat > "$OUTPUT_FILE" << 'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Downloads - Coffee</title>
  <meta name="keywords" content="C, C programming language, cup, coffee, toolchain, downloads">
  <meta name="description" content="Download C and C++ development tools installable by Cup">
  <link rel="stylesheet" href="https://coffee-clang.github.io/normalize.css">
  <link rel="stylesheet" href="https://coffee-clang.github.io/cup.css">
  <link rel="icon" type="image/svg+xml" href="https://coffee-clang.github.io/logo.svg">
  <style>
    /* Download table styles */
    .download-table { width: 100%; border-collapse: collapse; margin-bottom: 1.5em; }
    .download-table th { background-color: #4a2c2a; color: #f5e6d3; padding: 8px; border: 1px solid #4a2c2a; text-align: left; }
    .download-table td { border: 1px solid #4a2c2a; padding: 8px; text-align: left; vertical-align: top; }
    .download-table tbody tr:nth-child(odd) { background-color: #e8dcc8; }
    .download-table tbody tr:nth-child(even) { background-color: #f5e6d3; }
    .dl-links { list-style: none; margin: 0; padding: 0; display: inline; }
    .dl-links li { display: inline; border: none; padding: 0; }
    .dl li + li::before { content: " | "; color: #6b4438; }
    .version-cell { white-space: nowrap; }
    @media screen and (max-width: 600px) {
      .download-table, .download-table thead, .download-table tbody,
      .download-table th, .download-table td, .download-table tr { display: block; }
      .download-table thead { display: none; }
      .download-table td {
        position: relative;
        padding-left: 40%;
        border: none;
        border-bottom: 1px solid #d4a574;
        min-height: 1.5em;
      }
      .download-table td::before {
        position: absolute;
        left: 8px;
        width: 35%;
        padding-right: 10px;
        font-weight: bold;
        color: #4a2c2a;
        content: attr(data-label);
      }
      .download-table tr {
        border: 2px solid #4a2c2a;
        margin-bottom: 0.5em;
        border-radius: 4px;
        display: block;
      }
      .dl li { display: block; margin: 0.2px 0; }
      .dl li + li::before { content: none; }
    }
  </style>
</head>
<body>

<!-- Header with logo -->
<div class="logo-container">
  <div class="logo">
    <img src="logo.svg" alt="Coffee logo" width="120" height="120">
  </div>
  <div class="tagline">
    <h1>Coffee</h1>
    <p>A modern C toolchain</p>
  </div>
</div>

<!-- Navigation -->
<nav class="menu mainmenu">
  <ul>
    <li><a href="https://coffee-clang.github.io/">Home</a></li>
    <li><a href="downloads.html" class="active">Downloads</a></li>
    <li><a href="https://github.com/coffee-clang">GitHub</a></li>
  </ul>
</nav>

<div class="content">

  <h1>Downloads</h1>

  <p>All tools installable by <strong>Cup</strong>. Click a format link to download directly, or use <code>cup install &lt;tool&gt;</code> to install via the package manager.</p>


HTML_HEAD

# --- 4. Per-category sections ---
for cat in "${CATEGORY_ORDER[@]}"; do
  # Check if this category has any tools
  has_tools=0
  for key in "${!CATEGORY_TOOLS[@]}"; do
    c="${key%%→*}"
    if [[ "$c" == "$cat" ]]; then
      has_tools=1
      break
    fi
  done
  [[ "$has_tools" -eq 0 ]] && continue

  label="${CATEGORY_LABELS[$cat]:-$cat}"
  echo "  <h2>$(html_escape "$label")</h2>" >> "$OUTPUT_FILE"

  # Collect tools for this category, sorted
  declare -a tools_in_cat=()
  for key in "${!CATEGORY_TOOLS[@]}"; do
    c="${key%%→*}"
    t="${key#*→}"
    if [[ "$c" == "$cat" ]]; then
      tools_in_cat+=("$t")
    fi
  done
  IFS=$'\n' tools_in_cat=($(sort <<< "${tools_in_cat[*]}")); unset IFS

  for tool in "${tools_in_cat[@]}"; do
    website="${TOOL_WEBSITES[$cat.$tool]:-}"

    echo "  <h3><a href=\"$(html_escape "$website")\">$(html_escape "$tool")</a></h3>" >> "$OUTPUT_FILE"
    echo "  <table class=\"download-table\">" >> "$OUTPUT_FILE"
    echo "    <thead>" >> "$OUTPUT_FILE"
    echo "      <tr>" >> "$OUTPUT_FILE"
    echo "        <th>Host → Target</th>" >> "$OUTPUT_FILE"
    echo "        <th>Latest Version</th>" >> "$OUTPUT_FILE"
    echo "        <th>Downloads</th>" >> "$OUTPUT_FILE"
    echo "        <th>All Versions</th>" >> "$OUTPUT_FILE"
    echo "      </tr>" >> "$OUTPUT_FILE"
    echo "    </thead>" >> "$OUTPUT_FILE"
    echo "    <tbody>" >> "$OUTPUT_FILE"

    # Collect platform combinations for this tool, sorted
    declare -a combos=()
    for key in "${!TOOL_COMBOS[@]}"; do
      IFS='→' read -r c t h tg <<< "$key"
      if [[ "$c" == "$cat" && "$t" == "$tool" ]]; then
        combos+=("$h|$tg")
      fi
    done
    IFS=$'\n' combos=($(sort <<< "${combos[*]}")); unset IFS

    for combo in "${combos[@]}"; do
      host="${combo%%|*}"
      target="${combo#*|}"

      # Build config key prefix
      prefix="${cat}.${tool}.${host}.${target}"

      stable_version="$(get_cfg "${prefix}.stable_version")"
      formats="$(get_cfg "${prefix}.formats")"
      url_template="$(get_cfg "${prefix}.url_template")"

      [[ -z "$stable_version" ]] && continue

      host_label="$(platform_label "$host")"
      target_label="$(platform_label "$target")"

      echo "      <tr>" >> "$OUTPUT_FILE"
      echo "        <td data-label=\"Host → Target\">$(html_escape "$host_label → $target_label")</td>" >> "$OUTPUT_FILE"
      echo "        <td data-label=\"Latest Version\" class=\"version-cell\">$(html_escape "$stable_version")</td>" >> "$OUTPUT_FILE"

      # Downloads column: links for each format
      echo -n "        <td data-label=\"Downloads\"><ul class=\"dl-links dl\">" >> "$OUTPUT_FILE"
      IFS=',' read -ra format_list <<< "$formats"
      for fmt in "${format_list[@]}"; do
        fmt="$(echo "$fmt" | xargs)"
        [[ -z "$fmt" ]] && continue
        # Substitute placeholders
        dl_url="$url_template"
        dl_url="${dl_url//\{version\}/$stable_version}"
        dl_url="${dl_url//\{host_platform\}/$host}"
        dl_url="${dl_url//\{target_platform\}/$target}"
        dl_url="${dl_url//\{format\}/$fmt}"
        echo -n "<li><a href=\"$(html_escape "$dl_url")\">$(html_escape "$fmt")</a></li>" >> "$OUTPUT_FILE"
      done
      echo "</ul></td>" >> "$OUTPUT_FILE"

      # All versions link
      release_url="https://github.com/coffee-clang/cup/releases?q=${tool}+${host}+${target}"
      echo "        <td data-label=\"All Versions\"><a href=\"$(html_escape "$release_url")\">View all releases ↗</a></td>" >> "$OUTPUT_FILE"
      echo "      </tr>" >> "$OUTPUT_FILE"
    done

    echo "    </tbody>" >> "$OUTPUT_FILE"
    echo "  </table>" >> "$OUTPUT_FILE"
  done
done

# --- 5. Footer ---
cat >> "$OUTPUT_FILE" << 'HTML_FOOT'

  <hr class="xhr">

  <p id="help">
    Need help?<br>
    Run <code>cup help</code> in your terminal, or visit the <a href="https://github.com/coffee-clang/cup">Cup GitHub page</a>.
  </p>
  <p id="about">
    Coffee is an open-source project.
    &nbsp;&middot;&nbsp;
    <a href="https://github.com/coffee-clang">GitHub</a>
    inspired by <a href="https://github.com/rust-lang/cargo">Cargo</a>
  </p>
  <p id="about">
    Cup is a <a href="https://coffee-clang.github.io/">Coffee</a> project.
    &nbsp;&middot;&nbsp;
    <a href="https://github.com/coffee-clang/cup">GitHub</a>
    &nbsp;&middot;&nbsp;
    Inspired by <a href="https://rustup.rs">Rustup</a>
  </p>

</div>

</body>
</html>
HTML_FOOT

echo "Generated: $OUTPUT_FILE"