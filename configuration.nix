{ config, pkgs, lib, ... }:

{
  # ── Boot & Image ──────────────────────────────────────────────
  # Images are built via `nix build .#iso` or `nix build .#raw` using
  # the native NixOS image modules (system.build.images.*).
  # The image modules override root FS and bootloader; defaults here
  # satisfy NixOS assertions for the base configuration.
  fileSystems."/" = lib.mkDefault {
    device = "none";
    fsType = "tmpfs";
  };
  boot.loader.grub.enable = lib.mkDefault false;

  # ── Unfree Packages ──────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  # ── System Basics ─────────────────────────────────────────────
  system.stateVersion = "25.05";
  networking.hostName = "OllamaLive";
  time.timeZone = "Europe/Berlin";
  console.keyMap = "de";

  # Passwordless auto-login for appliance use
  users.users.ollamalive = {
    isNormalUser = true;
    extraGroups = [ "docker" "video" "render" "wheel" ];
    shell = pkgs.zsh;
    initialPassword = ""; # set a real password or use SSH keys
  };

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 10000;
  };

  system.userActivationScripts.ollamalive-zshrc = {
    text = ''
      if [ ! -f /home/ollamalive/.zshrc ]; then
        printf '#prevent setup\n' > /home/ollamalive/.zshrc
        chown ollamalive:users /home/ollamalive/.zshrc
        chmod 0644 /home/ollamalive/.zshrc
      fi
    '';
  };

  # Auto-login to TTY (no desktop environment needed)
  services.getty.autologinUser = "ollamalive";

  # ── Networking ────────────────────────────────────────────────
  networking.networkmanager.enable = true;
  # Enable SSH so you can manage it remotely
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    extraConfig = ''
      AuthorizedKeysFile .ssh/authorized_keys /persist/ssh/authorized_keys
    '';
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
      "uid=1000"        # maps to the 'ollamalive' user
      "gid=100"         # users group
      "dmask=022"
      "fmask=133"
      "nofail"          # don't fail boot if drive is missing
      "x-systemd.automount"
      "x-systemd.idle-timeout=0"
    ];
  };

  # ── Persistent Storage (on USB stick) ─────────────────────────
  # Separate ext4 partition labeled PERSIST on the same USB drive.
  # Created manually after first flash; survives system reflashes.
  fileSystems."/persist" = {
    device = "/dev/disk/by-label/PERSIST";
    fsType = "ext4";
    options = [ "rw" "nofail" ];
  };

  # Bind-mount Docker state and SSH host keys to the persistent partition
  # so they survive system reflashes.
  fileSystems."/var/lib/docker" = {
    device = "/persist/docker";
    options = [ "bind" "nofail" ];
  };

  fileSystems."/etc/ssh" = {
    device = "/persist/ssh";
    options = [ "bind" "nofail" ];
  };

  # ── Useful System Packages ────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # System tools
    htop
    nvtopPackages.full # GPU monitoring
    pciutils
    usbutils
    git
    curl
    nano
    tree

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
  boot.loader.timeout = lib.mkDefault 3;

  # ── Nix Settings ──────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
}
