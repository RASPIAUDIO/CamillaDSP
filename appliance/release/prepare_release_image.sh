#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo on the Pi before imaging the SD card." >&2
  exit 1
fi

echo "Preparing RASPIAUDIO appliance image for release..."

IMAGE_BUILD="${RASPIAUDIO_IMAGE_BUILD:-0}"

set_local_hostname_files() {
  local name="$1"
  printf '%s\n' "$name" >/etc/hostname
  if [ -f /etc/hosts ]; then
    if grep -qE '^127\.0\.1\.1[[:space:]]+' /etc/hosts; then
      sed -i -E "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${name}/" /etc/hosts
    else
      printf '127.0.1.1\t%s\n' "$name" >>/etc/hosts
    fi
  fi
}

if [ "$IMAGE_BUILD" != "1" ]; then
  systemctl stop camilladsp.service camillagui.service raspiaudio-web.service nginx 2>/dev/null || true
fi

if [ "$IMAGE_BUILD" = "1" ]; then
  find /tmp -mindepth 1 -maxdepth 1 ! -name bdebstrap-output -exec rm -rf {} +
else
  rm -rf /tmp/*
fi
rm -rf /var/tmp/*
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/journal/* 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true

rm -f /root/.bash_history /home/*/.bash_history 2>/dev/null || true
rm -rf /root/.ssh /home/*/.ssh 2>/dev/null || true
rm -f /etc/ssh/ssh_host_* 2>/dev/null || true

rm -f /etc/machine-id
touch /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

rm -f /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || true
rm -rf /var/lib/NetworkManager/* 2>/dev/null || true
set_local_hostname_files raspiaudio

cat >/etc/raspiaudio/box.conf <<'EOF'
hardware=8xout
active_mode=usb_7_1_to_8out
sample_rate=48000
# For 8xIN+8xOUT images, set this to the exact driver option that enables ADC
# input loading in the hifiberry-dac8x based RASPIAUDIO overlay.
adc_driver_option=
EOF

/usr/local/sbin/raspiaudio-mode set usb_7_1_to_8out || true
systemctl disable ssh 2>/dev/null || true
systemctl enable avahi-daemon nginx raspiaudio-spdif.service camilladsp.service camillagui.service raspiaudio-web.service >/dev/null 2>&1 || true
if [ -f /etc/systemd/system/raspiaudio-spdif-firstboot.service ]; then
  systemctl enable raspiaudio-spdif-firstboot.service >/dev/null 2>&1 || true
fi

sync

cat <<'EOF'
Release cleanup complete.

Now shut down the Pi:
  sudo poweroff

Then image the SD card from your PC and compress it as:
  raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz

Publish it with a matching SHA256 file.
EOF
