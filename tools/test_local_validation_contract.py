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
        self.assertIn("$fullProjectPassAllowed -and $fullProjectPassBlockers.Count -gt 0", self.script)
        self.assertIn("cannot be authorized while unresolved blockers remain", self.script)
        self.assertIn("Full project PASS blockers:", self.script)

    def test_runner_packages_dirty_worktree_status_without_reset(self) -> None:
        self.assertIn("git -C $entry.Path status --porcelain", self.script)
        self.assertIn("$dirtyWorktreeIssues.Count -gt 0", self.script)
        self.assertIn("DIRTY_WORKTREE_OR_PENDING_UNARCHIVED_EVIDENCE", self.script)
        self.assertIn("Repository branch/HEAD/status:", self.script)
        self.assertIn("were not deleted, reset, cleaned, or overwritten", self.script)
        self.assertIn("Compress-Archive -LiteralPath $pendingItems -DestinationPath $pendingDeliveryZip", self.script)

    def test_runner_packages_pending_evidence_without_overwriting(self) -> None:
        guard = self.script.index("$pendingValidationFiles = @(")
        package = self.script.index("Compress-Archive -LiteralPath $pendingItems")
        checksum = self.script.index("$pendingVerifiedHash =")
        pending_exit = self.script.index("exit 1", guard)
        self.assertLess(guard, package)
        self.assertLess(package, checksum)
        self.assertLess(checksum, pending_exit)
        self.assertIn("$pendingValidationFiles.Count -gt 0", self.script)
        self.assertIn("Existing validation files were packaged as-is; originals were not deleted or modified.", self.script)

    def test_runner_packages_pending_evidence_without_deleting_it(self) -> None:
        self.assertIn("$pendingValidationFiles.Count -gt 0", self.script)
        self.assertIn("$pendingItems += $pendingSummaryPath", self.script)
        self.assertIn("Compress-Archive -LiteralPath $pendingItems -DestinationPath $pendingDeliveryZip", self.script)
        self.assertIn("originals were not deleted or modified", self.script)
        self.assertIn("Pending-evidence delivery package SHA-256 verification failed", self.script)

    def test_one_click_entry_runs_the_local_contract_test(self) -> None:
        self.assertIn("tools\\test_local_validation_contract.py", self.script)
        self.assertIn("$pythonExe -B $contractTestPath", self.script)
        self.assertIn("$contractExitCode -ne 0", self.script)
        self.assertIn("$preflightDeliveryZip", self.script)
        self.assertIn("Refusing to overwrite an existing preflight delivery artifact", self.script)
        self.assertIn("LOCAL_VALIDATION_CONTRACT_PREFLIGHT", self.script)
        self.assertIn("local_validation_contract_status = 'PASS'", self.script)
        self.assertEqual(
            self.manifest["local_execution"]["preflight_contract_test"],
            "tools/test_local_validation_contract.py",
        )
        self.assertEqual(
            self.manifest["local_execution"]["preflight_contract_log"],
            "work/validation/local_validation_contract_test.txt",
        )
        self.assertTrue(any(
            "local_validation_contract_test.txt" in item
            for item in self.issue_workflow["archive_contains"]
        ))
        self.assertTrue(any(
            "summary" in item and ("MATLAB_NOT_STARTED" in item or "MATLAB was not started" in item)
            for item in self.issue_workflow["archive_contains"]
        ))

    def test_preflight_failure_packages_evidence_before_nonzero_exit(self) -> None:
        preflight_start = self.script.index("if ($contractExitCode -ne 0)")
        package = self.script.index("Compress-Archive -LiteralPath $preflightItems", preflight_start)
        checksum = self.script.index("$preflightVerifiedHash =", preflight_start)
        preflight_exit = self.script.index("exit 1", preflight_start)
        self.assertLess(package, checksum)
        self.assertLess(checksum, preflight_exit)
        self.assertIn("LOCAL_VALIDATION_CONTRACT_PREFLIGHT", self.script)
        self.assertIn("Flight_Matlab commit: $projectCommit", self.script)
        self.assertIn("Flight commit: $flightCommit", self.script)
        self.assertIn("MATLAB was not started; no MATLAB result is claimed.", self.script)

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
