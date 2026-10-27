#!/bin/bash
# Install bx into ~/.local/bin (or --prefix DIR).
#
#   ./install.sh            copy bin/bx to ~/.local/bin/bx
#   ./install.sh --link     symlink instead (edits in this checkout take effect)
#   ./install.sh --prefix DIR
set -euo pipefail

SRC_DIR=$(cd "$(dirname "$0")" && pwd -P)
PREFIX="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bx"
LINK=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --link)   LINK=1; shift ;;
    --prefix) [[ $# -ge 2 ]] || { echo "install: --prefix needs a directory" >&2; exit 2; }
              PREFIX=$2; shift 2 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install: unknown option '$1'" >&2; exit 2 ;;
  esac
done

[[ $(uname -s) == Darwin ]] || { echo "install: bx requires macOS (sandbox-exec)" >&2; exit 1; }
[[ -x /usr/bin/sandbox-exec ]] || { echo "install: /usr/bin/sandbox-exec not found" >&2; exit 1; }

mkdir -p "$PREFIX"
TARGET="$PREFIX/bx"
rm -f "$TARGET"
if [[ $LINK -eq 1 ]]; then
  ln -s "$SRC_DIR/bin/bx" "$TARGET"
  echo "Linked $TARGET -> $SRC_DIR/bin/bx"
else
  install -m 0755 "$SRC_DIR/bin/bx" "$TARGET"
  echo "Installed $TARGET"
fi

if [[ ! -e $CONFIG_DIR/config ]]; then
  mkdir -p "$CONFIG_DIR"
  install -m 0644 "$SRC_DIR/examples/config" "$CONFIG_DIR/config"
  echo "Created $CONFIG_DIR/config (all entries commented out)"
else
  echo "Kept existing $CONFIG_DIR/config"
fi

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) echo
     echo "Note: $PREFIX is not on your PATH. Add this to ~/.zshrc:"
     echo "  export PATH=\"$PREFIX:\$PATH\"" ;;
esac

"$TARGET" --version
