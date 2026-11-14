#Requires -Version 5.1
<#
.SYNOPSIS
    Prove that a validation run which dies early still produces a complete archive.

.DESCRIPTION
    The archive is the only artefact a reviewer sees, so it must not depend on
    the run reaching its happy path.  This gate builds a throw-away git fixture,
    lets MATLAB write the pre-run snapshot and then crash, and asserts that
    archive_validation_run.ps1 still synthesises the post-run state, records the
    missing pieces in archive_completeness and ships the evidence in the ZIP.

    Cases:
      F-01  MATLAB exits with an error after the pre-run snapshot
      F-02  the archive refuses to lose the run: git_state_after.json is synthesised
      F-03  the manifest reports the incompleteness instead of pretending success
      F-04  both snapshots travel inside the ZIP
      F-05  a dirty worktree is reported through source_clean / source_dirty_files
#>
param(
    [switch]$KeepFixture
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$reportPath = Join-Path $repoRoot "work/validation/archive_failure_path_report.json"
$cases = New-Object System.Collections.ArrayList

function Add-Case {
    param([string]$Id, [string]$Title, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    [void]$cases.Add([pscustomobject]@{ id = $Id; title = $Title; status = $status; detail = $Detail })
    Write-Host ("{0,-5} {1}  ({2})" -f $Id, $status, $Detail)
}

function New-Fixture {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("fmt-archive-" + [guid]::NewGuid().ToString("N").Substring(0, 10))
    New-Item -ItemType Directory -Path (Join-Path $path "tools") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $path "config") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $path "models/plant") -Force | Out-Null
    foreach ($name in @("fingerprint_sources.py", "fingerprint_artifacts.py", "git_state.py", "flight_acceptance_snapshot.m")) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "tools/$name") -Destination (Join-Path $path "tools/$name") -Force
    }
    Set-Content -LiteralPath (Join-Path $path ".gitignore") -Value "work/"
    Set-Content -LiteralPath (Join-Path $path "config/vehicle.yaml") -Value "mass_kg: 1.0"
    Set-Content -LiteralPath (Join-Path $path "models/plant/FMT_Demo.slx") -Value "model-v1"
    & git -C $path init -q -b main
    & git -C $path config user.name "flight-acceptance"
    & git -C $path config user.email "acceptance@example.invalid"
    & git -C $path add -A
    & git -C $path commit -q -m "fixture-baseline"
    if ($LASTEXITCODE -ne 0) { throw "Could not create the git fixture." }
    return $path
}

$fixture = New-Fixture
try {
    $escaped = $fixture.Replace("\", "/")
    $snapshot = "addpath('$escaped/tools'); r=flight_acceptance_snapshot('$escaped','before'); fprintf('SNAPSHOT=%s\n', r.source_fingerprint); error('Flight:SimulatedEarlyExit','simulated crash after the pre-run snapshot');"
    $matlabOutput = & matlab -batch $snapshot 2>&1
    $matlabExit = $LASTEXITCODE

    $beforePath = Join-Path $fixture "work/validation/git_state_before.json"
    $afterPath = Join-Path $fixture "work/validation/git_state_after.json"
    Add-Case "F-01" "MATLAB failed but the pre-run snapshot survived" `
        ($matlabExit -ne 0 -and (Test-Path -LiteralPath $beforePath) -and -not (Test-Path -LiteralPath $afterPath)) `
        ("exit=$matlabExit before=" + (Test-Path -LiteralPath $beforePath) + " after=" + (Test-Path -LiteralPath $afterPath))

    $zipBefore = @(Get-ChildItem -Path $fixture -Recurse -Filter "*.zip" -ErrorAction SilentlyContinue).Count
    $archiveOutput = & pwsh -File (Join-Path $repoRoot "tools/archive_validation_run.ps1") -RepoRoot $fixture -RunId "fmat-failure" 2>&1
    $archiveExit = $LASTEXITCODE
    # The archive empties the live validation directory once the ZIP is sealed,
    # so the synthesised snapshot has to be checked in the archived copy.
    $archivedAfter = Join-Path $fixture "work/validation/archives/fmat-failure/git_state_after.json"
    Add-Case "F-02" "archive synthesised the missing post-run state" `
        ($archiveExit -eq 0 -and (Test-Path -LiteralPath $archivedAfter)) `
        ("exit=$archiveExit archived_after=" + (Test-Path -LiteralPath $archivedAfter))

    $zipPath = Join-Path $fixture "work/validation/archives/fmat-failure.zip"
    $manifest = $null
    $names = @()
    if (Test-Path -LiteralPath $zipPath) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq "run_manifest.json" }
            if ($entry) {
                $reader = New-Object System.IO.StreamReader($entry.Open())
                $manifest = $reader.ReadToEnd() | ConvertFrom-Json
                $reader.Close()
            }
            $names = @($zip.Entries | ForEach-Object { $_.FullName })
        }
        finally { $zip.Dispose() }
    }
    Add-Case "F-03" "manifest reports the incompleteness instead of success" `
        ($null -ne $manifest -and $manifest.schema -eq "flight-matalab-run-archive/1.1" `
            -and $manifest.archive_completeness.git_after -eq $true `
            -and $manifest.archive_completeness.component_report -eq $false `
            -and $manifest.component_status -eq "NO_COMPONENT_REPORT") `
        ("schema=" + $(if ($manifest) { $manifest.schema } else { "MISSING" }) +
            " component_report=" + $(if ($manifest) { $manifest.archive_completeness.component_report } else { "?" }))

    $zipHasBoth = ($names -contains "git_state_before.json") -and ($names -contains "git_state_after.json")
    Add-Case "F-04" "both snapshots travel inside the ZIP" $zipHasBoth `
        ("entries=" + $names.Count)

    Set-Content -LiteralPath (Join-Path $fixture "config/vehicle.yaml") -Value "mass_kg: 9.9"
    & python -B (Join-Path $fixture "tools/fingerprint_sources.py") --root $fixture 2>&1 | Out-Null
    $dirtyOutput = & pwsh -File (Join-Path $repoRoot "tools/archive_validation_run.ps1") -RepoRoot $fixture -RunId "fmat-failure-dirty" 2>&1
    $dirtyExit = $LASTEXITCODE
    $dirtyZip = Join-Path $fixture "work/validation/archives/fmat-failure-dirty.zip"
    $dirtyManifest = $null
    if (Test-Path -LiteralPath $dirtyZip) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($dirtyZip)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq "run_manifest.json" }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            $dirtyManifest = $reader.ReadToEnd() | ConvertFrom-Json
            $reader.Close()
        }
        finally { $zip.Dispose() }
    }
    Add-Case "F-05" "a dirty worktree is reported, not hidden" `
        ($null -ne $dirtyManifest -and $dirtyManifest.source_clean -eq $false `
            -and @($dirtyManifest.source_dirty_files) -contains "config/vehicle.yaml") `
        ("source_clean=" + $(if ($dirtyManifest) { $dirtyManifest.source_clean } else { "MISSING" }))
}
finally {
    if (-not $KeepFixture -and (Test-Path -LiteralPath $fixture)) {
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$passed = @($cases | Where-Object { $_.status -eq "PASS" }).Count
$report = [ordered]@{
    scope = "ARCHIVE_FAILURE_PATH"
    status = if ($passed -eq $cases.Count) { "PASS" } else { "FAIL" }
    case_count = $cases.Count
    passed_count = $passed
    cases = $cases
}
$reportDirectory = Split-Path -Parent $reportPath
if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host ("STATUS=" + $report.status + " " + $passed + "/" + $cases.Count)
if ($report.status -ne "PASS") { exit 1 }
