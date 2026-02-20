# OllamaLiveNix

## Goal

Create a bootable USB stick running a minimal NixOS system that turns the gaming PC (RTX 3090 24GB) into an on-demand AI inference server. The server (5060 Ti) handles daily workloads and hosts Open WebUI; the gaming PC is only booted into Linux when heavy GPU power is needed.

## Hardware Context

- **Gaming PC:** AMD Ryzen 7 7800X3D, 32GB DDR5-6000, RTX 3090 24GB
- **Server:** Hosts Open WebUI and runs lighter models on 5060 Ti 16GB
- **USB Stick:** Boot drive for NixOS (system partition + persistent ext4 partition)
- **NTFS Drive:** Shared between Windows and Linux, stores model files

## Architecture

```text
[Server: Open WebUI] --HTTP:11434--> [Gaming PC: NixOS USB → Docker → Ollama → RTX 3090]
                                                                        ↓
                                                              [NTFS Drive: /mnt/models]
```

## Must Haves

- **Declarative NixOS config** — entire system defined in `configuration.nix`, reproducible and version-controlled
- **Bootable USB image** — built via native NixOS image modules, flashable with `dd`
- **NVIDIA proprietary drivers + CUDA** — required for GPU inference
- **nvidia-container-toolkit** — GPU passthrough into Docker containers
- **Docker + Ollama container** — starts automatically on boot, listens on `0.0.0.0:11434`
- **NTFS mount** — mounts the shared model drive at `/mnt/models`, Ollama reads/writes models there
- **SSH access** — remote management from server or any other device on the network
- **Firewall** — only expose SSH (22) and Ollama API (11434)

## Nice to Haves

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
├── .github/workflows/
│   └── build.yml          # CI: builds ISO + raw images on push
├── configuration.nix      # Main system config
├── flake.nix              # Flake wrapper for reproducible builds
└── README.md              # This file
```

## Build Steps

### GitHub Actions (recommended)

Push to `main` to automatically build both ISO and raw-efi images. Download them from the Actions tab under artifacts. You can also trigger a build manually via `workflow_dispatch`.

### Local Build

#### 1. Setup Build Environment

Choose one of:

#### Option A: Native Linux (e.g. Ubuntu 24 LTS)

```bash
# Install Nix (single-user, no daemon)
sh <(curl -L https://nixos.org/nix/install) --no-daemon
. ~/.nix-profile/etc/profile.d/nix.sh

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

#### Option B: macOS via Docker

```bash
docker run --rm -it --platform linux/amd64 \
  --name ollamalive-build \
  -v "$(pwd)":/workspace \
  -v ollamalive-nix-cache:/nix \
  -w /workspace \
  nixos/nix bash -c "
    echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf
    echo 'sandbox = false' >> /etc/nix/nix.conf
    echo 'filter-syscalls = false' >> /etc/nix/nix.conf
    echo 'max-jobs = auto' >> /etc/nix/nix.conf
    echo 'cores = 0' >> /etc/nix/nix.conf
    OUT=\$(nix build .#iso --no-link --print-out-paths)
    mkdir -p /workspace/result
    find \$OUT -type f \( -name '*.img' -o -name '*.iso' \) -exec cp -L {} /workspace/result/ \;
  "
```

The image lands in `./result/` on your host. The `ollamalive-nix-cache` volume caches the Nix store across runs so only the first build is slow.

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
nix build .#raw    # Raw EFI disk image for USB (default)
nix build .#iso    # ISO for testing in VM (optional)
```

### 5. Test in VM (Optional)

Boot the ISO in QEMU or VirtualBox. GPU/Ollama won't work but validates base system, networking, mounts, and SSH.

### 6. Flash to USB

#### First flash

Write the full system image, then create the persistent partition in the remaining space:

```bash
# Identify the USB device
lsblk

# Flash the system image
sudo dd if=result/nixos.img of=/dev/sdX bs=4M status=progress conv=fsync

# Create the PERSIST partition in remaining space
sudo fdisk /dev/sdX
# → n (new partition), accept defaults, w (write)

# Format and label it
sudo mkfs.ext4 -L PERSIST /dev/sdX3

# Pre-create directories for bind mounts
sudo mkdir -p /mnt/persist
sudo mount /dev/sdX3 /mnt/persist
sudo mkdir -p /mnt/persist/docker /mnt/persist/ssh
sudo umount /mnt/persist
```

#### Subsequent flashes (system update)

Only overwrite the system partitions, leaving PERSIST intact:

```bash
# Get the exact image size in bytes
IMG_SIZE=$(stat --format=%s result/nixos.img)

# Calculate block count (4M blocks)
BLOCKS=$((IMG_SIZE / 4194304))

# Flash only the system portion
sudo dd if=result/nixos.img of=/dev/sdX bs=4M count=$BLOCKS status=progress conv=fsync
```

### 7. First Boot on Hardware

1. Boot gaming PC from USB
2. SSH in from server: `ssh ollamalive@<gaming-pc-ip>`
3. Verify GPU: `nvidia-smi`
4. Verify persistent mount: `df -h /persist`
5. Test Ollama: `docker logs ollama`
6. Test NTFS writes: `ollama pull llama3.2:7b` (via docker exec or API)
7. Point Open WebUI on server to `http://<gaming-pc-ip>:11434`

## USB Partition Layout

```text
/dev/sdX
├── sdX1  ESP (boot)           ~256 MB   ← system image
├── sdX2  Root (NixOS)         ~2-8 GB   ← system image
└── sdX3  PERSIST (ext4)       remaining ← survives reflash
              ├── docker/                   Docker container state
              └── ssh/                      SSH host keys
```

## Iteration Workflow

Edit `configuration.nix` → `nix build .#raw` → reflash system partitions only → reboot.
Docker state and SSH keys persist across updates.
