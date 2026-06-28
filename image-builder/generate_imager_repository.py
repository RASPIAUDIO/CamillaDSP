#!/usr/bin/env python3
"""Generate a Raspberry Pi Imager repository JSON for a release image."""

from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import os
import pathlib
import sys
from datetime import date


DEFAULT_NAME = "RASPIAUDIO CamillaDSP Box"
DEFAULT_DESCRIPTION = (
    "Open miniDSP-style appliance for Raspberry Pi 5 and RASPIAUDIO 8xOUT / "
    "8xIN+8xOUT. USB 7.1 audio, CamillaDSP, 8 analog outputs and optional "
    "TOSLINK."
)
DEFAULT_ICON = "https://raspiaudio.com/wp-content/uploads/2025/raspiaudio-icon.png"
DEFAULT_WEBSITE = "https://github.com/RASPIAUDIO/CamillaDSP"


def sha256_file(path: pathlib.Path, chunk_size: int = 1024 * 1024) -> tuple[int, str]:
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            total += len(chunk)
            digest.update(chunk)
    return total, digest.hexdigest()


def sha256_xz_payload(path: pathlib.Path, chunk_size: int = 1024 * 1024) -> tuple[int, str]:
    digest = hashlib.sha256()
    total = 0
    with lzma.open(path, "rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            total += len(chunk)
            digest.update(chunk)
    return total, digest.hexdigest()


def parse_size_hash(size: str | None, sha: str | None) -> tuple[int | None, str | None]:
    if size is None and sha is None:
        return None, None
    if size is None or sha is None:
        raise SystemExit("--extract-size and --extract-sha256 must be passed together")
    try:
        parsed_size = int(size)
    except ValueError as exc:
        raise SystemExit(f"Invalid --extract-size: {size}") from exc
    if len(sha) != 64 or any(char not in "0123456789abcdefABCDEF" for char in sha):
        raise SystemExit("--extract-sha256 must be a 64-character SHA256 hex digest")
    return parsed_size, sha.lower()


def build_repository(args: argparse.Namespace) -> dict:
    image = pathlib.Path(args.image).resolve()
    if not image.is_file():
        raise SystemExit(f"Image not found: {image}")

    download_size, download_sha = sha256_file(image)

    extract_size, extract_sha = parse_size_hash(args.extract_size, args.extract_sha256)
    if extract_size is None or extract_sha is None:
        if args.raw_image:
            raw_image = pathlib.Path(args.raw_image).resolve()
            if not raw_image.is_file():
                raise SystemExit(f"Raw image not found: {raw_image}")
            extract_size, extract_sha = sha256_file(raw_image)
        else:
            if image.suffix != ".xz" and not image.name.endswith(".img.xz"):
                raise SystemExit(
                    "Cannot infer extract hash for non-xz image. Pass --raw-image "
                    "or --extract-size plus --extract-sha256."
                )
            extract_size, extract_sha = sha256_xz_payload(image)

    devices = [item.strip() for item in args.devices.split(",") if item.strip()]
    if not devices:
        raise SystemExit("--devices cannot be empty")

    item = {
        "name": args.name,
        "description": args.description,
        "icon": args.icon,
        "website": args.website,
        "subitems_url": "",
        "release_date": args.release_date,
        "extract_size": extract_size,
        "extract_sha256": extract_sha,
        "image_download_size": download_size,
        "image_download_sha256": download_sha,
        "url": args.url,
        "devices": devices,
    }

    if args.init_format:
        item["init_format"] = args.init_format

    return {"os_list": [item]}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate Raspberry Pi Imager repository JSON for RASPIAUDIO images."
    )
    parser.add_argument("--image", required=True, help="Path to the .img.xz release image.")
    parser.add_argument("--url", required=True, help="Public download URL for the image.")
    parser.add_argument("--output", required=True, help="Output repository JSON path.")
    parser.add_argument("--raw-image", help="Optional raw .img path used for extract SHA/size.")
    parser.add_argument("--extract-size", help="Known uncompressed image size in bytes.")
    parser.add_argument("--extract-sha256", help="Known uncompressed image SHA256.")
    parser.add_argument("--release-date", default=date.today().isoformat())
    parser.add_argument("--name", default=DEFAULT_NAME)
    parser.add_argument("--description", default=DEFAULT_DESCRIPTION)
    parser.add_argument("--icon", default=DEFAULT_ICON)
    parser.add_argument("--website", default=DEFAULT_WEBSITE)
    parser.add_argument("--devices", default="pi5-64bit")
    parser.add_argument(
        "--init-format",
        default="none",
        help="Raspberry Pi Imager customization format. Use 'none' until first-boot customization is validated.",
    )
    args = parser.parse_args()

    repository = build_repository(args)
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(repository, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output}")
    print(json.dumps(repository["os_list"][0], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

