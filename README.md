# bx

`bx` runs a program inside a macOS `sandbox-exec` profile built for coding agents
such as Claude Code, Codex, pi, Devin, opencode and Gemini CLI.

```sh
bx claude --dangerously-skip-permissions
bx codex --dangerously-bypass-approvals-and-sandbox
bx pi
bx devin
bx -w ../shared-lib -- opencode --standalone
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
| **Processes** | `process-fork` and `process-exec` are allowed, so agents can run shells, compilers and test runners. The program bx started and everything it spawns inherit the sandbox. A service that was already running before bx does not — see [Agents with a background service](#agents-with-a-background-service) |
| **Network** | Allowed. `--no-network` limits it to localhost and unix sockets |
| **Environment** | Inherited unchanged: `HOME`, `USER`, `PATH`, `JAVA_HOME`, `NODE_OPTIONS`, `MAVEN_OPTS`, `JAVA_OPTS`, API keys and so on. If `JAVA_HOME` is unset, bx fills it in from SDKMAN or `/usr/libexec/java_home`. Inside the sandbox, `BX_SANDBOX=1` and `BX_WORKSPACE` are set |

The sandbox does **not** let a program write to shell rc files, `~/.ssh`,
`~/.local/bin`, `~/Library`, other projects, or anywhere else outside the list above.

## Agents with a background service

`bx` confines the process it starts and its descendants. Some agents are split
into a thin client plus a long-lived background service, and then the client
you sandbox does no real work: every tool call — including the bash tool — runs
in the service, which was started outside `bx` and is not confined.

The sandbox is process state: `sandbox-exec` installs it before `exec`, and
`fork()` copies it, so every descendant stays confined (a nested sandbox can
only tighten it). It is inherited in no other way — not over IPC, not
retroactively — so processes that were already running, or that `launchd`
starts on the caller's behalf, keep their own, empty sandbox.

opencode v2 is the known case. Its TUI connects to `opencode serve --service`:

```sh
opencode service status                                          # prints the service URL
ps -o pid,ppid,command -p $(pgrep -f 'opencode serve --service')  # ppid 1: daemonized
```

That daemon is started before `bx` (or by an earlier plain `opencode` run),
detaches from its parent (PPID 1) and survives across `bx` invocations, so
`bx opencode` gives you a sandboxed UI that talks to an unsandboxed worker.
Writing outside the workspace then succeeds, which makes the sandbox look
broken when it was never applied to the process that writes.

Run opencode in standalone mode so the server lives inside the sandboxed
process tree:

```sh
bx opencode --standalone
```

Or stop the background service first, so the CLI spawns one under `bx`:

```sh
opencode service stop
bx opencode
```

A service spawned from inside `bx` inherits the sandbox, but it keeps the
profile of the run that created it for its whole lifetime — so its writable
workspace is whichever directory that first `bx` run used. Prefer
`--standalone` (one server per session) over reusing a sandboxed daemon.

To confirm the sandbox is active, run `bx --log` in another terminal and ask
the agent to write outside the workspace: a real block shows up as
`deny(1) file-write-create /path`. No log line means the write happened in an
unconfined process.

The same applies to any agent or tool with a pre-existing daemon (Docker
daemons, `launchctl`-managed helpers, other client/server agents): `bx` can
only restrict what it actually started.

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

Homebrew (this repository is its own tap):

```sh
brew tap serhii-ilin/bx https://github.com/serhii-ilin/bx
brew install serhii-ilin/bx/bx
```

`brew upgrade bx` picks up new releases. Use `brew install --HEAD serhii-ilin/bx/bx`
for the latest `main`, and `brew uninstall bx && brew untap serhii-ilin/bx` to remove it.

One-liner, no checkout or Homebrew needed (installs the latest release):

```sh
curl -fsSL https://raw.githubusercontent.com/serhii-ilin/bx/main/install.sh | bash
```

Options go after `bash -s --`, e.g. `... | bash -s -- --prefix ~/bin`.
To install a specific tag or branch, set `BX_REF`:
`curl -fsSL .../install.sh | BX_REF=v1.0.0 bash`.

Uninstall the same way:

```sh
curl -fsSL https://raw.githubusercontent.com/serhii-ilin/bx/main/uninstall.sh | bash
curl -fsSL https://raw.githubusercontent.com/serhii-ilin/bx/main/uninstall.sh | bash -s -- --purge
```

From a checkout:

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

## Releases

Each push to `main` that passes shellcheck and the macOS smoke tests is
tagged and released by `.github/workflows/release.yml`:

- The new version is the latest `vX.Y.Z` tag with the patch number bumped.
  For a minor or major bump, raise `BX_VERSION` in `bin/bx`; the workflow
  uses it when it is higher than the latest tag.
- A GitHub Release is created with generated notes.
- `Formula/bx.rb` is pointed at the new tag and its sha256 in a follow-up
  commit on `main` by `github-actions[bot]`. Run `git pull --rebase` before
  your next push. The bot commit itself is not released again.

`BX_VERSION` in the source tree is only the base version. The installer and
the Homebrew formula stamp the real release number into the installed `bx`.

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
- **Only what bx started is sandboxed.** An agent with a client/server split
  does its file writes in the background service, not in the client bx
  launched. Stop the service or use the agent's standalone mode; details in
  [Agents with a background service](#agents-with-a-background-service).
- **Agents' own sandboxes still work under bx.** Nested sandboxes stack, so
  Codex's seatbelt and Claude Code's sandbox can only restrict further. They
  cannot grant more than bx allows.
- **Self-updates may fail.** An agent that updates by rewriting a symlink in
  `~/.local/bin` (e.g. `claude update`) can't do it inside bx. Run the update
  outside bx.
- **`sandbox-exec` is deprecated but still works.** Apple has marked it
  deprecated for years, and it is still the mechanism behind Codex's and Claude
  Code's macOS sandboxes.

## License

[MIT](LICENSE)
