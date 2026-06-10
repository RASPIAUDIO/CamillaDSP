# CamillaGUI Installation

CamillaGUI is the web interface for CamillaDSP. It is useful for editing
configuration files, selecting the active configuration, checking levels, and
controlling a running CamillaDSP process from a browser.

This repository uses the official bundled `camillagui-backend` release. The
bundle includes the backend server, the React frontend, and its Python runtime.

## Prerequisites

Install CamillaDSP first:

```bash
./scripts/install_camilladsp_global_pi5.sh
```

The installer uses `sudo` and will ask for the user's password if needed.

The CamillaDSP system service must expose its websocket API for live GUI
control. The service shipped in this repository starts CamillaDSP with:

```text
-w -p 1234 -s /var/lib/camilladsp/statefile.yml
```

The GUI can still open and edit configuration files when CamillaDSP is stopped,
but live status, volume, and apply/reload actions require CamillaDSP to be
running.

## Quick Install

From this repository on the Raspberry Pi:

```bash
./scripts/install_camillagui_pi5.sh
```

If the Linux user is not the current shell user, set it explicitly:

```bash
CAMILLA_USER=rosco ./scripts/install_camillagui_pi5.sh
```

The installer creates or updates:

```text
/opt/camillagui-backend-v4.1.0
/opt/camillagui-backend
/etc/systemd/system/camillagui.service
/var/lib/camilladsp/statefile.yml
```

It also writes the CamillaGUI configuration to:

```text
/opt/camillagui-backend/_internal/config/camillagui.yml
```

## Open the GUI

After installation, open:

```text
http://<raspberry-pi-ip>:5005/gui/index.html
```

For example:

```text
http://192.168.1.154:5005/gui/index.html
```

## Services

Start the GUI:

```bash
sudo systemctl start camillagui.service
```

Check the GUI:

```bash
sudo systemctl status camillagui.service
curl -I http://127.0.0.1:5005/gui/index.html
```

Enable the GUI at boot:

```bash
sudo systemctl enable camillagui.service
```

Start CamillaDSP for live GUI control:

```bash
sudo systemctl start camilladsp.service
```

Check that both ports are listening:

```bash
ss -ltnp | grep -E ':5005|:1234'
```

Expected ports:

```text
5005  CamillaGUI web interface
1234  CamillaDSP websocket API
```

## Configuration Directories

By default the GUI edits files from this repository:

```text
configs/
coeffs/
```

Override these locations if needed:

```bash
CAMILLA_CONFIG_DIR=/home/rosco/myCamillaDSP/configs \
CAMILLA_COEFF_DIR=/home/rosco/myCamillaDSP/coeffs \
./scripts/install_camillagui_pi5.sh
```

## Security Note

The default GUI configuration binds to `0.0.0.0` so it is reachable from another
computer on the local network. There is no authentication in front of the GUI by
default, so do not expose port `5005` to the internet.

## Loopback Warning

If outputs are physically connected back to inputs for latency or loopback
testing, avoid starting a passthrough CamillaDSP configuration at high volume.
Disconnect the loopback cables or use a safe gain-limited test configuration.

## Troubleshooting

If the browser opens but cannot connect to CamillaDSP, check that the DSP service
is running with websocket support:

```bash
sudo systemctl status camilladsp.service
sudo journalctl -u camilladsp.service -n 100 --no-pager
```

If the GUI is not reachable from another machine:

```bash
sudo systemctl status camillagui.service
sudo journalctl -u camillagui.service -n 100 --no-pager
ss -ltnp | grep 5005
```
