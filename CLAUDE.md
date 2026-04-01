# Claude Code Godot Development Environment

## Environment

This project runs in a devcontainer with two Godot MCP servers connected to a Godot editor on the host machine.

## MCP Servers

### godot-mcp (11 tools)
Full Godot editor integration via WebSocket (port 6550):
- Visual inspection: editor state, scenes, running games, errors, performance
- Node/resource inspection: scene tree, properties, resources
- Modification: scenes, nodes, scripts, animations, tilemaps
- Game testing: runtime execution, input injection
- Documentation: `godot_docs` for on-demand Godot docs retrieval

### minimal-godot-mcp (4 tools)
LSP-based diagnostics via port 6005:
- `get_diagnostics` — analyze single GDScript files
- `scan_workspace_diagnostics` — examine all .gd files in workspace
- `get_console_output` — retrieve debug session output
- `clear_console_output` — clear buffered console entries

## Authentication

Run `claude login` inside the container on first use. Credentials persist in a Docker volume across container restarts.

## Prerequisites

For the MCP servers to work, the host machine must have:
1. **Godot 4.5+** editor running
2. **godot-mcp addon** installed and enabled (Project > Project Settings > Plugins)
3. **LSP server** enabled (Editor > Editor Settings > Network > Language Server)

## Workspace

The Godot project is mounted at `/workspace`. All file paths are relative to this directory.

## User Config

User-level Claude Code config (skills, CLAUDE.md) is mounted from `CLAUDE_USER_CONFIG_DIR` on the host and symlinked into `~/.claude/` inside the container. Login credentials persist separately in a Docker volume.

## Asset Generation Tools

The container includes tools for programmatic asset creation:

- **2D**: `convert` (ImageMagick) for CLI image ops; `python3` with Pillow for programmatic textures/sprites
- **3D**: `python3` with trimesh for procedural mesh generation (export to glTF/OBJ/STL); `gltf-transform` for optimizing/compressing glTF; `obj2gltf` and `fbx2gltf` for format conversion
- **Audio**: `ffmpeg` for format conversion and simple sound effect generation (sine waves, noise, filters)

## File Editing Guidelines

- **Direct editing**: GDScript (.gd), shaders (.gdshader), project.godot — plain text, safe to edit
- **Use MCP tools**: Scenes (.tscn), resources (.tres), animations — complex formats, prefer MCP tools for manipulation
