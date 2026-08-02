# Blender MCP addon

`addon.py` is the Blender side of [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp).
It opens a TCP socket server inside Blender on `127.0.0.1:9876`; the `blender-mcp`
Python package in the container connects out to it.

Source: upstream `main`, addon `bl_info` version **(1, 2)**, paired with the
`blender-mcp==1.6.5` pin in `.devcontainer/Dockerfile`. MIT, Copyright (c) 2025
Siddharth Ahuja — full text in `LICENSE`. A **verbatim copy**; update it by
re-downloading from upstream and bumping the pip pin in the same commit.

## Why it is vendored

The pip package and this addon version independently, and a mismatched pair
fails silently rather than loudly — exactly the failure that left this project's
Godot addon two major versions behind its server. Pinning the package while
installing the addon from GitHub `main` would recreate that. Keeping both in one
commit makes them move together.

Unlike `.devcontainer/addons/`, this is **not** synced into the project by
`poststart.sh`. Blender's addon directory is on the host, unreachable from the
container, so this is only a version-matched local file to install from.

## Installing it

1. **Edit > Preferences > Add-ons**
2. On Blender 4.2+, use the dropdown in the top-right and pick
   **Install legacy Add-on**. Upstream's instructions predate the Extensions
   platform and say plain "Install from file", which no longer matches the UI.
   Legacy `bl_info` add-ons are still supported; only the button moved.
3. Select this directory's `addon.py`, then tick **Interface: Blender MCP**.
4. In the 3D viewport press **N**, open the **BlenderMCP** tab, and click
   **Connect to MCP server**.

Step 4 is required after **every** Blender launch — the socket server does not
autostart.

Blender must be running with a GUI. The addon explicitly refuses to start under
`blender --background`, since commands are dispatched on the UI thread via
`bpy.app.timers` and would never execute. (`xvfb-run -a blender` also works.)

## Notes for this setup

- The host's Blender is a **Flatpak**, whose config lives under
  `~/.var/app/org.blender.Blender/config/blender/<version>/` rather than
  `~/.config/blender/`. Using the Preferences installer above avoids needing to
  know that path. The Flatpak has `shared=network`, so its loopback bind is
  visible to the host-side `bridge.sh` relay.
- The optional asset integrations (Poly Haven, Sketchfab, Hyper3D Rodin,
  Hunyuan3D) are toggled in that same **BlenderMCP** sidebar tab. Poly Haven is
  free; the others need API keys entered there, not in this repo.

## Verified against

Blender **5.2.0 LTS**: imports, `register()` and `unregister()` all succeed
despite the addon declaring a 3.0 minimum.
