#!/bin/bash
# Remove bx from ~/.local/bin (or --prefix DIR).
#
#   ./uninstall.sh            remove ~/.local/bin/bx, keep ~/.config/bx
#   ./uninstall.sh --purge    also remove ~/.config/bx
#   ./uninstall.sh --prefix DIR
#
# Without a checkout:
#   curl -fsSL https://raw.githubusercontent.com/serhii-ilin/bx/main/uninstall.sh | bash
#   curl -fsSL .../uninstall.sh | bash -s -- --purge
set -euo pipefail

# Everything runs from main() so a truncated `curl | bash` download never
# executes a partial script.
main() {
  local prefix="$HOME/.local/bin"
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bx"
  local purge=0 target

  while [[ $# -gt 0 ]]; do
    case $1 in
      --purge)  purge=1; shift ;;
      --prefix) [[ $# -ge 2 ]] || die "--prefix needs a directory"
                prefix=$2; shift 2 ;;
      -h|--help) echo "Usage: uninstall.sh [--purge] [--prefix DIR]"; exit 0 ;;
      *) die "unknown option '$1'" ;;
    esac
  done

  target="$prefix/bx"
  if [[ -L $target || -f $target ]]; then
    # Only remove a file that is actually bx, not some other tool named bx.
    if grep -q '^# bx - run a program' "$target" 2>/dev/null ||
       [[ -L $target && $(readlink "$target") == */bin/bx ]]; then
      rm -f "$target"
      echo "Removed $target"
    else
      echo "uninstall: $target is not bx, leaving it alone" >&2
      exit 1
    fi
  else
    echo "Nothing to remove at $target"
  fi

  if [[ $purge -eq 1 && -d $config_dir ]]; then
    rm -rf "$config_dir"
    echo "Removed $config_dir"
  elif [[ -d $config_dir ]]; then
    echo "Kept $config_dir (use --purge to remove it)"
  fi
}

die() { echo "uninstall: $*" >&2; exit 2; }

main "$@"
