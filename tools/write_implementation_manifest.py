"""Publish a scoped Host SIL artifact inventory after all required evidence exists.

Plant/P-10 are intentionally PARTIAL in this delivery. The manifest must say so;
it must never relabel a partial Host SIL implementation as a complete PASS.
"""
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ENTRIES = ("FMT_DataSIM", "FMT_MILSIM", "FMT_ExtINS_DataSIM")
EXPECTED_STATUSES = {
    "input_preflight": "PASS",
    "flight_entries": "PASS",
    "cold_start_report": "PASS",
    "plant_open_loop_report": "PARTIAL",
    "component_checks": "PARTIAL_PASS",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_evidence(validation, name):
    path = validation / f"{name}.json"
    if not path.is_file():
        raise SystemExit(f"Required evidence is missing: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    expected = EXPECTED_STATUSES[name]
    actual = data.get("status")
    if actual != expected:
        raise SystemExit(
            f"Cannot publish manifest: {name}.status={actual!r}; expected {expected!r}"
        )
    return data


def require_gate(checks, name, expected="PASS"):
    gate = checks.get(name)
    if not isinstance(gate, dict) or gate.get("status") != expected:
        actual = gate.get("status") if isinstance(gate, dict) else None
        raise SystemExit(
            f"Cannot publish manifest: component gate {name}.status={actual!r}; "
            f"expected {expected!r}"
        )
    return gate


def main():
    validation = ROOT / "work/validation"
    evidence = {
        name: read_evidence(validation, name)
        for name in EXPECTED_STATUSES
    }

    plant = evidence["plant_open_loop_report"]
    if plant.get("implemented_gate_status") != "PASS":
        raise SystemExit("Cannot publish manifest: implemented Plant gates did not pass")
    if plant.get("coverage", {}).get("status") != "PARTIAL":
        raise SystemExit("Cannot publish manifest: Plant coverage boundary is not explicitly PARTIAL")

    component = evidence["component_checks"]
    checks = component.get("checks", {})
    require_gate(checks, "input_preflight")
    require_gate(checks, "m6_job_contract")
    require_gate(checks, "m6_jobs")
    require_gate(checks, "p10b_summary")
    require_gate(checks, "plant", "PARTIAL")
    if checks["plant"].get("implemented_gate_status") != "PASS":
        raise SystemExit("Cannot publish manifest: component report does not prove implemented Plant gates")

    firmware = validation / "firmware_sil.log"
    if not firmware.is_file():
        raise SystemExit(f"Required upstream Host SIL log is missing: {firmware}")
    match = re.search(
        r"sil_flight: (\d+) checks, 0 failures",
        firmware.read_text(encoding="utf-8-sig"),
    )
    if not match:
        raise SystemExit("Upstream Flight Host SIL evidence is missing or failed")

    source = json.loads((ROOT / "config/flight_baseline.json").read_text(encoding="utf-8"))
    artifacts = {}
    suffixes = {".m", ".c", ".h", ".py", ".ps1", ".json", ".yaml", ".sldd", ".slx", ".mat"}
    for folder in (
        "adapters", "config", "dictionaries", "interfaces", "models",
        "scenarios", "simulation", "tests", "tools",
    ):
        for path in sorted((ROOT / folder).rglob("*")):
            if path.is_file() and path.suffix in suffixes:
                artifacts[path.relative_to(ROOT).as_posix()] = sha(path)

    entry_paths = {name: f"simulation/{name}.slx" for name in ENTRIES}
    if not all(path in artifacts for path in entry_paths.values()):
        raise SystemExit("One or more final Simulink entry models are missing from the artifact inventory")
    if "scenarios/flight_sil_recording.mat" not in artifacts:
        raise SystemExit("The current Flight SIL replay recording is missing from the artifact inventory")

    manifest = {
        "schema": "flight-matlab-implementation/3",
        "status": "PARTIAL_PASS_HOST_SIL",
        "host_sil_acceptance_status": "PARTIAL_PASS",
        "plant_status": "PARTIAL",
        "p10_status": "PARTIAL",
        "hardware_validation_status": "NOT_RUN",
        "implementation": source["implementation"],
        "three_final_entries_complete": True,
        "firmware_equivalent": False,
        "contract_schema": source["contract_schema"],
        "product_contract_revision": source["product_contract_revision"],
        "upstream_source_count": len(source["sources_sha256"]),
        "upstream_sil_checks_passed": int(match[1]),
        "final_entries": entry_paths,
        "evidence_statuses": {
            name: data.get("status") for name, data in evidence.items()
        },
        "evidence": evidence,
        "artifacts_sha256": artifacts,
        "scope": (
            "Windows Host SIL; synthetic quadrotor, sensor and replay fixtures. "
            "Plant/P-10 coverage remains PARTIAL. No STM32 target timing, raw sensor "
            "acquisition, physical PPS, UART/DMA board path, physical motors, HIL "
            "transport or real-flight evidence."
        ),
    }
    target = ROOT / "implementation_manifest.json"
    target.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"{manifest['status']}: {target}")


if __name__ == "__main__":
    main()
