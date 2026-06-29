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

## Validate Before Uploading

From the repository root, run the draft check while the release image is still
missing:

```bash
python3 scripts/validate_public_camilladsp_box.py --allow-missing-downloads
```

Before uploading the page as a real public release, copy the generated image,
SHA256 file and Raspberry Pi Imager repository JSON into this folder, then run
the strict check:

```bash
python3 scripts/validate_public_camilladsp_box.py
```

After uploading to `raspiaudio.com`, verify the live page and release channel:

```bash
python3 scripts/validate_public_camilladsp_box.py \
  --base-url https://raspiaudio.com/camilladsp-box
```

For a draft handoff zip before the final image exists:

```bash
python3 scripts/validate_public_camilladsp_box.py \
  --allow-missing-downloads \
  --package artifacts/camilladsp-box-public-draft.zip \
  --allow-package-with-failures
```

The appliance `Update system` button reads:

```text
https://raspiaudio.com/camilladsp-box/releases.json
```

If a beta image needs another channel, write the URL to:

```text
/etc/raspiaudio/update-channel-url
```
