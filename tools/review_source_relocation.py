"""Report upstream changes relative to the current Flight SIL lock."""

import json
from pathlib import Path

from record_flight_baseline import digest


def main():
    root = Path(__file__).resolve().parents[1]
    baseline = json.loads((root / "config/flight_baseline.json").read_text())
    upstream = root / baseline["firmware_root"]
    expected = baseline["sources_sha256"]
    missing = [name for name in expected if not (upstream / name).is_file()]
    changed = [name for name, sha in expected.items()
               if (upstream / name).is_file() and digest(upstream / name) != sha]
    print(json.dumps({"checked": len(expected), "missing": missing, "changed": changed}, indent=2))
    return bool(missing or changed)


if __name__ == "__main__":
    raise SystemExit(main())
