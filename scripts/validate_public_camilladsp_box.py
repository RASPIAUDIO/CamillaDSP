#!/usr/bin/env python3
"""Validate the public RASPIAUDIO CamillaDSP Box page and release channel."""

from __future__ import annotations

import argparse
import hashlib
import html.parser
import json
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timezone


DEFAULT_PUBLIC_DIR = pathlib.Path("public/camilladsp-box")
DEFAULT_VERSION_FILE = pathlib.Path("appliance/VERSION")
REQUIRED_HTML_SNIPPETS = (
    "RASPIAUDIO CamillaDSP Box",
    "Download image",
    "raspberry-pi-imager-custom-image-windows.mp4",
    "Setup in 8 steps.",
    "Download diagnostics zip",
    "Technical documentation stays on GitHub",
    "http://raspiaudio.local",
)
REQUIRED_ASSETS = (
    "assets/raspiaudio-8xout-pi5-usb-wiring.png",
    "assets/raspberry-pi-imager-custom-image-windows.mp4",
    "assets/camilladsp-usb-7-1-meters.png",
    "assets/pi5-spdif-minimal-led-toslink.png",
)


class LinkParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []
        self.sources: list[str] = []
        self.step_classes = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        if "href" in values:
            self.links.append(values["href"])
        if "src" in values:
            self.sources.append(values["src"])
        classes = set(values.get("class", "").split())
        if "step" in classes:
            self.step_classes += 1


def sha256_file(path: pathlib.Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def read_expected_version(path: pathlib.Path) -> str:
    if not path.is_file():
        raise SystemExit(f"Version file not found: {path}")
    version = path.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}", version):
        raise SystemExit(f"Unexpected version format in {path}: {version!r}")
    return version


def read_json(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON: {path}: {exc}") from exc


def add(results: list[dict], key: str, ok: bool, message: str, evidence: str = "") -> None:
    results.append({"key": key, "ok": ok, "message": message, "evidence": evidence})


def add_local_file_check(
    results: list[dict],
    key: str,
    path: pathlib.Path,
    label: str,
    allow_missing: bool,
) -> None:
    exists = path.is_file()
    if exists:
        add(results, key, True, f"{label} exists locally", str(path))
    elif allow_missing:
        add(results, key, True, f"{label} is missing locally, allowed for draft validation", str(path))
    else:
        add(results, key, False, f"{label} exists locally", str(path))


def relative_url_path(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    return parsed.path.lstrip("/")


def strip_public_prefix(path: str) -> str:
    prefix = "camilladsp-box/"
    if path.startswith(prefix):
        return path[len(prefix) :]
    return path


def local_path_for_url(public_dir: pathlib.Path, url: str) -> pathlib.Path:
    path = strip_public_prefix(relative_url_path(url))
    return public_dir / urllib.parse.unquote(path)


def validate_local(args: argparse.Namespace, version: str) -> list[dict]:
    public_dir = pathlib.Path(args.public_dir)
    results: list[dict] = []
    index = public_dir / "index.html"
    release_json = public_dir / "releases.json"

    add(results, "public_dir", public_dir.is_dir(), f"Public directory: {public_dir}")
    add(results, "index_html", index.is_file(), "index.html exists")
    add(results, "releases_json", release_json.is_file(), "releases.json exists")
    if not index.is_file() or not release_json.is_file():
        return results

    html = index.read_text(encoding="utf-8")
    parser = LinkParser()
    parser.feed(html)

    for snippet in REQUIRED_HTML_SNIPPETS:
        add(
            results,
            f"html_snippet:{snippet[:28]}",
            snippet in html,
            f"HTML contains {snippet!r}",
        )
    add(results, "setup_steps", parser.step_classes == 8, "Public tutorial has exactly 8 visible setup steps", str(parser.step_classes))
    beginner_bad_phrases = (
        "enable ssh",
        "open ssh",
        "ssh ",
        "remote shell",
        "sudo ",
        "apt ",
        "git clone",
    )
    lower_html = html.lower()
    bad_matches = [phrase for phrase in beginner_bad_phrases if phrase in lower_html]
    add(
        results,
        "no_beginner_terminal_steps",
        not bad_matches,
        "Beginner page does not ask for SSH, sudo, apt or git clone",
        ", ".join(bad_matches),
    )

    for asset in REQUIRED_ASSETS:
        path = public_dir / asset
        add(results, f"asset:{asset}", path.is_file(), f"Required asset exists: {asset}", str(path))

    releases = read_json(release_json)
    latest = str(releases.get("latest_version", ""))
    add(results, "version_match", latest == version, "Release JSON version matches appliance/VERSION", f"{latest} vs {version}")
    add(results, "download_page", releases.get("download_page") == "https://raspiaudio.com/camilladsp-box", "Release JSON points to the public page")

    image_url = str(releases.get("image_url", ""))
    sha_url = str(releases.get("sha256_url", ""))
    imager_url = str(releases.get("imager_repository_url", ""))
    image_name = pathlib.Path(urllib.parse.urlparse(image_url).path).name
    sha_name = pathlib.Path(urllib.parse.urlparse(sha_url).path).name
    imager_name = pathlib.Path(urllib.parse.urlparse(imager_url).path).name
    expected_image_name = f"raspiaudio-dspbox-pi5-{version}.img.xz"
    expected_sha_name = f"{expected_image_name}.sha256"
    expected_imager_name = f"raspiaudio-imager-repository-{version}.json"

    add(results, "image_filename", image_name == expected_image_name, "Image filename matches release version", image_name)
    add(results, "sha_filename", sha_name == expected_sha_name, "SHA256 filename matches release version", sha_name)
    add(results, "imager_filename", imager_name == expected_imager_name, "Imager repository filename matches release version", imager_name)
    add(results, "download_link_in_html", f"downloads/{expected_image_name}" in html, "Download button points to the expected image")

    image_path = local_path_for_url(public_dir, image_url)
    sha_path = local_path_for_url(public_dir, sha_url)
    imager_path = local_path_for_url(public_dir, imager_url)
    missing_ok = bool(args.allow_missing_downloads)
    add_local_file_check(results, "image_file", image_path, "Release image file", missing_ok)
    add_local_file_check(results, "sha_file", sha_path, "Release SHA256 file", missing_ok)
    add_local_file_check(results, "imager_file", imager_path, "Raspberry Pi Imager repository JSON", missing_ok)

    if image_path.is_file() and sha_path.is_file():
        actual_sha = sha256_file(image_path)
        sha_text = sha_path.read_text(encoding="utf-8", errors="replace")
        add(results, "sha_matches_image", actual_sha in sha_text, "SHA256 file matches the release image", actual_sha)
    elif not missing_ok:
        add(results, "sha_matches_image", False, "Cannot verify SHA256 until image and .sha256 files exist")

    if imager_path.is_file():
        imager = read_json(imager_path)
        imager_text = json.dumps(imager)
        add(results, "imager_mentions_image", expected_image_name in imager_text, "Imager repository references the release image")

    return results


def fetch_url(url: str, timeout: int = 12) -> tuple[bool, int | None, str]:
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "RASPIAUDIO-release-validator/1.0"})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            return True, response.status, body
    except urllib.error.HTTPError as exc:
        return False, exc.code, exc.read().decode("utf-8", errors="replace")[:400]
    except Exception as exc:
        return False, None, str(exc)


def head_url(url: str, timeout: int = 12) -> tuple[bool, int | None, str]:
    try:
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "RASPIAUDIO-release-validator/1.0"})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return True, response.status, response.headers.get("Content-Length", "")
    except urllib.error.HTTPError as exc:
        return False, exc.code, ""
    except Exception as exc:
        return False, None, str(exc)


def validate_live(args: argparse.Namespace, version: str) -> list[dict]:
    base_url = str(args.base_url).rstrip("/") + "/"
    results: list[dict] = []
    ok, status, html = fetch_url(base_url)
    add(results, "live_index", ok and status == 200, "Live public page returns HTTP 200", f"{status}")
    if ok:
        add(results, "live_version_copy", "RASPIAUDIO CamillaDSP Box" in html, "Live page contains product name")
        add(results, "live_8_steps", html.count('class="step"') == 8, "Live page has 8 setup steps", str(html.count('class="step"')))

    release_url = urllib.parse.urljoin(base_url, "releases.json")
    ok, status, body = fetch_url(release_url)
    add(results, "live_releases_json", ok and status == 200, "Live release channel returns HTTP 200", f"{status}")
    releases = None
    if ok:
        try:
            releases = json.loads(body)
            add(results, "live_json_valid", True, "Live release channel is valid JSON")
        except json.JSONDecodeError as exc:
            add(results, "live_json_valid", False, f"Live release channel JSON is invalid: {exc}")
    if releases:
        latest = str(releases.get("latest_version", ""))
        add(results, "live_version_match", latest == version, "Live release version matches appliance/VERSION", f"{latest} vs {version}")
        for key in ("image_url", "sha256_url", "imager_repository_url"):
            url = str(releases.get(key, ""))
            ok, status, evidence = head_url(url)
            add(results, f"live_head:{key}", ok and status == 200, f"Live {key} returns HTTP 200", f"{status} {evidence}")

    return results


def make_package(args: argparse.Namespace, version: str, results: list[dict]) -> None:
    if not args.package:
        return
    failures = [item for item in results if not item["ok"]]
    if failures and not args.allow_package_with_failures:
        raise SystemExit("Refusing to package while validation has failures. Use --allow-package-with-failures for a draft package.")
    public_dir = pathlib.Path(args.public_dir)
    package = pathlib.Path(args.package)
    package.parent.mkdir(parents=True, exist_ok=True)
    missing_allowed = [
        item
        for item in results
        if item["ok"] and "missing locally, allowed for draft validation" in item["message"]
    ]
    manifest = {
        "product": "RASPIAUDIO CamillaDSP Box",
        "version": version,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "upload_target": "https://raspiaudio.com/camilladsp-box/",
        "strict_release_ready": not failures and not missing_allowed,
        "validation_results": results,
    }
    publishing_lines = [
        "RASPIAUDIO CamillaDSP Box public page package",
        f"Version: {version}",
        "Upload target: https://raspiaudio.com/camilladsp-box/",
        "",
        "Upload all files from this ZIP into the camilladsp-box folder on raspiaudio.com.",
        "After upload, verify with:",
        "python3 scripts/validate_public_camilladsp_box.py --base-url https://raspiaudio.com/camilladsp-box",
        "",
    ]
    if failures:
        publishing_lines.append("Status: NOT READY FOR PUBLIC RELEASE")
        publishing_lines.append("Blocking validation failures:")
        publishing_lines.extend(f"- {item['key']}: {item['message']} {item.get('evidence', '')}".rstrip() for item in failures)
    elif missing_allowed:
        publishing_lines.append("Status: DRAFT PACKAGE")
        publishing_lines.append("The public page is structurally valid, but these release files are still missing:")
        publishing_lines.extend(f"- {item['evidence']}" for item in missing_allowed)
    else:
        publishing_lines.append("Status: READY TO UPLOAD")
        publishing_lines.append("Local strict validation passed, including image, SHA256 and Imager JSON files.")
    publishing_text = "\n".join(publishing_lines) + "\n"
    with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in public_dir.rglob("*"):
            if path.is_file():
                zf.write(path, path.relative_to(public_dir))
        zf.writestr("PUBLISHING.txt", publishing_text)
        zf.writestr("validation-results.json", json.dumps(manifest, indent=2) + "\n")
    print(f"PACKAGED {package} for RASPIAUDIO CamillaDSP Box {version}")


def print_results(results: list[dict]) -> int:
    failed = 0
    for item in results:
        status = "OK" if item["ok"] else "FAIL"
        if not item["ok"]:
            failed += 1
        evidence = f" [{item['evidence']}]" if item.get("evidence") else ""
        print(f"{status} {item['key']}: {item['message']}{evidence}")
    if failed:
        print(f"\n{failed} check(s) failed.")
        return 1
    print("\nAll checks passed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-dir", default=str(DEFAULT_PUBLIC_DIR), help="Local public page directory.")
    parser.add_argument("--version-file", default=str(DEFAULT_VERSION_FILE), help="Appliance VERSION file.")
    parser.add_argument("--allow-missing-downloads", action="store_true", help="Allow local validation before the .img.xz, .sha256 and Imager JSON are copied in.")
    parser.add_argument("--base-url", help="Also validate the live deployed public page.")
    parser.add_argument("--package", help="Optional output zip path for the public page contents.")
    parser.add_argument("--allow-package-with-failures", action="store_true", help="Create the zip even when validation still has failures.")
    args = parser.parse_args()

    version = read_expected_version(pathlib.Path(args.version_file))
    results = validate_local(args, version)
    if args.base_url:
        results.extend(validate_live(args, version))
    make_package(args, version, results)
    return print_results(results)


if __name__ == "__main__":
    sys.exit(main())
