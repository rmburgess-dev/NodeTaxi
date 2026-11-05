#!/usr/bin/env python3
"""Build the CurseForge-ready zip.

Usage (from the addon folder):
    python3 tools/package.py

Creates dist/NodeTaxi-<version>.zip with a single top-level NodeTaxi/ folder.
Only runtime files, Media and the release docs are included; tests, tools,
docs, .git and .pkgmeta stay out.
"""
import hashlib
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
INCLUDE_ROOT_FILES = ("README.md", "CHANGELOG.md", "LICENSE", "ATTRIBUTION.md")


def read_version():
    toc = ROOT / "NodeTaxi.toc"
    match = re.search(r"^## Version:\s*(\S+)", toc.read_text(encoding="utf-8"), re.M)
    if not match:
        raise SystemExit("No ## Version in NodeTaxi.toc")
    return match.group(1)


def toc_entries():
    entries = []
    for line in (ROOT / "NodeTaxi.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("##"):
            continue
        entries.append(line.replace("\\", "/"))
    return entries


def collect():
    files = [ROOT / "NodeTaxi.toc"]
    files += sorted(p for p in ROOT.glob("*.lua") if p.is_file())
    files += sorted(p for p in (ROOT / "Media").rglob("*") if p.is_file())
    for name in INCLUDE_ROOT_FILES:
        path = ROOT / name
        if path.exists():
            files.append(path)

    # Make sure every file named in the TOC is actually packaged.
    packaged = {p.relative_to(ROOT).as_posix() for p in files}
    missing = [e for e in toc_entries() if e not in packaged]
    if missing:
        raise SystemExit("TOC references missing files: " + ", ".join(missing))

    return files


def main():
    version = read_version()
    DIST.mkdir(exist_ok=True)
    out = DIST / f"NodeTaxi-{version}.zip"

    files = collect()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in files:
            arcname = "NodeTaxi/" + path.relative_to(ROOT).as_posix()
            zf.write(path, arcname)

    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    print(f"{out} ({out.stat().st_size / 1024:.0f} KiB)")
    print(f"sha256 {digest}")
    print(f"{len(files)} files:")
    for path in files:
        print("  NodeTaxi/" + path.relative_to(ROOT).as_posix())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
