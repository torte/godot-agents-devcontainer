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
COPY --chown=node:node addons /home/node/.devcontainer/addons
COPY --chown=node:node render-doctor /home/node/.devcontainer/render-doctor
RUN chmod +x /home/node/.devcontainer/poststart.sh /home/node/.devcontainer/opencode-launch.sh

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/home/node/.local/bin:/home/node/.opencode/bin:$PATH:/usr/local/share/npm-global/bin

# Install Claude Code and opencode as the node user so their native
# self-updaters can write to $HOME and keep the binaries current.
RUN curl -fsSL https://claude.ai/install.sh | bash \
  && curl -fsSL https://opencode.ai/install | bash

# Headroom: local compression proxy wrapping Claude Code and OpenCode (see
# opencode-launch.sh and package.json's claude* scripts). Beacon (anonymous
# usage reporting) is disabled — no telemetry leaves the container.
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
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
  && uv tool install --python 3.13 "headroom-ai[proxy,code]>=0.36.0" \
  && uv tool run --from "headroom-ai[proxy,code]" python3 -c \
    "from headroom.transforms.kompress_compressor import KompressCompressor; KompressCompressor().compress('warm the model cache. ' * 500)"

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

# Extended variant: rendering under Xvfb with Mesa (llvmpipe, or the host GPU
# when RENDER_DEVICE passes /dev/dri in). Lets Godot draw real frames for
# screenshots and videos without a host display. See `npm run doctor:render`.
# Last, so switching variants reuses every layer above from cache.
USER root
ARG VARIANT=basic
ENV DEVCONTAINER_VARIANT=$VARIANT
RUN if [ "$VARIANT" = "extended" ]; then \
    apt-get update && apt-get install -y --no-install-recommends \
      xvfb \
      xauth \
      libgl1-mesa-dri \
      libgl1 \
      libegl1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*; \
  elif [ "$VARIANT" != "basic" ]; then \
    echo "Unknown VARIANT '$VARIANT' (expected basic or extended)" >&2; exit 1; \
  fi
USER node
