# Godot Agents Devcontainer for Indie Developers

A devcontainer setup that runs [Claude Code](https://claude.ai/claude-code) and [OpenCode](https://opencode.ai) with two Godot MCP servers for AI-assisted Godot game development.

Ideal for indie or solo game developers, which simply would like solid tooling without wanting to run an entire game studio using AI.

## What's Included

- **Claude Code CLI** running with `--dangerously-skip-permissions` inside a sandboxed container
- **[OpenCode](https://opencode.ai)** — Alternative AI coding agent with multi-provider support (OpenAI, Anthropic, Google, local models, etc.)
- **[godot-mcp](https://github.com/satelliteoflove/godot-mcp)** — Full Godot editor integration (11 tools): scene manipulation, node management, script editing, documentation lookup, game testing
- **[minimal-godot-mcp](https://github.com/ryanmazzolini/minimal-godot-mcp)** — LSP-based diagnostics (4 tools): GDScript error checking, workspace scanning, console output
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

# Optional: Godot headless CLI version (default: 4.6.1)
# GODOT_VERSION=4.6.1
```

`CLAUDE_USER_CONFIG_DIR` should point to a directory containing any of:

- `skills/` — custom skills (shared by Claude Code and OpenCode)
- `CLAUDE.md` — global instructions for Claude Code (also read by OpenCode as fallback)
- `AGENTS.md` — global instructions for OpenCode (takes precedence over CLAUDE.md)

If you manage your Claude config in a separate repo (e.g., with `CLAUDE.md` as a symlink to another file), point this to that directory. Symlinks within the directory resolve correctly inside the container.

### 3. Build and start the devcontainer

```bash
npm run devcontainer:build
npm run devcontainer:up
```

### 4. Log in to Claude Code

On first use, log in inside the container:

```bash
npm run claude
```

Claude Code will prompt you to authenticate. Credentials are stored in a Docker volume and persist across container restarts.

### 5. Set up Godot for MCP integration

#### Install the godot-mcp addon

```bash
npm run install-godot-addon
```

This copies the godot-mcp addon into your Godot project's `addons/` directory.

#### Enable the addon in Godot

1. Open your Godot project in the editor
2. Go to **Project > Project Settings > Plugins**
3. Enable the **godot-mcp** plugin

#### Enable the LSP server (for minimal-godot-mcp)

1. In Godot, go to **Editor > Editor Settings > Network > Language Server**
2. Ensure the language server is **enabled**
3. Note the port (default: 6005)

### 6. Start developing

With Godot running on the host, start the container and launch your preferred AI coding agent:

```bash
npm run devcontainer:up
npm run claude    # or: npm run opencode
```

On Linux, a port bridge starts automatically with the container, relaying Godot's localhost-bound ports to the Docker network. On macOS and Windows, Docker Desktop handles this natively — no bridge needed. Both Claude Code and OpenCode have access to all MCP tools on all platforms. You can verify with the `/mcp` command inside Claude Code.

When done:

```bash
npm run devcontainer:down
```

## Available Commands

| Command                             | Description                                                              |
| ----------------------------------- | ------------------------------------------------------------------------ |
| `npm run devcontainer:build`        | Build the container image                                                |
| `npm run devcontainer:up`           | Start the container (auto-starts port bridge on Linux; skipped on macOS/Windows) |
| `npm run devcontainer:down`         | Stop and remove the container (auto-stops port bridge on Linux)          |
| `npm run devcontainer:shell`        | Open a shell inside the container                                        |
| `npm run bridge:start`              | Manually start host-side port bridge (Linux only; no-op on macOS/Windows) |
| `npm run bridge:stop`               | Manually stop the port bridge (Linux only)                               |
| `npm run claude`                    | Launch Claude Code with `--dangerously-skip-permissions`                 |
| `npm run claude:resume`             | Resume a previous Claude Code session                                    |
| `npm run claude:prompt -- "prompt"` | Run a one-shot prompt                                                    |
| `npm run opencode`                  | Launch OpenCode TUI                                                      |
| `npm run opencode:prompt -- "prompt"` | Run a one-shot prompt with OpenCode                                    |
| `npm run install-godot-addon`       | Install godot-mcp addon into the Godot project                           |

## How It Works

### macOS / Windows (Docker Desktop)

```
Host Machine                          Container
+------------------+                  +--------------------+
| Godot 4.5+       |  host.docker.    | Claude Code CLI    |
|  127.0.0.1:6550  |  internal        |   godot-mcp        |
|  127.0.0.1:6005  | <--------------> |   minimal-godot-   |
|                  |  (native)        |     mcp            |
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
|                  |  (host socat)    |     mcp            |
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

The container includes the Godot engine binary (v4.6.1 by default), usable via `godot --headless` for:

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

Both Claude Code and OpenCode share the same Godot MCP servers — the container startup script configures them for both tools automatically. Your skills and instructions (`CLAUDE.md`, `AGENTS.md`, `skills/`) are also shared:

| Feature | Claude Code | OpenCode |
| --- | --- | --- |
| MCP servers | Configured via `claude mcp add` | Configured via `opencode.json` |
| Global rules | `CLAUDE.md` | `AGENTS.md` (falls back to `CLAUDE.md`) |
| Skills | `~/.claude/skills/` | Reads from `~/.claude/skills/` |
| Permissions | `--dangerously-skip-permissions` | `"permission": { "*": "allow" }` in config |

### Model configuration

To change the default model, create or edit `opencode.json` in your Godot project root:

```json
{
  "model": "openai/gpt-4o",
  "small_model": "openai/gpt-4o-mini"
}
```

See the [OpenCode documentation](https://opencode.ai/docs/providers/) for the full list of supported providers and models.

## Troubleshooting

### MCP servers can't connect to Godot

- Ensure Godot is running on the host **before** launching Claude Code
- **Linux**: Verify the port bridge is running (`npm run bridge:start`) — this starts automatically with `devcontainer:up` but may need restarting if Godot was restarted
- **macOS / Windows**: No bridge needed, but ensure Docker Desktop is running
- Verify the godot-mcp addon is enabled in Project Settings > Plugins
- Check that the LSP server is enabled in Editor Settings > Network > Language Server

### Container can't resolve `host.docker.internal`

- **macOS / Windows**: Docker Desktop provides this automatically. Ensure Docker Desktop is up to date.
- **Linux (Docker Engine)**: Requires Docker 20.10+. The `--add-host=host.docker.internal:host-gateway` flag is set in `devcontainer.json`. Verify with:

```bash
devcontainer exec --workspace-folder . ping -c 1 host.docker.internal
```

### Login doesn't persist

Credentials are stored in the Docker volume `godot-agents-config-<id>`. If you destroy the volume (e.g., `docker volume prune`), you'll need to log in again.

### Godot LSP connection refused

Godot binds to `127.0.0.1` only.

- **macOS / Windows**: Docker Desktop can reach host localhost ports natively. Ensure Docker Desktop is running and up to date.
- **Linux**: The host-side bridge relays from the Docker bridge IP to localhost. The bridge starts automatically with `devcontainer:up`. If it still fails:
  - Verify socat is installed (`sudo apt-get install socat`)
  - Manually restart the bridge: `npm run bridge:stop && npm run bridge:start`

### Windows / WSL2 notes

If running Godot natively on Windows with Docker Desktop using the WSL2 backend, `host.docker.internal` resolves to the Windows host. This should work without additional configuration, but networking through the WSL2 VM can occasionally cause connectivity issues. If MCP tools fail to connect, verify that Godot's ports (6550, 6005) are not blocked by the Windows firewall.
