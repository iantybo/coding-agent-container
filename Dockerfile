FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=1000

ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    bash \
    bat \
    build-essential \
    ca-certificates \
    curl \
    dnsutils \
    fd-find \
    gh \
    git \
    git-lfs \
    gnupg \
    jq \
    less \
    make \
    man-db \
    nano \
    openssh-client \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    shellcheck \
    sudo \
    tini \
    tmux \
    tree \
    unzip \
    vim \
    wget \
    xz-utils \
    zip \
    zsh \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && git lfs install --system \
 && ln -sf /usr/bin/batcat /usr/local/bin/bat \
 && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

RUN group_name="$(getent group "${USER_GID}" | cut -d: -f1 || true)" \
 && if [ -z "$group_name" ]; then groupadd --gid "${USER_GID}" "${USERNAME}"; group_name="${USERNAME}"; fi \
 && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
 && mkdir -p /workspace \
 && chown -R "${USERNAME}:${group_name}" /workspace "/home/${USERNAME}"

RUN npm install -g \
    @anthropic-ai/claude-code \
    @github/copilot \
    @openai/codex

RUN temp_home="$(mktemp -d)" \
 && HOME="$temp_home" /bin/sh -c 'curl -fsSL https://cli.coderabbit.ai/install.sh | sh' \
 && coderabbit_bin="$(find "$temp_home" /root/.local/bin -type f -name coderabbit 2>/dev/null | head -n 1)" \
 && cr_bin="$(find "$temp_home" /root/.local/bin -type f -name cr 2>/dev/null | head -n 1)" \
 && test -n "$coderabbit_bin" \
 && install -m 0755 "$coderabbit_bin" /usr/local/bin/coderabbit \
 && if [ -n "$cr_bin" ]; then install -m 0755 "$cr_bin" /usr/local/bin/cr; else ln -sf /usr/local/bin/coderabbit /usr/local/bin/cr; fi \
 && rm -rf "$temp_home"

COPY scripts/entrypoint.sh /usr/local/bin/agentic-entrypoint
COPY scripts/claude-yolo /usr/local/bin/claude-yolo
COPY scripts/codex-yolo /usr/local/bin/codex-yolo
COPY scripts/copilot-yolo /usr/local/bin/copilot-yolo
COPY scripts/coderabbit-review /usr/local/bin/coderabbit-review
COPY WORKSPACE_CLAUDE.md /etc/agentic/CLAUDE.md

RUN chmod 0755 \
    /usr/local/bin/agentic-entrypoint \
    /usr/local/bin/claude-yolo \
    /usr/local/bin/codex-yolo \
    /usr/local/bin/copilot-yolo \
    /usr/local/bin/coderabbit-review

USER ${USERNAME}
WORKDIR /workspace

ENV HOME=/home/${USERNAME} \
    SHELL=/bin/bash \
    WORKSPACE=/workspace

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/agentic-entrypoint"]
CMD ["bash"]
