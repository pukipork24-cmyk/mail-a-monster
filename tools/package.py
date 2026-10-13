#!/usr/bin/env python3
"""Package complete source and the built place for a downloadable handoff."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    place = ROOT / "build/MailAMonster.rbxlx"
    if not place.exists():
        raise SystemExit("Run python3 tools/build.py first.")
    output = ROOT / "build/MailAMonster-source.zip"
    paths = [ROOT / p for p in ("README.md", ".gitattributes", ".gitignore", "default.project.json", "rokit.toml")]
    for folder in ("src", "tests", "docs", "tools"):
        paths.extend(p for p in (ROOT / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc")
    paths.append(place)
    # Stable archive metadata makes packaging reproducible for unchanged files.
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(set(paths)):
            if not path.exists():
                raise SystemExit(f"Missing delivery file: {path.relative_to(ROOT)}")
            info = zipfile.ZipInfo("MailAMonster/" + path.relative_to(ROOT).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())
    print(f"Packaged {len(paths)} files: {output.relative_to(ROOT)} ({output.stat().st_size:,} bytes).")


if __name__ == "__main__":
    main()
