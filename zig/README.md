# claudeinjail (Zig port)

A Zig implementation of the `claudeinjail` CLI, ported from the original
`claudeinjail.sh` in the repository root. It is behavior-compatible: same
commands, flags, prompts, profile/image on-disk layout, and generated
Dockerfiles/entrypoint.

## Requirements

- Zig **0.15.2** or newer
- Docker (at runtime)
- git (a resolvable `user.name`/`user.email` is required, same as the shell version)

## Build

```sh
zig build                      # debug build -> zig-out/bin/claudeinjail
zig build -Doptimize=ReleaseSafe   # optimized build
```

Run directly through the build system:

```sh
zig build run -- --help
zig build run -- profile list
```

Or install the binary somewhere on your `PATH`:

```sh
zig build -Doptimize=ReleaseSafe
install -m755 zig-out/bin/claudeinjail ~/.local/bin/claudeinjail
```

## Usage

Identical to the shell version — see the repository-root `README.md` for the full
reference. Quick examples:

```sh
claudeinjail                       # build + run with the default profile (Alpine)
claudeinjail -w                    # interactive wizard
claudeinjail -p work               # use the "work" profile
claudeinjail -i                    # pick the image (built-in bases + custom)
claudeinjail -c ~/docs             # mount an extra dir read-only at /context/docs
claudeinjail -s                    # open a shell in the container
claudeinjail -t --exit-node host   # Tailscale with an exit node
claudeinjail profile create work   # profile management
claudeinjail eject my-python       # export a customizable Dockerfile
```

## Architecture

The single shell script is split into focused modules under `src/`:

| File | Responsibility |
|------|----------------|
| `main.zig` | Argument parsing, dispatch, `docker run` assembly + exec |
| `config.zig` | Resolved host paths (`~/.config`, `~/.cache`) and constants |
| `util.zig` | stdout/stderr, stdin line reader, subprocess/exec, filesystem, name helpers |
| `templates.zig` | Embedded Dockerfiles, entrypoint, help text; variant/family helpers |
| `profile.zig` | `profile create/list/delete/set-default` |
| `images.zig` | Custom images, `eject`, the `-i` image picker |
| `wizard.zig` | Interactive `-w` mode |
| `app.zig` | Shared CLI state + `add_context_dir` |
| `run.zig` | `docker build`, profile resolution/validation, git identity |
| `templates/` | Raw Dockerfiles, `entrypoint-head.sh`, and `help.txt`, embedded via `@embedFile` |

Templates live as plain files under `src/templates/` and are compiled into the
binary with `@embedFile`, so the executable is self-contained.

## Linting

The project is linted with [zlint](https://github.com/DonIsaac/zlint). Rules are
pinned in `zlint.json` (errors on suppressed errors, `std.debug.print`, unused
declarations, unsafe `undefined`, and homeless `try`).

```sh
zig build lint     # runs zlint (must be installed on PATH)
# or directly:
zlint
```

Formatting is enforced with the compiler's own formatter:

```sh
zig fmt --check src/ build.zig
```

## Debugging

Set `CLAUDEINJAIL_DRYRUN=1` to print the assembled `docker run` command instead
of executing it (the image is still built). Useful for inspecting mounts, flags,
and the resolved container command without launching a container.

```sh
CLAUDEINJAIL_DRYRUN=1 claudeinjail -s -p work
```
