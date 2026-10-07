# Godot Agents Development Environment

## Environment

This project runs in a devcontainer with two Godot MCP servers connected to a Godot editor on the host machine, plus a Blender MCP server connected to an optional Blender session on the same host.

## MCP Servers

### godot-mcp (21 tools, 86 actions)
Full Godot editor integration via WebSocket (port 6550). Tools are
action-dispatched — pass an `action` naming the operation.

**Playing the game** (verify your own work instead of guessing):
- `godot_editor_edit` — `run` / `stop` / `restart` the game
- `godot_input` — inject input into the running game: `sequence` (actions,
  joypad, raw keys, mouse-look), `type_text`, `get_map`
- `godot_editor_read` — `screenshot_game`, `screenshot_editor`, `get_state`,
  `get_selection`, `get_log_messages`, `get_stack_trace`
- `godot_runtime_state` — live game state as JSON: `digest`, `watch_start` /
  `watch_collect` / `watch_stop`
- `godot_game_time` — deterministic playtesting: `freeze`, `step`,
  `step_until`, `thaw`, `status`
- `godot_exec` — `run` GDScript inside the running game to set up scenarios
- `godot_profiler` — metric snapshots and per-frame series with spike detection

**Editing and inspection:**
- `godot_scene` — `open`, `save`, `reload` (picks up on-disk edits made outside
  the editor — use this after writing a `.tscn` from the container)
- `godot_node_read` / `godot_node_edit` — scene tree, effective properties
- `godot_resource` — type-aware resource inspection (SpriteFrames, TileSet,
  materials, textures)
- `godot_animation_read` / `godot_animation_edit` — keyframe authoring
- `godot_tilemap_read` / `godot_tilemap_edit`, `godot_gridmap_read` /
  `godot_gridmap_edit`, `godot_scene3d`, `godot_validate_meshes`
- `godot_project` — `get_info`, `get_settings`, `addon_status`, `check_stale`
- `godot_docs` — on-demand Godot documentation retrieval

Note: v4 removed scene/node *creation* actions on purpose — write `.tscn` files
directly, then verify with `godot_node_read`.

### minimal-godot-mcp (4 tools)
LSP-based diagnostics via port 6005, plus DAP console capture via port 6006:
- `get_diagnostics` — analyze single GDScript files
- `scan_workspace_diagnostics` — examine all .gd files in workspace
- `get_console_output` — retrieve debug session output (needs DAP enabled)
- `clear_console_output` — clear buffered console entries

### blender-mcp (22 tools)
Drives a Blender session running on the **host** via a socket on port 9876.
The GUI Blender these tools talk to runs on the host, not in this container
(for the optional in-container `blender`, see "Headless Blender" below). If
these tools fail to connect, host Blender is either not running or its
BlenderMCP addon has not been connected (the user must
press **Connect to MCP server** in the View3D sidebar after each launch).

**Inspection:**
- `get_scene_info` — objects, materials, and scene structure
- `get_object_info` — detail on a single named object
- `get_viewport_screenshot` — what the user is actually looking at

**Scripting:**
- `execute_blender_code` — run arbitrary Python against the scene. This is the
  workhorse; most modelling is done through it. It executes **on the host**,
  outside this container's isolation, so treat it with the same care as any
  host-side action: no destructive filesystem work, and prefer `bpy` operations
  scoped to the scene.

**Asset sourcing** (each needs its integration enabled in the addon sidebar;
check first rather than assuming):
- Poly Haven (free) — `get_polyhaven_status`, `get_polyhaven_categories`,
  `search_polyhaven_assets`, `download_polyhaven_asset`, `set_texture`
- Sketchfab — `get_sketchfab_status`, `search_sketchfab_models`,
  `get_sketchfab_model_preview`, `download_sketchfab_model`
- Hyper3D Rodin (text/image to 3D) — `get_hyper3d_status`,
  `generate_hyper3d_model_via_text`, `generate_hyper3d_model_via_images`,
  `poll_rodin_job_status`, `import_generated_asset`
- Hunyuan3D — `get_hunyuan3d_status`, `generate_hunyuan3d_model`,
  `poll_hunyuan_job_status`, `import_generated_asset_hunyuan`

For batch or headless mesh work that does not need a live Blender session, the
container's own `trimesh` / `gltf-transform` tooling is usually the better fit.

### Headless Blender (optional)

`BLENDER=on` (check: `blender --version`) installs Blender in the container
for scripted work without a GUI:
`blender --background --python make.py -- <args>` (the script reads its own
arguments after `--` from `sys.argv`). Export with
`bpy.ops.export_scene.gltf(filepath=..., export_format="GLB")`, then run
`gltf-transform validate` on the file. It is the choice when a mesh needs
bevels, modifiers, UV unwrapping or anything trimesh lacks; otherwise trimesh
is faster to start. Keep the script next to its output, like audio generators.

## Auto-reload addon

The `auto_reload` editor plugin polls once a second and reloads externally
changed files, so scripts you write into `/workspace` usually appear in the
editor on their own.

It only watches the **currently edited scene and the scripts attached to nodes
in it**. Outside that scope — a new file, a scene that is not open — nothing
happens automatically, so still call `godot_scene reload` when you have edited a
`.tscn` the editor has open, or when you need a change reflected right now
rather than within a second.

## Authentication

Run `claude login` inside the container on first use. Credentials persist in a Docker volume across container restarts.

If you also run Claude Code on the host under the **same Anthropic account**, the
container can get logged out (usually the first session of the day): the account's
rotating refresh token is invalidated by whichever client refreshed most recently.
To avoid this, set an optional long-lived token (`CLAUDE_CODE_OAUTH_TOKEN`) in `.env`
— see README "Staying logged in across days". Leave it unset to keep normal login.

## Context Compression

When `HEADROOM=on` is set in `.env` (default off), Claude Code and OpenCode
invocations are routed through
[Headroom](https://github.com/headroomlabs-ai/headroom), a local compression
proxy that shrinks tool output/logs before they reach the model. Its usage
beacon is disabled (`HEADROOM_BEACON=off`). Run `headroom doctor` inside the
container to check its status and savings. Check `echo $HEADROOM` to see if it
is active.

## Prerequisites

For the MCP servers to work, the host machine must have:
1. **Godot 4.5+** editor running
2. **godot-mcp addon** enabled (Project > Project Settings > Plugins). The
   addon itself is installed automatically at container start from the pinned
   npm package, so it can never drift out of sync with the server — but a
   version bump still needs the plugin re-enabled and the editor restarted.
3. **LSP server** enabled (Editor > Editor Settings > Network > Language Server)
4. **Debug Adapter** enabled on port 6006 (optional, only for
   `get_console_output`)
5. **Blender 3.0+** running with a GUI, its BlenderMCP addon enabled, and
   **Connect to MCP server** pressed in the View3D sidebar (optional, only for
   the `blender-mcp` tools). The addon lives at `.devcontainer/blender/addon.py`
   in the devcontainer repo on the host.

Run `npm run bridge:doctor` on the host to check all of this end-to-end,
including addon-vs-package version skew. Ports 6006 and 9876 are reported as
optional there, so a green doctor does not mean Blender is connected.

## Workspace

The Godot project is mounted at `/workspace`. All file paths are relative to this directory.

## User Config

User-level Claude Code config (skills, CLAUDE.md) is mounted from `CLAUDE_USER_CONFIG_DIR` on the host and symlinked into `~/.claude/` inside the container. Login credentials persist separately in a Docker volume.

## Asset Generation Tools

The container includes tools for programmatic asset creation:

- **2D**: `convert` (ImageMagick) for CLI image ops; `python3` with Pillow for programmatic textures/sprites
- **3D**: `python3` with trimesh for procedural mesh generation (export to glTF/OBJ/STL); `gltf-transform` for optimizing/compressing glTF; `obj2gltf` and `fbx2gltf` for format conversion
- **Audio**: `ffmpeg` for format conversion and simple sound effect generation (sine waves, noise, filters)

### Audio (optional)

Three build switches add procedural audio tooling; all default to off, so
check before relying on them:

- `AUDIO=on` (check: `python3 -c "import pedalboard"`): numpy/scipy for
  synthesis, `soundfile` for WAV I/O, `pedalboard` for effects (Reverb, Delay,
  LowpassFilter, Compressor, Distortion, Chorus, ...), `pyloudnorm` for
  loudness, `librosa` for analysis, `pyo` for ready-made oscillators/envelopes
  (offline: `Server(audio="offline")` + `recordOptions`; keep every pyo object
  in a variable, unreferenced ones are garbage-collected and render silence), and `jsfxr` for retro
  sfxr presets (pickupCoin, laserShoot, explosion, powerUp, hitHurt, jump,
  blipSelect).
- `AUDIO_MUSIC=on` (check: `ls /usr/share/sounds/sf2`): write MIDI with `mido`,
  render with `fluidsynth -ni -q -F out.wav -r 44100 <font.sf2> song.mid`.
  Two General MIDI fonts: `FluidR3_GM.sf2` and `GeneralUser-GS.sf2` (usually
  the better sounding one). Render the same MIDI with both to let the user
  compare, or render parts with different fonts and mix them in Python.
- `SPEECH=on` (check: `espeak-ng --version`): text to speech.
  - Kokoro for natural voices (24 kHz output):
    ```python
    import soundfile as sf
    from kokoro_onnx import Kokoro
    k = Kokoro("/opt/kokoro/kokoro-v1.0.onnx", "/opt/kokoro/voices-v1.0.bin")
    samples, sr = k.create("Wave seven incoming!", voice="am_michael", speed=1.0, lang="en-us")
    sf.write("line.wav", samples, sr)
    ```
    `k.get_voices()` lists the 54 voices. The prefix is language and gender:
    `af_`/`am_` American English (lang `en-us`), `bf_`/`bm_` British
    (`en-gb`), then `e` Spanish (`es`), `f` French (`fr-fr`), `i` Italian
    (`it`), `p` Brazilian Portuguese (`pt-br`), `h` Hindi, `j` Japanese,
    `z` Mandarin. English sounds best; there is no German.
  - espeak-ng for robotic, retro or alien voices and other languages:
    `espeak-ng -v en+m3 -s 150 -p 40 -w out.wav "text"` (`-v` voice and
    variant, see `espeak-ng --voices` and the variants in
    `espeak-ng-data/voices/!v`; `-s` words per minute; `-p` pitch 0-99; `-m`
    reads SSML).
  - Singing (with `AUDIO=on` for librosa): espeak-ng cannot hit exact notes,
    but SSML `<prosody range="0%">` makes it monotone. Render each syllable
    that way, measure its pitch with `librosa.pyin`, then
    `librosa.effects.pitch_shift` to the note and
    `librosa.effects.time_stretch` to its length, and concatenate. The smoke
    test below does it; expect a robot choir, not a singer.

`bash ~/.devcontainer/audio-smoke.sh` renders a working example with every
installed tool; read it for starting points.

**Conventions:**
- SFX: WAV, 16-bit PCM, 44.1 kHz, mono, peak normalized to -1 dBFS, no
  leading silence (Godot plays it on trigger) and a short fade-out instead of a
  hard cut.
- Voice lines: the same as SFX. Kokoro renders at 24 kHz and espeak-ng at
  22.05 kHz, so resample (`ffmpeg -i in.wav -ar 44100 -ac 1 out.wav`) and trim
  the leading silence.
- Music: OGG Vorbis (`ffmpeg -i in.wav -c:a libvorbis -q:a 5 out.ogg`), around
  -16 LUFS integrated. For loops, render whole bars and let the reverb tail wrap
  around to the start so the loop point does not click; enable loop in the
  Godot import settings.
- No MP3. Put files in the project's existing audio folder, else
  `res://audio/sfx` and `res://audio/music`.
- Keep the generator script next to the output (e.g. `laser.py` beside
  `laser.wav`) so a sound can be regenerated, tweaked or varied later.
- jsfxr from node: `sfxr.generate("laserShoot")`, set `sample_size = 16`, then
  write `Buffer.from(sfxr.toWave(params).wav)`. Its `sfxr-to-wav` CLI defaults
  to 8-bit. Global npm modules need `NODE_PATH="$(npm root -g)"`.

**You cannot hear the result.** Check it instead of guessing:
- Spectrogram to view (time left to right, 0 Hz at the bottom up to sr/2,
  linear; brightness covers the top 80 dB). Shows pitch sweeps, harmonics,
  noise, aliasing, clicks and tail length. Don't use ffmpeg's
  `showspectrumpic` for short SFX: its FFT window shrinks with clip length and
  everything smears into noise.
  ```python
  import sys, numpy as np, soundfile as sf
  from scipy.signal import stft
  from PIL import Image
  x, sr = sf.read(sys.argv[1], always_2d=True)
  f, t, Z = stft(x.mean(axis=1), sr, nperseg=1024, noverlap=1024 - 128)
  db = 20 * np.log10(np.abs(Z) + 1e-9)
  db = np.clip((db - db.max() + 80) / 80, 0, 1)
  Image.fromarray((db[::-1] * 255).astype(np.uint8)).resize((800, 400)).save(sys.argv[2])
  ```
- Waveform (envelope, clipping, silence):
  `ffmpeg -i s.wav -lavfi showwavespic=s=800x200 w.png`.
- Numbers: duration, peak, LUFS (`pyloudnorm`), leading/trailing silence.
- Then ask the user to listen, and iterate on their feedback. Offering 2-3
  variations at once makes that faster.

## Godot Headless CLI

`godot` is available system-wide. Use `--headless` unless you need pixels.
- Run GDScript: `godot --headless --path /workspace -s res://script.gd`
- Export project: `godot --headless --path /workspace --export-release "preset" output_path`
- Validate project: `godot --headless --path /workspace --check-only`

**Drawing real frames** needs an optional rendering pathway
(`echo $RENDER_OPENGL $RENDER_VULKAN $RENDER_DEFAULT`). Then run Godot through
`godot-render`, which wraps Xvfb and sets the display, rendering and audio
flags (`opengl`: Compatibility method forced; `vulkan`: the project's
Forward+ or Mobile method, on lavapipe); other arguments pass through:
`godot-render --path /workspace ...` (screenshots via
`get_viewport().get_texture().get_image()`, videos via `--write-movie`). It
renders on the CPU (llvmpipe or lavapipe): correct but slow. `bash ~/.devcontainer/render-doctor/run.sh`
checks the setup.

## File Editing Guidelines

- **Direct editing**: GDScript (.gd), shaders (.gdshader), project.godot — plain text, safe to edit
- **Use MCP tools**: Scenes (.tscn), resources (.tres), animations — complex formats, prefer MCP tools for manipulation
