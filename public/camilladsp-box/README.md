# RASPIAUDIO CamillaDSP Box Public Page

Publish this directory as:

```text
https://raspiaudio.com/camilladsp-box/
```

Upload all files in this folder, including:

- `index.html`
- `releases.json`
- `assets/`
- `downloads/raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz`
- `downloads/raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz.sha256`
- `raspiaudio-imager-repository-YYYY.MM.DD.json`

Before publishing a release, replace the placeholder URLs in `index.html` and
`releases.json` with the exact validated image filename and SHA256 file.

The appliance `Update system` button reads:

```text
https://raspiaudio.com/camilladsp-box/releases.json
```

If a beta image needs another channel, write the URL to:

```text
/etc/raspiaudio/update-channel-url
```
