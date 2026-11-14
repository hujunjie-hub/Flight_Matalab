"""Focused negative checks for evidence invalidation and specification validation."""
import json
import hashlib
import io
import sys
from pathlib import Path
import tempfile
import unittest

import check_specs as checker


class SpecValidationTests(unittest.TestCase):
    def test_implementation_phase_preserves_strict_default_and_root_boundary(self):
        with tempfile.TemporaryDirectory(prefix='flightsim-implementation-phase-') as folder:
            root = Path(folder)
            (root / 'models').mkdir()
            (root / 'models/FMT_Leaf.slx').write_bytes(b'fixture')
            (root / '.github/workflows').mkdir(parents=True)
            (root / '.github/workflows/static-validation.yml').write_text('name: static-validation')
            (root / 'unexpected.outside').write_text('fixture')
            outside, rejected = checker.project_artifacts(root)
            self.assertEqual(
                set(outside),
                {'models/FMT_Leaf.slx', '.github/workflows/static-validation.yml', 'unexpected.outside'},
            )
            self.assertEqual(set(rejected), set(outside))
            outside, rejected = checker.project_artifacts(root, allow_implementation=True)
            self.assertEqual(rejected, ['unexpected.outside'])

    def test_range_expansion_covers_middle_ids(self):
        self.assertEqual(checker.expanded_references("T-FMS-01～04"), {f"T-FMS-{i:02d}" for i in range(1, 5)})
        self.assertEqual(checker.expanded_references("P-07..10", "plant"), {f"P-{i:02d}" for i in range(7, 11)})
        with self.assertRaises(ValueError):
            checker.expanded_references("T-FMS-04..01")

    def test_missing_anchor_is_an_error_even_when_file_exists(self):
        with tempfile.TemporaryDirectory(prefix="flightsim-spec-anchor-") as folder:
            root = Path(folder)
            (root / "target.md").write_text("# 目标章节\n", encoding="utf-8")
            source = root / "source.md"
            source.write_text("[bad](target.md#不存在)\n", encoding="utf-8")
            errors, count = checker.document_links(source)
            self.assertEqual(count, 1)
            self.assertEqual(len(errors), 1)
            source.write_text("[ok](target.md#目标章节)\n", encoding="utf-8")
            self.assertEqual(checker.document_links(source), ([], 1))

    def test_source_drift_includes_added_deleted_and_modified(self):
        self.assertEqual(checker.changed_paths({"a": "1", "b": "1"}, {"a": "2", "c": "1"}), ["a", "b", "c"])
        self.assertTrue(checker.normative("09_需求验证实施与发布管理.md"))
        self.assertTrue(checker.normative("11_审核问题闭环与变更追踪.md"))
        self.assertFalse(checker.normative("validation/temporary_report.json"))

    def test_invalid_input_replaces_prior_pass_with_fail(self):
        with tempfile.TemporaryDirectory(prefix="flightsim-spec-fail-") as folder:
            spec = Path(folder)
            evidence = spec / "validation"
            evidence.mkdir()
            for name in ["spec_review_report.json", "source_integrity_report.json", "design_arithmetic_report.json"]:
                (evidence / name).write_text('{"status":"PASS"}', encoding="utf-8")
            (evidence / "spec_scope.json").write_text("{broken", encoding="utf-8")
            self.assertEqual(checker.validate(spec, emit_output=False), 1)
            self.assertEqual(checker.read_json(evidence / "spec_review_report.json")["status"], "FAIL")
            for name in ["source_integrity_report.json", "design_arithmetic_report.json"]:
                self.assertEqual(checker.read_json(evidence / name)["status"], "NOT_RUN")

    def test_design_coverage_is_separate_from_simulation(self):
        result = checker.check_arithmetic()
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["model_execution"], "NOT_RUN")
        coverage = next(v for v in result["checks"] if v["id"] == "MPC_CAUSAL_COVERAGE")
        self.assertEqual(coverage["details"], {"1000": .95, "2000": .9})


    def test_semantic_evidence_rejects_changed_documents_script_and_duplicates(self):
        with tempfile.TemporaryDirectory(prefix="flightsim-semantic-evidence-") as folder:
            spec = Path(folder)
            (spec / "validation").mkdir()
            (spec / "tools").mkdir()
            design = spec / "design.md"
            design.write_text("# Design", encoding="utf-8")
            script = spec / "tools/check_semantic_references.py"
            script.write_text("pass", encoding="utf-8")
            report = {"cases":[{"id":"D4-01","status":"PASS"}],"status":"PASS",
                      "scope":"EXECUTABLE_SPEC_REFERENCE","matlab_model_execution":"NOT_RUN","production_algorithm_execution":"NOT_RUN",
                      "script_sha256":checker.sha(script),"document_sha256":{"design.md":checker.sha(design)},
                      "independent_polynomial_extrema_checks":192}
            checker.write_json(spec / "validation", "semantic_reference_report.json", report)
            scope = {"required_semantic_cases":["D4-01"]}
            self.assertEqual(checker.check_semantic_evidence(spec, scope)[0], [])
            design.write_text("# Changed", encoding="utf-8")
            self.assertTrue(any("stale" in e for e in checker.check_semantic_evidence(spec, scope)[0]))
            script.write_text("raise RuntimeError", encoding="utf-8")
            report["cases"].append({"id":"D4-01","status":"PASS"})
            checker.write_json(spec / "validation", "semantic_reference_report.json", report)
            errors = checker.check_semantic_evidence(spec, scope)[0]
            self.assertTrue(any("script changed" in e for e in errors))
            self.assertTrue(any("duplicated" in e for e in errors))

    def test_round_identifier_pattern_covers_current_and_historical_rounds(self):
        import re
        rows = "\n".join(f"| R{i}-01 | issue |" for i in range(1, 7))
        self.assertEqual(set(re.findall(r"^\| (R[1-9]\d*-\d{2}) \|", rows, re.M)), {f"R{i}-01" for i in range(1, 7)})


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SpecValidationTests)
    captured = io.StringIO()
    result = unittest.TextTestRunner(stream=captured, verbosity=2).run(suite)
    output = captured.getvalue()
    sys.stderr.write(output)
    spec = Path(__file__).resolve().parents[1]
    record = {"date":"2026-11-05", "scope":"SPEC_VALIDATOR_NEGATIVE_TESTS",
              "status":"PASS" if result.wasSuccessful() else "FAIL", "tests_run":result.testsRun,
              "exit_code":0 if result.wasSuccessful() else 1,
              "script_sha256":checker.sha(Path(__file__).resolve()),
              "validator_sha256":checker.sha(Path(checker.__file__).resolve()),
              "output":output, "model_execution":"NOT_RUN"}
    checker.write_json(spec / "validation", "validator_negative_tests.json", record)
    raise SystemExit(record["exit_code"])

