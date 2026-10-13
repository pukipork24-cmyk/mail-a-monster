#!/usr/bin/env python3
"""Install pinned upstream binaries locally, with published SHA256 verification."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".tools"


def main() -> None:
    machine = platform.machine().lower()
    arch = {"amd64": "x86_64", "arm64": "aarch64"}.get(machine, machine)
    target = platform.system().lower() + "-" + arch
    manifest = json.loads((ROOT / "tools/versions.json").read_text())
    (TOOLS / "downloads").mkdir(parents=True, exist_ok=True)
    (TOOLS / "bin").mkdir(parents=True, exist_ok=True)
    for name, spec in manifest.items():
        if target not in spec["assets"]:
            raise SystemExit(f"No pinned {name} binary for {target}. Use a supported Linux x86_64, macOS, or Windows x86_64 machine.")
        asset, expected = spec["assets"][target]
        archive = TOOLS / "downloads" / f"{spec['version']}-{asset}"
        if not archive.exists():
            url = f"https://github.com/{spec['repository']}/releases/download/{spec['tag']}/{asset}"
            temporary = archive.with_suffix(".download")
            print(f"Downloading {name} {spec['version']} from its official release…", flush=True)
            if shutil.which("curl"):
                subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2", "--proto", "=https", "--proto-redir", "=https", "--output", str(temporary), url], check=True)
            else:
                with urllib.request.urlopen(url, timeout=90) as source, temporary.open("wb") as dest:
                    shutil.copyfileobj(source, dest)
            temporary.replace(archive)
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f"Checksum mismatch for {archive.name}. Stop: no executable was installed. Remove this download and investigate the upstream release.")
        # Extract only known executables; archive paths cannot write outside bin.
        allowed = {"rojo"} if name == "rojo" else {"luau", "luau-analyze", "luau-compile", "luau-ast"}
        with zipfile.ZipFile(archive) as package:
            for member in package.infolist():
                filename = PurePosixPath(member.filename).name
                if member.is_dir() or filename.removesuffix(".exe") not in allowed:
                    continue
                destination = TOOLS / "bin" / filename
                destination.write_bytes(package.read(member))
                destination.chmod(0o755)
        print(f"Verified and installed {name} {spec['version']} ({target}).")
    print("Ready. Run python3 tools/check.py, then python3 tools/build.py.")


if __name__ == "__main__":
    main()
