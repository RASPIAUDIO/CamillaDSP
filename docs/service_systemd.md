# systemd Services

## Recommended System Service

The global installation provides this service:

```text
/etc/systemd/system/camilladsp.service
```

It runs CamillaDSP as user `ros` with the `audio` group and uses:

```text
/usr/local/bin/camilladsp
/etc/camilladsp/8in_8out_passthrough.yml
/var/log/camilladsp/camilladsp.log
```

Install or refresh it:

```bash
sudo install -m 0644 systemd/camilladsp.service /etc/systemd/system/camilladsp.service
sudo systemctl daemon-reload
```

Start, stop, and inspect it:

```bash
sudo systemctl start camilladsp.service
sudo systemctl status camilladsp.service
sudo journalctl -u camilladsp.service -f
sudo systemctl stop camilladsp.service
```

Enable automatic startup at boot:

```bash
sudo systemctl enable camilladsp.service
```

Disable automatic startup:

```bash
sudo systemctl disable camilladsp.service
```

## User Service Fallback

Copy the configuration and service:

```bash
mkdir -p ~/.config/systemd/user ~/camilladsp/configs ~/camilladsp/logs
cp configs/*.yml ~/camilladsp/configs/
cp systemd/camilladsp-user.service ~/.config/systemd/user/camilladsp.service
systemctl --user daemon-reload
systemctl --user enable camilladsp.service
systemctl --user start camilladsp.service
```

Check the service:

```bash
systemctl --user status camilladsp.service
journalctl --user -u camilladsp.service -f
tail -f ~/camilladsp/logs/camilladsp.log
```

To allow the user service to start without an interactive login session:

```bash
sudo loginctl enable-linger ros
```

The user service is no longer the preferred deployment, but it remains useful
when system-wide installation is not allowed.
