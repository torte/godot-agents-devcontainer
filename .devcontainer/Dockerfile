FROM node:22

ARG TZ
ENV TZ="$TZ"

# Install development tools, asset generation tools, and socat for port forwarding
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iproute2 \
  jq \
  nano \
  vim \
  socat \
  imagemagick \
  ffmpeg \
  python3 \
  python3-pip \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python libraries for asset generation, plus the Blender MCP server.
# blender-mcp is pinned because it pairs with a Blender addon installed host-side:
# a mismatched pair fails silently rather than loudly (see .devcontainer/blender/).
RUN pip3 install --break-system-packages Pillow numpy trimesh blender-mcp==1.6.5

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude /home/node/.config/opencode /home/node/.headroom && \
  chown -R node:node /workspace /home/node/.claude /home/node/.config /home/node/.headroom

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install Godot headless CLI
ARG GODOT_VERSION=4.7.2
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip && \
  unzip -q /tmp/godot.zip -d /tmp/godot && \
  mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot && \
  chmod +x /usr/local/bin/godot && \
  rm -rf /tmp/godot.zip /tmp/godot

# Copy startup and launcher scripts
COPY --chown=node:node poststart.sh /home/node/.devcontainer/poststart.sh
COPY --chown=node:node opencode-launch.sh /home/node/.devcontainer/opencode-launch.sh
COPY --chown=node:node claude-launch.sh /home/node/.devcontainer/claude-launch.sh
COPY --chown=node:node headroom-enabled.sh /home/node/.devcontainer/headroom-enabled.sh
COPY --chown=node:node audio-smoke.sh /home/node/.devcontainer/audio-smoke.sh
COPY --chown=node:node addons /home/node/.devcontainer/addons
COPY --chown=node:node render-doctor /home/node/.devcontainer/render-doctor
COPY --chown=node:node godot-render.sh /usr/local/bin/godot-render
RUN chmod +x /home/node/.devcontainer/poststart.sh /home/node/.devcontainer/opencode-launch.sh /home/node/.devcontainer/claude-launch.sh /home/node/.devcontainer/audio-smoke.sh /usr/local/bin/godot-render

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/home/node/.local/bin:/home/node/.opencode/bin:$PATH:/usr/local/share/npm-global/bin

# Install Claude Code and opencode as the node user so their native
# self-updaters can write to $HOME and keep the binaries current.
RUN curl -fsSL https://claude.ai/install.sh | bash \
  && curl -fsSL https://opencode.ai/install | bash

# Headroom: optional local compression proxy wrapping Claude Code and OpenCode
# (see claude-launch.sh and opencode-launch.sh). Only installed with the build
# arg HEADROOM=on (from .env, default off), since it adds uv, a Python
# interpreter and an ONNX model to the image. Beacon (anonymous usage
# reporting) is disabled — no telemetry leaves the container.
# >=0.36.0 is a hard floor: earlier releases break streaming responses against
# recent Claude Code versions (headroom-ai/headroom#3017, fixed in #3091/#3094).
# [proxy,code] (not [all]/[ml]): the Kompress text compressor auto-picks its
# lightweight ONNX Runtime backend from [proxy] (no torch needed); [ml] would
# additionally drag in full PyTorch + CUDA/triton (multi-GB) for a backend we
# don't use. [code] adds tree-sitter-based AST-aware code compression.
ENV HEADROOM_BEACON=off
# uv's tool venvs (UV_TOOL_DIR) and managed Python interpreters
# (UV_PYTHON_INSTALL_DIR) both default under $HOME/.local, which is shadowed
# at runtime by the persisted godot-agents-local volume (kept around so
# Claude/OpenCode's own auto-updaters survive rebuilds) — a rebuilt image's
# new/updated files there would never be seen by an existing
# container. Redirect the whole tree, plus the shim dir, to /usr/local/share,
# which is already on PATH and isn't volume-backed.
ENV UV_TOOL_DIR=/usr/local/share/uv-tools
ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv-python
ENV UV_TOOL_BIN_DIR=/usr/local/share/npm-global/bin
# Declared this late so switching HEADROOM keeps every earlier layer cached.
ARG HEADROOM=off
RUN case "$(echo "$HEADROOM" | tr '[:upper:]' '[:lower:]')" in \
    on) curl -LsSf https://astral.sh/uv/install.sh | sh \
      && uv tool install --python 3.13 "headroom-ai[proxy,code]>=0.36.0" \
      && uv tool run --from "headroom-ai[proxy,code]" python3 -c \
        "from headroom.transforms.kompress_compressor import KompressCompressor; KompressCompressor().compress('warm the model cache. ' * 500)" ;; \
    off|"") echo "Headroom disabled (HEADROOM=off), skipping install" ;; \
    *) echo "Unknown HEADROOM '$HEADROOM' (expected on or off)" >&2; exit 1 ;; \
  esac

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Godot MCP servers and 3D asset tools.
# The MCP servers are pinned: godot-mcp ships the Godot addon that poststart.sh
# installs into the project, so an unpinned bump would silently change both the
# tool surface and the addon written into the user's Godot project.
RUN npm install -g \
  @satelliteoflove/godot-mcp@4.1.0 \
  @ryanmazzolini/minimal-godot-mcp@0.1.6 \
  @gltf-transform/cli \
  obj2gltf \
  fbx2gltf

# Optional audio tooling for procedural SFX and music (see README "Optional:
# audio tools"), both off by default and declared last so toggling them keeps
# every earlier layer cached. Two independent gates:
# - AUDIO=on: SFX stack. scipy/soundfile for DSP and I/O, pedalboard (Spotify,
#   JUCE effects), pyloudnorm, librosa for analysis, pyo (from apt: PyPI has
#   no Linux wheel for this Python) and jsfxr for retro sfxr presets.
# - AUDIO_MUSIC=on: MIDI rendering. mido, fluidsynth and two General MIDI
#   soundfonts: FluidR3_GM (apt) and GeneralUser GS, pinned to a commit since
#   the project publishes no releases.
USER root
ARG AUDIO=off
RUN case "$(echo "$AUDIO" | tr '[:upper:]' '[:lower:]')" in \
    on) apt-get update && apt-get install -y --no-install-recommends python3-pyo \
      && apt-get clean && rm -rf /var/lib/apt/lists/* \
      && pip3 install --break-system-packages scipy soundfile pedalboard pyloudnorm librosa \
      && su node -c "npm install -g jsfxr" ;; \
    off|"") echo "Audio SFX tools disabled (AUDIO=off), skipping install" ;; \
    *) echo "Unknown AUDIO '$AUDIO' (expected on or off)" >&2; exit 1 ;; \
  esac
ARG AUDIO_MUSIC=off
ARG GENERALUSER_GS_COMMIT=684543d5e5efaef08d02be50dcda8d552478fa60
RUN case "$(echo "$AUDIO_MUSIC" | tr '[:upper:]' '[:lower:]')" in \
    on) apt-get update && apt-get install -y --no-install-recommends fluidsynth fluid-soundfont-gm \
      && apt-get clean && rm -rf /var/lib/apt/lists/* \
      && pip3 install --break-system-packages mido \
      && wget -q "https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/${GENERALUSER_GS_COMMIT}/GeneralUser-GS.sf2" \
        -O /usr/share/sounds/sf2/GeneralUser-GS.sf2 ;; \
    off|"") echo "Audio music tools disabled (AUDIO_MUSIC=off), skipping install" ;; \
    *) echo "Unknown AUDIO_MUSIC '$AUDIO_MUSIC' (expected on or off)" >&2; exit 1 ;; \
  esac

# Optional headless Blender for scripted modelling and export
# (`blender --background --python x.py`; see README "Optional: headless
# Blender"). Off by default: the official LTS build adds about 1 GB. Debian's
# own package is too old for current glTF export. Only the X and GL client
# libraries it links against are installed; no display is needed.
ARG BLENDER=off
ARG BLENDER_VERSION=4.5.14
RUN case "$(echo "$BLENDER" | tr '[:upper:]' '[:lower:]')" in \
    on) apt-get update && apt-get install -y --no-install-recommends \
        xz-utils libx11-6 libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 \
        libsm6 libice6 libgl1 libegl1 libglu1-mesa \
      && apt-get clean && rm -rf /var/lib/apt/lists/* \
      && wget -q "https://download.blender.org/release/Blender${BLENDER_VERSION%.*}/blender-${BLENDER_VERSION}-linux-x64.tar.xz" -O /tmp/blender.tar.xz \
      && mkdir -p /opt/blender && tar -xJf /tmp/blender.tar.xz -C /opt/blender --strip-components=1 \
      && rm /tmp/blender.tar.xz \
      && ln -s /opt/blender/blender /usr/local/bin/blender ;; \
    off|"") echo "Blender disabled (BLENDER=off), skipping install" ;; \
    *) echo "Unknown BLENDER '$BLENDER' (expected on or off)" >&2; exit 1 ;; \
  esac

# Optional in-container rendering, so Godot can draw real frames for
# screenshots and videos without a host display (see README "Optional:
# rendering in the container" and `npm run doctor:render`). One switch per
# graphics API, both off by default; RENDER_DEFAULT (runtime) picks which one
# `godot-render` uses. Declared last so toggling keeps earlier layers cached.
# - RENDER_OPENGL=on: Xvfb + Mesa GL (llvmpipe, or the host GPU when
#   RENDER_DEVICE passes /dev/dri in).
# - RENDER_VULKAN=on: Xvfb + Mesa Vulkan (lavapipe, a CPU driver), for the
#   Forward+ and Mobile rendering methods.
# The values are baked into the image env so they always match what is
# installed.
USER root
ARG RENDER_OPENGL=off
ARG RENDER_VULKAN=off
ENV RENDER_OPENGL=${RENDER_OPENGL:-off}
ENV RENDER_VULKAN=${RENDER_VULKAN:-off}
RUN vk=$(echo "$RENDER_VULKAN" | tr '[:upper:]' '[:lower:]') \
  && gl=$(echo "$RENDER_OPENGL" | tr '[:upper:]' '[:lower:]') \
  && case "$vk" in on|off|"") ;; *) echo "Unknown RENDER_VULKAN '$RENDER_VULKAN' (expected on or off)" >&2; exit 1 ;; esac \
  && case "$gl" in on|off|"") ;; *) echo "Unknown RENDER_OPENGL '$RENDER_OPENGL' (expected on or off)" >&2; exit 1 ;; esac \
  && pkgs="" \
  && if [ "$gl" = on ] || [ "$vk" = on ]; then pkgs="xvfb xauth"; fi \
  && if [ "$gl" = on ]; then pkgs="$pkgs libgl1-mesa-dri libgl1 libegl1"; fi \
  && if [ "$vk" = on ]; then pkgs="$pkgs mesa-vulkan-drivers libvulkan1"; fi \
  && if [ -n "$pkgs" ]; then \
       apt-get update && apt-get install -y --no-install-recommends $pkgs \
       && apt-get clean && rm -rf /var/lib/apt/lists/*; \
     else echo "In-container rendering disabled (RENDER_OPENGL=off, RENDER_VULKAN=off), skipping install"; fi
USER node
