# Claude Code Godot Devcontainer for Indie Developers

A devcontainer setup that runs [Claude Code](https://claude.ai/claude-code) with two Godot MCP servers for AI-assisted Godot game development.

Ideal for indie or solo game developers, which simply would like solid tooling without wanting to run an entire game studio using AI.

## What's Included

- **Claude Code CLI** running with `--dangerously-skip-permissions` inside a sandboxed container
- **[godot-mcp](https://github.com/satelliteoflove/godot-mcp)** — Full Godot editor integration (11 tools): scene manipulation, node management, script editing, documentation lookup, game testing
- **[minimal-godot-mcp](https://github.com/ryanmazzolini/minimal-godot-mcp)** — LSP-based diagnostics (4 tools): GDScript error checking, workspace scanning, console output
- **Asset generation tools** — ImageMagick, FFmpeg, Python/Pillow, trimesh, gltf-transform, obj2gltf, fbx2gltf

## What's NOT included

- **Godot specific skills** - This is very subjective and each developer may have different preferences when it comes to skills. The setup will source your skills and global Claude setup based on an environment variable (see [2. Configure environment](#2-configure-environment) in the [Setup](#setup) guide). Personal recommendation for a good comprehensive Godot skill: [Godot skill for Claude Code](https://mcp.directory/skills/godot)
- **Blender CLI or MCP**: Turned out to be too big for the container and can be covered with some of the light-weight tooling installed with the devcontainer instead

## Prerequisites

- **Docker** (20.10+) installed and running
- **Node.js** (18+) on the host (for npm scripts and devcontainer CLI)
- **socat** on the host (`sudo apt-get install socat`) — bridges Godot's localhost ports to the Docker network (Linux only)
- **Godot 4.5+** editor installed on the host

## Setup

### 1. Clone and install

```bash
git clone <this-repo>
cd claude-code-godot-setup
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
```

`CLAUDE_USER_CONFIG_DIR` should point to a directory containing any of:

- `skills/` — custom Claude Code skills
- `CLAUDE.md` — global instructions for Claude Code

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

With Godot running on the host, start the container and launch Claude Code:

```bash
npm run devcontainer:up
npm run claude
```

The port bridge (Linux only) starts automatically with the container, relaying Godot's localhost-bound ports to the Docker network. Claude Code will have access to all MCP tools. You can verify with the `/mcp` command inside Claude Code.

When done:

```bash
npm run devcontainer:down
```

## Available Commands

| Command                             | Description                                                              |
| ----------------------------------- | ------------------------------------------------------------------------ |
| `npm run devcontainer:build`        | Build the container image                                                |
| `npm run devcontainer:up`           | Start the container (auto-starts port bridge on Linux)                   |
| `npm run devcontainer:down`         | Stop and remove the container (auto-stops port bridge)                   |
| `npm run devcontainer:shell`        | Open a shell inside the container                                        |
| `npm run bridge:start`              | Manually start host-side port bridge (auto-started by `devcontainer:up`) |
| `npm run bridge:stop`               | Manually stop the port bridge (auto-stopped by `devcontainer:down`)      |
| `npm run claude`                    | Launch Claude Code with `--dangerously-skip-permissions`                 |
| `npm run claude:resume`             | Resume a previous Claude Code session                                    |
| `npm run claude:prompt -- "prompt"` | Run a one-shot prompt                                                    |
| `npm run install-godot-addon`       | Install godot-mcp addon into the Godot project                           |

## How It Works

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

- Your Godot project is bind-mounted into the container at `/workspace`
- **Port bridging** (Linux only): Godot binds to `127.0.0.1`, but the container reaches the host via the Docker bridge (`172.17.0.1`). The host-side bridge (`npm run bridge:start`) relays between these interfaces. Container-side socat then forwards `localhost` to `host.docker.internal`.
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

## Troubleshooting

### MCP servers can't connect to Godot

- Ensure Godot is running on the host **before** launching Claude Code
- Verify the port bridge is running (`npm run bridge:start`) — this starts automatically with `devcontainer:up` but may need restarting if Godot was restarted
- Verify the godot-mcp addon is enabled in Project Settings > Plugins
- Check that the LSP server is enabled in Editor Settings > Network > Language Server

### Container can't resolve `host.docker.internal`

This requires Docker 20.10+ on Linux. The `--add-host=host.docker.internal:host-gateway` flag is set in `devcontainer.json`. Verify with:

```bash
devcontainer exec --workspace-folder . ping -c 1 host.docker.internal
```

### Login doesn't persist

Credentials are stored in the Docker volume `claude-code-config-<id>`. If you destroy the volume (e.g., `docker volume prune`), you'll need to log in again.

### Godot LSP connection refused

Godot binds to `127.0.0.1` only. The host-side bridge handles this by relaying from the Docker bridge IP to localhost. The bridge starts automatically with `devcontainer:up`. If it still fails:

- Verify socat is installed on the host (`sudo apt-get install socat`)
- Manually restart the bridge: `npm run bridge:stop && npm run bridge:start`
