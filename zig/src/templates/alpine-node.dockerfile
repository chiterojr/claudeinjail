FROM node:lts-alpine

# Create non-root user
ARG USERNAME=claude
ARG USER_UID=1000
ARG USER_GID=1000

# node:lts-alpine already has a "node" user with uid 1000, remove it first
RUN deluser --remove-home node 2>/dev/null || true \
    && addgroup -g ${USER_GID} ${USERNAME} \
    && adduser -u ${USER_UID} -G ${USERNAME} -s /bin/sh -D ${USERNAME}

# Install system deps (libgcc + libstdc++ + ripgrep required by native installer on Alpine)
RUN apk add --no-cache \
        ca-certificates \
        curl \
        git \
        bash \
        libgcc \
        libstdc++ \
        ripgrep \
        jq \
        zip \
        openssh-client \
        imagemagick \
        iptables \
        github-cli \
        su-exec

# Install Tailscale from official static binaries (Alpine repo is outdated)
RUN ARCH="$(uname -m)" \
    && case "$ARCH" in x86_64) ARCH="amd64";; aarch64) ARCH="arm64";; esac \
    && curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_latest_${ARCH}.tgz" \
       | tar xz -C /tmp \
    && cp /tmp/tailscale_*/tailscale /tmp/tailscale_*/tailscaled /usr/local/bin/ \
    && rm -rf /tmp/tailscale_*

# Install Bun and Claude Code as the non-root user
USER ${USERNAME}
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.bun/bin:${PATH}"
ENV USE_BUILTIN_RIPGREP=0

RUN curl -fsSL https://bun.sh/install | bash
RUN curl -fsSL https://claude.ai/install.sh | bash

# Run as root so su-exec can drop privileges to the claude user.
# The working directory is set at runtime (docker run -w) from the host path.
USER root

CMD ["su-exec", "claude", "claude"]
