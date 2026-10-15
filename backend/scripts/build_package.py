"""Builds dist/neurolens-cpanel.zip: exactly what a cPanel host needs, and nothing from this machine.

    python backend/scripts/build_package.py

Layout inside the zip (unzip it into your home folder on the server):
    neurolens/backend/   the app, passenger_wsgi.py, requirements-cpanel.txt, scripts/smoke_test.py, scripts/prefetch_models.py
    neurolens/frontend/  the website
Left out on purpose: the virtualenv, backend/data (databases, accounts, keys, sessions), backend/eval, tests, the Flutter app, the
personal export zips, git history and every __pycache__."""

import hashlib
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "dist" / "neurolens-cpanel.zip"

BACKEND_FILES = ["passenger_wsgi.py", "requirements-cpanel.txt", "scripts/smoke_test.py", "scripts/prefetch_models.py"]


def add(z, src, arc):
    z.write(src, f"neurolens/{arc}")


def main():
    OUT.parent.mkdir(exist_ok=True)
    n = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in sorted((ROOT / "backend" / "neurolens").glob("*.py")):
            add(z, p, f"backend/neurolens/{p.name}"); n += 1
        for rel in BACKEND_FILES:
            add(z, ROOT / "backend" / rel, f"backend/{rel}"); n += 1
        for p in sorted((ROOT / "frontend").rglob("*")):
            rel = p.relative_to(ROOT / "frontend")
            if p.is_dir() or "tests" in rel.parts or "__pycache__" in rel.parts or p.suffix == ".map":
                continue
            add(z, p, f"frontend/{rel.as_posix()}"); n += 1
        z.writestr("neurolens/backend/data/.gitkeep", "")  # the app creates what it needs; NL_DATA_DIR normally points elsewhere
    digest = hashlib.sha256(OUT.read_bytes()).hexdigest()
    print(f"{OUT.relative_to(ROOT)}: {n} files, {OUT.stat().st_size / 1e6:.1f} MB, sha256 {digest[:16]}...")


if __name__ == "__main__":
    sys.exit(main())
