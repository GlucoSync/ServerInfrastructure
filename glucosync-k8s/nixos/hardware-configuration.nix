# Hardware configuration template
# This file should be generated automatically with:
# nixos-generate-config --show-hardware-config > hardware-configuration.nix

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # Boot settings
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Filesystem configuration
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  # Swap configuration (adjust as needed)
  swapDevices = [ { device = "/dev/sda2"; } ];

  # Networking
  networking.useDHCP = lib.mkDefault true;

  # CPU and hardware
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # NOTE: This is a template! Generate actual hardware config with:
  # nixos-generate-config --show-hardware-config
}
