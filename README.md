# claudeinjail

Run [Claude Code](https://claude.ai) CLI inside a Docker container, isolated from your host system.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/chiterojr/claudeinjail/main/install.sh | bash
```

This downloads a single self-contained script to `~/.local/bin/claudeinjail`. No git clone needed — the Dockerfiles are embedded in the script itself.

**Requirements:** Docker and either curl or wget.

## Quick start

```bash
# Create your first profile
claudeinjail profile create personal

# Set it as default
claudeinjail profile set-default personal

# Launch Claude Code
claudeinjail
```

On the first run the Docker image will be built automatically. Subsequent runs use the cached image.

## Usage

```
claudeinjail [command] [options]
```

### Commands

| Command | Description |
|---|---|
| *(none)* | Build the image and start the container |
| `profile create <name>` | Create a new profile |
| `profile list` | List all profiles |
| `profile delete <name> --confirm` | Delete a profile (requires interactive confirmation) |
| `profile set-default <name>` | Set the default profile |
| `eject` | Export the Dockerfile for customization |
| `help` | Show help message |

### Options

| Option | Description |
|---|---|
| `-p, --profile <name>` | Use a specific profile |
| `-i, --select-image` | Prompt to choose base image (Alpine or Debian) |
| `-b, --build-only` | Only build the Docker image, don't start a container |
| `-s, --shell` | Open a shell in the container instead of launching Claude |

### Examples

```bash
claudeinjail                              # Start with default profile (Alpine)
claudeinjail -p work                      # Start with the "work" profile
claudeinjail -i                           # Choose base image interactively
claudeinjail -b                           # Build image only
claudeinjail -s                           # Open a shell in the container
claudeinjail -s -p work                   # Shell with "work" profile
claudeinjail profile create work          # Create a new profile
claudeinjail profile list                 # List existing profiles
claudeinjail profile delete work --confirm # Delete the "work" profile
claudeinjail profile set-default work     # Set "work" as default
```

## Profiles

Profiles are stored in `~/.config/claudeinjail/` and each contains:

```
~/.config/claudeinjail/
  default              # File pointing to the default profile name
  personal/
    .claude/           # Settings, OAuth sessions, agents
    .claude.json       # State, MCP servers, tool permissions
  work/
    .claude/
    .claude.json
```

These directories are mounted into the container at `/home/claude/.claude` and `/home/claude/.claude.json`, so Claude Code sees them as its native config.

## Docker images

Two base images are supported (selectable with `-i`):

| Image | Base | Notes |
|---|---|---|
| `claudeinjail-alpine` *(default)* | `alpine:3.21` | Smaller and faster to build |
| `claudeinjail-debian` | `debian:bookworm-slim` | Better compatibility with conventional Linux tools |

Both install Claude Code via the official installer as a non-root user and include common utilities (git, curl, jq, etc.). The Dockerfiles are embedded in the `claudeinjail` script and generated at build time in `~/.cache/claudeinjail/`.

## Customizing the image

To add packages, tools, or runtimes to the container, eject the Dockerfile:

```bash
claudeinjail eject
```

This writes the Dockerfile to `~/.config/claudeinjail/Dockerfile`. Edit it as needed — it will be picked up automatically on the next build. To revert to the built-in Dockerfile, just delete it:

```bash
rm ~/.config/claudeinjail/Dockerfile
```

## Environment variables

| Variable | Description |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic API key (optional, depends on auth method) |

The current directory (`pwd`) is mounted as `/workspace` inside the container. Just `cd` into your project and run `claudeinjail`.

## Uninstall

```bash
rm ~/.local/bin/claudeinjail
rm -rf ~/.config/claudeinjail  # profiles and settings
rm -rf ~/.cache/claudeinjail   # cached Dockerfiles
```

## License

MIT
