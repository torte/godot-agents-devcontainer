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

# Install Python libraries for asset generation
RUN pip3 install --break-system-packages Pillow numpy trimesh

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
RUN mkdir -p /workspace /home/node/.claude /home/node/.config/opencode && \
  chown -R node:node /workspace /home/node/.claude /home/node/.config/opencode

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install Godot headless CLI
ARG GODOT_VERSION=4.6.1
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip && \
  unzip -q /tmp/godot.zip -d /tmp/godot && \
  mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot && \
  chmod +x /usr/local/bin/godot && \
  rm -rf /tmp/godot.zip /tmp/godot

# Install Claude Code via native installer and make available system-wide
RUN curl -fsSL https://claude.ai/install.sh | bash \
  && cp /root/.local/bin/claude /usr/local/bin/claude

# Copy startup script
COPY --chown=node:node poststart.sh /home/node/.devcontainer/poststart.sh
RUN chmod +x /home/node/.devcontainer/poststart.sh

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

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

# Install AI coding agents, Godot MCP servers, and 3D asset tools
RUN npm install -g \
  opencode-ai \
  @satelliteoflove/godot-mcp \
  @ryanmazzolini/minimal-godot-mcp \
  @gltf-transform/cli \
  obj2gltf \
  fbx2gltf
