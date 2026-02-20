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
│   ├── build.yml          # CI: builds ISO + raw images, creates release
│   └── pr.yml             # PR: builds ISO for validation
├── configuration.nix      # Main system config
├── flake.nix              # Flake wrapper for reproducible builds
└── README.md              # This file
```

## Quick Start

Choose your path:

- **[macOS Path](#macos-path)** — Download pre-built image from GitHub Releases, flash to USB
- **[Linux Path](#linux-path)** — Build locally with Nix, flash to USB

---

## macOS Path

### 1. Download Image

Go to the [Releases](../../releases) page and download the latest `nixos-*.img.zst` (raw-efi image for USB).

Decompress before flashing:

```bash
brew install zstd   # if not installed
zstd -d nixos-*.img.zst
```

### 2. Configure (before first build)

If you need to change the NixOS config (NTFS UUID, timezone, etc.), edit the `.nix` files and push to `main`. GitHub Actions will build new images automatically.

### 3. Flash to USB

#### Initial setup

```bash
diskutil list
diskutil unmountDisk /dev/diskX
sudo dd if=nixos-*.img of=/dev/rdiskX bs=4m status=progress

# Create PERSIST partition (install e2fsprogs first: brew install e2fsprogs)
sudo gdisk /dev/diskX   # → n, accept defaults, w
diskutil unmountDisk /dev/diskX
$(brew --prefix)/opt/e2fsprogs/sbin/mkfs.ext4 -L PERSIST /dev/diskXs3
```

> **Note:** macOS can't mount ext4. On first Linux boot, run:
> `sudo mkdir -p /persist/docker /persist/ssh`
> Then add your SSH public key:
> `sudo sh -c 'cat >> /persist/ssh/authorized_keys' < ~/.ssh/id_ed25519.pub`

#### System update

```bash
IMG_SIZE=$(stat -f %z nixos-*.img)
BLOCKS=$((IMG_SIZE / 4194304))
diskutil unmountDisk /dev/diskX
sudo dd if=nixos-*.img of=/dev/rdiskX bs=4m count=$BLOCKS status=progress
```

### 4. Test in VM (Optional)

To verify the config before flashing, download the `nixos-*.iso.zst` from Releases and test in UTM:

1. Decompress: `zstd -d nixos-*.iso.zst`
2. Open UTM → **Create new VM** → **Emulate** (not Virtualize)
3. Architecture: **x86_64**, System: **Standard PC (Q35)**
4. RAM: **4096 MB**, skip storage
5. In VM settings: uncheck **UEFI Boot** under QEMU
6. Drives → **Import** the `.iso`, set interface to **IDE**, move to top of boot order

It will be slow under emulation but boots to TTY with auto-login. GPU and Docker won't work, but you can verify the config:

```bash
systemctl list-units --failed
ip addr
cat /etc/ssh/sshd_config
```

### 5. First Boot

Jump to [First Boot on Hardware](#first-boot-on-hardware).

---

## Linux Path

### 1. Setup Nix

```bash
# Install Nix (single-user, no daemon)
sh <(curl -L https://nixos.org/nix/install) --no-daemon
. ~/.nix-profile/etc/profile.d/nix.sh

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
```

### 2. Configure

- Get NTFS drive UUID: run `blkid` on any Linux system and replace `YOUR-NTFS-DRIVE-UUID-HERE` in config
- Set timezone if not `Europe/Berlin`
- Set a real password or add SSH keys for the `ollamalive` user
- Review Ollama volume path: `/mnt/models/ollama` maps to `/root/.ollama` inside the container

### 3. Validate

```bash
nix flake check
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

```bash
lsblk
sudo dd if=result/nixos.img of=/dev/sdX bs=4M status=progress conv=fsync

# Create PERSIST partition in remaining space
sudo fdisk /dev/sdX   # → n, accept defaults, w
sudo mkfs.ext4 -L PERSIST /dev/sdX3

# Pre-create directories and add SSH key
sudo mkdir -p /mnt/persist
sudo mount /dev/sdX3 /mnt/persist
sudo mkdir -p /mnt/persist/docker /mnt/persist/ssh
cat ~/.ssh/id_ed25519.pub | sudo tee /mnt/persist/ssh/authorized_keys
sudo umount /mnt/persist
```

#### Subsequent flashes (system update)

```bash
IMG_SIZE=$(stat --format=%s result/nixos.img)
BLOCKS=$((IMG_SIZE / 4194304))
sudo dd if=result/nixos.img of=/dev/sdX bs=4M count=$BLOCKS status=progress conv=fsync
```

---

## First Boot on Hardware

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

Edit `configuration.nix` → push to `main` (or `nix build .#raw` locally) → download/reflash system partitions only → reboot.
Docker state and SSH keys persist across updates.
