#!/usr/bin/env python3
"""Compile all Luau sources and execute the deterministic CLI test suites."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / ".tools/bin"


def executable(name: str) -> str:
    path = BIN / (name + (".exe" if os.name == "nt" else ""))
    if not path.exists():
        raise SystemExit("Run python3 tools/setup.py first.")
    return str(path)


def main() -> None:
    sources = sorted({p for folder in ("src", "tests") for p in (ROOT / folder).rglob("*") if p.suffix in (".lua", ".luau")})
    if not sources:
        raise SystemExit("No Luau files found.")
    failures = []
    for source in sources:
        result = subprocess.run([executable("luau-compile"), "--binary", str(source)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        if result.returncode:
            failures.append(source)
            print(result.stderr)
    if failures:
        raise SystemExit(f"FAIL: {len(failures)} Luau files did not compile.")
    print(f"PASS: Luau compilation ({len(sources)} files).", flush=True)
    suites = sorted((ROOT / "tests").glob("*.luau"))
    if not suites:
        raise SystemExit("No executable tests/*.luau test suites found.")
    for suite in suites:
        print(f"Running {suite.relative_to(ROOT)}", flush=True)
        subprocess.run([executable("luau"), str(suite.relative_to(ROOT))], cwd=ROOT, check=True)
    print("PASS: executable CLI test suites. Studio and Roblox live-service checks remain separate.")


if __name__ == "__main__":
    main()
