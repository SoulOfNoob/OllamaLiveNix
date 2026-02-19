{ config, pkgs, lib, ... }:

{
  # ── Boot & Image ──────────────────────────────────────────────
  # This config is intended to be built as a bootable ISO/USB image
  # using nixos-generators or the built-in ISO module.
  # For ISO: imports = [ <nixpkgs/nixos/modules/installer/cd-dvd/iso-image.nix> ];
  # For USB with persistence, use nixos-generators with the "raw" format.

  imports = [
    # If building an ISO image:
    # "${toString pkgs.path}/nixos/modules/installer/cd-dvd/iso-image.nix"
  ];

  # ── System Basics ─────────────────────────────────────────────
  system.stateVersion = "24.11";
  networking.hostName = "OllamaLive";
  time.timeZone = "Europe/Berlin"; # adjust to your timezone

  # Passwordless auto-login for appliance use
  users.users.ai = {
    isNormalUser = true;
    extraGroups = [ "docker" "video" "render" "wheel" ];
    initialPassword = ""; # set a real password or use SSH keys
  };

  # Auto-login to TTY (no desktop environment needed)
  services.getty.autologinUser = "ollamalive";

  # ── Networking ────────────────────────────────────────────────
  networking.networkmanager.enable = true;
  # Enable SSH so you can manage it remotely from Windows
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true; # switch to false once you add SSH keys
    };
  };

  # ── NVIDIA Drivers ────────────────────────────────────────────
  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    open = false; # use proprietary drivers for best CUDA support
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Ensure the nvidia driver is loaded
  services.xserver.videoDrivers = [ "nvidia" ];

  # NVIDIA container toolkit for GPU passthrough to Docker
  hardware.nvidia-container-toolkit.enable = true;

  # ── Docker & Containers ───────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableNvidia = true; # deprecated in newer nixos, use nvidia-container-toolkit above
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # ── Ollama via OCI Container ──────────────────────────────────
  # Declarative container definition - starts automatically on boot
  # Bind Ollama to all interfaces so your server can reach it
  # By default Ollama only listens on localhost
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      ollama = {
        image = "ollama/ollama:latest";
        ports = [ "0.0.0.0:11434:11434" ];
        environment = {
          OLLAMA_HOST = "0.0.0.0";
        };
        volumes = [
          "/mnt/models/ollama:/root/.ollama"  # models on your NTFS drive
        ];
        extraOptions = [
          "--gpus=all"
          "--restart=unless-stopped"
        ];
      };

      # Add more containers here as needed, e.g.:
      # stable-diffusion, text-generation-webui, etc.
    };
  };

  # ── Mount NTFS Models Drive ───────────────────────────────────
  # Identify your drive's UUID with: blkid
  # Replace the UUID below with your actual drive UUID
  fileSystems."/mnt/models" = {
    device = "/dev/disk/by-uuid/YOUR-NTFS-DRIVE-UUID-HERE";
    fsType = "ntfs-3g";
    options = [
      "rw"
      "uid=1000"        # maps to the 'ai' user
      "gid=100"         # users group
      "dmask=022"
      "fmask=133"
      "nofail"          # don't fail boot if drive is missing
      "x-systemd.automount"
      "x-systemd.idle-timeout=0"
    ];
  };

  # ── Persistent Storage (optional, on USB stick) ───────────────
  # If you add a second partition on the USB for persistent data:
  # fileSystems."/persist" = {
  #   device = "/dev/disk/by-label/PERSIST";
  #   fsType = "ext4";
  #   options = [ "rw" "nofail" ];
  # };

  # ── Useful System Packages ────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # System tools
    htop
    nvtop              # GPU monitoring
    pciutils
    usbutils
    git
    curl
    vim

    # NVIDIA / CUDA
    cudaPackages.cudatoolkit
    nvidia-docker

    # Networking
    inetutils
    tmux               # keep sessions alive after SSH disconnect
  ];

  # ── Firewall ──────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22     # SSH
      11434  # Ollama API
    ];
  };

  # ── Boot Splash (optional) ────────────────────────────────────
  # Minimal boot, no GUI, straight to services
  boot.loader.timeout = 3;

  # ── Nix Settings ──────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
}
