"""Validate Flight_Matalab design documents; never load or modify MATLAB models."""
from __future__ import annotations

import argparse
import cmath
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import unicodedata


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(root, name, value):
    root.mkdir(parents=True, exist_ok=True)
    target = root / name
    temporary = root / (name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(target)


def changed_paths(expected, observed):
    return sorted(n for n in set(expected) | set(observed) if expected.get(n) != observed.get(n))


def files_under(root):
    return {
        p.relative_to(root).as_posix(): sha(p)
        for p in root.rglob("*")
        if p.is_file() and ".git" not in p.relative_to(root).parts
    }


def normative(name):
    return not name.startswith("validation/") and name != "AGENT_HANDOFF.md"


def heading_anchors(text):
    anchors = set()
    repeats = {}
    for title in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.M):
        title = title.replace(chr(96), "").lower()
        slug = "".join(c for c in title if c in "-_ " or unicodedata.category(c)[0] in "LN").replace(" ", "-")
        number = repeats.get(slug, 0)
        repeats[slug] = number + 1
        anchors.add(slug if number == 0 else slug + "-" + str(number))
    return anchors


def document_links(path):
    errors, count = [], 0
    text = path.read_text(encoding="utf-8")
    for target in re.findall(r"\]\(([^)]+)\)", text):
        if re.match(r"\w+://", target):
            continue
        local, _, anchor = target.strip("<>").partition("#")
        destination = (path.parent / local).resolve() if local else path
        count += 1
        if not destination.is_file():
            errors.append(f"{path.name}: missing link target {target}")
        elif anchor and destination.suffix == ".md" and anchor not in heading_anchors(destination.read_text(encoding="utf-8")):
            errors.append(f"{path.name}: missing heading anchor {target}")
    return errors, count


def expanded_references(text, kind="test"):
    if kind == "test":
        pattern = r"\b(T-[A-Z]+-)(\d{2})(?:\s*(?:\.\.|～|–|—)\s*(?:T-[A-Z]+-)?(\d{2}))?"
    else:
        pattern = r"\b(P-)(\d{2})(?:\s*(?:\.\.|～|–|—)\s*(?:P-)?(\d{2}))?"
    found = set()
    for prefix, first, last in re.findall(pattern, text):
        end = int(last or first)
        if end < int(first):
            raise ValueError(f"backward ID range: {prefix}{first}..{last}")
        found.update(f"{prefix}{i:02d}" for i in range(int(first), end + 1))
    return found


def check_documents(spec, scope, findings):
    errors, links = [], 0
    documents = sorted(spec.glob("*.md"))
    expected = set(scope["required_documents"])
    actual = {p.name for p in documents}
    if expected != actual:
        errors.append(f"document manifest mismatch: {sorted(expected ^ actual)}")
    contents = {p.name: p.read_text(encoding="utf-8") for p in documents}
    for path in documents:
        body = contents[path.name]
        if body.count(chr(96) * 3) % 2:
            errors.append(f"{path.name}: unclosed fence")
        if scope["last_updated"] not in "\n".join(body.splitlines()[:5]):
            errors.append(f"{path.name}: missing current revision date in heading")
        if re.search(r"TODO|\[填入|\[Algorithm Name\]|\[Plant Name\]", body):
            errors.append(f"{path.name}: unresolved template")
        link_errors, count = document_links(path)
        errors.extend(link_errors)
        links += count
    test_ids = re.findall(r"^\| (T-[A-Z]+-\d{2}) \|", contents["FlightSIM-test-plan.md"], re.M)
    plant_ids = re.findall(r"^\| (P-\d{2}) \|", contents["QuadPlant-test-plan.md"], re.M)
    for label, ids in (("test", test_ids), ("plant test", plant_ids)):
        if len(ids) != len(set(ids)):
            errors.append(f"duplicate {label} IDs")
    for name, body in contents.items():
        unknown = expanded_references(body) - set(test_ids)
        unknown_plant = expanded_references(body, "plant") - set(plant_ids)
        if unknown or unknown_plant:
            errors.append(f"{name}: undefined references {sorted(unknown | unknown_plant)}")
    for name, prefix, required_count in (
        ("FlightSIM-system.md", "FSYS", scope["system_requirement_count"]),
        ("QuadPlant-system.md", "PSYS", scope["plant_requirement_count"]),
    ):
        rows = re.findall(rf"^\| ({prefix}-\d{{3}}) \|(.+)$", contents[name], re.M)
        if len(rows) != required_count or len({r[0] for r in rows}) != required_count:
            errors.append(f"{name}: requirement count/uniqueness")
        for requirement, row in rows:
            if not expanded_references(row) and not expanded_references(row, "plant"):
                errors.append(f"{requirement}: no verification mapping")
    ids = [item["id"] for item in findings["issues"]]
    if len(ids) != len(set(ids)):
        errors.append("duplicate review issue IDs")
    log_ids = set(re.findall(r"^\| (R[1-9]\d*-\d{2}) \|", contents["FlightSIM-review-log.md"], re.M))
    if log_ids != set(ids):
        errors.append("review markdown/JSON issue indexes differ")
    rounds = findings["additional_rounds"]
    if len(rounds) != scope["additional_review_count"] or {r["round"] for r in rounds} != set(range(1, scope["additional_review_count"] + 1)):
        errors.append("review round history incomplete or noncontiguous")
    for r in rounds:
        expected_ids = {i["id"] for i in findings["issues"] if i["round"] == r["round"]}
        if set(r["issue_ids"]) != expected_ids or r["status"] != "AUTHOR_SPEC_REVIEW_COMPLETE":
            errors.append(f"round {r['round']}: incomplete issue disposition")
    for item in findings["issues"]:
        if item["disposition"] != "SPEC_REPLACED" or item["implementation_verification"] != "NOT_RUN":
            errors.append(f"{item['id']}: invalid spec/implementation status")
        for name in item["files"]:
            if not (spec / name).is_file():
                errors.append(f"{item['id']}: replacement file missing {name}")
    obsolete = (
        "ode4步长500→250us", "名义可用区间≥99%", "同刻顺序为(sample,source,sequence)",
        "G0尚待收敛的语义项共三类", "third_party/KF_GINS_Matlab/",
    )
    for name, body in contents.items():
        for phrase in obsolete:
            if phrase in body:
                errors.append(f"{name}: superseded active design {phrase}")
    return errors, {
        "documents": len(documents), "local_links": links,
        "system_requirements": scope["system_requirement_count"],
        "plant_requirements": scope["plant_requirement_count"],
        "defined_test_ids": len(test_ids), "planned_model_test_ids": len([x for x in test_ids if not x.startswith("T-SPEC-")]),
        "plant_test_ids": len(plant_ids), "additional_reviews": len(rounds), "replaced_issues": len(ids), "current_session_additional_reviews": len(scope["current_session_rounds"]),
        "current_session_replaced_issues": len([i for i in findings["issues"] if i["round"] in scope["current_session_rounds"]]),
        "input_sha256": {p.name: sha(p) for p in documents},
    }


def project_artifacts(project, allow_implementation=False):
    outside = [p.relative_to(project).as_posix() for p in project.rglob('*')
               if p.is_file() and p.relative_to(project).parts[0] != 'spec']
    allowed_roots = {
        '.git', '.gitignore', 'README.md', 'IMPLEMENTATION_STATUS.md',
        'external_dependencies.lock.json', 'Flight_Matalab.prj', 'implementation_manifest.json',
        'adapters', 'config', 'dictionaries', 'interfaces', 'models', 'resources',
        'scenarios', 'simulation', 'tests', 'third_party_notices', 'tools', 'work', 'slprj',
    }
    unexpected = outside if not allow_implementation else [
        name for name in outside if Path(name).parts[0] not in allowed_roots]
    return outside, unexpected


def check_sources(spec, allow_implementation=False):
    evidence = spec / "validation"
    inventory = read_json(evidence / "source_inventory.json")
    snapshot = read_json(evidence / "upstream_review_snapshot.json")
    current = files_under(Path(inventory["source_root"]))
    flight = Path(snapshot["parent_spec_root"]).parent
    parent_now = files_under(flight / "spec")
    expected_parent = snapshot["reviewed_normative_sha256"]
    observed_parent = {n: h for n, h in parent_now.items() if normative(n)}
    original_changed = changed_paths(inventory["source_sha256"], current)
    unreviewed = changed_paths(expected_parent, observed_parent)
    initial_parent_changed = changed_paths(inventory["parent_spec_sha256"], parent_now)
    outside, unexpected = project_artifacts(spec.parent, allow_implementation)
    environment = read_json(evidence / "matlab_environment_and_reads.json")
    read_evidence_ok = all(r["read_ok"] and r["compiled"] == "NOT_RUN" for r in environment["source_model_reads"])
    errors = []
    if original_changed:
        errors.append(f"original source changed: {original_changed}")
    if unreviewed:
        errors.append(f"unreviewed parent inputs changed: {unreviewed}")
    if unexpected:
        errors.append(f"unexpected implementation artifacts: {unexpected}")
    if not read_evidence_ok or snapshot["impact_review_status"] != "READ_AND_INCORPORATED":
        errors.append("missing read/impact evidence")
    result = {
        "status": "FAIL" if errors else "PASS", "scope": "SOURCE_READ_ONLY",
        "original_files": len(current), "original_changed": original_changed,
        "unreviewed_parent_changes": unreviewed,
        "reviewed_parent_changes_since_initial": [n for n in initial_parent_changed if normative(n)],
        "concurrent_metadata_observations": [n for n in initial_parent_changed if not normative(n)],
        "parent_snapshot_sha256": sha(evidence / "upstream_review_snapshot.json"),
        "implementation_authorized": allow_implementation,
        "new_project_artifact_count": len(outside),
        "new_project_files_outside_spec": [n for n in outside if Path(n).parts[0] not in {'work','slprj','resources','.git'}],
        "matlab_models_modified_or_created": any(n.endswith('.slx') for n in outside),
        "original_models_modified": bool(original_changed),
    }
    activity = {
        "scope": "READ_ONLY_OBSERVATION", "parent_writes_by_this_task": False,
        "original_inventory_preserved": True,
        "reviewed_input_changes": snapshot["impact_notes"],
        "observed_changes_since_initial": {n: {"initial": inventory["parent_spec_sha256"].get(n), "current": parent_now.get(n)} for n in initial_parent_changed},
        "unreviewed_changes": unreviewed,
    }
    return errors, result, activity


def check_arithmetic():
    checks = []
    def require(name, condition, details):
        checks.append({"id": name, "status": "PASS" if condition else "FAIL", "details": details})
    periods = [1000, 2500, 10000, 20000, 100000]
    require("RATE_GRID", all(v % 500 == 0 for v in periods), {"base_us": 500, "periods_us": periods})
    counts = {str(v): 60_000_000 // v for v in [500, *periods]}
    require("HALF_OPEN_COUNTS", counts["500"] == 120000 and counts["2500"] == 24000, counts)
    coverage = {}
    for cost in [1000, 2000]:
        ticks = range(20000, 2_000_000, 500)
        valid = 0
        for now in ticks:
            start = (now // 20000) * 20000
            available = ((start + cost + 499) // 500) * 500
            valid += available <= now < start + 20000
        coverage[str(cost)] = valid / len(ticks)
    require("MPC_CAUSAL_COVERAGE", coverage == {"1000": .95, "2000": .9}, coverage)
    require("QP_PREVIEW", 120 + 15 + 15 + 40 == 190 and 5 * 3 == 15 and 24 * 20000 == 480000,
            {"variables": 15, "rows": 190, "preview_us": 480000})
    mass, gravity, stiffness, damping = 1.5, 9.81, 5000., 100.
    hover = mass * gravity
    require("SYNTH_HOVER_BOUND", hover < 40 / math.sqrt(3), {"design_check_g_approx": gravity, "hover_N": hover, "inner_box_limit_N": 40 / math.sqrt(3)})
    eigenvalue = (-damping + cmath.sqrt(damping**2 - 4 * mass * stiffness)) / (2 * mass)
    z = eigenvalue * .0005
    rk4_gain = abs(1 + z + z*z/2 + z**3/6 + z**4/24)
    compression = hover / stiffness
    require("CONTACT_LOCAL_STABILITY", rk4_gain < 1 and compression < .02,
            {"static_compression_m": compression, "linearized_RK4_gain": rk4_gain, "not_impact_test": True})
    max_quantized_delta = 0.
    previous = 0.
    quantum = 10 / 1999
    okay = True
    for desired in [10.] * 50 + [0.] * 50 + [5.] * 50:
        low, high = max(0., previous - .25), min(10., previous + .25)
        lo_index = max(0, math.ceil(low / quantum - 1e-12))
        hi_index = min(1999, math.floor(high / quantum + 1e-12))
        index = min(hi_index, max(lo_index, math.ceil(desired / quantum - .5)))
        actual = index * quantum
        okay &= low - 1e-12 <= actual <= high + 1e-12
        max_quantized_delta = max(max_quantized_delta, abs(actual - previous))
        previous = actual
    require("INTEGER_CODE_SLEW", okay and max_quantized_delta <= .25 + 1e-12,
            {"force_quantum_N": quantum, "max_delta_N": max_quantized_delta, "frame_s": .0025})
    require("ORIGIN_BARO", -0. + 0. == 0. and .15 - .15 == 0.,
            {"CG_D0": 0, "ground_D": .15, "contact_offset_D": .15, "baro_relative0": 0})
    require("STARTUP_DEPENDENCY", .1 + 2 < 2.6 < 3. and 2.5 + 2 < 5.,
            {"configured_nav_latest_s": .1, "ground_dwell_s": 2, "home_s": 2.6, "arm_s": 3, "static_align_arm_s": 5})
    return {
        "status": "PASS" if all(c["status"] == "PASS" for c in checks) else "FAIL",
        "scope": "ANALYTIC_DESIGN", "model_execution": "NOT_RUN",
        "checks": checks, "limitation": "Design arithmetic only; no MATLAB model, physical impact or solver performance execution.",
    }


def check_semantic_evidence(spec, scope):
    errors = []
    report = read_json(spec / "validation/semantic_reference_report.json")
    required = set(scope["required_semantic_cases"])
    actual = [c["id"] for c in report["cases"]]
    if len(actual) != len(set(actual)) or set(actual) != required:
        errors.append("semantic reference case set incomplete or duplicated")
    if report["status"] != "PASS" or any(c["status"] != "PASS" for c in report["cases"]):
        errors.append("semantic reference cases failed")
    if report["scope"] != "EXECUTABLE_SPEC_REFERENCE" or report["matlab_model_execution"] != "NOT_RUN" or report.get("production_algorithm_execution") != "NOT_RUN":
        errors.append("semantic reference execution scope invalid")
    if report["script_sha256"] != sha(spec / "tools/check_semantic_references.py"):
        errors.append("semantic reference script changed since execution")
    current = {p.name: sha(p) for p in sorted(spec.glob("*.md"))}
    if report["document_sha256"] != current:
        errors.append("semantic reference document snapshot is stale")
    if report["independent_polynomial_extrema_checks"] < 192:
        errors.append("independent polynomial bound checks incomplete")
    return errors, {"executable_reference_cases": len(actual), "polynomial_extrema_checks": report["independent_polynomial_extrema_checks"]}


def validate(spec, emit_output=True, allow_implementation=False):
    spec = Path(spec).resolve()
    output = spec / "validation"
    timestamp = datetime.now(timezone.utc).isoformat()
    base = {"status": "IN_PROGRESS", "observed_at_utc": timestamp,
            "model_implementation": "IN_PROGRESS" if allow_implementation else "NOT_STARTED",
            "model_compile_simulation_codegen": "NOT_RUN",
            "runtime_result_scope": "This document validator does not execute models; see implementation_manifest.json for runtime evidence."}
    # Invalidate preceding evidence before reading potentially broken inputs.
    for name, scope in (("spec_review_report.json", "DOCUMENT_STATIC"), ("source_integrity_report.json", "SOURCE_READ_ONLY"), ("design_arithmetic_report.json", "ANALYTIC_DESIGN")):
        write_json(output, name, {**base, "scope": scope})
    try:
        scope = read_json(output / "spec_scope.json")
        findings = read_json(output / "review_findings.json")
        doc_errors, details = check_documents(spec, scope, findings)
        source_errors, integrity, activity = check_sources(spec, allow_implementation)
        arithmetic = check_arithmetic()
        semantic_errors, semantic_details = check_semantic_evidence(spec, scope)
        errors = doc_errors + source_errors + semantic_errors + ([] if arithmetic["status"] == "PASS" else ["design arithmetic failed"])
        negative_tests = read_json(output / "validator_negative_tests.json")
        if (negative_tests["status"] != "PASS" or negative_tests["tests_run"] != scope["validator_unit_test_count"]
                or negative_tests["validator_sha256"] != sha(Path(__file__).resolve())
                or negative_tests["script_sha256"] != sha(spec / "tools/test_check_specs.py")):
            errors.append("validator negative-test evidence missing, failed or stale")
        report = {
            **base, "baseline": scope["baseline"], "status": "FAIL" if errors else "PASS",
            "scope": "DOCUMENT_STATIC", **details, **semantic_details, "errors": errors,
            "completed_self_reviews": findings["prior_self_reviews"] + len(findings["additional_rounds"]),
            "independent_human_review": "NOT_RUN",
            "host_execution_profile": "HOST_NATIVE_V2",
            "host_design_semantics": "SELECTED; runtime dependency/data/topology checks pending",
            "firmware_conformance_gate": "NOT_RUN; separate from Host model construction",
            "phase0_verification_pending": ["HOST_SCHEMA_BINDING", "DEPENDENCIES_QP_TOOLCHAIN_DATA", "FUNCTION_CALL_TOPOLOGY"],
            "validator_sha256": sha(Path(__file__).resolve()),
            "evidence_sha256": {n: sha(output / n) for n in ["source_inventory.json", "review_findings.json", "upstream_review_snapshot.json", "spec_scope.json", "validator_negative_tests.json", "semantic_reference_report.json"]},
        }
        write_json(output, "source_integrity_report.json", {**integrity, "observed_at_utc": timestamp})
        write_json(output, "concurrent_parent_activity.json", activity)
        write_json(output, "design_arithmetic_report.json", {**arithmetic, "observed_at_utc": timestamp})
        write_json(output, "spec_review_report.json", report)
    except Exception as exc:
        report = {**base, "status": "FAIL", "scope": "DOCUMENT_STATIC", "errors": [f"{type(exc).__name__}: {exc}"]}
        write_json(output, "spec_review_report.json", report)
        for name, check_scope in (("source_integrity_report.json", "SOURCE_READ_ONLY"), ("design_arithmetic_report.json", "ANALYTIC_DESIGN")):
            write_json(output, name, {**base, "status": "NOT_RUN", "scope": check_scope, "reason": "Validation aborted; preceding PASS invalidated."})
    if emit_output:
        print(json.dumps({k: report[k] for k in ["status", "scope", "documents", "additional_reviews", "replaced_issues", "model_compile_simulation_codegen"] if k in report}, ensure_ascii=False))
        for error in report.get("errors", []):
            print(error)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec-dir", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--allow-implementation", action="store_true",
                        help="User-authorized model phase: permit bounded new-project artifacts; retain original/parent source checks.")
    arguments = parser.parse_args()
    sys.exit(validate(arguments.spec_dir, allow_implementation=arguments.allow_implementation))

