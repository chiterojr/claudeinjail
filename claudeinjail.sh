#!/usr/bin/env bash
set -e

CONFIG_DIR="$HOME/.config/claudeinjail"
CACHE_DIR="$HOME/.cache/claudeinjail"
DEFAULT_FILE="$CONFIG_DIR/default"
IMAGES_DIR="$CONFIG_DIR/images"
DESC_PREFIX="# claudeinjail-description:"

# Default image
IMAGE_NAME="claudeinjail-alpine"
IMAGE_VARIANT="alpine"

# ============================================================================
# Embedded Dockerfiles
# ============================================================================

generate_dockerfile_alpine() {
  cat <<'DOCKERFILE'
FROM alpine:3

# Create non-root user
ARG USERNAME=claude
ARG USER_UID=1000
ARG USER_GID=1000

RUN addgroup -g ${USER_GID} ${USERNAME} \
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

# Install claude-code natively as the non-root user
USER ${USERNAME}
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
ENV USE_BUILTIN_RIPGREP=0

RUN curl -fsSL https://claude.ai/install.sh | bash

# Workspace
USER root
RUN mkdir -p /workspace && chown ${USERNAME}:${USERNAME} /workspace

WORKDIR /workspace

CMD ["su-exec", "claude", "claude"]
DOCKERFILE
}

generate_dockerfile_debian() {
  cat <<'DOCKERFILE'
FROM debian:12-slim

# Create non-root user
ARG USERNAME=claude
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        tree \
        wget \
        zip \
        unzip \
        openssh-client \
        imagemagick \
        whois \
        ipcalc \
        gosu \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
        | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
        | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update && apt-get install -y --no-install-recommends tailscale \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install claude-code natively as the non-root user
USER ${USERNAME}
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

RUN curl -fsSL https://claude.ai/install.sh | bash

# Workspace
USER root
RUN mkdir -p /workspace && chown ${USERNAME}:${USERNAME} /workspace

WORKDIR /workspace

CMD ["gosu", "claude", "claude"]
DOCKERFILE
}

generate_dockerfile_alpine_node() {
  cat <<'DOCKERFILE'
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

# Workspace
USER root
RUN mkdir -p /workspace && chown ${USERNAME}:${USERNAME} /workspace

WORKDIR /workspace

CMD ["su-exec", "claude", "claude"]
DOCKERFILE
}

generate_dockerfile_debian_node() {
  cat <<'DOCKERFILE'
FROM node:lts-slim

# Create non-root user
ARG USERNAME=claude
ARG USER_UID=1000
ARG USER_GID=1000

# node:lts-slim already has a "node" user with uid 1000, remove it first
RUN userdel -r node 2>/dev/null || true \
    && groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        tree \
        wget \
        zip \
        unzip \
        openssh-client \
        imagemagick \
        whois \
        ipcalc \
        gosu \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
        | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
        | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update && apt-get install -y --no-install-recommends tailscale \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Bun and Claude Code as the non-root user
USER ${USERNAME}
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.bun/bin:${PATH}"

RUN curl -fsSL https://bun.sh/install | bash
RUN curl -fsSL https://claude.ai/install.sh | bash

# Workspace
USER root
RUN mkdir -p /workspace && chown ${USERNAME}:${USERNAME} /workspace

WORKDIR /workspace

CMD ["gosu", "claude", "claude"]
DOCKERFILE
}

# ============================================================================
# Help
# ============================================================================

show_help() {
  cat <<'HELP'
claudeinjail — Claude Code Docker Runner
=========================================

Runs Claude Code inside a Docker container with support for multiple profiles.
Each profile maintains isolated credentials and settings, allowing you to use
different accounts (e.g., personal, work) without conflicts.

USAGE
  claudeinjail [command] [options]

COMMANDS
  (no command)                    Build the image and start the container.
                                  If no profile is specified, the script tries
                                  to load the default profile. If none is set,
                                  it lists available profiles or guides the
                                  creation of the first one.

  profile create <name>           Create a new profile with the given name.
                                  Valid names: letters, numbers, hyphens, and
                                  underscores.

  profile list                    List all existing profiles and indicate
                                  which one is the default (if any).

  profile delete <name>           Delete a profile. The script asks for
                                  confirmation before removing. Also accepts
                                  the --confirm flag to skip the interactive
                                  prompt (still required explicitly as an
                                  extra safety layer).

  profile set-default <name>      Set an existing profile as the default.
                                  The default profile is loaded automatically
                                  when no --profile is specified.

  eject [name]                    Export a Dockerfile based on one of the
                                  built-in bases (Alpine, Debian, Alpine+Node,
                                  Debian+Node) so you can customize it. Each
                                  custom image is stored under:
                                    ~/.config/claudeinjail/images/<name>/Dockerfile
                                  Prompts for name (if omitted), short
                                  description (max 60 chars), and base image.
                                  Custom images appear in the 'claudeinjail -i'
                                  picker alongside the built-in bases.

  help                            Show this message.

OPTIONS
  -w, --wizard                    Interactive mode. Asks everything through
                                  guided prompts (profile, image, context
                                  directories, resume, and Tailscale) so you don't have
                                  to remember the individual flags. Explicit
                                  flags still work and override what the wizard
                                  would ask.

  -c, --context <dir>             Mount an extra host directory read-only inside
                                  the container at /context/<dir-name>. The
                                  directory must exist. Repeatable to mount
                                  several; each must have a unique base name.

  -p, --profile <name>            Use the specified profile when starting
                                  the container. The profile must already exist.

  -i, --select-image              Prompt which image to use. Lists the four
                                  built-in bases (Alpine, Debian, Alpine+Node,
                                  Debian+Node) plus any custom images ejected
                                  via 'claudeinjail eject'. Without this flag,
                                  Alpine is the default.

  -b, --build-only                Only build the Docker image without starting
                                  the container. Useful for preparing the image.

  -r, --resume                    Resume a previous Claude session. Forwards
                                  --resume to Claude, which shows an interactive
                                  picker of past sessions for the current
                                  workspace. Has no effect with --shell.

  -s, --shell                     Open a shell (/bin/bash) in the container
                                  instead of launching Claude. Useful for
                                  inspecting the container, installing tools,
                                  or debugging.

  -t, --tailscale                 Connect the container to your Tailscale
                                  network (tailnet). Authentication is done
                                  via browser on the first run; subsequent
                                  runs reconnect automatically. State is
                                  persisted per profile.

  --exit-node <node>              Route all container traffic through a
                                  Tailscale exit node. Requires --tailscale.
                                  Accepts a Tailscale IP or machine name.
                                  LAN access is allowed automatically.

  --safe                          Run Claude Code with standard permission
                                  prompts. By default, claudeinjail launches
                                  with --dangerously-skip-permissions since
                                  the container provides isolation. Use --safe
                                  to restore normal permission checks.

  -v, --verbose                   Show Tailscale daemon logs in the terminal.
                                  Useful for debugging connection issues.

PROFILES
  Profiles are stored in:
    ~/.config/claudeinjail/<name>/

  Each profile contains:
    .claude/          Settings, OAuth sessions, and agents directory
    .claude.json      State, MCP servers, and tool permissions

  The default profile is saved in:
    ~/.config/claudeinjail/default

ENVIRONMENT VARIABLES
  ANTHROPIC_API_KEY               Anthropic API key (optional, depends on the
                                  authentication method used).

EXAMPLES
  claudeinjail                              Start with default profile and Alpine
  claudeinjail -w                           Interactive wizard (asks everything)
  claudeinjail -c ~/docs -c ../shared-lib   Mount dirs at /context/docs, /context/shared-lib
  claudeinjail -p work                      Start with the "work" profile
  claudeinjail -i                           Prompt which image to use
  claudeinjail -b                           Only build the Alpine image
  claudeinjail -r                           Resume a previous Claude session
  claudeinjail -s                           Open a shell in the container
  claudeinjail -s -p work                   Shell with "work" profile
  claudeinjail -b -i                        Prompt image and build without starting
  claudeinjail profile create personal      Create the "personal" profile
  claudeinjail profile list                 List existing profiles
  claudeinjail profile delete personal      Delete the "personal" profile
  claudeinjail profile set-default work     Set "work" as default
  claudeinjail eject                        Eject a Dockerfile (prompts name)
  claudeinjail eject my-python              Eject directly with the given name
  claudeinjail --safe                        Start with permission prompts enabled
  claudeinjail --tailscale                  Start with Tailscale connected
  claudeinjail -t --exit-node my-server     Tailscale with exit node
HELP
}

# ============================================================================
# Utilities
# ============================================================================

sanitize_name() {
  echo "$1" | tr -cd 'a-zA-Z0-9_-'
}

generate_instance_name() {
  local dir raw
  dir="$(basename "$(pwd)")"
  raw="claudeinjail-${dir}-$$"
  raw="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  echo "${raw:0:63}"
}

generate_entrypoint() {
  local drop_privs="$1"  # "su-exec" or "gosu"

  cat <<'ENTRYPOINT_HEAD'
#!/bin/bash
set -e

if [ "$TAILSCALE_ENABLED" = "true" ]; then
  TS_LOG="/dev/null"
  [ "$TS_VERBOSE" = "true" ] && TS_LOG="/tmp/tailscaled.log"
  echo "Starting Tailscale daemon..."
  tailscaled --state=/var/lib/tailscale/tailscaled.state >"$TS_LOG" 2>&1 &
  TAILSCALED_PID=$!

  # Wait for tailscaled socket (up to 15 seconds)
  for i in $(seq 1 30); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 0.5
  done

  if [ ! -S /var/run/tailscale/tailscaled.sock ]; then
    echo "Error: tailscaled failed to start."
    [ -f "$TS_LOG" ] && cat "$TS_LOG"
    [ "$TS_LOG" = "/dev/null" ] && echo "Retry with --verbose for details."
    exit 1
  fi

  # Build tailscale up args
  TS_ARGS="--accept-routes --authkey=$TS_AUTHKEY --hostname=$TS_HOSTNAME"
  [ -n "$TS_EXIT_NODE" ] && TS_ARGS="$TS_ARGS --exit-node=$TS_EXIT_NODE --exit-node-allow-lan-access"

  echo "Connecting to Tailscale network..."
  tailscale up $TS_ARGS

  if ! tailscale status >/dev/null 2>&1; then
    echo "Error: Tailscale failed to connect."
    [ -f "$TS_LOG" ] && cat "$TS_LOG"
    [ "$TS_LOG" = "/dev/null" ] && echo "Retry with --verbose for details."
    kill $TAILSCALED_PID 2>/dev/null
    exit 1
  fi

  echo "Tailscale connected as $(tailscale ip -4 2>/dev/null || echo 'unknown')."
  echo ""
fi

ENTRYPOINT_HEAD

  echo "exec ${drop_privs} \"\$@\""
}

get_default_profile() {
  [[ -f "$DEFAULT_FILE" ]] && tr -d '[:space:]' < "$DEFAULT_FILE" || true
}

list_profiles() {
  find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d -not -name images -printf '%f\n' 2>/dev/null | sort
}

# ============================================================================
# Custom image helpers
# ============================================================================

validate_image_name() {
  local name="$1"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]{1,}[a-z0-9]$ ]]
}

read_image_description() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local first
  first="$(head -n1 "$file")"
  if [[ "$first" == "$DESC_PREFIX"* ]]; then
    local desc="${first#"$DESC_PREFIX"}"
    echo "${desc## }"
  fi
}

list_custom_images() {
  find "$IMAGES_DIR" -mindepth 2 -maxdepth 2 -name Dockerfile -printf '%h\n' 2>/dev/null \
    | xargs -r -n1 basename | sort
}

detect_image_family() {
  local variant="$1"
  case "$variant" in
    alpine|alpine-node) echo "alpine"; return ;;
    debian|debian-node) echo "debian"; return ;;
  esac
  if [[ "$variant" == custom:* ]]; then
    local cname="${variant#custom:}"
    local from_line
    from_line="$(grep -m1 -iE '^FROM[[:space:]]' "$IMAGES_DIR/$cname/Dockerfile" 2>/dev/null || true)"
    if [[ "$from_line" == *alpine* ]]; then
      echo "alpine"
    else
      echo "debian"
    fi
    return
  fi
  echo "debian"
}

variant_base_label() {
  case "$1" in
    alpine)      echo "Alpine (alpine:3)" ;;
    debian)      echo "Debian (debian:12-slim)" ;;
    alpine-node) echo "Alpine + Node.js + Bun (node:lts-alpine)" ;;
    debian-node) echo "Debian + Node.js + Bun (node:lts-slim)" ;;
    *)           echo "$1" ;;
  esac
}

generate_dockerfile_for_variant() {
  case "$1" in
    alpine)      generate_dockerfile_alpine ;;
    debian)      generate_dockerfile_debian ;;
    alpine-node) generate_dockerfile_alpine_node ;;
    debian-node) generate_dockerfile_debian_node ;;
    *) return 1 ;;
  esac
}

prompt_base_variant() {
  echo "" >&2
  echo "Select the base image." >&2
  echo "Alpine is smaller and lighter; Debian has better compatibility with" >&2
  echo "conventional Linux tools. The Node.js+Bun variants include both JS runtimes." >&2
  echo "" >&2
  echo "  1) Alpine (alpine:3)  [default]" >&2
  echo "  2) Debian (debian:12-slim)" >&2
  echo "  3) Alpine + Node.js + Bun (node:lts-alpine)" >&2
  echo "  4) Debian + Node.js + Bun (node:lts-slim)" >&2
  read -rp "Choose [1/2/3/4]: " choice
  case "$choice" in
    2) echo "debian" ;;
    3) echo "alpine-node" ;;
    4) echo "debian-node" ;;
    *) echo "alpine" ;;
  esac
}

prompt_image_name() {
  local name
  while true; do
    read -rp "Image name (lowercase, digits, hyphens; min 3 chars): " name
    name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    if validate_image_name "$name"; then
      if [[ -f "$IMAGES_DIR/$name/Dockerfile" ]]; then
        echo "An image named '$name' already exists at $IMAGES_DIR/$name/" >&2
        read -rp "Overwrite? [y/N]: " ans
        [[ "$ans" == "y" || "$ans" == "Y" ]] || continue
      fi
      echo "$name"
      return 0
    fi
    echo "Invalid name. Use only [a-z0-9-], no leading/trailing hyphen, min 3 chars." >&2
  done
}

prompt_image_description() {
  local desc
  while true; do
    read -rp "Short description (max 60 chars, may be empty): " desc
    desc="$(echo "$desc" | tr -d '\n\r' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    if [[ ${#desc} -le 60 ]]; then
      echo "$desc"
      return 0
    fi
    echo "Description too long (${#desc} chars). Limit is 60." >&2
  done
}

write_custom_image() {
  local name="$1" variant="$2" desc="$3"
  local dir="$IMAGES_DIR/$name"
  mkdir -p "$dir"
  {
    if [[ -n "$desc" ]]; then
      echo "$DESC_PREFIX $desc"
    else
      echo "$DESC_PREFIX"
    fi
    generate_dockerfile_for_variant "$variant"
  } > "$dir/Dockerfile"
}


# ============================================================================
# Profile commands
# ============================================================================

cmd_profile_create() {
  local name
  name="$(sanitize_name "$1")"

  if [[ -z "$name" ]]; then
    echo "Error: invalid or missing profile name."
    echo "Use only letters, numbers, hyphens, and underscores."
    echo ""
    echo "Usage: claudeinjail profile create <name>"
    exit 1
  fi

  if [[ "$name" == "images" ]]; then
    echo "Error: 'images' is a reserved name (used for custom images)."
    exit 1
  fi

  local profile_dir="$CONFIG_DIR/$name"
  if [[ -d "$profile_dir" ]]; then
    echo "Profile '$name' already exists at $profile_dir"
    exit 1
  fi

  mkdir -p "$profile_dir/.claude"
  echo '{}' > "$profile_dir/.claude.json"

  echo "Profile '$name' created successfully."
  echo "Location: $profile_dir"
  echo ""
  echo "To use it:"
  echo "  claudeinjail -p $name"
  echo ""
  echo "To set it as default:"
  echo "  claudeinjail profile set-default $name"
}

cmd_profile_list() {
  mkdir -p "$CONFIG_DIR"

  local default_name
  default_name="$(get_default_profile)"

  mapfile -t profiles < <(list_profiles)

  if [[ ${#profiles[@]} -eq 0 ]]; then
    echo "No profiles found."
    echo ""
    echo "Create one with: claudeinjail profile create <name>"
    exit 0
  fi

  echo "Existing profiles:"
  echo ""
  for p in "${profiles[@]}"; do
    if [[ "$p" == "$default_name" ]]; then
      echo "  * $p  (default)"
    else
      echo "    $p"
    fi
  done
  echo ""
  echo "Location: $CONFIG_DIR"

  if [[ -z "$default_name" ]]; then
    echo ""
    echo "No default profile set."
    echo "Set one with: claudeinjail profile set-default <name>"
  fi
}

cmd_profile_delete() {
  local name
  name="$(sanitize_name "$1")"
  local confirm_flag="$2"

  if [[ -z "$name" ]]; then
    echo "Error: profile name not provided."
    echo ""
    echo "Usage: claudeinjail profile delete <name>"
    echo ""
    echo "Deletion requires two confirmations to prevent accidental loss:"
    echo "  1) The --confirm flag in the command"
    echo "  2) An interactive confirmation"
    echo ""
    echo "Example: claudeinjail profile delete my-profile --confirm"
    exit 1
  fi

  local profile_dir="$CONFIG_DIR/$name"
  if [[ ! -d "$profile_dir" ]]; then
    echo "Error: profile '$name' not found in $CONFIG_DIR"
    exit 1
  fi

  if [[ "$confirm_flag" != "--confirm" ]]; then
    echo "To delete a profile, pass the --confirm flag as an extra"
    echo "safety layer against accidental deletions."
    echo ""
    echo "Usage: claudeinjail profile delete $name --confirm"
    exit 1
  fi

  echo "You are about to delete the profile '$name'."
  echo "This will permanently remove all credentials and settings"
  echo "stored in: $profile_dir"
  echo ""
  read -rp "Are you sure? Type '$name' to confirm: " answer

  if [[ "$answer" != "$name" ]]; then
    echo "Deletion cancelled. The text entered does not match the profile name."
    exit 0
  fi

  local default_name
  default_name="$(get_default_profile)"
  if [[ "$default_name" == "$name" ]]; then
    rm -f "$DEFAULT_FILE"
    echo "The default profile pointer was removed (it pointed to '$name')."
  fi

  rm -rf "$profile_dir"
  echo "Profile '$name' deleted successfully."
}

cmd_profile_set_default() {
  local name
  name="$(sanitize_name "$1")"

  if [[ -z "$name" ]]; then
    echo "Error: profile name not provided."
    echo ""
    echo "Usage: claudeinjail profile set-default <name>"
    exit 1
  fi

  if [[ ! -d "$CONFIG_DIR/$name" ]]; then
    echo "Error: profile '$name' not found in $CONFIG_DIR"
    echo ""
    echo "Available profiles:"
    list_profiles | sed 's/^/  - /'
    exit 1
  fi

  mkdir -p "$CONFIG_DIR"
  echo "$name" > "$DEFAULT_FILE"
  echo "Default profile set to '$name'."
}

# ============================================================================
# Eject command
# ============================================================================

cmd_eject() {
  local name="$1"

  mkdir -p "$IMAGES_DIR"

  if [[ -n "$name" ]]; then
    name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    if ! validate_image_name "$name"; then
      echo "Error: invalid image name '$name'."
      echo "Use only [a-z0-9-], no leading/trailing hyphen, min 3 chars."
      exit 1
    fi
    if [[ -f "$IMAGES_DIR/$name/Dockerfile" ]]; then
      echo "An image named '$name' already exists at $IMAGES_DIR/$name/"
      read -rp "Overwrite? [y/N]: " ans
      if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
        echo "Eject cancelled."
        exit 0
      fi
    fi
  else
    name="$(prompt_image_name)"
  fi

  local desc
  desc="$(prompt_image_description)"

  local variant
  variant="$(prompt_base_variant)"

  write_custom_image "$name" "$variant" "$desc"

  local dockerfile="$IMAGES_DIR/$name/Dockerfile"
  echo ""
  echo "Image '$name' ejected."
  echo ""
  echo "Dockerfile location:"
  echo "  $dockerfile"
  echo ""
  echo "Base: $(variant_base_label "$variant")"
  [[ -n "$desc" ]] && echo "Description: $desc"
  echo ""
  echo "You can edit this Dockerfile freely — add packages, tools, runtimes, etc."
  echo ""
  echo "IMPORTANT: keep the first line ('$DESC_PREFIX ...') intact."
  echo "It is parsed by 'claudeinjail -i' to show the image description."
  echo "If you remove it, the image still works but loses its description label."
  echo ""
  echo "To use this image on the next run, pick it via:"
  echo "  claudeinjail -i"
  echo ""
  echo "To remove this image, delete its directory:"
  echo "  rm -rf $IMAGES_DIR/$name"
}

# ============================================================================
# Image selection (optional, Alpine is the default)
# ============================================================================

select_image() {
  [[ "$SELECT_IMAGE" == true ]] || return 0

  mapfile -t customs < <(list_custom_images)

  echo ""
  echo "Select the container image."
  echo "Built-in bases ship with Claude Code preinstalled. Custom images are"
  echo "previously ejected Dockerfiles you have customized."
  echo ""
  echo "  1) Alpine (alpine:3)  [default]"
  echo "  2) Debian (debian:12-slim)"
  echo "  3) Alpine + Node.js + Bun (node:lts-alpine)"
  echo "  4) Debian + Node.js + Bun (node:lts-slim)"

  local i=5
  local -a idx_to_name=()
  for name in "${customs[@]}"; do
    local desc
    desc="$(read_image_description "$IMAGES_DIR/$name/Dockerfile")"
    if [[ -n "$desc" ]]; then
      echo "  $i) custom: $name — $desc"
    else
      echo "  $i) custom: $name"
    fi
    idx_to_name+=("$name")
    i=$((i+1))
  done

  local last=$((i-1))
  read -rp "Choose [1-$last]: " choice

  if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 5 && "$choice" -le "$last" ]]; then
    local picked="${idx_to_name[$((choice-5))]}"
    IMAGE_NAME="claudeinjail-custom-$picked"
    IMAGE_VARIANT="custom:$picked"
    return
  fi

  case "$choice" in
    2)
      IMAGE_NAME="claudeinjail-debian"
      IMAGE_VARIANT="debian"
      ;;
    3)
      IMAGE_NAME="claudeinjail-alpine-node"
      IMAGE_VARIANT="alpine-node"
      ;;
    4)
      IMAGE_NAME="claudeinjail-debian-node"
      IMAGE_VARIANT="debian-node"
      ;;
    *)
      IMAGE_NAME="claudeinjail-alpine"
      IMAGE_VARIANT="alpine"
      ;;
  esac
}

# ============================================================================
# Docker build
# ============================================================================

build_image() {
  mkdir -p "$CACHE_DIR"
  local dockerfile="$CACHE_DIR/Dockerfile"

  if [[ "$IMAGE_VARIANT" == custom:* ]]; then
    local cname="${IMAGE_VARIANT#custom:}"
    local src="$IMAGES_DIR/$cname/Dockerfile"
    if [[ ! -f "$src" ]]; then
      echo "Error: custom image '$cname' not found at $src"
      exit 1
    fi
    cp "$src" "$dockerfile"
    echo ""
    echo "Using custom image '$cname' from $src"
    echo "Building image '$IMAGE_NAME'..."
    echo ""
  else
    case "$IMAGE_VARIANT" in
      alpine)      generate_dockerfile_alpine > "$dockerfile" ;;
      alpine-node) generate_dockerfile_alpine_node > "$dockerfile" ;;
      debian-node) generate_dockerfile_debian_node > "$dockerfile" ;;
      debian)      generate_dockerfile_debian > "$dockerfile" ;;
      *)           generate_dockerfile_alpine > "$dockerfile" ;;
    esac
    echo ""
    echo "Building image '$IMAGE_NAME'. Docker cache ensures that"
    echo "rebuilds with no changes are instantaneous."
    echo ""
  fi

  docker build -t "$IMAGE_NAME" -f "$dockerfile" "$CACHE_DIR"
}

# ============================================================================
# Automatic profile resolution (interactive mode)
# ============================================================================

resolve_profile() {
  [[ -n "$PROFILE" ]] && return 0

  mkdir -p "$CONFIG_DIR"

  if [[ -f "$DEFAULT_FILE" ]]; then
    PROFILE="$(tr -d '[:space:]' < "$DEFAULT_FILE")"

    if [[ -d "$CONFIG_DIR/$PROFILE" ]]; then
      echo "Default profile found: '$PROFILE'"
      echo "To use a different profile, pass the --profile <name> flag."
      return
    fi

    echo "The default profile '$PROFILE' is configured in $DEFAULT_FILE"
    echo "but the corresponding directory was not found in $CONFIG_DIR"
    echo ""
    read -rp "Do you want to remove this pointer? [y/N]: " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] && rm -f "$DEFAULT_FILE"
    PROFILE=""
    echo ""
  fi

  mapfile -t profiles < <(list_profiles)

  if [[ ${#profiles[@]} -eq 0 ]]; then
    echo ""
    echo "No profiles found in $CONFIG_DIR"
    echo ""
    echo "Profiles let you use different Claude accounts (e.g., personal, work)."
    echo "Each profile keeps its own credentials and settings fully isolated."
    echo ""
    read -rp "Name for the first profile to create: " PROFILE
    PROFILE="$(sanitize_name "$PROFILE")"
    return
  fi

  echo ""
  echo "No default profile set in $DEFAULT_FILE"
  echo ""
  echo "Profiles let you use different Claude accounts (e.g., personal, work)."
  echo "Select an existing profile or create a new one:"
  echo ""
  for i in "${!profiles[@]}"; do
    echo "  $((i+1))) ${profiles[$i]}"
  done
  echo "  n) Create new profile"
  echo ""
  read -rp "Choose: " pchoice

  if [[ "$pchoice" == "n" || "$pchoice" == "N" ]]; then
    echo ""
    echo "The profile name will be used as a directory in $CONFIG_DIR"
    echo "Use only letters, numbers, hyphens, and underscores."
    echo ""
    read -rp "New profile name: " PROFILE
    PROFILE="$(sanitize_name "$PROFILE")"
    return
  fi

  if [[ "$pchoice" =~ ^[0-9]+$ ]] && \
     [[ "$pchoice" -ge 1 ]] && \
     [[ "$pchoice" -le "${#profiles[@]}" ]]; then
    PROFILE="${profiles[$((pchoice-1))]}"
    return
  fi

  echo "Invalid option."
  exit 1
}

# ============================================================================
# --profile validation
# ============================================================================

validate_profile() {
  [[ -z "$PROFILE" ]] && return 0

  PROFILE="$(sanitize_name "$PROFILE")"
  if [[ -z "$PROFILE" ]]; then
    echo "Error: invalid profile name. Use only letters, numbers, hyphens, and underscores."
    exit 1
  fi

  if [[ ! -d "$CONFIG_DIR/$PROFILE" ]]; then
    echo "Error: profile '$PROFILE' not found in $CONFIG_DIR"
    echo ""
    echo "Available profiles:"
    list_profiles | sed 's/^/  - /' || echo "  (none)"
    echo ""
    echo "Create one with: claudeinjail profile create $PROFILE"
    exit 1
  fi
}

# ============================================================================
# Context directories (mounted read-only at /context/<name>)
# ============================================================================
#
# Shared validation used by both the -c/--context flags and the wizard.
# Resolves the path to an absolute directory, checks it exists, and rejects
# /context/<name> collisions. On success appends to CONTEXT_PATHS/CONTEXT_NAMES.

add_context_dir() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo "Error: empty context directory path." >&2
    return 1
  fi

  # Expand a leading ~ (the shell already does this for flags, not for reads).
  input="${input/#\~/$HOME}"

  local abs
  abs="$(cd "$input" 2>/dev/null && pwd)" || {
    echo "Error: context directory not found (or not a directory): $input" >&2
    return 1
  }

  local name
  name="$(basename "$abs")"
  if [[ -z "$name" || "$name" == "/" ]]; then
    echo "Error: cannot derive a /context name from: $abs" >&2
    return 1
  fi

  local existing
  for existing in "${CONTEXT_NAMES[@]}"; do
    if [[ "$existing" == "$name" ]]; then
      echo "Error: '/context/$name' is already mapped — directory names must be unique." >&2
      return 1
    fi
  done

  CONTEXT_PATHS+=("$abs")
  CONTEXT_NAMES+=("$name")
  return 0
}

# ============================================================================
# Wizard (interactive mode: -w / --wizard)
# ============================================================================
#
# A single flag that asks everything interactively, so you don't have to
# remember the individual flags. To add a new question, write a wizard_*
# helper that sets the relevant state variable and add a line for it to the
# ordered list in run_wizard() below.

wizard_create_profile() {
  local name
  while true; do
    read -rp "New profile name: " name
    name="$(sanitize_name "$name")"
    if [[ -z "$name" ]]; then
      echo "Invalid name. Use only letters, numbers, hyphens, and underscores." >&2
      continue
    fi
    if [[ "$name" == "images" ]]; then
      echo "'images' is a reserved name (used for custom images)." >&2
      continue
    fi
    break
  done

  if [[ ! -d "$CONFIG_DIR/$name" ]]; then
    mkdir -p "$CONFIG_DIR/$name/.claude"
    echo '{}' > "$CONFIG_DIR/$name/.claude.json"
    echo "Profile '$name' created."
  fi
  PROFILE="$name"
}

wizard_pick_profile() {
  # Respect an explicit -p/--profile.
  [[ -n "$PROFILE" ]] && return 0

  mkdir -p "$CONFIG_DIR"
  local default_name
  default_name="$(get_default_profile)"
  local -a profiles=()
  mapfile -t profiles < <(list_profiles)

  echo ""
  echo "Profile — which account/credentials to use."
  echo ""

  if [[ ${#profiles[@]} -eq 0 ]]; then
    echo "No profiles found — let's create your first one."
    wizard_create_profile
    return
  fi

  while true; do
    local i
    for i in "${!profiles[@]}"; do
      if [[ "${profiles[$i]}" == "$default_name" ]]; then
        echo "  $((i+1))) ${profiles[$i]}  (default)"
      else
        echo "  $((i+1))) ${profiles[$i]}"
      fi
    done
    echo "  n) Create new profile"
    read -rp "Choose [${default_name:-1}]: " choice

    if [[ -z "$choice" ]]; then
      if [[ -n "$default_name" ]]; then PROFILE="$default_name"; else PROFILE="${profiles[0]}"; fi
      return
    fi
    if [[ "$choice" == "n" || "$choice" == "N" ]]; then
      wizard_create_profile
      return
    fi
    if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#profiles[@]}" ]]; then
      PROFILE="${profiles[$((choice-1))]}"
      return
    fi
    echo "Invalid option, try again." >&2
    echo ""
  done
}

wizard_pick_context() {
  echo ""
  echo "Context directories — mounted read-only at /context/<name>."
  echo "Expose extra host directories to Claude. Press Enter (empty) to finish."
  echo ""
  while true; do
    read -rp "Context directory (empty to finish): " dir
    [[ -z "$dir" ]] && break
    if add_context_dir "$dir"; then
      echo "  mapped /context/${CONTEXT_NAMES[-1]}  <-  ${CONTEXT_PATHS[-1]}"
    fi
  done
}

wizard_pick_resume() {
  # Respect an explicit -r/--resume.
  [[ "$RESUME" == true ]] && return 0

  echo ""
  read -rp "Resume a previous Claude session? [y/N]: " ans
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    RESUME=true
  fi
}

wizard_pick_tailscale() {
  # Respect an explicit -t/--tailscale.
  [[ "$TAILSCALE" == true ]] && return 0

  echo ""
  read -rp "Connect to Tailscale? [y/N]: " ans
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    TAILSCALE=true
    read -rp "Exit node (machine name or IP; empty for none): " node
    node="$(echo "$node" | tr -d '[:space:]')"
    [[ -n "$node" ]] && EXIT_NODE="$node"
  fi
}

run_wizard() {
  echo ""
  echo "claudeinjail wizard"
  echo "Answer the prompts below. Press Enter to accept the default."

  # Ordered list of wizard steps. Add new questions here.
  wizard_pick_profile
  SELECT_IMAGE=true
  select_image          # reuses the standard image picker
  SELECT_IMAGE=false
  wizard_pick_context
  wizard_pick_resume
  wizard_pick_tailscale
}

# ============================================================================
# Main
# ============================================================================

# State variables
BUILD_ONLY=false
PROFILE=""
SELECT_IMAGE=false
SHELL_ONLY=false
SAFE_MODE=false
RESUME=false
TAILSCALE=false
EXIT_NODE=""
VERBOSE=false
WIZARD=false
CONTEXT_PATHS=()
CONTEXT_NAMES=()
COMMAND=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    help|--help|-h)
      show_help
      exit 0
      ;;
    eject)
      cmd_eject "${2:-}"
      exit 0
      ;;
    profile)
      COMMAND="profile"
      SUBCOMMAND="${2:-}"
      SUBARG="${3:-}"
      SUBARG2="${4:-}"
      break
      ;;
    list|ls)
      COMMAND="profile"
      SUBCOMMAND="list"
      break
      ;;
    --build-only|-b)
      BUILD_ONLY=true
      ;;
    --profile|-p)
      PROFILE="$2"
      shift
      ;;
    --select-image|-i)
      SELECT_IMAGE=true
      ;;
    --wizard|-w)
      WIZARD=true
      ;;
    --context|-c)
      add_context_dir "$2" || exit 1
      shift
      ;;
    --context=*)
      add_context_dir "${1#--context=}" || exit 1
      ;;
    --safe)
      SAFE_MODE=true
      ;;
    --resume|-r)
      RESUME=true
      ;;
    --shell|-s)
      SHELL_ONLY=true
      ;;
    --tailscale|-t)
      TAILSCALE=true
      ;;
    --exit-node)
      EXIT_NODE="$2"
      shift
      ;;
    --exit-node=*)
      EXIT_NODE="${1#--exit-node=}"
      ;;
    --verbose|-v)
      VERBOSE=true
      ;;
  esac
  shift
done

# Dispatch profile command
if [[ "$COMMAND" == "profile" ]]; then
  case "$SUBCOMMAND" in
    create)   cmd_profile_create "$SUBARG" ;;
    list|ls)  cmd_profile_list ;;
    delete|rm) cmd_profile_delete "$SUBARG" "$SUBARG2" ;;
    set-default) cmd_profile_set_default "$SUBARG" ;;
    *)
      echo "Unknown profile command: '$SUBCOMMAND'"
      echo ""
      echo "Available commands:"
      echo "  profile create <name>"
      echo "  profile list"
      echo "  profile delete <name> --confirm"
      echo "  profile set-default <name>"
      exit 1
      ;;
  esac
  exit 0
fi

# Wizard mode: ask everything interactively (profile, image, Tailscale)
if [[ "$WIZARD" == true ]]; then
  run_wizard
fi

# Validate --exit-node requires --tailscale
if [[ -n "$EXIT_NODE" && "$TAILSCALE" != true ]]; then
  echo "Error: --exit-node requires --tailscale."
  echo ""
  echo "Usage: claudeinjail --tailscale --exit-node=<node>"
  exit 1
fi

# Normal flow: build + run
validate_profile
select_image
build_image

if $BUILD_ONLY; then
  echo ""
  echo "Build complete."
  exit 0
fi

resolve_profile

if [[ -z "$PROFILE" ]]; then
  echo "Error: empty profile name."
  exit 1
fi

PROFILE_DIR="$CONFIG_DIR/$PROFILE"
mkdir -p "$PROFILE_DIR/.claude"
[[ -f "$PROFILE_DIR/.claude.json" ]] || echo '{}' > "$PROFILE_DIR/.claude.json"

echo ""
echo "Profile:     $PROFILE"
echo "Configs at:  $PROFILE_DIR"
if [[ ${#CONTEXT_PATHS[@]} -gt 0 ]]; then
  echo "Context:"
  for idx in "${!CONTEXT_PATHS[@]}"; do
    echo "  /context/${CONTEXT_NAMES[$idx]}  <-  ${CONTEXT_PATHS[$idx]}  (ro)"
  done
fi
echo ""

# Generate temporary gitconfig with resolved values from the current directory
GITCONFIG_TMP=""
if command -v git >/dev/null 2>&1; then
  git_name="$(git config user.name 2>/dev/null || true)"
  git_email="$(git config user.email 2>/dev/null || true)"

  if [[ -n "$git_name" || -n "$git_email" ]]; then
    GITCONFIG_TMP="/tmp/$(generate_instance_name)-gitconfig"
    trap 'rm -f "$GITCONFIG_TMP"' EXIT
    {
      echo "[user]"
      [[ -n "$git_name" ]]  && echo "    name = $git_name"
      [[ -n "$git_email" ]] && echo "    email = $git_email"
    } > "$GITCONFIG_TMP"
  fi
fi

# Build docker run arguments
DOCKER_ARGS=(
  --rm -it
  --name "$(generate_instance_name)"
  -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
  -v "$(pwd)":/workspace
  -v "$PROFILE_DIR/.claude":/home/claude/.claude
  -v "$PROFILE_DIR/.claude.json":/home/claude/.claude.json
)

# Mount git config (resolved from host) and SSH keys
[[ -n "$GITCONFIG_TMP" ]] && DOCKER_ARGS+=(-v "$GITCONFIG_TMP":/home/claude/.gitconfig:ro)
[[ -d "$HOME/.ssh" ]] && DOCKER_ARGS+=(-v "$HOME/.ssh":/home/claude/.ssh:ro)

# Mount extra context directories read-only at /context/<name>
for idx in "${!CONTEXT_PATHS[@]}"; do
  DOCKER_ARGS+=(-v "${CONTEXT_PATHS[$idx]}":"/context/${CONTEXT_NAMES[$idx]}":ro)
done

# Tailscale support
if [[ "$TAILSCALE" == true ]]; then
  mkdir -p "$PROFILE_DIR/tailscale"

  # Read or prompt for auth key
  TS_AUTHKEY_FILE="$PROFILE_DIR/tailscale/authkey"
  if [[ -f "$TS_AUTHKEY_FILE" ]]; then
    TS_AUTHKEY="$(tr -d '[:space:]' < "$TS_AUTHKEY_FILE")"
  fi

  if [[ -z "$TS_AUTHKEY" ]]; then
    echo ""
    echo "No Tailscale auth key found for profile '$PROFILE'."
    echo ""
    echo "Generate a reusable auth key at:"
    echo "  https://login.tailscale.com/admin/settings/keys"
    echo ""
    echo "Recommended settings:"
    echo "  - Reusable: yes"
    echo "  - Ephemeral: yes"
    echo ""
    read -rp "Paste your auth key: " TS_AUTHKEY
    TS_AUTHKEY="$(echo "$TS_AUTHKEY" | tr -d '[:space:]')"

    if [[ -z "$TS_AUTHKEY" ]]; then
      echo "Error: auth key cannot be empty."
      exit 1
    fi

    echo "$TS_AUTHKEY" > "$TS_AUTHKEY_FILE"
    chmod 600 "$TS_AUTHKEY_FILE"
    echo "Auth key saved to $TS_AUTHKEY_FILE"
    echo ""
  fi

  # Generate entrypoint
  mkdir -p "$CACHE_DIR"
  local_drop_privs="gosu claude"
  [[ "$(detect_image_family "$IMAGE_VARIANT")" == "alpine" ]] && local_drop_privs="su-exec claude"

  generate_entrypoint "$local_drop_privs" > "$CACHE_DIR/entrypoint.sh"
  chmod +x "$CACHE_DIR/entrypoint.sh"

  DOCKER_ARGS+=(
    --cap-add=NET_ADMIN
    --cap-add=NET_RAW
    --device=/dev/net/tun:/dev/net/tun
    -v "$CACHE_DIR/entrypoint.sh":/entrypoint.sh:ro
    -e TAILSCALE_ENABLED=true
    -e "TS_AUTHKEY=$TS_AUTHKEY"
    -e "TS_HOSTNAME=$(generate_instance_name)"
    --entrypoint /entrypoint.sh
  )

  [[ -n "$EXIT_NODE" ]] && DOCKER_ARGS+=(-e "TS_EXIT_NODE=$EXIT_NODE")
  [[ "$VERBOSE" == true ]] && DOCKER_ARGS+=(-e "TS_VERBOSE=true")

  echo "Tailscale:   enabled"
  echo "Hostname:    $(generate_instance_name)"
  [[ -n "$EXIT_NODE" ]] && echo "Exit node:   $EXIT_NODE"
  echo ""
fi

# Determine privilege-dropping command based on image family
if [[ "$(detect_image_family "$IMAGE_VARIANT")" == "alpine" ]]; then
  DROP_PRIVS="su-exec"
else
  DROP_PRIVS="gosu"
fi

# Flags forwarded to the Claude CLI inside the container
CLAUDE_FLAGS=()
[[ "$SAFE_MODE" != true ]] && CLAUDE_FLAGS+=("--dangerously-skip-permissions")
[[ "$RESUME" == true ]] && CLAUDE_FLAGS+=("--resume")

# Determine command
CONTAINER_CMD=()
if [[ "$SHELL_ONLY" == true ]]; then
  CONTAINER_CMD=("/bin/bash")
  echo "Starting shell in container ($IMAGE_NAME)..."
  echo ""
elif [[ "$TAILSCALE" == true ]]; then
  # Tailscale entrypoint handles drop_privs; pass the full target command.
  CONTAINER_CMD=("claude" "${CLAUDE_FLAGS[@]}")
else
  CONTAINER_CMD=("$DROP_PRIVS" "claude" "claude" "${CLAUDE_FLAGS[@]}")
fi

exec docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "${CONTAINER_CMD[@]}"
