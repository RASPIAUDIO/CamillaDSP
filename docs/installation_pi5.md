# Installation on Raspberry Pi 5

This procedure installs CamillaDSP on a Raspberry Pi 5 for the RASPIAUDIO
8xIN + 8xOUT board. The recommended deployment is the global installation using
`/usr/local/bin`, `/etc/camilladsp`, and a system `camilladsp.service`.

## Prerequisites

```bash
sudo apt update
sudo apt install -y alsa-utils wget tar
```

Passwordless sudo is required for the global installation:

```bash
sudo -n true
```

If `sudo` is not available non-interactively, use the user-local installation as
a fallback and check that these tools are present:

```bash
command -v aplay arecord wget tar
```

## User-Local Staging Installation

From this repository:

```bash
./scripts/install_camilladsp_pi5.sh
```

The installer creates:

```text
~/camilladsp/bin/camilladsp
~/camilladsp/configs/
~/camilladsp/logs/
~/camilladsp/downloads/
```

Verify the installation:

```bash
~/camilladsp/bin/camilladsp --version
```

Tested version:

```text
CamillaDSP 4.1.3
```

## Global Installation

From this repository:

```bash
./scripts/install_camilladsp_global_pi5.sh
```

The global installer creates or updates:

```text
/usr/local/bin/camilladsp
/etc/camilladsp/8in_8out_passthrough.yml
/etc/camilladsp/8in_8out_gain_test.yml
/etc/systemd/system/camilladsp.service
/var/log/camilladsp/
```

Verify the global installation:

```bash
/usr/local/bin/camilladsp --version
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_passthrough.yml
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_gain_test.yml
```

## Copying the Configurations Manually

```bash
sudo install -d -m 0755 /etc/camilladsp
sudo install -m 0644 configs/*.yml /etc/camilladsp/
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_passthrough.yml
```

## Manual Startup

```bash
/usr/local/bin/camilladsp -v -l info /etc/camilladsp/8in_8out_passthrough.yml
```

Stop it with `Ctrl+C`.
