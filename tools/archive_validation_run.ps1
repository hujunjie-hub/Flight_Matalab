param(
    [string]$RunId = "",
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { $repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
$validationRoot = Join-Path $repoRoot "work/validation"
$archiveRoot = Join-Path $validationRoot "archives"
$componentReportPath = Join-Path $validationRoot "component_checks.json"
$fingerprintPath = Join-Path $validationRoot "current_source_fingerprint.json"
$scenarioPath = Join-Path $repoRoot "scenarios/flight_sil_recording.mat"

$gitBeforePath = Join-Path $validationRoot "git_state_before.json"
$gitAfterPath = Join-Path $validationRoot "git_state_after.json"
$artifactReportPath = Join-Path $validationRoot "current_artifact_fingerprint.json"
$generatedAssetsPath = Join-Path $validationRoot "generated_assets.json"

# A run can die before it writes its own post-run snapshot - a MATLAB crash, a
# killed build, an assertion in the middle of the checks. The archive must still
# describe the tree it is archiving, so fill the gaps from the current state
# rather than refusing to produce evidence.
if (-not (Test-Path -LiteralPath $gitAfterPath)) {
    & python -B (Join-Path $repoRoot "tools/git_state.py") "after" $gitAfterPath 2>&1 | Out-Null
}
if (-not (Test-Path -LiteralPath $artifactReportPath)) {
    & python -B (Join-Path $repoRoot "tools/fingerprint_artifacts.py") "--output" $artifactReportPath 2>&1 | Out-Null
}

function Read-ReportField {
    param([string]$Path, [string]$Field, $Default)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Default }
    try {
        $report = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $value = $report.$Field
        if ($null -eq $value) { return $Default }
        return $value
    }
    catch { return $Default }
}

$sourceCommitted = Read-ReportField $fingerprintPath "committed_sha256" "UNAVAILABLE"
$sourceClean = Read-ReportField $fingerprintPath "clean" "UNKNOWN"
$sourceDirty = @(Read-ReportField $fingerprintPath "dirty_files" @())
$artifactFingerprint = Read-ReportField $artifactReportPath "sha256" "UNAVAILABLE"
$artifactFiles = Read-ReportField $artifactReportPath "file_count" 0
$generatedSummary = Read-ReportField $generatedAssetsPath "summary" @{}

$gitBefore = [ordered]@{
    branch = Read-ReportField $gitBeforePath "branch" "UNAVAILABLE"
    commit = Read-ReportField $gitBeforePath "commit" "UNAVAILABLE"
    clean = Read-ReportField $gitBeforePath "worktree_clean" "UNKNOWN"
    entry_count = Read-ReportField $gitBeforePath "entry_count" 0
}
$gitAfter = [ordered]@{
    branch = Read-ReportField $gitAfterPath "branch" "UNAVAILABLE"
    commit = Read-ReportField $gitAfterPath "commit" "UNAVAILABLE"
    clean = Read-ReportField $gitAfterPath "worktree_clean" "UNKNOWN"
    entry_count = Read-ReportField $gitAfterPath "entry_count" 0
}
$completeness = [ordered]@{
    component_report = (Test-Path -LiteralPath $componentReportPath -PathType Leaf)
    source_fingerprint = (Test-Path -LiteralPath $fingerprintPath -PathType Leaf)
    artifact_fingerprint = (Test-Path -LiteralPath $artifactReportPath -PathType Leaf)
    git_before = (Test-Path -LiteralPath $gitBeforePath -PathType Leaf)
    git_after = (Test-Path -LiteralPath $gitAfterPath -PathType Leaf)
    generated_assets = (Test-Path -LiteralPath $generatedAssetsPath -PathType Leaf)
}

if (-not (Test-Path -LiteralPath $validationRoot -PathType Container)) {
    throw "Validation directory does not exist: $validationRoot"
}

$payloadItems = @(Get-ChildItem -LiteralPath $validationRoot -Force | Where-Object { $_.Name -ne "archives" })
if ($payloadItems.Count -eq 0) {
    throw "No current validation reports/logs found to archive."
}

function Get-GitText {
    param([string]$Path, [string[]]$GitArguments)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return "UNKNOWN" }
    $output = & git -C $Path @GitArguments 2>$null
    if ($LASTEXITCODE -ne 0) { return "UNKNOWN" }
    return (($output -join "`n").Trim())
}

$projectBranch = Get-GitText -Path $repoRoot -GitArguments @("branch", "--show-current")
$projectCommit = Get-GitText -Path $repoRoot -GitArguments @("rev-parse", "HEAD")
$projectDirty = Get-GitText -Path $repoRoot -GitArguments @("status", "--porcelain")
$flightRoot = Join-Path (Split-Path $repoRoot -Parent) "Flight"
$flightCommit = Get-GitText -Path $flightRoot -GitArguments @("rev-parse", "HEAD")

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
    $shortCommit = if ($projectCommit -match "^[0-9a-f]{7,}$") { $projectCommit.Substring(0,7) } else { "unknown" }
    $RunId = "${stamp}_${shortCommit}"
}

if ($RunId -notmatch "^[A-Za-z0-9._-]+$") {
    throw "RUN_ID contains unsupported characters: $RunId"
}

New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
$runDirectory = Join-Path $archiveRoot $RunId
$zipPath = Join-Path $archiveRoot "${RunId}.zip"
if (Test-Path -LiteralPath $runDirectory) { throw "Archive already exists; refusing to overwrite: $runDirectory" }
if (Test-Path -LiteralPath $zipPath) { throw "Archive ZIP already exists; refusing to overwrite: $zipPath" }

New-Item -ItemType Directory -Path $runDirectory | Out-Null
foreach ($item in $payloadItems) {
    Copy-Item -LiteralPath $item.FullName -Destination $runDirectory -Recurse -Force
}

if (Test-Path -LiteralPath $scenarioPath -PathType Leaf) {
    $inputDirectory = Join-Path $runDirectory "inputs"
    New-Item -ItemType Directory -Force -Path $inputDirectory | Out-Null
    Copy-Item -LiteralPath $scenarioPath -Destination (Join-Path $inputDirectory "flight_sil_recording.mat") -Force
}

$componentStatus = "NO_COMPONENT_REPORT"
if (Test-Path -LiteralPath $componentReportPath -PathType Leaf) {
    try {
        $componentReport = Get-Content -LiteralPath $componentReportPath -Raw | ConvertFrom-Json
        $componentStatus = [string]$componentReport.status
    }
    catch {
        $componentStatus = "INVALID_COMPONENT_REPORT"
    }
}

$sourceFingerprint = "UNAVAILABLE"
if (Test-Path -LiteralPath $fingerprintPath -PathType Leaf) {
    try {
        $fingerprintReport = Get-Content -LiteralPath $fingerprintPath -Raw | ConvertFrom-Json
        if ($fingerprintReport.sha256) { $sourceFingerprint = [string]$fingerprintReport.sha256 }
    }
    catch {
        $sourceFingerprint = "INVALID_FINGERPRINT_REPORT"
    }
}

$artifactHashes = @(
    Get-ChildItem -LiteralPath $runDirectory -File -Recurse | ForEach-Object {
        $relativePath = [System.IO.Path]::GetRelativePath($runDirectory, $_.FullName).Replace("\", "/")
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [pscustomobject]@{
            path = $relativePath
            size_bytes = $_.Length
            sha256 = $hash
        }
    }
)

$manifest = [ordered]@{
    schema = "flight-matalab-run-archive/1.1"
    run_id = $RunId
    archived_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_branch = $projectBranch
    project_commit = $projectCommit
    project_worktree_status = $projectDirty
    flight_commit = $flightCommit
    component_status = $componentStatus
    # Source and artifacts are reported separately from 1.1 on: the source
    # digest only covers committed-style inputs, while models, dictionaries,
    # MEX kernels and recordings are build output with their own digest.
    source_fingerprint_sha256 = $sourceFingerprint
    source_fingerprint_committed_sha256 = $sourceCommitted
    source_clean = $sourceClean
    source_dirty_files = $sourceDirty
    artifact_fingerprint_sha256 = $artifactFingerprint
    artifact_file_count = $artifactFiles
    generated_assets_summary = $generatedSummary
    git_state_before = $gitBefore
    git_state_after = $gitAfter
    archive_completeness = $completeness
    artifact_count = $artifactHashes.Count
    artifacts = $artifactHashes
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $runDirectory "run_manifest.json") -Encoding utf8

Compress-Archive -Path (Join-Path $runDirectory "*") -DestinationPath $zipPath -CompressionLevel Optimal
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Archive ZIP was not created: $zipPath"
}
$zipSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = "${zipPath}.sha256"
"${zipSha256}  $(Split-Path $zipPath -Leaf)" | Set-Content -LiteralPath $checksumPath -Encoding ascii

# Preserve the immutable archive, then clear only the current top-level workspace.
foreach ($item in $payloadItems) {
    Remove-Item -LiteralPath (Join-Path $validationRoot $item.Name) -Recurse -Force
}

[pscustomobject]@{
    run_id = $RunId
    component_status = $componentStatus
    archive_directory = $runDirectory
    archive_zip = $zipPath
    archive_zip_sha256 = $zipSha256
    checksum_file = $checksumPath
    artifact_count = $artifactHashes.Count
    source_fingerprint_sha256 = $sourceFingerprint
    source_fingerprint_committed_sha256 = $sourceCommitted
    source_clean = $sourceClean
    artifact_fingerprint_sha256 = $artifactFingerprint
    archive_completeness = $completeness
}
