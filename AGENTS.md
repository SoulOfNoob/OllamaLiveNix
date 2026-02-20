# OllamaLiveNix - Session Context

## What This Project Is

A bootable NixOS USB appliance that turns a gaming PC (RTX 3090 24GB) into an on-demand AI inference server. A separate server runs Open WebUI and forwards heavy model requests to the gaming PC over HTTP.

**Repo:** `git@personal.github.com:SoulOfNoob/OllamaLiveNix.git`

## Current State of Files

### `flake.nix`

- Uses **nixpkgs `nixos-25.05`** (no external dependencies, nixos-generators was dropped)
- Exposes `packages.x86_64-linux.{iso, raw, default}` via native `system.build.images.*`
- `default = raw` (raw-efi for USB flashing)
- `nixosConfigurations.OllamaLive` exists for `nix flake check` and image building

### `configuration.nix`

- **System:** NixOS 25.05, hostname `OllamaLive`, timezone `Europe/Berlin`, German keyboard (`de`)
- **User:** `ollamalive` with zsh (autosuggestions, syntax highlighting, history), auto-login on TTY
- **SSH:** Key-only auth (no passwords), reads keys from both `~/.ssh/authorized_keys` and `/persist/ssh/authorized_keys`
- **NVIDIA:** Proprietary drivers, `nvidia-container-toolkit` for Docker GPU passthrough
- **Docker:** Enabled with weekly auto-prune
- **Ollama:** Declarative OCI container, listens on `0.0.0.0:11434`, models stored on NTFS drive at `/mnt/models/ollama`
- **NTFS mount:** `/mnt/models` via `ntfs-3g`, UUID placeholder `YOUR-NTFS-DRIVE-UUID-HERE` still needs replacing
- **Persistence:** ext4 partition labeled `PERSIST` mounted at `/persist`, bind mounts for `/var/lib/docker` and `/etc/ssh`
- **Firewall:** Only SSH (22) and Ollama API (11434) open
- **Unfree packages:** Allowed globally (`nixpkgs.config.allowUnfree = true`)
- **Base config workarounds:** Dummy root FS (`tmpfs`) and `grub.enable = false` with `mkDefault` to satisfy NixOS assertions (image modules override these)

### `.github/workflows/build.yml`

- Triggers on push to `main` (only `*.nix` or workflow file changes) + `workflow_dispatch`
- Builds both `iso` and `raw` in parallel matrix
- Enables KVM on runner (needed for raw-efi)
- Runs `nix flake check` before building
- Compresses outputs with `zstd` + generates SHA256 checksums
- Creates GitHub Release tagged `build-<run_number>` with `.zst` assets

### `.github/workflows/pr.yml`

- Triggers on PRs to `main` (only `*.nix` or workflow file changes)
- Builds ISO only (no KVM needed)
- Uploads as temporary artifact (14-day retention)

### `README.md`

- Two separate paths: **macOS** (download from Releases + flash) and **Linux** (build locally with Nix + flash)
- macOS path includes Docker command for local ISO builds and UTM VM testing instructions
- Both paths have first-flash (full `dd` + create PERSIST partition) and update-flash (sized `dd` with `count=`)
- USB partition layout documented: ESP + Root + PERSIST

## Key Decisions Made

| Decision | Rationale |
|---|---|
| Dropped `nixos-generators` | Deprecated; functionality upstreamed into nixpkgs 25.05 |
| `raw-efi` as default, not ISO | Proper GPT partitions, supports persistent storage, faster to build |
| ext4 for PERSIST (not exFAT) | Docker and SSH need POSIX permissions, symlinks, hardlinks |
| No `cudaPackages.cudatoolkit` | Ollama container bundles its own CUDA; host only needs kernel driver |
| `zstd` compression for releases | Raw image is ~8 GB, exceeds GitHub's 2 GB release asset limit |
| `--no-daemon` Nix install | Lighter weight for build machines, no root needed |
| SSH key-only auth | Security; keys stored on PERSIST partition at `/persist/ssh/authorized_keys` |

## Known Limitations

- **raw-efi requires KVM** — can't build on macOS Docker (only ISO works there)
- **NTFS UUID is a placeholder** — must be replaced before first real boot
- **PERSIST partition created manually** — not auto-created on first boot
- **macOS can't mount ext4** — bind mount dirs (`/persist/docker`, `/persist/ssh`) must be created on first Linux boot
- **No Nix sandbox in single-user mode** — `sandbox = false` and `filter-syscalls = false` required in `nix.conf`

## Build Cheat Sheet

```bash
# GitHub Actions (recommended) — push to main, download from Releases

# Linux local build
nix build .#raw    # USB image
nix build .#iso    # VM testing

# macOS local ISO (Docker)
docker run --rm -it --platform linux/amd64 \
  --name ollamalive-build \
  -v "$(pwd)":/workspace \
  -v ollamalive-nix-cache:/nix \
  -w /workspace \
  nixos/nix bash -c "
    echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf
    echo 'sandbox = false' >> /etc/nix/nix.conf
    echo 'filter-syscalls = false' >> /etc/nix/nix.conf
    nix flake check
    OUT=\$(nix build .#iso --no-link --print-out-paths)
    mkdir -p /workspace/result
    find \$OUT -type f \( -name '*.img' -o -name '*.iso' \) -exec cp -L {} /workspace/result/ \;
  "
```
