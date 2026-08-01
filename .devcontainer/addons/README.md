# Vendored Godot addons

Addons copied into the Godot project at `/workspace/addons/` by
`poststart.sh` on every container start. Unlike the `godot_mcp` addon — which
ships inside the `@satelliteoflove/godot-mcp` npm package and is installed by
that package's own installer — these have no upstream package to install from,
so they are vendored here.

## `auto_reload`

Source: [HaD0Yun/Doyunha-Gopeak](https://github.com/HaD0Yun/Doyunha-Gopeak),
`src/addon/auto_reload/` at v2.3.9. MIT, Copyright (c) 2025 Solomon Elias — full
text in `auto_reload/LICENSE`. Files are **verbatim copies**; update them by
re-copying from upstream rather than editing in place.

An `EditorPlugin` that polls every second and reloads files changed outside the
editor, with no confirmation popup. It is fully standalone: 126 lines of
GDScript, no network, no bridge, no dependency on GoPeak's MCP server or its
other two addons. That is why it can be taken on its own.

It exists here because agents write files into `/workspace` from inside the
container, and the Godot editor does not notice on its own. `godot_scene reload`
covers the same ground manually; this removes the need to remember to call it.

### Scope — narrower than the name suggests

`_update_watched_files()` watches only the **currently edited scene** and the
scripts attached to nodes within it. `_reload_scene()` reloads only if the
changed path *is* the currently edited scene. So:

- editing a script attached to a node in the open scene → picked up
- editing the open scene file itself → picked up
- a new or changed file not attached to the open scene → **not** picked up

For anything outside that, use `godot_scene reload` or `godot_project check_stale`.

Note also that `watched_extensions` is declared upstream but never actually used
for filtering — dead code, left as-is to keep the copy verbatim.
