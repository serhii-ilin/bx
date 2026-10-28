#!/bin/bash
# Smoke tests for bx. Run from anywhere: ./tests/smoke.sh [path-to-bx]
# Single-quoted $VARs are meant to expand inside the sandboxed shell.
# shellcheck disable=SC2016
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
BX=${1:-$ROOT/bin/bx}
WS="$ROOT/tests/.ws.$$"
OUTSIDE="$ROOT/tests/.outside.$$"
CFG=$(mktemp -d)
TAG="bx-test-$$"
PASS=0 FAIL=0

mkdir -p "$WS"
# Docker creates ~/.docker outside bx; do the same on machines without it.
DOCKER_CREATED=0
[[ -d $HOME/.docker ]] || { mkdir "$HOME/.docker" && DOCKER_CREATED=1; }
cleanup() {
  rm -rf "$WS" "$OUTSIDE" "$CFG" "${HOME:?}/$TAG" "${HOME:?}/.claude/$TAG" "${HOME:?}/.claude.json.$TAG"
  [[ $DOCKER_CREATED -eq 1 ]] && rmdir "$HOME/.docker/buildx" "$HOME/.docker" 2>/dev/null
}
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

# expect_ok NAME CMD...    / expect_fail NAME CMD...
expect_ok()   { local n=$1; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else fail "$n"; fi; }
expect_fail() { local n=$1; shift; if "$@" >/dev/null 2>&1; then fail "$n"; else ok "$n"; fi; }
# expect_eq NAME EXPECTED CMD...
expect_eq() {
  local n=$1 want=$2 got; shift 2
  got=$("$@" 2>&1)
  if [[ $got == "$want" ]]; then ok "$n"; else fail "$n (got: $got)"; fi
}

bx() { "$BX" --no-config -w "$WS" "$@"; }

echo "bx smoke tests ($BX)"

echo "filesystem:"
expect_ok   "write inside workspace"        bx sh -c "echo x > '$WS/f' && mkdir -p '$WS/d/e'"
expect_ok   "write to /tmp"                  bx sh -c "echo x > /tmp/$TAG && rm /tmp/$TAG"
expect_ok   "write to \$TMPDIR"              bx sh -c 'f=$(mktemp) && rm "$f"'
expect_fail "write next to workspace"        bx sh -c "mkdir '$OUTSIDE'"
expect_fail "write to \$HOME"                bx sh -c "echo x > '$HOME/$TAG'"
expect_fail "append to ~/.zshrc"             bx sh -c ": >> '$HOME/.zshrc'"
expect_fail "write to ~/.local/bin"          bx sh -c "echo x > '$HOME/.local/bin/$TAG'"
expect_ok   "write agent dir (~/.claude)"    bx sh -c "mkdir -p '$HOME/.claude' && echo x > '$HOME/.claude/$TAG'"
expect_ok   "write ~/.claude.json sibling"   bx sh -c "echo x > '$HOME/.claude.json.$TAG'"
expect_ok   "write npm cache"                bx sh -c "mkdir -p '$HOME/.npm/$TAG' && rmdir '$HOME/.npm/$TAG'"
expect_ok   "write maven repository"         bx sh -c "mkdir -p '$HOME/.m2/repository/$TAG' && rmdir '$HOME/.m2/repository/$TAG'"
expect_fail "write ~/.m2/settings.xml"       bx sh -c ": >> '$HOME/.m2/settings.xml'"
expect_ok   "write docker buildx state"      bx sh -c "mkdir -p '$HOME/.docker/buildx/$TAG' && rmdir '$HOME/.docker/buildx/$TAG'"
expect_fail "write ~/.docker/config.json"    bx sh -c ": >> '$HOME/.docker/config.json'"
expect_fail "write bx config dir"            bx sh -c "mkdir -p '$HOME/.config/bx/$TAG'"
expect_ok   "read system files"              bx cat /etc/hosts
expect_ok   "read \$HOME"                    bx ls "$HOME"
expect_fail "--ro carve-out"                 bx --ro "$WS/locked" sh -c "mkdir -p '$WS/locked'"
expect_fail "--deny hides path"              bx --deny "$WS" ls "$WS"
expect_ok   "--rw extra path"                "$BX" --no-config -w "$WS" --rw "$OUTSIDE" sh -c "mkdir '$OUTSIDE'"

echo "processes and arguments:"
expect_eq   "arguments passed verbatim"      'x|a b|-c|$HOME|' bx /bin/sh -c 'printf "%s|" "$@"' sh x "a b" -c '$HOME'
expect_eq   "exit status propagated"         7 sh -c "'$BX' --no-config -w '$WS' sh -c 'exit 7'; echo \$?"
expect_eq   "fork + exec"                    nested bx sh -c 'sh -c "sh -c \"echo nested\""'
expect_eq   "cwd preserved"                  "$ROOT" sh -c "cd '$ROOT' && '$BX' --no-config -w '$WS' pwd -P"
expect_ok   "nested bx"                      bx "$BX" --no-config -w "$WS" true

echo "environment:"
expect_eq   "env inherited"                  "-Xmx1g|--max-old-space-size=4096|1" \
            env MAVEN_OPTS=-Xmx1g NODE_OPTIONS=--max-old-space-size=4096 "$BX" --no-config -w "$WS" \
            sh -c 'echo "$MAVEN_OPTS|$NODE_OPTIONS|$BX_SANDBOX"'
expect_eq   "BX_WORKSPACE set"               "$WS" bx sh -c 'echo "$BX_WORKSPACE"'
expect_eq   "-e NAME=VAL"                    bar bx -e FOO=bar sh -c 'echo "$FOO"'
expect_eq   "--clean-env keeps allowlist"    "$HOME|$USER|-Xmx1g|1" \
            env MAVEN_OPTS=-Xmx1g "$BX" --no-config -w "$WS" --clean-env \
            sh -c 'echo "$HOME|$USER|$MAVEN_OPTS|$BX_SANDBOX"'
expect_eq   "--clean-env drops others"       "|kept" \
            env SOME_SECRET=s KEEP_ME=kept "$BX" --no-config -w "$WS" --clean-env -e KEEP_ME \
            sh -c 'echo "${SOME_SECRET-}|$KEEP_ME"'
expect_eq   "JAVA_HOME filled when unset"    yes \
            env -u JAVA_HOME "$BX" --no-config -w "$WS" sh -c '[ -n "$JAVA_HOME" ] && echo yes || echo no'

echo "config:"
mkdir -p "$CFG/bx"
cat > "$CFG/bx/config" <<EOF
# test config
rw   $OUTSIDE
set  FROM_CONFIG=yes
EOF
expect_eq   "config rw + set"                yes \
            env BX_CONFIG_DIR="$CFG/bx" "$BX" -w "$WS" sh -c "mkdir -p '$OUTSIDE' && echo \$FROM_CONFIG"
echo '(deny file-read* (subpath "/etc"))' > "$CFG/bx/profile.sb"
expect_fail "profile.sb appended"            env BX_CONFIG_DIR="$CFG/bx" "$BX" -w "$WS" cat /etc/hosts
expect_ok   "--no-config ignores profile.sb" env BX_CONFIG_DIR="$CFG/bx" "$BX" --no-config -w "$WS" cat /etc/hosts

echo "safety:"
expect_fail "refuses \$HOME workspace"       "$BX" --no-config -w "$HOME" true
expect_fail "refuses / workspace"            "$BX" --no-config -w / true
expect_fail "unknown option rejected"        "$BX" --bogus true

if command -v curl >/dev/null 2>&1 && curl -s -m 5 -o /dev/null https://example.com; then
  echo "network:"
  expect_ok   "network allowed"              bx curl -s -m 5 -o /dev/null https://example.com
  expect_fail "--no-network blocks"          bx --no-network curl -s -m 5 -o /dev/null https://example.com
fi

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
