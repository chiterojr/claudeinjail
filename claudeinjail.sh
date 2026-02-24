#!/usr/bin/env bash
set -e

CONFIG_DIR="$HOME/.config/claudeinjail"
CACHE_DIR="$HOME/.cache/claudeinjail"
DEFAULT_FILE="$CONFIG_DIR/default"

# Default image
IMAGE_NAME="claudeinjail-alpine"
IMAGE_VARIANT="alpine"

# ============================================================================
# Embedded Dockerfiles
# ============================================================================

generate_dockerfile_alpine() {
  cat <<'DOCKERFILE'
FROM alpine:3.21

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
FROM debian:bookworm-slim

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

  eject                           Export the embedded Dockerfile to
                                  ~/.config/claudeinjail/Dockerfile so you can
                                  customize it. Prompts which base image to use
                                  (Alpine or Debian). Once ejected, builds will
                                  use your custom Dockerfile automatically.

  help                            Show this message.

OPTIONS
  -p, --profile <name>            Use the specified profile when starting
                                  the container. The profile must already exist.

  -i, --select-image              Prompt which base image to use (Alpine or
                                  Debian). Without this flag, Alpine is the
                                  default.

  -b, --build-only                Only build the Docker image without starting
                                  the container. Useful for preparing the image.

  -s, --shell                     Open a shell in the container instead of
                                  launching Claude. Alpine uses /bin/sh,
                                  Debian uses /bin/bash. Useful for inspecting
                                  the container, installing tools, or debugging.

  -t, --tailscale                 Connect the container to your Tailscale
                                  network (tailnet). Authentication is done
                                  via browser on the first run; subsequent
                                  runs reconnect automatically. State is
                                  persisted per profile.

  --exit-node <node>              Route all container traffic through a
                                  Tailscale exit node. Requires --tailscale.
                                  Accepts a Tailscale IP or machine name.
                                  LAN access is allowed automatically.

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
  claudeinjail -p work                      Start with the "work" profile
  claudeinjail -i                           Prompt which image to use
  claudeinjail -b                           Only build the Alpine image
  claudeinjail -s                           Open a shell in the container
  claudeinjail -s -p work                   Shell with "work" profile
  claudeinjail -b -i                        Prompt image and build without starting
  claudeinjail profile create personal      Create the "personal" profile
  claudeinjail profile list                 List existing profiles
  claudeinjail profile delete personal      Delete the "personal" profile
  claudeinjail profile set-default work     Set "work" as default
  claudeinjail eject                        Export Dockerfile for customization
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

generate_ts_hostname() {
  local dir rand raw
  dir="$(basename "$(pwd)")"
  rand="$(( RANDOM % 900 + 100 ))"
  raw="claudeinjail-${dir}-${rand}"
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
  [ "$TS_VERBOSE" = "true" ] && TS_LOG="/var/lib/tailscale/tailscaled.log"
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
  TS_ARGS="--accept-routes --ephemeral --hostname=$TS_HOSTNAME"
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

  echo "exec ${drop_privs} claude \"\$@\""
}

get_default_profile() {
  [[ -f "$DEFAULT_FILE" ]] && tr -d '[:space:]' < "$DEFAULT_FILE" || true
}

list_profiles() {
  find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
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
  local dest="$CONFIG_DIR/Dockerfile"

  echo ""
  echo "Select the base image to eject."
  echo "Alpine is smaller and lighter; Debian has better compatibility with conventional Linux tools."
  echo ""
  echo "  1) Alpine (alpine:3.21)  [default]"
  echo "  2) Debian (debian:bookworm-slim)"
  read -rp "Choose [1/2]: " choice

  if [[ -f "$dest" ]]; then
    echo ""
    echo "A custom Dockerfile already exists at $dest"
    read -rp "Overwrite? [y/N]: " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
      echo "Eject cancelled."
      exit 0
    fi
  fi

  mkdir -p "$CONFIG_DIR"

  case "$choice" in
    2) generate_dockerfile_debian > "$dest" ;;
    *) generate_dockerfile_alpine > "$dest" ;;
  esac

  echo ""
  echo "Dockerfile ejected to: $dest"
  echo ""
  echo "Edit it to customize your image (add packages, tools, runtimes, etc.)."
  echo "It will be used automatically on the next build."
  echo ""
  echo "To revert to the embedded Dockerfile, simply delete it:"
  echo "  rm $dest"
}

# ============================================================================
# Image selection (optional, Alpine is the default)
# ============================================================================

select_image() {
  [[ "$SELECT_IMAGE" == true ]] || return 0

  echo ""
  echo "Select the container base image."
  echo "Alpine is smaller and lighter; Debian has better compatibility with conventional Linux tools."
  echo ""
  echo "  1) Alpine (alpine:3.21)  [default]"
  echo "  2) Debian (debian:bookworm-slim)"
  read -rp "Choose [1/2]: " choice

  case "$choice" in
    2)
      IMAGE_NAME="claudeinjail-debian"
      IMAGE_VARIANT="debian"
      ;;
  esac
}

# ============================================================================
# Docker build
# ============================================================================

build_image() {
  mkdir -p "$CACHE_DIR"

  local dockerfile="$CACHE_DIR/Dockerfile"
  local custom_dockerfile="$CONFIG_DIR/Dockerfile"

  if [[ -f "$custom_dockerfile" ]]; then
    IMAGE_NAME="claudeinjail-custom"
    cp "$custom_dockerfile" "$dockerfile"
    echo ""
    echo "Using custom Dockerfile from $custom_dockerfile"
    echo "Building image '$IMAGE_NAME'..."
    echo ""
  else
    if [[ "$IMAGE_VARIANT" == "alpine" ]]; then
      generate_dockerfile_alpine > "$dockerfile"
    else
      generate_dockerfile_debian > "$dockerfile"
    fi
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
# Main
# ============================================================================

# State variables
BUILD_ONLY=false
PROFILE=""
SELECT_IMAGE=false
SHELL_ONLY=false
TAILSCALE=false
EXIT_NODE=""
VERBOSE=false
COMMAND=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    help|--help|-h)
      show_help
      exit 0
      ;;
    eject)
      cmd_eject
      exit 0
      ;;
    profile)
      COMMAND="profile"
      SUBCOMMAND="${2:-}"
      SUBARG="${3:-}"
      SUBARG2="${4:-}"
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
echo ""

# Build docker run arguments
DOCKER_ARGS=(
  --rm -it
  --name "claudeinjail"
  -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
  -v "$(pwd)":/workspace
  -v "$PROFILE_DIR/.claude":/home/claude/.claude
  -v "$PROFILE_DIR/.claude.json":/home/claude/.claude.json
)

# Tailscale support
if [[ "$TAILSCALE" == true ]]; then
  mkdir -p "$PROFILE_DIR/tailscale"

  # Generate entrypoint
  mkdir -p "$CACHE_DIR"
  local_drop_privs="su-exec claude"
  [[ "$IMAGE_VARIANT" != "alpine" ]] && local_drop_privs="gosu claude"

  generate_entrypoint "$local_drop_privs" > "$CACHE_DIR/entrypoint.sh"
  chmod +x "$CACHE_DIR/entrypoint.sh"

  DOCKER_ARGS+=(
    --cap-add=NET_ADMIN
    --cap-add=NET_RAW
    --device=/dev/net/tun:/dev/net/tun
    -v "$PROFILE_DIR/tailscale":/var/lib/tailscale
    -v "$CACHE_DIR/entrypoint.sh":/entrypoint.sh:ro
    -e TAILSCALE_ENABLED=true
    -e "TS_HOSTNAME=$(generate_ts_hostname)"
    --entrypoint /entrypoint.sh
  )

  [[ -n "$EXIT_NODE" ]] && DOCKER_ARGS+=(-e "TS_EXIT_NODE=$EXIT_NODE")
  [[ "$VERBOSE" == true ]] && DOCKER_ARGS+=(-e "TS_VERBOSE=true")

  echo "Tailscale:   enabled"
  echo "Hostname:    $(generate_ts_hostname)"
  [[ -n "$EXIT_NODE" ]] && echo "Exit node:   $EXIT_NODE"
  echo ""
fi

# Determine command
CONTAINER_CMD=()
if [[ "$SHELL_ONLY" == true ]]; then
  if [[ "$IMAGE_VARIANT" == "alpine" ]]; then
    CONTAINER_CMD=("/bin/sh")
  else
    CONTAINER_CMD=("/bin/bash")
  fi
  echo "Starting shell in container ($IMAGE_NAME)..."
  echo ""
fi

exec docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "${CONTAINER_CMD[@]}"
