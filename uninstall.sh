#!/bin/bash
# Remove bx from ~/.local/bin (or --prefix DIR).
#
#   ./uninstall.sh            remove ~/.local/bin/bx, keep ~/.config/bx
#   ./uninstall.sh --purge    also remove ~/.config/bx
#   ./uninstall.sh --prefix DIR
set -euo pipefail

PREFIX="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bx"
PURGE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --purge)  PURGE=1; shift ;;
    --prefix) [[ $# -ge 2 ]] || { echo "uninstall: --prefix needs a directory" >&2; exit 2; }
              PREFIX=$2; shift 2 ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "uninstall: unknown option '$1'" >&2; exit 2 ;;
  esac
done

TARGET="$PREFIX/bx"
if [[ -L $TARGET || -f $TARGET ]]; then
  # Only remove a file that is actually bx, not some other tool named bx.
  if grep -q '^# bx - run a program' "$TARGET" 2>/dev/null ||
     [[ -L $TARGET && $(readlink "$TARGET") == */bin/bx ]]; then
    rm -f "$TARGET"
    echo "Removed $TARGET"
  else
    echo "uninstall: $TARGET is not bx, leaving it alone" >&2
    exit 1
  fi
else
  echo "Nothing to remove at $TARGET"
fi

if [[ $PURGE -eq 1 && -d $CONFIG_DIR ]]; then
  rm -rf "$CONFIG_DIR"
  echo "Removed $CONFIG_DIR"
elif [[ -d $CONFIG_DIR ]]; then
  echo "Kept $CONFIG_DIR (use --purge to remove it)"
fi
