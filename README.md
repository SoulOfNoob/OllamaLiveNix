# OllamaLiveNix

## Goal

Create a bootable USB stick running a minimal NixOS system that turns the gaming PC (RTX 3090 24GB) into an on-demand AI inference server. The server (5060 Ti) handles daily workloads and hosts Open WebUI; the gaming PC is only booted into Linux when heavy GPU power is needed.

## Hardware Context

- **Gaming PC:** AMD Ryzen 7 7800X3D, 32GB DDR5-6000, RTX 3090 24GB
- **Server:** Hosts Open WebUI and runs lighter models on 5060 Ti 16GB
- **USB Stick:** Boot drive for NixOS (read-only root + optional persistent partition)
- **NTFS Drive:** Shared between Windows and Linux, stores model files

## Architecture

```text
[Server: Open WebUI] --HTTP:11434--> [Gaming PC: NixOS USB → Docker → Ollama → RTX 3090]
                                                                        ↓
                                                              [NTFS Drive: /mnt/models]
```

## Must Haves

- **Declarative NixOS config** — entire system defined in `configuration.nix`, reproducible and version-controlled
- **Bootable USB image** — built via `nixos-generators`, flashable with `dd`
- **NVIDIA proprietary drivers + CUDA** — required for GPU inference
- **nvidia-container-toolkit** — GPU passthrough into Docker containers
- **Docker + Ollama container** — starts automatically on boot, listens on `0.0.0.0:11434`
- **NTFS mount** — mounts the shared model drive at `/mnt/models`, Ollama reads/writes models there
- **SSH access** — remote management from server or any other device on the network
- **Firewall** — only expose SSH (22) and Ollama API (11434)

## Nice to Haves

- Small persistent ext4 partition on the USB for container state/logs
- Fallback: separate ext4 drive for models if NTFS write causes issues
- tmux or similar for persistent SSH sessions
- nvtop for GPU monitoring

## Known Risks & Caveats

- **NTFS writes from Docker:** Ollama downloads large blob files + small JSON manifests to the NTFS mount. Large sequential writes should be fine. Watch for permission issues — the container runs as root (uid 0) but the NTFS mount maps to uid 1000. May need mount option adjustments (`uid=0,gid=0` or `allow_other`)
- **NVIDIA driver version:** Must match between the NixOS host driver and the nvidia-container-toolkit. NixOS handles this if both come from the same package set, but verify after build
- **No GUI:** This is a headless appliance. If you need a display for debugging, it boots to TTY with auto-login

## Project Structure

```text
ollamalive/
├── configuration.nix      # Main system config (provided by Claude)
├── flake.nix              # Flake wrapper for reproducible builds
└── README.md              # This file
```

## Build Steps

### 1. Setup Build Environment

Building NixOS images requires a Linux environment. Choose one of:

#### Option A: Native Linux (server or any Linux machine)

```bash
# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

# Install nixos-generators
nix-env -iA nixpkgs.nixos-generators
```

#### Option B: macOS via Docker

No Nix installation needed — Docker Desktop provides the Linux environment:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace \
  -w /workspace \
  nixos/nix bash -c "
    echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf
    nix build .#iso
  "
```

Replace `.#iso` with `.#raw` to build the USB image. The result appears in `./result/` on the host.

### 2. Configure

- Get NTFS drive UUID: run `blkid` on any Linux system and replace `YOUR-NTFS-DRIVE-UUID-HERE` in config
- Set timezone if not `Europe/Berlin`
- Set a real password or add SSH keys for the `ollamalive` user
- Review Ollama volume path: `/mnt/models/ollama` maps to `/root/.ollama` inside the container

### 3. Validate

```bash
# With flake
nix flake check

# Without flake
nix-instantiate --eval -E 'import ./configuration.nix'
```

### 4. Build Image

```bash
# With flake (recommended)
nix build .#iso    # ISO for testing in VM
nix build .#raw    # Raw EFI disk image for USB

# Without flake
nixos-generate -f iso -c ./configuration.nix -o result
nixos-generate -f raw -c ./configuration.nix -o result
```

### 5. Test in VM (Optional but Recommended)

Boot ISO in QEMU or VirtualBox. GPU/Ollama won't work but validates base system, networking, mounts, and SSH.

### 6. Flash to USB

```bash
# From Mac
diskutil list
diskutil unmountDisk /dev/diskX
sudo dd if=result/nixos.img of=/dev/rdiskX bs=4M status=progress
diskutil eject /dev/diskX
```

### 7. First Boot on Hardware

1. Boot gaming PC from USB
2. SSH in from server: `ssh ollamalive@<gaming-pc-ip>`
3. Verify GPU: `nvidia-smi`
4. Test Ollama: `docker logs ollama`
5. Test NTFS writes: `ollama pull llama3.2:7b` (via docker exec or API)
6. Point Open WebUI on server to `http://<gaming-pc-ip>:11434`

## Iteration Workflow

Edit `configuration.nix` → rebuild image → reflash USB → reboot. All changes are declarative and tracked in git.
