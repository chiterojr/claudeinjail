# Claude in Jail

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

On the first run the Docker image will be built automatically using Alpine by default. Use `-i` to choose between Alpine and Debian. Subsequent runs use the cached image. If you need to add packages or tools to the image, see [Customizing the image](#customizing-the-image).

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
| `-t, --tailscale` | Connect the container to your Tailscale network |
| `--exit-node <node>` | Route all container traffic through a Tailscale exit node (requires `--tailscale`) |
| `-v, --verbose` | Enable Tailscale daemon logging to the profile directory |

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
claudeinjail --tailscale                  # Start with Tailscale connected
claudeinjail -t --exit-node my-server     # Tailscale with exit node
```

## Profiles

A profile is a set of local directories that get mounted as volumes into the container, providing Claude Code with its configuration, credentials, and session data. Each profile is fully isolated, so you can have as many accounts as you want (personal, work, client projects, etc.) and switch between them without any conflicts.

Profiles are stored in `~/.config/claudeinjail/`:

```
~/.config/claudeinjail/
  default              # File pointing to the default profile name
  personal/
    .claude/           # Settings, OAuth sessions, agents
    .claude.json       # State, MCP servers, tool permissions
    tailscale/         # Tailscale state (if --tailscale is used)
  work/
    .claude/
    .claude.json
    tailscale/
```

At runtime, the selected profile's directories are bind-mounted into the container at `/home/claude/.claude` and `/home/claude/.claude.json`, so Claude Code sees them as its native config. This means credentials persist across runs and each profile can be logged into a completely different account.

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

## Tailscale

The `--tailscale` flag connects the container to your [Tailscale](https://tailscale.com) network (tailnet), giving Claude Code access to internal services, APIs, databases, or MCP servers on your private network.

### How it works

When `--tailscale` is passed, the container starts a `tailscaled` daemon before launching Claude Code. Tailscale creates a virtual network interface (TUN) inside the container to establish the VPN tunnel.

This requires three extra Docker flags that are **only added when `--tailscale` is used**:

| Flag | Why it's needed |
|---|---|
| `--cap-add=NET_ADMIN` | Allows creating and configuring network interfaces and routes inside the container |
| `--cap-add=NET_RAW` | Allows raw socket operations needed by the Tailscale tunnel |
| `--device=/dev/net/tun` | Provides access to the kernel TUN device for creating the VPN interface |

Without `--tailscale`, none of these are added and the container runs with no extra privileges.

### Host isolation

The TUN interface, routes, and firewall rules created by Tailscale are **confined to the container's network namespace**. They do not appear on the host, do not modify host routes, and do not affect the host's internet connectivity. Starting and stopping the container has no side effects on the host network. It behaves like a completely separate machine on your tailnet.

### Authentication

On the first run, `tailscale up` prints a URL in the terminal. Open it in your browser to authorize the device. The authentication state is persisted in the profile directory (`~/.config/claudeinjail/<profile>/tailscale/`), so subsequent runs reconnect automatically without prompting.

Each profile has its own independent Tailscale identity — the "personal" profile can be on one tailnet and the "work" profile on another.

### Hostname

The container registers on your tailnet as an ephemeral node — it disappears automatically from the Tailscale admin panel when the container stops, keeping your tailnet clean. The hostname follows the format `claudeinjail-<dirname>-<random>`, for example `claudeinjail-my-project-472`. It is sanitized (lowercase, alphanumeric and dashes only) and limited to 63 characters.

### Exit nodes

Use `--exit-node` to route all container traffic through a Tailscale exit node. LAN access is preserved automatically so the container can still reach local services.

```bash
# Route all traffic through an exit node
claudeinjail --tailscale --exit-node=my-server

# Using a Tailscale IP
claudeinjail -t --exit-node=100.64.0.1
```

### Logging

By default, `tailscaled` daemon output is silenced to keep the terminal clean. Use `--verbose` to enable logging — logs are written to `~/.config/claudeinjail/<profile>/tailscale/tailscaled.log`. If a connection error occurs without `--verbose`, the error message will suggest retrying with the flag.

### Usage

```bash
# Connect to your tailnet
claudeinjail --tailscale

# With an exit node
claudeinjail --tailscale --exit-node=my-server

# With verbose logging
claudeinjail --tailscale --verbose

# Combined with other flags
claudeinjail -t -p work -s   # Tailscale + work profile + shell
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

## TODO

- [x] Tailscale support inside the container
- [ ] Improve connectivity with local network services (DNS, host networking, etc.)
- [ ] macOS support
- [ ] Windows support

## License

MIT
