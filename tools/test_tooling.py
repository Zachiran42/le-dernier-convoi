#!/usr/bin/env python3
"""Offline supply-chain and false-success regression checks for the build tools."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parent / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fetch = load("fetch_godot", "fetch-godot.py")
runner = load("run_godot", "run-godot.py")


class BuildGuards(unittest.TestCase):
    def test_official_api_digest_cannot_silently_change(self):
        name = f"Godot_v{fetch.TAG}_linux.x86_64.zip"
        asset = {"name": name, "digest": "sha256:" + "0" * 64, "browser_download_url": f"https://github.com/godotengine/godot-builds/releases/download/{fetch.TAG}/{name}"}
        release = {"tag_name": fetch.TAG, "assets": [asset]}
        with self.assertRaisesRegex(ValueError, "digest changed"):
            fetch.release_asset(release, name)
        asset["digest"] = "sha256:" + fetch.ARCHIVE_SHA256[name]
        self.assertIs(fetch.release_asset(release, name), asset)
        release["prerelease"] = True
        with self.assertRaisesRegex(ValueError, "stable release"):
            fetch.release_asset(release, name)

    def test_extraction_is_an_exact_name_allowlist(self):
        with tempfile.TemporaryDirectory(prefix="convoi-build-guard-") as directory:
            root = Path(directory).resolve()
            archive = root / "test.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("templates/version.txt", "4.7.2.stable\n")
                output.writestr("../../unexpected.txt", "must never be extracted")
            target = root / "selected"
            result = fetch.extract_selected(archive, ["templates/version.txt"], target)
            self.assertEqual([item.name for item in target.iterdir()], ["version.txt"])
            self.assertEqual(result[0]["bytes"], 13)

    def test_crc_rejects_corrupted_entry_and_discards_partial(self):
        with tempfile.TemporaryDirectory(prefix="convoi-build-guard-") as directory:
            root = Path(directory).resolve()
            archive = root / "corrupt.zip"
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as output:
                output.writestr("templates/version.txt", "4.7.2.stable\n")
            contents = bytearray(archive.read_bytes())
            with zipfile.ZipFile(archive) as source:
                info = source.getinfo("templates/version.txt")
                offset = info.header_offset + 30 + len(info.filename.encode()) + len(info.extra)
            contents[offset] ^= 1
            archive.write_bytes(contents)
            with self.assertRaises(zipfile.BadZipFile):
                fetch.extract_selected(archive, ["templates/version.txt"], root / "selected")
            self.assertFalse((root / "selected/version.txt").exists())
            self.assertFalse((root / "selected/version.txt.partial").exists())

    def test_godot_zero_exit_parser_output_is_a_failure(self):
        self.assertTrue(runner.failed_output('Godot Engine\nSCRIPT ERROR: Parse Error: invalid type\n'))
        self.assertTrue(runner.failed_output('\x1b[31mERROR: Project export failed.\x1b[0m\n'))
        self.assertFalse(runner.failed_output('Godot Engine\nWARNING: harmless SDK fallback\nAll state tests passed\n'))


if __name__ == "__main__":
    unittest.main(verbosity=2)
