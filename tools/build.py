#!/usr/bin/env python3
"""Build an openable Roblox place using the pinned genuine Rojo CLI."""
from pathlib import Path
import os
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    rojo = ROOT / ".tools/bin" / ("rojo.exe" if os.name == "nt" else "rojo")
    if not rojo.exists():
        raise SystemExit("Run python3 tools/setup.py first.")
    output = ROOT / "build/MailAMonster.rbxlx"
    output.parent.mkdir(exist_ok=True)
    subprocess.run([str(rojo), "build", "default.project.json", "--output", str(output)], cwd=ROOT, check=True)
    document = ET.parse(output)
    scripts = document.findall(".//Item[@class='Script']")
    clients = document.findall(".//Item[@class='LocalScript']")
    modules = document.findall(".//Item[@class='ModuleScript']")
    if not scripts or not clients:
        raise SystemExit("Build lacks a server Script or client LocalScript; check Bootstrap filenames.")
    print(f"Built {output.relative_to(ROOT)} ({output.stat().st_size:,} bytes; {len(scripts)} server scripts, {len(clients)} client scripts, {len(modules)} modules).")
    print("The archipelago is generated when Play starts in Roblox Studio.")


if __name__ == "__main__":
    main()
