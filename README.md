# Godot Agents Devcontainer for Indie Developers

A devcontainer setup that runs [Claude Code](https://claude.ai/claude-code) and [OpenCode](https://opencode.ai) with two Godot MCP servers for AI-assisted Godot game development.

Ideal for indie or solo game developers, which simply would like solid tooling without wanting to run an entire game studio using AI.

## What's Included

- **Claude Code CLI** running with `--dangerously-skip-permissions` inside a sandboxed container
- **[OpenCode](https://opencode.ai)** — Alternative AI coding agent with multi-provider support (OpenAI, Anthropic, Google, local models, etc.)
- **[godot-mcp](https://github.com/satelliteoflove/godot-mcp)** — Full Godot editor integration (21 tools, 86 actions): scene and node editing, resource and animation authoring, plus a full playtesting loop — run the game, inject input, screenshot it, step the game clock, and read live runtime state
- **[minimal-godot-mcp](https://github.com/ryanmazzolini/minimal-godot-mcp)** — LSP-based diagnostics (4 tools): GDScript error checking, workspace scanning, console output
- **`auto_reload` addon** — reloads the open scene and its scripts within ~1s of an external change, so files written from inside the container show up in the editor without a manual reload ([vendored from GoPeak](https://github.com/HaD0Yun/Doyunha-Gopeak), MIT)
- **Godot headless CLI** — Run scenes, export projects, execute GDScript, and validate projects from the command line (`godot --headless`)
- **Asset generation tools** — ImageMagick, FFmpeg, Python/Pillow, trimesh, gltf-transform, obj2gltf, fbx2gltf

## What's NOT included

- **Godot specific skills** - This is very subjective and each developer may have different preferences when it comes to skills. The setup will source your skills and global Claude setup based on an environment variable (see [2. Configure environment](#2-configure-environment) in the [Setup](#setup) guide). Personal recommendation for a good comprehensive Godot skill: [Godot skill for Claude Code](https://mcp.directory/skills/godot)
- **Blender CLI or MCP**: Turned out to be too big for the container and can be covered with some of the light-weight tooling installed with the devcontainer instead

## Prerequisites

- **Docker** (20.10+) installed and running
  - **macOS / Windows**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (recommended)
  - **Windows (WSL2)**: Docker Desktop with WSL2 backend, or Docker Engine inside WSL2
  - **Linux**: Docker Engine or Docker Desktop
- **Node.js** (18+) on the host (for npm scripts and devcontainer CLI)
- **socat** (Linux only) — bridges Godot's localhost ports to the Docker network. Not needed on macOS or Windows where Docker Desktop handles this natively. Install with `sudo apt-get install socat`
- **Godot 4.5+** editor installed on the host

## Setup

### 1. Clone and install

```bash
git clone <this-repo>
cd godot-agents-devcontainer
npm install
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and set the required variables:

```bash
# Required: absolute path to your Godot project
GODOT_PROJECT_PATH=/home/you/projects/my-godot-game

# Your Claude Code user config directory (skills, CLAUDE.md, etc.)
# Default: $HOME/.claude (standard Claude Code setup)
CLAUDE_USER_CONFIG_DIR=$HOME/.claude

# Optional: Godot headless CLI version (default: 4.7.1)
# GODOT_VERSION=4.7.1

# Optional: long-lived Claude Code token so the container stays logged in
# (only needed if you also use the same Anthropic account elsewhere).
# See "Staying logged in across days" below.
# CLAUDE_CODE_OAUTH_TOKEN=
```

`CLAUDE_USER_CONFIG_DIR` should point to a directory containing any of:

- `skills/` — custom skills (shared by Claude Code and OpenCode)
- `CLAUDE.md` — global instructions for Claude Code (also read by OpenCode as fallback)
- `AGENTS.md` — global instructions for OpenCode (takes precedence over CLAUDE.md)

If you manage your Claude config in a separate repo (e.g., with `CLAUDE.md` as a symlink to another file), point this to that directory. Symlinks within the directory resolve correctly inside the container.

### 3. Build and start the devcontainer

```bash
npm run build
npm run up
```

### 4. Log in to Claude Code

On first use, log in inside the container:

```bash
npm run claude
```

Claude Code will prompt you to authenticate. Credentials are stored in a Docker volume and persist across container restarts.

#### Staying logged in across days (optional long-lived token)

Interactive `claude login` is all you need **if this container is the only place you
use that Anthropic account**. But if you also run Claude Code on your host (or another
machine) under the **same account**, the container tends to get logged out — usually on
the first session of the day. This is not a bug in this setup: Anthropic uses rotating,
single-use refresh tokens, so when your host refreshes the account's token it invalidates
the copy stored in the container's volume.

The fix is a **long-lived token** that is independent of that rotation. It's optional — leave
`CLAUDE_CODE_OAUTH_TOKEN` unset and everything works as before.

1. **Requirements:** an active Claude subscription (Pro, Max, or Team). This token is created
   from your **Claude subscription account** via the CLI below — it is *not* a
   `console.anthropic.com` API key (those bill against the pay-as-you-go API, not your
   subscription).
2. On a machine that has a browser **and** Claude Code installed (e.g. your host, not the
   headless container), run:
   ```bash
   claude setup-token
   ```
   Complete the browser sign-in. It prints a token and the line
   `export CLAUDE_CODE_OAUTH_TOKEN=<token>`. Copy the `<token>` value.
3. Add it to `.env` (which is git-ignored — never commit it):
   ```bash
   CLAUDE_CODE_OAUTH_TOKEN=<token>
   ```
4. Recreate the container so the token is injected:
   ```bash
   npm run up
   ```
   From now on `npm run claude` authenticates with the token automatically — no `claude login`
   needed, and it survives shutdowns and multi-day gaps.

Notes:
- **Inference-only.** Long-lived tokens are scoped to inference, which covers normal coding.
- **Expiry.** The token is long-lived (about a year), not infinite — regenerate with
  `claude setup-token` when it eventually expires.
- If the token is set, it **overrides** any interactive login. To go back to `claude login`,
  blank out `CLAUDE_CODE_OAUTH_TOKEN` in `.env` and run `npm run up` again.
- **Still see a login screen after setting the token?** A leftover `~/.claude/.credentials.json`
  from a previous interactive login can make the TUI prompt even though the token authenticates
  fine. `npm run up` clears it automatically when the token is set; to fix it immediately,
  delete that file once (`npm run shell` → `rm ~/.claude/.credentials.json`).

### 5. Set up Godot for MCP integration

#### Install the godot-mcp addon

The addon is installed into your Godot project's `addons/` directory
**automatically every time the container starts**, from the version pinned in
the image. This keeps the addon and the MCP server in lockstep — a mismatched
addon does not error, it silently drops whole tools. Re-running is a no-op when
the versions already match, and it will never downgrade a newer addon.

To install it manually (for example when running without the devcontainer):

```bash
npm run install-godot-addon
```

#### Enable the addon in Godot

1. Open your Godot project in the editor
2. Go to **Project > Project Settings > Plugins**
3. Enable the **godot-mcp** plugin

After the addon is upgraded to a new version, re-enable the plugin and restart
the editor so the new commands register.

#### Enable auto-reload (recommended)

In the same **Plugins** list, also enable **Godot MCP Auto Reload**. It polls
once a second and reloads the open scene and its attached scripts when they
change on disk, so edits an agent makes from inside the container appear in the
editor without you doing anything.

Its scope is narrower than the name suggests: it watches **only the currently
edited scene and the scripts attached to nodes in it**. For anything else, the
agent should call `godot_scene reload` explicitly. Details and provenance in
[`.devcontainer/addons/README.md`](.devcontainer/addons/README.md).

#### Enable the LSP server (for minimal-godot-mcp)

1. In Godot, go to **Editor > Editor Settings > Network > Language Server**
2. Ensure the language server is **enabled**
3. Note the port (default: 6005)

#### Enable the Debug Adapter (optional)

Only needed for `get_console_output`.

1. In Godot, go to **Editor > Editor Settings > Network > Debug Adapter**
2. Ensure the debug adapter is **enabled**
3. Note the port (default: 6006 — override with `GODOT_DAP_PORT` if changed)

### 6. Start developing

With Godot running on the host, start the container and launch your preferred AI coding agent:

```bash
npm run up
npm run claude    # or: npm run opencode
```

On Linux, a port bridge starts automatically with the container, relaying Godot's localhost-bound ports to the Docker network. On macOS and Windows, Docker Desktop handles this natively — no bridge needed. Both Claude Code and OpenCode have access to all MCP tools on all platforms. You can verify with the `/mcp` command inside Claude Code.

When done:

```bash
npm run down
```

## Available Commands

| Command                               | Description                                                                      |
| ------------------------------------- | -------------------------------------------------------------------------------- |
| `npm run build`                       | Build the container image                                                        |
| `npm run up`                          | Start the container (auto-starts port bridge on Linux; skipped on macOS/Windows) |
| `npm run down`                        | Stop and remove the container (auto-stops port bridge on Linux)                  |
| `npm run shell`                       | Open a shell inside the container                                                |
| `npm run bridge:start`                | Manually start host-side port bridge (Linux only; no-op on macOS/Windows)        |
| `npm run bridge:stop`                 | Manually stop the port bridge (Linux only)                                       |
| `npm run bridge:status`               | Show whether host-side bridge relays are listening                               |
| `npm run bridge:doctor`               | End-to-end health check: Godot ports, host bridge, container-side relay, addon version |
| `npm run claude`                      | Launch Claude Code with `--dangerously-skip-permissions`                         |
| `npm run claude:resume`               | Resume a previous Claude Code session                                            |
| `npm run claude:prompt -- "prompt"`   | Run a one-shot prompt                                                            |
| `npm run opencode`                    | Launch OpenCode TUI                                                              |
| `npm run opencode:prompt -- "prompt"` | Run a one-shot prompt with OpenCode                                              |
| `npm run install-godot-addon`         | Install godot-mcp addon into the Godot project                                   |

> **Note:** `npm up` is a built-in npm alias for `npm update`. Always use `npm run up` (with `run`) to start the container.

## How It Works

### macOS / Windows (Docker Desktop)

```
Host Machine                          Container
+------------------+                  +--------------------+
| Godot 4.5+       |  host.docker.    | Claude Code CLI    |
|  127.0.0.1:6550  |  internal        |   godot-mcp        |
|  127.0.0.1:6005  | <--------------> |   minimal-godot-   |
|  127.0.0.1:6006  |  (native)        |     mcp            |
+------------------+                  +--------------------+
                                      | /workspace (bind)  |
                                      |   = Godot project  |
                                      +--------------------+
                                      | ~/.claude (volume)  |
                                      |   + skills/ (link)  |
                                      |   + CLAUDE.md (link) |
                                      +--------------------+
```

Docker Desktop resolves `host.docker.internal` to the host and can reach localhost-bound ports natively. No bridge needed.

### Linux (Docker Engine)

```
Host Machine                          Container
+------------------+                  +--------------------+
| Godot 4.5+       |                  | Claude Code CLI    |
|  127.0.0.1:6550  |   bridge.sh      |   godot-mcp        |
|  127.0.0.1:6005  | ------------->   |   minimal-godot-   |
|  127.0.0.1:6006  |  (host socat)    |     mcp            |
+------------------+  binds on        +--------------------+
                      docker bridge    | /workspace (bind)  |
                      172.17.0.1       |   = Godot project  |
                          |            +--------------------+
                          +-- socat -> | ~/.claude (volume)  |
                         (container)   |   + skills/ (link)  |
                                       |   + CLAUDE.md (link) |
                                       +--------------------+
```

Godot binds to `127.0.0.1`, but the container reaches the host via the Docker bridge gateway (`172.17.0.1`). The host-side bridge (`bridge.sh` / socat) relays between these interfaces. Container-side socat forwards `localhost` to `host.docker.internal`.

### Common to all platforms

- Your Godot project is bind-mounted into the container at `/workspace`
- Your Claude user config (`CLAUDE_USER_CONFIG_DIR`) is mounted read-only; skills and CLAUDE.md are symlinked into the persisted `~/.claude` volume on startup
- The container has unrestricted network access (Docker provides filesystem and process isolation)

## Asset Generation Tools

The container includes tools that Claude Code can use to generate and manipulate game assets:

| Tool                 | Type  | What it does                                                                                     |
| -------------------- | ----- | ------------------------------------------------------------------------------------------------ |
| **ImageMagick**      | 2D    | Image manipulation, format conversion, compositing (`convert` CLI)                               |
| **Pillow** (Python)  | 2D    | Programmatic texture/sprite generation, pixel art, normal maps                                   |
| **numpy** (Python)   | 2D/3D | Numerical operations for procedural generation, used by Pillow and trimesh                       |
| **FFmpeg**           | Audio | Audio format conversion, simple sound effect generation (`ffmpeg` CLI)                           |
| **trimesh** (Python) | 3D    | Procedural mesh generation (primitives, extrusions, booleans), export to glTF/OBJ/STL            |
| **gltf-transform**   | 3D    | Optimize, compress (Draco/meshopt), merge, convert glTF files                                    |
| **obj2gltf**         | 3D    | Convert OBJ models to glTF                                                                       |
| **fbx2gltf**         | 3D    | Convert FBX models to glTF (Node.js API, use via `node -e "require('fbx2gltf')(input, output)"`) |

## Godot Headless CLI

The container includes the Godot engine binary (v4.7.1 by default), usable via `godot --headless` for:

- **Running scenes**: `godot --headless --path /workspace -s res://script.gd`
- **Automated testing**: Run test frameworks like GUT or GdUnit4 from the command line
- **Exporting projects**: `godot --headless --path /workspace --export-release "Linux" build/game`
- **Project validation**: `godot --headless --path /workspace --check-only`

The version can be changed by setting `GODOT_VERSION` in your `.env` file before building the container.

> **Note**: There is no display server in the container — always use `--headless`. The Godot editor runs on your host machine.

## Using OpenCode

[OpenCode](https://opencode.ai) is included as an alternative AI coding agent with support for 75+ model providers (OpenAI, Anthropic, Google, local models via Ollama, and more).

### Quick start

```bash
npm run opencode
```

On first launch, use the `/connect` command inside OpenCode to add your API credentials (e.g., OpenAI, Anthropic). Credentials are stored in a persisted volume.

### MCP and skills compatibility

Both Claude Code and OpenCode share the same Godot MCP servers. Claude Code's MCP registration runs at container start; OpenCode's is generated lazily by `npm run opencode` so it doesn't hold the godot-mcp connection when idle. Your skills and instructions (`CLAUDE.md`, `AGENTS.md`, `skills/`) are also shared:

| Feature      | Claude Code                      | OpenCode                                   |
| ------------ | -------------------------------- | ------------------------------------------ |
| MCP servers  | Configured via `claude mcp add`  | Configured via `opencode.json`             |
| Global rules | `CLAUDE.md`                      | `AGENTS.md` (falls back to `CLAUDE.md`)    |
| Skills       | `~/.claude/skills/`              | Reads from `~/.claude/skills/`             |
| Permissions  | `--dangerously-skip-permissions` | `"permission": { "*": "allow" }` in config |

### Model configuration

To change the default model, create or edit `opencode.json` in your Godot project root:

```json
{
  "model": "openai/gpt-4o",
  "small_model": "openai/gpt-4o-mini"
}
```

See the [OpenCode documentation](https://opencode.ai/docs/providers/) for the full list of supported providers and models.

## Running Without the Devcontainer

You don't need the devcontainer to use the Godot MCP servers — both `godot-mcp` and `minimal-godot-mcp` are plain npm packages, and running your agent natively on the same machine as Godot is actually simpler than the container setup: Godot binds to `127.0.0.1`, and a native agent process is already on `127.0.0.1` with it, so none of the bridging machinery (socat, `host.docker.internal`) is needed.

What you give up: the container's sandboxing/isolation, and the auto-installed asset-generation tools (ImageMagick, Pillow, trimesh, gltf-transform, obj2gltf, fbx2gltf) — install those yourself if you want them.

### Setup

1. Enable Godot's LSP server (and optionally the Debug Adapter) as described in step 5 above ("Set up Godot for MCP integration") — identical whether or not you use the container.
2. Install the MCP server packages globally. Pin them: godot-mcp ships the Godot addon, and an addon that does not match the server silently drops whole tools.
   ```bash
   npm install -g @satelliteoflove/godot-mcp@4.1.0 @ryanmazzolini/minimal-godot-mcp@0.1.6
   ```
   Then install the addon into your project and enable it in **Project > Project Settings > Plugins**:
   ```bash
   godot-mcp --install-addon /absolute/path/to/your/godot-project
   ```
   Re-run that command after any version bump — it is idempotent.
3. Register the MCP servers with your agent, pointing at `127.0.0.1` instead of `host.docker.internal`:

   **Claude Code:**
   ```bash
   claude mcp add godot-mcp -s user \
     -e GODOT_HOST=127.0.0.1 \
     -e GODOT_PORT=6550 \
     -- npx -y @satelliteoflove/godot-mcp

   claude mcp add minimal-godot-mcp -s user \
     -e GODOT_LSP_PORT=6005 \
     -e GODOT_DAP_PORT=6006 \
     -e GODOT_WORKSPACE_PATH=/absolute/path/to/your/godot-project \
     -- npx -y @ryanmazzolini/minimal-godot-mcp
   ```

   **OpenCode:** add the equivalent block to `opencode.json` in your Godot project root:
   ```json
   {
     "mcp": {
       "godot-mcp": {
         "type": "local",
         "command": ["npx", "-y", "@satelliteoflove/godot-mcp"],
         "environment": {
           "GODOT_HOST": "127.0.0.1",
           "GODOT_PORT": "6550"
         }
       },
       "minimal-godot-mcp": {
         "type": "local",
         "command": ["npx", "-y", "@ryanmazzolini/minimal-godot-mcp"],
         "environment": {
           "GODOT_LSP_PORT": "6005",
           "GODOT_DAP_PORT": "6006",
           "GODOT_WORKSPACE_PATH": "/absolute/path/to/your/godot-project"
         }
       }
     }
   }
   ```
4. Start Godot, then launch your agent as usual (`claude` / `opencode`) from your project directory.

### Notes

- No port bridge is needed on any platform — `127.0.0.1` reaches Godot directly.
- Only one MCP client can hold the godot-mcp WebSocket connection at a time — the same "Another MCP server connected and replaced this one" behavior applies if you run Claude Code and OpenCode against Godot simultaneously (see Troubleshooting below).
- `.devcontainer/poststart.sh` patches `minimal-godot-mcp`'s `diagnostics-manager.js` so Godot's `workspaceChange` LSP notification doesn't overwrite `GODOT_WORKSPACE_PATH` with an unreachable container path. Running natively this mismatch shouldn't occur, since your workspace path already matches what Godot reports — but if diagnostics start resolving to the wrong file paths, that patch is the place to look.
- Skills and `CLAUDE.md`/`AGENTS.md` are read directly from wherever your agent normally looks (e.g. `~/.claude`) — no `CLAUDE_USER_CONFIG_DIR` symlink step needed.

## Troubleshooting

### MCP servers can't connect to Godot

Run `npm run bridge:doctor` first — it checks every link in the chain (Godot listener, host-side bridge, container-side relay) and prints which one is broken.

- Ensure Godot is running on the host **before** launching Claude Code
- **Linux**: Verify the port bridge is running (`npm run bridge:start`) — this starts automatically with `npm run up` but may need restarting if Godot was restarted
- **macOS / Windows**: No bridge needed, but ensure Docker Desktop is running
- Verify the godot-mcp addon is enabled in Project Settings > Plugins
- Check that the LSP server is enabled in Editor Settings > Network > Language Server

### "Another MCP server connected and replaced this one"

The godot-mcp addon allows **only one WebSocket client at a time** — when a second client connects (e.g. OpenCode), it disconnects the first (e.g. Claude Code). Run only one AI tool against Godot at a time. OpenCode's MCP servers are now registered lazily by `npm run opencode` (not at container startup), so OpenCode does not squat the connection slot when idle. To switch tools mid-session, exit one before launching the other.

### Container can't resolve `host.docker.internal`

- **macOS / Windows**: Docker Desktop provides this automatically. Ensure Docker Desktop is up to date.
- **Linux (Docker Engine)**: Requires Docker 20.10+. The `--add-host=host.docker.internal:host-gateway` flag is set in `devcontainer.json`. Verify with:

```bash
devcontainer exec --workspace-folder . ping -c 1 host.docker.internal
```

### Login doesn't persist

Credentials are stored in the Docker volume `godot-agents-config-<id>`. If you destroy the volume (e.g., `docker volume prune`), you'll need to log in again.

If you get logged out **repeatedly — typically on the first session of the day** — and you
also run Claude Code elsewhere under the **same Anthropic account**, that's the rotating
refresh token being invalidated across clients, not lost credentials. Set a long-lived
`CLAUDE_CODE_OAUTH_TOKEN` as described in [Staying logged in across days](#staying-logged-in-across-days-optional-long-lived-token).

### Godot LSP connection refused

Godot binds to `127.0.0.1` only.

- **macOS / Windows**: Docker Desktop can reach host localhost ports natively. Ensure Docker Desktop is running and up to date.
- **Linux**: The host-side bridge relays from the Docker bridge IP to localhost. The bridge starts automatically with `npm run up`. If it still fails:
  - Verify socat is installed (`sudo apt-get install socat`)
  - Manually restart the bridge: `npm run bridge:stop && npm run bridge:start`

### Windows / WSL2 notes

If running Godot natively on Windows with Docker Desktop using the WSL2 backend, `host.docker.internal` resolves to the Windows host. This should work without additional configuration, but networking through the WSL2 VM can occasionally cause connectivity issues. If MCP tools fail to connect, verify that Godot's ports (6550, 6005) are not blocked by the Windows firewall.
