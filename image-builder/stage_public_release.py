#!/usr/bin/env python3
"""Stage a validated appliance image into the public download bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
from datetime import date


REPO_DIR = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_PUBLIC_DIR = REPO_DIR / "public" / "camilladsp-box"
DEFAULT_VERSION_FILE = REPO_DIR / "appliance" / "VERSION"
DEFAULT_BASE_URL = "https://raspiaudio.com/camilladsp-box"


def sha256_file(path: pathlib.Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def read_version(path: pathlib.Path, override: str | None) -> str:
    version = override or path.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}", version):
        raise SystemExit(f"Invalid release version: {version!r}")
    return version


def copy_file(src: pathlib.Path, dst: pathlib.Path) -> None:
    src = src.resolve()
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and src == dst.resolve():
        return
    shutil.copy2(src, dst)


def update_index_download_link(index_path: pathlib.Path, image_name: str) -> None:
    html = index_path.read_text(encoding="utf-8")
    updated = re.sub(
        r"downloads/raspiaudio-dspbox-pi5-\d{4}\.\d{2}\.\d{2}\.img\.xz",
        f"downloads/{image_name}",
        html,
    )
    if updated != html:
        index_path.write_text(updated, encoding="utf-8")


def update_releases_json(
    release_path: pathlib.Path,
    *,
    version: str,
    release_date: str,
    base_url: str,
    image_name: str,
    sha_name: str,
    imager_name: str,
) -> None:
    payload = json.loads(release_path.read_text(encoding="utf-8"))
    base = base_url.rstrip("/")
    payload.update(
        {
            "product": "RASPIAUDIO CamillaDSP Box",
            "latest_version": version,
            "release_date": release_date,
            "download_page": base,
            "image_url": f"{base}/downloads/{image_name}",
            "sha256_url": f"{base}/downloads/{sha_name}",
            "imager_repository_url": f"{base}/{imager_name}",
        }
    )
    release_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def generate_imager_json(
    *,
    image: pathlib.Path,
    raw_image: pathlib.Path | None,
    output: pathlib.Path,
    url: str,
    release_date: str,
    base_url: str,
) -> None:
    generator = REPO_DIR / "image-builder" / "generate_imager_repository.py"
    cmd = [
        sys.executable,
        str(generator),
        "--image",
        str(image),
        "--url",
        url,
        "--output",
        str(output),
        "--release-date",
        release_date,
        "--website",
        base_url.rstrip("/"),
        "--quiet",
    ]
    if raw_image:
        cmd.extend(["--raw-image", str(raw_image)])
    subprocess.run(cmd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True, help="Validated .img.xz release image.")
    parser.add_argument("--raw-image", help="Optional raw .img file for faster exact Imager extract hash.")
    parser.add_argument("--imager-json", help="Optional pre-generated Raspberry Pi Imager repository JSON.")
    parser.add_argument("--public-dir", default=str(DEFAULT_PUBLIC_DIR))
    parser.add_argument("--version-file", default=str(DEFAULT_VERSION_FILE))
    parser.add_argument("--version", help="Release version. Defaults to appliance/VERSION.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--release-date", default=date.today().isoformat())
    parser.add_argument("--skip-validation", action="store_true")
    args = parser.parse_args()

    version = read_version(pathlib.Path(args.version_file), args.version)
    image_src = pathlib.Path(args.image)
    if not image_src.is_file():
        raise SystemExit(f"Image not found: {image_src}")
    if not image_src.name.endswith(".img.xz"):
        raise SystemExit("Expected a Raspberry Pi Imager .img.xz image")

    public_dir = pathlib.Path(args.public_dir)
    downloads_dir = public_dir / "downloads"
    image_name = f"raspiaudio-dspbox-pi5-{version}.img.xz"
    sha_name = f"{image_name}.sha256"
    imager_name = f"raspiaudio-imager-repository-{version}.json"
    image_dst = downloads_dir / image_name
    sha_dst = downloads_dir / sha_name
    imager_dst = public_dir / imager_name

    copy_file(image_src, image_dst)
    image_sha = sha256_file(image_dst)
    sha_dst.write_text(f"{image_sha}  {image_name}\n", encoding="utf-8")

    if args.imager_json:
        copy_file(pathlib.Path(args.imager_json), imager_dst)
    else:
        raw_image = pathlib.Path(args.raw_image) if args.raw_image else None
        if raw_image and not raw_image.is_file():
            raise SystemExit(f"Raw image not found: {raw_image}")
        generate_imager_json(
            image=image_dst,
            raw_image=raw_image,
            output=imager_dst,
            url=f"{args.base_url.rstrip('/')}/downloads/{image_name}",
            release_date=args.release_date,
            base_url=args.base_url,
        )

    update_releases_json(
        public_dir / "releases.json",
        version=version,
        release_date=args.release_date,
        base_url=args.base_url,
        image_name=image_name,
        sha_name=sha_name,
        imager_name=imager_name,
    )
    update_index_download_link(public_dir / "index.html", image_name)

    print("Staged public release:")
    print(f"  image: {image_dst}")
    print(f"  sha256: {sha_dst}")
    print(f"  imager: {imager_dst}")
    print(f"  release channel: {public_dir / 'releases.json'}")

    if not args.skip_validation:
        print()
        print("Validating staged public release...")
        sys.stdout.flush()
        subprocess.run(
            [
                sys.executable,
                str(REPO_DIR / "scripts" / "validate_public_camilladsp_box.py"),
                "--public-dir",
                str(public_dir),
                "--version-file",
                str(pathlib.Path(args.version_file)),
            ],
            check=True,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
