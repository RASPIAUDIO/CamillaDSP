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

Before publishing a release, stage the exact validated image into this bundle:

```bash
python3 image-builder/stage_public_release.py \
  --image ~/rpi-image-gen/work/deploy-v2.7.0/raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz \
  --raw-image ~/rpi-image-gen/work/image-raspiaudio-dspbox-pi5/raspiaudio-dspbox-pi5.img \
  --version YYYY.MM.DD
```

This updates `index.html`, `releases.json`, the SHA256 file and the Raspberry Pi
Imager repository JSON from the actual image artefact.

## Validate Before Uploading

From the repository root, run the draft check while the release image is still
missing:

```bash
python3 scripts/validate_public_camilladsp_box.py --allow-missing-downloads
```

Before uploading the page as a real public release, run the strict check:

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
python3 scripts/package_public_camilladsp_box.py
```

For the real public release after the image, SHA256 and Imager JSON are staged:

```bash
python3 scripts/package_public_camilladsp_box.py --strict
```

The appliance `Update system` button reads:

```text
https://raspiaudio.com/camilladsp-box/releases.json
```

The generated ZIP includes `PUBLISHING.txt` and `validation-results.json` so the
upload handoff shows the target URL, validation state and missing release files.

If a beta image needs another channel, write the URL to:

```text
/etc/raspiaudio/update-channel-url
```
