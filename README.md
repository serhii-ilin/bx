# bx

`bx` runs a program inside a macOS `sandbox-exec` profile built for coding agents
such as Claude Code, Codex, pi, Devin, opencode and Gemini CLI.

```sh
bx claude --dangerously-skip-permissions
bx codex --dangerously-bypass-approvals-and-sandbox
bx pi
bx devin
bx -w ../shared-lib -- opencode
```

`bx` stops reading its own options at the first argument that is not a bx
option, so the program gets every argument after its name exactly as given.
Use `--` when the program name itself starts with `-`.

## What the sandbox allows

| | |
|---|---|
| **Read** | The whole filesystem, except paths you hide with `deny` / `--deny` |
| **Write** | `/tmp`, `/private/tmp`, `/private/var/tmp`, `$TMPDIR` and the per-user `/private/var/folders/…/{T,C}` dirs |
| | The workspace: the git top-level of `$PWD`, or `$PWD`, or every `-w DIR`. For a linked git worktree, the main repo's `.git` dir is also writable |
| | Agent state, including skills, rules, memory, sessions and auth: `~/.claude`, `~/.claude.json*`, `~/.codex`, `~/.pi`, `~/.devin`, `~/.config/devin`, `~/.gemini`, `~/.cursor`, `~/.config/opencode`, `~/.agents`, … (see `AGENT_DIRS` in `bin/bx`) |
| | Caches: `~/.cache`, `~/Library/Caches` (pip, uv, poetry, go-build, …), `~/.npm`, pnpm, yarn, bun, `~/.m2`, `~/.gradle`, `~/.sdkman/{tmp,var,archives}`, `~/.local/share/uv`, cargo registry, Go module cache. Locations set through env vars (`NPM_CONFIG_CACHE`, `PIP_CACHE_DIR`, `UV_CACHE_DIR`, `GRADLE_USER_HOME`, `SDKMAN_DIR`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, …) are added too |
| **Read-only inside writable areas** | `~/.m2/settings*.xml`, `~/.gradle/gradle.properties`, `~/.gradle/init.d`, and `~/.config/bx` itself |
| **Processes** | `process-fork` and `process-exec` are allowed, so agents can run shells, compilers and test runners. Child processes inherit the sandbox |
| **Network** | Allowed. `--no-network` limits it to localhost and unix sockets |
| **Environment** | Inherited unchanged: `HOME`, `USER`, `PATH`, `JAVA_HOME`, `NODE_OPTIONS`, `MAVEN_OPTS`, `JAVA_OPTS`, API keys and so on. If `JAVA_HOME` is unset, bx fills it in from SDKMAN or `/usr/libexec/java_home`. Inside the sandbox, `BX_SANDBOX=1` and `BX_WORKSPACE` are set |

The sandbox does **not** let a program write to shell rc files, `~/.ssh`,
`~/.local/bin`, `~/Library`, other projects, or anywhere else outside the list above.

## Options

```
-w, --workspace DIR   Writable workspace (repeatable)
    --rw PATH         Extra writable path (repeatable)
    --ro PATH         Read-only carve-out inside writable paths
    --deny PATH       Hide a path (no read, no write)
-e, --env NAME[=VAL]  Set a variable, or keep NAME under --clean-env
    --clean-env       Pass only an allowlist of environment variables
    --no-network      Block network except localhost and unix sockets
    --no-config       Ignore ~/.config/bx/{config,profile.sb}
    --force           Allow $HOME or / as workspace (refused by default)
    --print-profile   Print the generated SBPL profile
-n, --dry-run         Show what would run (env values are not printed)
-v, --verbose         Print a sandbox summary to stderr
    --log             Stream sandbox denials (run it in a second terminal)
```

`--clean-env` keeps terminal, locale, proxy and toolchain variables (`JAVA_*`,
`MAVEN_*`, `GRADLE_*`, `SDKMAN_*`, `NODE_*`, `NVM_*`, `npm_config_*`, `PYTHON*`,
`UV_*`, `GO*`, `CARGO_*`, …). It also keeps agent and provider variables
(`ANTHROPIC_*`, `CLAUDE_*`, `OPENAI_*`, `CODEX_*`, `GEMINI_*`, `AWS_*`, `PI_*`,
`DEVIN_*`, `GH_TOKEN`, …). Everything else is dropped.

## Configuration

`~/.config/bx/config` (the installer creates it with every line commented out):

```
rw   ~/.docker
ro   $PWD/.git/hooks
deny ~/.aws
env  MY_COMPANY_*
set  PYTHONDONTWRITEBYTECODE=1
clean-env yes
network no
```

`~/.config/bx/profile.sb` holds raw SBPL. bx appends it to the end of the
generated profile, so its rules win. Example:

```scheme
(allow file-write* (subpath "/Users/me/.nvm"))
```

To see the full profile, run `bx --print-profile`.

## Install

```sh
./install.sh            # copies bin/bx to ~/.local/bin/bx
./install.sh --link     # symlink instead (for working on bx)
./uninstall.sh          # removes ~/.local/bin/bx
./uninstall.sh --purge  # also removes ~/.config/bx
```

Both scripts accept `--prefix DIR`. The code runs on the stock macOS `/bin/bash` 3.2.

## Debugging denials

When a tool fails with `Operation not permitted`, run `bx --log` in another
terminal and repeat the action. Each blocked path shows up as
`deny(1) file-write-create /path`. To allow it, add it with `--rw` or a `rw`
line in the config.

## Tests

```sh
./tests/smoke.sh        # tests ./bin/bx
./tests/smoke.sh ~/.local/bin/bx
```

## Limits and notes

- **Agent dirs are writable by design.** An agent can change its own settings
  and hooks, e.g. `~/.claude/settings.json`. If you sometimes run the same agent
  without bx, those hooks then run unsandboxed.
- **The `.git` dir inside the workspace is writable.** A process can plant
  `.git/hooks/*` or change `core.hooksPath`, and that code runs the next time you
  use git outside the sandbox. Use `ro $PWD/.git/hooks` if this worries you.
- **The profile starts from `(allow default)`.** It limits writes, not IPC.
  A sandboxed process can still ask other processes to act for it: `open`,
  `osascript` / Apple Events, `launchctl`, a Docker daemon. Those processes
  run outside the sandbox.
- **Agents' own sandboxes still work under bx.** Nested sandboxes stack, so
  Codex's seatbelt and Claude Code's sandbox can only restrict further. They
  cannot grant more than bx allows.
- **Self-updates may fail.** An agent that updates by rewriting a symlink in
  `~/.local/bin` (e.g. `claude update`) can't do it inside bx. Run the update
  outside bx.
- **`sandbox-exec` is deprecated but still works.** Apple has marked it
  deprecated for years, and it is still the mechanism behind Codex's and Claude
  Code's macOS sandboxes.
