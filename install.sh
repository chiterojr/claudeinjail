#!/usr/bin/env bash
set -e

REPO="chiterojr/claudeinjail"
BRANCH="main"
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="claudeinjail"
SOURCE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/claudeinjail.sh"
LOCAL=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --local) LOCAL=true ;;
  esac
done

echo ""
echo "claudeinjail installer"
echo "======================"
echo ""

# ── Check dependencies ──────────────────────────────────────────────────────

check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if ! check_cmd docker; then
  echo "Error: docker is required but not found."
  echo "Install it from https://docs.docker.com/get-docker/"
  exit 1
fi

# ── Resolve SHA256 command ──────────────────────────────────────────────────

if check_cmd sha256sum; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif check_cmd shasum; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  echo "Warning: sha256sum/shasum not found, skipping checksum comparison."
  sha256() { echo "unavailable"; }
fi

# ── Fetch source to a temp file ─────────────────────────────────────────────

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

if [[ "$LOCAL" == true ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  LOCAL_SOURCE="$SCRIPT_DIR/claudeinjail.sh"

  if [[ ! -f "$LOCAL_SOURCE" ]]; then
    echo "Error: claudeinjail.sh not found in $SCRIPT_DIR"
    exit 1
  fi

  echo "Source: $LOCAL_SOURCE (local)"
  cp "$LOCAL_SOURCE" "$TMPFILE"
else
  if ! check_cmd curl && ! check_cmd wget; then
    echo "Error: curl or wget is required but neither was found."
    exit 1
  fi

  echo "Source: $SOURCE_URL"

  if check_cmd curl; then
    curl -fsSL "$SOURCE_URL" -o "$TMPFILE"
  else
    wget -qO "$TMPFILE" "$SOURCE_URL"
  fi
fi

# ── Compare checksums ───────────────────────────────────────────────────────

INSTALLED="$INSTALL_DIR/$SCRIPT_NAME"
NEW_SHA="$(sha256 "$TMPFILE")"

if [[ -f "$INSTALLED" ]]; then
  OLD_SHA="$(sha256 "$INSTALLED")"

  if [[ "$NEW_SHA" != "unavailable" && "$NEW_SHA" == "$OLD_SHA" ]]; then
    echo ""
    echo "Already up to date (sha256: ${NEW_SHA:0:16}...)."
    echo "Location: $INSTALLED"
    echo ""
    exit 0
  fi

  echo ""
  if [[ "$NEW_SHA" != "unavailable" ]]; then
    echo "Updating (${OLD_SHA:0:16}... -> ${NEW_SHA:0:16}...)"
  else
    echo "Updating $INSTALLED"
  fi
fi

# ── Install ─────────────────────────────────────────────────────────────────

mkdir -p "$INSTALL_DIR"
cp "$TMPFILE" "$INSTALLED"
chmod +x "$INSTALLED"

# ── Verify PATH ─────────────────────────────────────────────────────────────

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo ""
  echo "Warning: $INSTALL_DIR is not in your PATH."
  echo ""
  echo "Add it by appending one of these to your shell profile:"
  echo ""
  echo "  # bash (~/.bashrc or ~/.bash_profile)"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
  echo "  # zsh (~/.zshrc)"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
  echo "  # fish (~/.config/fish/config.fish)"
  echo "  fish_add_path \$HOME/.local/bin"
  echo ""
  echo "Then restart your shell or run: source ~/.bashrc"
fi

# ── Done ────────────────────────────────────────────────────────────────────

echo ""
echo "Installed successfully: $INSTALLED"
if [[ "$NEW_SHA" != "unavailable" ]]; then
  echo "SHA256: $NEW_SHA"
fi
echo ""
echo "Get started:"
echo "  claudeinjail profile create personal"
echo "  claudeinjail profile set-default personal"
echo "  claudeinjail"
echo ""
