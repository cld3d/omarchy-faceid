#!/bin/bash
set -euo pipefail

if (( EUID == 0 )); then
  echo "Run this as your normal user, not with sudo." >&2
  exit 1
fi

for cmd in yay v4l2-ctl; do
  command -v $cmd >/dev/null 2>&1 || { echo "Missing '$cmd'" >&2; exit 1; }
done

echo "==> Installing packages..."
yay -S --noconfirm --needed howdy-bin linux-enable-ir-emitter-bin

HOWDY_DIR=/usr/lib/security/howdy
if [[ ! -f $HOWDY_DIR/compare.py ]]; then
  echo "Could not find $HOWDY_DIR/compare.py" >&2
  exit 1
fi

IR_BIN=$(command -v linux-enable-ir-emitter)
if [[ -z $IR_BIN ]]; then echo "Missing linux-enable-ir-emitter" >&2; exit 1; fi

echo "==> Detecting IR camera..."
IR_DEV=""
for d in /dev/video*; do
  if v4l2-ctl -d "$d" --all 2>/dev/null | grep -Eq "IR Camera|'GREY'"; then
    IR_DEV=$d; break
  fi
done
if [[ -z $IR_DEV ]]; then
  for d in /dev/video*; do [[ -e $d ]] && { IR_DEV=$d; break; }; done
fi
if [[ -z $IR_DEV ]]; then echo "No camera found." >&2; exit 1; fi
echo "  Camera: $IR_DEV"

echo "==> Configuring IR emitter..."
tmp=$(mktemp)
if ! sudo "$IR_BIN" --device "$IR_DEV" configure --no-gui 2>&1 | tee "$tmp"; then
  if grep -q "already working" "$tmp"; then
    echo "  Already configured."
  else
    rm -f "$tmp"; echo "IR emitter config failed." >&2; exit 1
  fi
fi
rm -f "$tmp"

echo "==> Configuring Howdy..."
CONFIG=/usr/lib/security/howdy/config.ini
sudo cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"

sudo python3 - <<PY
from pathlib import Path
import re
p = Path('$CONFIG')
t = p.read_text()
def s(k, v):
  return re.sub(rf'^(\s*#?\s*{re.escape(k)}\s*=\s*).*$', lambda m: f"{m.group(1)}{v}", t, flags=re.MULTILINE)
for k, v in [("device_path", "$IR_DEV"), ("timeout", "10"), ("certainty", "5.0"), ("recording_plugin", "opencv"), ("detection_notice", "true")]:
  t = s(k, v)
p.write_text(t)
PY

echo "==> Creating PAM helper..."
PAM_HELPER=/usr/local/bin/pam-howdy-compare
sudo tee "$PAM_HELPER" > /dev/null <<'SCRIPT'
#!/bin/bash
exec /usr/bin/python3 /usr/lib/security/howdy/compare.py "${PAM_USER:-$USER}"
SCRIPT
sudo chmod +x "$PAM_HELPER"

echo "==> Patching PAM configs..."
backup() { sudo cp "$1" "$1.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true; }
prepend() {
  local f=$1 l=$2
  if ! sudo grep -Fqx "$l" "$f" 2>/dev/null; then backup "$f"; sudo sed -i "1i $l" "$f"; fi
}

PAM_HOWDY="auth [success=done default=ignore] pam_exec.so quiet $PAM_HELPER"
PAM_EMITTER="auth optional pam_exec.so $IR_BIN run"

for f in /etc/pam.d/sudo /etc/pam.d/hyprlock /etc/pam.d/sddm; do
  if sudo grep -Eq 'pam_python\.so|pam-howdy-compare' "$f" 2>/dev/null; then
    backup "$f"
    sudo sed -i '/pam_python\.so/d;/pam-howdy-compare/d' "$f"
  fi
  prepend "$f" "$PAM_HOWDY"
  prepend "$f" "$PAM_EMITTER"
  echo "  Patched: $f"
done

echo ""
echo "========================================"
echo "  Face ID setup complete!"
echo "========================================"
echo ""

read -rp "Enroll your face now? [Y/n] " yn
if [[ ${yn:-y} =~ ^[Yy]$ ]]; then
  sudo howdy add
fi

read -rp "Test face matching? [Y/n] " yn
if [[ ${yn:-y} =~ ^[Yy]$ ]]; then
  echo "Look at the camera..."
  if sudo $PAM_HELPER; then
    echo "Face matched!"
  else
    echo "No face detected."
  fi
fi

read -rp "Test sudo with face auth? [Y/n] " yn
if [[ ${yn:-y} =~ ^[Yy]$ ]]; then
  sudo -k
  if sudo -v; then
    echo "sudo face auth works!"
  fi
fi

echo ""
echo "Done. Lock screen to test hyprlock, or reboot to test SDDM login."
