#!/usr/bin/env python3
"""Create the upload ZIP for the public CamillaDSP Box page."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "appliance" / "VERSION"
VALIDATOR = ROOT / "scripts" / "validate_public_camilladsp_box.py"


def read_version() -> str:
    version = VERSION_FILE.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}", version):
        raise SystemExit(f"Unexpected version format in {VERSION_FILE}: {version!r}")
    return version


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Require the image, SHA256 and Raspberry Pi Imager JSON to exist before packaging.",
    )
    parser.add_argument(
        "--base-url",
        help="Also validate an already uploaded public page, for example https://raspiaudio.com/camilladsp-box.",
    )
    parser.add_argument(
        "--package",
        help="Output ZIP path. Defaults to artifacts/camilladsp-box-public-draft-VERSION.zip or public-VERSION.zip.",
    )
    args = parser.parse_args()

    version = read_version()
    package = pathlib.Path(args.package) if args.package else None
    if package is None:
        suffix = "public" if args.strict else "public-draft"
        package = ROOT / "artifacts" / f"camilladsp-box-{suffix}-{version}.zip"

    command = [
        sys.executable,
        str(VALIDATOR),
        "--package",
        str(package),
    ]
    if not args.strict:
        command.extend(["--allow-missing-downloads", "--allow-package-with-failures"])
    if args.base_url:
        command.extend(["--base-url", args.base_url])

    print("Packaging RASPIAUDIO CamillaDSP Box public page", flush=True)
    print(f"Version: {version}", flush=True)
    print(f"Mode: {'strict public release' if args.strict else 'draft without image files'}", flush=True)
    print(f"Output: {package}", flush=True)
    print(flush=True)

    result = subprocess.run(command, cwd=ROOT, check=False)
    if result.returncode != 0:
        return result.returncode

    print()
    print("Package created.")
    print(f"Upload ZIP contents to: https://raspiaudio.com/camilladsp-box/")
    print("After upload, verify with:")
    print("python3 scripts/validate_public_camilladsp_box.py --base-url https://raspiaudio.com/camilladsp-box")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
