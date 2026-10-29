#!/usr/bin/env python3
"""Install the pinned official Godot editor and only Android/Web export files.

No third-party Python packages. The release API digest must match the lock below;
every downloaded archive is hashed before selected ZIP entries are read with CRC
validation. No engine binary is run by this installer.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import sys
import time
import urllib.request
import zipfile

VERSION = "4.7.2"
TAG = f"{VERSION}-stable"
TEMPLATE_VERSION = f"{VERSION}.stable"
API_URL = f"https://api.github.com/repos/godotengine/godot-builds/releases/tags/{TAG}"
# Locked from the official release API, checked 2026-10-29.
ARCHIVE_SHA256 = {
    f"Godot_v{TAG}_linux.x86_64.zip": "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4",
    f"Godot_v{TAG}_win64.exe.zip": "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953",
    f"Godot_v{TAG}_export_templates.tpz": "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011",
}
TEMPLATE_FILES = (
    "version.txt", "android_debug.apk", "android_release.apk",
    "web_nothreads_debug.zip", "web_nothreads_release.zip",
)


def file_digest(file):
    digest = hashlib.sha256()
    with Path(file).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def request(url, api=False):
    headers = {"User-Agent": "Le-Dernier-Convoi-reproducible-build", "Accept": "application/vnd.github+json" if api else "application/octet-stream"}
    token = os.environ.get("GITHUB_TOKEN")
    if api and token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120)


def release_asset(release, name):
    if release.get("tag_name") != TAG or release.get("draft") or release.get("prerelease"):
        raise ValueError("The official API did not return the required stable release.")
    matches = [item for item in release.get("assets", []) if item.get("name") == name]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one official release asset: {name}")
    asset = matches[0]
    expected = ARCHIVE_SHA256[name]
    if asset.get("digest") != f"sha256:{expected}":
        raise ValueError(f"Official API digest changed or is unavailable for {name}; review the lock before upgrading.")
    expected_url = f"https://github.com/godotengine/godot-builds/releases/download/{TAG}/{name}"
    if asset.get("browser_download_url") != expected_url:
        raise ValueError("Unexpected release download URL.")
    return asset


def download(asset, directory):
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / asset["name"]
    expected = ARCHIVE_SHA256[asset["name"]]
    if target.is_file() and target.stat().st_size == asset["size"] and file_digest(target) == expected:
        print(f"Verified cached archive: {target.name}", flush=True)
        return target
    partial = target.with_suffix(target.suffix + ".part")
    for attempt in range(1, 4):
        try:
            print(f"Downloading {asset['name']} ({asset['size']:,} bytes)", flush=True)
            with request(asset["browser_download_url"]) as response, partial.open("wb") as output:
                shutil.copyfileobj(response, output, 1024 * 1024)
            if partial.stat().st_size != asset["size"] or file_digest(partial) != expected:
                raise ValueError(f"Size/SHA256 validation failed: {asset['name']}")
            partial.replace(target)
            return target
        except Exception:
            partial.unlink(missing_ok=True)
            if attempt == 3:
                raise
            time.sleep(attempt * 2)
    raise RuntimeError("Unreachable download state.")


def extract_selected(archive, entries, destination):
    """Exact-name allowlist, flat destinations, CRC checked by ZipExtFile reads."""
    destination.mkdir(parents=True, exist_ok=True)
    extracted = []
    with zipfile.ZipFile(archive) as source:
        for archive_name in entries:
            info = source.getinfo(archive_name)
            if info.is_dir() or info.flag_bits & 1:
                raise ValueError(f"Unexpected directory/encrypted entry: {archive_name}")
            name = Path(archive_name).name
            target = destination / name
            temporary = destination / (name + ".partial")
            try:
                with source.open(info) as input_stream, temporary.open("wb") as output:
                    shutil.copyfileobj(input_stream, output, 1024 * 1024)
                if temporary.stat().st_size != info.file_size:
                    raise ValueError(f"Incomplete extracted file: {name}")
                temporary.replace(target)
            finally:
                temporary.unlink(missing_ok=True)
            extracted.append({"name": name, "bytes": info.file_size, "crc32": f"{info.CRC:08x}", "sha256": file_digest(target)})
    return extracted


def install(destination, operating_system):
    with request(API_URL, api=True) as response:
        release = json.load(response)
    platform_slug = "linux.x86_64.zip" if operating_system == "linux" else "win64.exe.zip"
    editor_name = f"Godot_v{TAG}_{platform_slug}"
    editor_asset = release_asset(release, editor_name)
    template_asset = release_asset(release, f"Godot_v{TAG}_export_templates.tpz")
    editor_archive = download(editor_asset, destination / "downloads")
    template_archive = download(template_asset, destination / "downloads")
    editor_directory = destination / "editor"
    if operating_system == "linux":
        editor_entries = [f"Godot_v{TAG}_linux.x86_64"]
        executable_name = editor_entries[0]
    else:
        editor_entries = [f"Godot_v{TAG}_win64.exe", f"Godot_v{TAG}_win64_console.exe"]
        executable_name = editor_entries[1]
    editors = extract_selected(editor_archive, editor_entries, editor_directory)
    executable = editor_directory / executable_name
    if operating_system == "linux":
        executable.chmod(0o755)
    (editor_directory / "_sc_").touch()
    template_directory = editor_directory / "editor_data" / "export_templates" / TEMPLATE_VERSION
    templates = extract_selected(template_archive, ["templates/" + name for name in TEMPLATE_FILES], template_directory)
    if (template_directory / "version.txt").read_text().strip() != TEMPLATE_VERSION:
        raise ValueError("Export templates and editor versions differ.")
    result = {
        "version": TEMPLATE_VERSION, "release": release["html_url"],
        "executable": str(executable), "editor_data": str(editor_directory / "editor_data"),
        "archives": [{"name": asset["name"], "bytes": asset["size"], "sha256": ARCHIVE_SHA256[asset["name"]]} for asset in (editor_asset, template_asset)],
        "editor_files": editors, "templates": templates,
    }
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "install.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Installed official Godot {TEMPLATE_VERSION}: {executable}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path("build/toolchain/godot"))
    parser.add_argument("--platform", choices=("linux", "windows"), default="windows" if platform.system() == "Windows" else "linux")
    args = parser.parse_args()
    install(args.destination.resolve(), args.platform)


if __name__ == "__main__":
    main()
