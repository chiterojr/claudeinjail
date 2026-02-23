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
        imagemagick

# Install claude-code natively as the non-root user
USER ${USERNAME}
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
ENV USE_BUILTIN_RIPGREP=0

RUN curl -fsSL https://claude.ai/install.sh | bash

# Workspace
USER root
RUN mkdir -p /workspace && chown ${USERNAME}:${USERNAME} /workspace

USER ${USERNAME}
WORKDIR /workspace

CMD ["claude"]
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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install claude-code natively as the non-root user
USER ${USERNAME}
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

RUN curl -fsSL https://claude.ai/install.sh | bash

# Workspace
USER root
RUN mkdir -p /workspace && chown ${USERNAME}:${USERNAME} /workspace

USER ${USERNAME}
WORKDIR /workspace

CMD ["claude"]
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
HELP
}

# ============================================================================
# Utilities
# ============================================================================

sanitize_name() {
  echo "$1" | tr -cd 'a-zA-Z0-9_-'
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
  if [[ "$IMAGE_VARIANT" == "alpine" ]]; then
    generate_dockerfile_alpine > "$dockerfile"
  else
    generate_dockerfile_debian > "$dockerfile"
  fi

  echo ""
  echo "Building image '$IMAGE_NAME'. Docker cache ensures that"
  echo "rebuilds with no changes are instantaneous."
  echo ""
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
COMMAND=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    help|--help|-h)
      show_help
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

CONTAINER_CMD=("claude")
[[ "$SHELL_ONLY" == true ]] && [[ "$IMAGE_VARIANT" == "alpine" ]] && CONTAINER_CMD=("/bin/sh")
[[ "$SHELL_ONLY" == true ]] && [[ "$IMAGE_VARIANT" != "alpine" ]] && CONTAINER_CMD=("/bin/bash")
[[ "$SHELL_ONLY" == true ]] && echo "Starting shell in container ($IMAGE_NAME)..." && echo ""

exec docker run --rm -it \
  --name "claudeinjail" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
  -v "$(pwd)":/workspace \
  -v "$PROFILE_DIR/.claude":/home/claude/.claude \
  -v "$PROFILE_DIR/.claude.json":/home/claude/.claude.json \
  "$IMAGE_NAME" "${CONTAINER_CMD[@]}"
