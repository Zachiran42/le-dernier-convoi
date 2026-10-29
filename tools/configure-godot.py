#!/usr/bin/env python3
"""Configure this portable Godot installation without changing global settings."""
import argparse
import json
from pathlib import Path
import re


def configure(executable, java_sdk, android_sdk, keystore, disable_safe_save=False):
    executable = Path(executable).resolve(strict=True)
    java_sdk = Path(java_sdk).resolve(strict=True)
    android_sdk = Path(android_sdk).resolve(strict=True)
    keystore = Path(keystore).resolve(strict=True)
    editor = executable.parent
    (editor / "_sc_").touch()
    editor_data = editor / "editor_data"
    editor_data.mkdir(parents=True, exist_ok=True)
    settings = editor_data / "editor_settings-4.7.tres"
    text = settings.read_text(encoding="utf-8") if settings.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    values = {
        "export/android/java_sdk_path": java_sdk.as_posix(),
        "export/android/android_sdk_path": android_sdk.as_posix(),
        "export/android/debug_keystore": keystore.as_posix(),
        "export/android/debug_keystore_user": "androiddebugkey",
        "export/android/debug_keystore_pass": "android",
    }
    for name, value in values.items():
        line = f"{name} = {json.dumps(value, ensure_ascii=False)}"
        pattern = rf"(?m)^{re.escape(name)}\s*=.*$"
        text = re.sub(pattern, lambda match: line, text) if re.search(pattern, text) else text.rstrip() + "\n" + line + "\n"
    if disable_safe_save:
        name = "filesystem/on_save/safe_save_on_backup_then_rename"
        pattern = rf"(?m)^{re.escape(name)}\s*=.*$"
        line = name + " = false"
        text = re.sub(pattern, lambda match: line, text) if re.search(pattern, text) else text.rstrip() + "\n" + line + "\n"
    settings.write_text(text, encoding="utf-8")
    print(f"Portable editor settings: {settings}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--java-sdk", required=True)
    parser.add_argument("--android-sdk", required=True)
    parser.add_argument("--keystore", required=True)
    parser.add_argument("--disable-safe-save", action="store_true", help="Local Windows sandbox workaround; affects only this portable installation")
    options = parser.parse_args()
    configure(options.executable, options.java_sdk, options.android_sdk, options.keystore, options.disable_safe_save)
