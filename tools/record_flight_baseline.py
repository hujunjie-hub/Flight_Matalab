"""Record the effective firmware inputs and replay ABI used by the host DLL."""

import ctypes
import hashlib
import json
from pathlib import Path
import re
import sys


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def define(path, name):
    return int(re.search(rf"^#define\s+{name}\s+(\w+?)u?\s", path.read_text(), re.M)[1], 0)


def main(project, flight, build, dll):
    version = flight / "middleware/contracts/base_types/contract_version.h"
    product = flight / "middleware/contracts/product_contract/product_contract.h"
    paths = [flight / name for name in ("SConstruct", ".config") if (flight / name).is_file()]
    for folder in ("config", "applications", "middleware", "sensor_device", "board",
                   "libraries/HAL_Drivers/drivers", "tests/runtime/stubs", "tests/simulation",
                   "tests/time"):
        paths.extend(p for p in (flight / folder).rglob("*")
                     if p.is_file() and p.suffix in {".h", ".hpp", ".c", ".cpp", ".yaml", ".ps1"})
    lib = ctypes.CDLL(str(dll))
    lib.fmt_flight_nav_width.restype = ctypes.c_uint
    manifest = {
        "schema": "flight-matlab-firmware-sil/1",
        "firmware_root": "../Flight",
        "implementation": "FLIGHT_FIRMWARE_HOST_SIL",
        "contract_schema": [define(version, "CONTRACT_SCHEMA_MAJOR"),
                            define(version, "CONTRACT_SCHEMA_MINOR")],
        "product_contract_revision": f"{define(product, 'PRODUCT_CONTRACT_REVISION'):#010x}",
        "navigation_frame_bytes": lib.fmt_flight_nav_width(),
        "sources_sha256": {p.relative_to(flight).as_posix(): digest(p)
                           for p in sorted(set(paths))},
    }
    (project / "config/flight_baseline.json").write_text(json.dumps(manifest, indent=2) + "\n")
    report = project / "work/validation"
    report.mkdir(parents=True, exist_ok=True)
    (report / "firmware_sil.log").write_bytes((build / "sil_flight.log").read_bytes())
    print(f"Flight baseline {manifest['product_contract_revision']}, "
          f"navigation frame {manifest['navigation_frame_bytes']} bytes, {len(paths)} inputs")


if __name__ == "__main__":
    main(*(Path(arg) for arg in sys.argv[1:]))

