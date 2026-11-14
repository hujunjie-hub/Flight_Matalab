from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "tools" / "run_local_validation.ps1"
MANIFEST_PATH = ROOT / "spec" / "validation" / "matlab_acceptance_manifest.json"
ISSUE_WORKFLOW_PATH = ROOT / "spec" / "quality" / "issue-workflow.json"


class LocalValidationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = SCRIPT_PATH.read_text(encoding="utf-8")
        cls.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        cls.issue_workflow = json.loads(ISSUE_WORKFLOW_PATH.read_text(encoding="utf-8"))

    def test_main_is_the_only_validation_branch(self) -> None:
        self.assertEqual(self.manifest["branch"], "main")
        self.assertEqual(self.manifest["repository"], "hujunjie-hub/Flight_Matlab")
        self.assertEqual(
            self.manifest["local_execution"]["command"],
            "pwsh -NoProfile -ExecutionPolicy Bypass -File .\\tools\\run_local_validation.ps1",
        )

    def test_full_project_pass_requires_explicit_authorization(self) -> None:
        self.assertIs(self.manifest["full_project_pass_allowed"], False)
        self.assertTrue(self.manifest["full_project_pass_blockers"])
        self.assertIn("$fullProjectPassAllowed = $false", self.script)
        self.assertIn("[string]$acceptanceManifest.branch -ne 'main'", self.script)
        self.assertIn("[string]$acceptanceManifest.repository -ne 'hujunjie-hub/Flight_Matlab'", self.script)
        self.assertIn("-not $fullProjectPassAllowed", self.script)
        self.assertIn("Full project PASS blockers:", self.script)

    def test_failure_is_reported_after_delivery_package_is_created(self) -> None:
        package = self.script.index("Compress-Archive -LiteralPath $deliveryItems")
        checksum = self.script.index("$verifiedHash =")
        failure_exit = self.script.index("exit $scriptExitCode")
        self.assertLess(package, checksum)
        self.assertLess(checksum, failure_exit)
        self.assertIn("if ($matlabExitCode -ne 0)", self.script)
        self.assertIn("if ($componentStatus -notin @('PASS', 'PARTIAL_PASS'))", self.script)
        self.assertIn("if ($abiStatus -notin @('PASS', 'SKIPPED_TOOLCHAIN_MISSING'))", self.script)

    def test_delivery_package_contains_the_exact_manifest(self) -> None:
        self.assertIn("$manifestIncluded = Test-Path -LiteralPath $manifestPath -PathType Leaf", self.script)
        self.assertIn('"Acceptance manifest included in delivery: $manifestIncluded"', self.script)
        self.assertIn("$deliveryItems = @($matlabZip.FullName, $matlabChecksum, $summaryPath)", self.script)
        self.assertIn("if ($manifestIncluded)", self.script)
        self.assertIn("$deliveryItems += $manifestPath", self.script)
        self.assertIn("matlab_acceptance_manifest.json", self.issue_workflow["delivery_contains"][2])
        self.assertIn(
            "work/validation/archives/<RUN_ID>_DELIVERY.zip",
            self.issue_workflow["delivery_files"],
        )
        self.assertIn(
            "work/validation/archives/<RUN_ID>_DELIVERY.zip.sha256",
            self.issue_workflow["delivery_files"],
        )

    def test_partial_pass_is_not_mislabeled_as_full_pass(self) -> None:
        self.assertIn("$componentStatus -eq 'PARTIAL_PASS'", self.script)
        self.assertIn("$abiStatus -eq 'SKIPPED_TOOLCHAIN_MISSING'", self.script)
        self.assertIn("PARTIAL_PASS", self.manifest["overall_status_rules"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
