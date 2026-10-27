#!/bin/bash
# Install bx into ~/.local/bin (or --prefix DIR).
#
#   ./install.sh            copy bin/bx to ~/.local/bin/bx
#   ./install.sh --link     symlink instead (edits in this checkout take effect)
#   ./install.sh --prefix DIR
#
# Without a checkout:
#   curl -fsSL https://raw.githubusercontent.com/serhii-ilin/bx/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --prefix DIR
# BX_REF selects a branch or tag to download (default: main).
set -euo pipefail

BX_TMP=""

# Everything runs from main() so a truncated `curl | bash` download never
# executes a partial script.
main() {
  local repo_url="${BX_BASE_URL:-https://raw.githubusercontent.com/serhii-ilin/bx/${BX_REF:-main}}"
  local prefix="$HOME/.local/bin"
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bx"
  local link=0 src_dir target

  while [[ $# -gt 0 ]]; do
    case $1 in
      --link)   link=1; shift ;;
      --prefix) [[ $# -ge 2 ]] || die "--prefix needs a directory"
                prefix=$2; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option '$1'" ;;
    esac
  done

  [[ $(uname -s) == Darwin ]] || die "bx requires macOS (sandbox-exec)"
  [[ -x /usr/bin/sandbox-exec ]] || die "/usr/bin/sandbox-exec not found"

  # Run from a checkout, or download the sources when piped from curl.
  if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]] &&
     src_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) &&
     [[ -f $src_dir/bin/bx ]]; then
    :
  else
    [[ $link -eq 0 ]] || die "--link needs a local checkout"
    BX_TMP=$(mktemp -d)
    trap 'rm -rf "$BX_TMP"' EXIT
    src_dir=$BX_TMP
    mkdir -p "$src_dir/bin" "$src_dir/examples"
    echo "Downloading bx from $repo_url"
    fetch "$repo_url/bin/bx" "$src_dir/bin/bx"
    fetch "$repo_url/examples/config" "$src_dir/examples/config"
    if ! grep -q '^# bx - run a program' "$src_dir/bin/bx" || ! bash -n "$src_dir/bin/bx"; then
      die "downloaded bin/bx does not look like bx"
    fi
  fi

  mkdir -p "$prefix"
  target="$prefix/bx"
  rm -f "$target"
  if [[ $link -eq 1 ]]; then
    ln -s "$src_dir/bin/bx" "$target"
    echo "Linked $target -> $src_dir/bin/bx"
  else
    install -m 0755 "$src_dir/bin/bx" "$target"
    echo "Installed $target"
  fi

  if [[ ! -e $config_dir/config ]]; then
    mkdir -p "$config_dir"
    install -m 0644 "$src_dir/examples/config" "$config_dir/config"
    echo "Created $config_dir/config (all entries commented out)"
  else
    echo "Kept existing $config_dir/config"
  fi

  case ":$PATH:" in
    *":$prefix:"*) ;;
    *) echo
       echo "Note: $prefix is not on your PATH. Add this to ~/.zshrc:"
       echo "  export PATH=\"$prefix:\$PATH\"" ;;
  esac

  "$target" --version
}

die() { echo "install: $*" >&2; exit 2; }

fetch() {
  /usr/bin/curl -fsSL --retry 2 -o "$2" "$1" || die "failed to download $1"
}

usage() {
  cat <<'EOF'
Usage: install.sh [--link] [--prefix DIR]

  --link        symlink ~/.local/bin/bx to this checkout instead of copying
  --prefix DIR  install into DIR instead of ~/.local/bin

From the network:
  curl -fsSL https://raw.githubusercontent.com/serhii-ilin/bx/main/install.sh | bash
EOF
}

main "$@"
