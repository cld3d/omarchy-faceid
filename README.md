# Omarchy Face ID

Windows Hello-style facial authentication for [Omarchy](https://omarchy.org/) / Arch Linux with Hyprland.

Uses [Howdy](https://github.com/boltgolt/howdy) for face recognition and [linux-enable-ir-emitter](https://github.com/EmixamPP/linux-enable-ir-emitter) to activate IR blasters.

## Requirements

- Omarchy or Arch Linux with Hyprland
- Laptop/device with an IR camera
- `yay` AUR helper

## Usage

```bash
./install.sh
sudo howdy add
sudo -k && sudo -v
```

Then lock screen and unlock to test hyprlock, reboot to test SDDM login.

## What it does

1. Installs `howdy-bin` and `linux-enable-ir-emitter-bin` from AUR
2. Detects the IR camera device
3. Configures the IR emitter (interactive: answer Y/N to flashing)
4. Sets reasonable Howdy defaults (certainty=5.0, timeout=10s)
5. Creates `/usr/local/bin/pam-howdy-compare` (PAM helper using `pam_exec.so` instead of `pam_python.so`)
6. Patches PAM configs: `sudo`, `hyprlock`, `sddm`

## Notes

- Face ID is triggered on auth requests — press Enter on empty field on lock screen
- Password fallback always works
- Disk encryption (LUKS) cannot use Face ID (decrypts before OS boots)
