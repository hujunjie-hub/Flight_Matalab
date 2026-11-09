"""Publish the firmware-backed Simulink artifact inventory and scoped evidence."""

import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ENTRIES = ("FMT_DataSIM", "FMT_MILSIM", "FMT_ExtINS_DataSIM")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    validation = ROOT / "work/validation"
    evidence = {}
    for name in ("input_preflight", "flight_entries", "cold_start_report",
                 "plant_open_loop_report", "component_checks"):
        path = validation / f"{name}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        assert data["status"] == "PASS", f"Cannot publish failed evidence: {name}"
        evidence[name] = data
    firmware = validation / "firmware_sil.log"
    checks = re.search(r"sil_flight: (\d+) checks, 0 failures", firmware.read_text(encoding="utf-8-sig"))
    assert checks, "Upstream Flight Host SIL evidence is missing or failed"
    source = json.loads((ROOT / "config/flight_baseline.json").read_text())
    artifacts = {}
    suffixes = {".m", ".c", ".h", ".py", ".ps1", ".json", ".yaml", ".sldd", ".slx", ".mat"}
    for folder in ("adapters", "config", "dictionaries", "interfaces", "models",
                   "scenarios", "simulation", "tests", "tools"):
        for path in sorted((ROOT / folder).rglob("*")):
            if path.is_file() and path.suffix in suffixes:
                artifacts[path.relative_to(ROOT).as_posix()] = sha(path)
    entry_paths = {name: f"simulation/{name}.slx" for name in ENTRIES}
    assert all(path in artifacts for path in entry_paths.values())
    assert "scenarios/flight_sil_recording.mat" in artifacts
    manifest = {
        "schema": "flight-matlab-implementation/2",
        "status": "PASS_HOST_SIL",
        "implementation": source["implementation"],
        "three_final_entries_complete": True,
        "firmware_equivalent": False,
        "contract_schema": source["contract_schema"],
        "product_contract_revision": source["product_contract_revision"],
        "upstream_source_count": len(source["sources_sha256"]),
        "upstream_sil_checks_passed": int(checks[1]),
        "final_entries": entry_paths,
        "evidence": evidence,
        "artifacts_sha256": artifacts,
        "scope": "Windows Host SIL; synthetic quadrotor, sensor and replay fixtures. "
                 "No STM32 target timing, raw sensor acquisition, PPS, physical motors, "
                 "HIL transport or real-flight evidence.",
    }
    target = ROOT / "implementation_manifest.json"
    target.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"{manifest['status']}: {target}")


if __name__ == "__main__":
    main()

