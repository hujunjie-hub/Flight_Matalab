[CmdletBinding()]
param(
    [string]$GccDir = 'D:\STM32CubeCLT\mingw64\bin',
    [string]$ArmBin = 'D:\STM32CubeCLT\GNU-tools-for-STM32\bin',
    [string]$MatlabExe = ''
)

$ErrorActionPreference = 'Stop'

function Write-Stage([string]$Message) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
}

function Invoke-Git([string]$RepoPath, [string[]]$GitArgs) {
    $output = @(& git -C $RepoPath @GitArgs 2>&1)
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) {
        throw "Git command failed in $($RepoPath): git $($GitArgs -join ' ')"
    }
}

function Sync-MainRepository([string]$RepoPath, [string]$Label) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        throw "$Label repository not found or not a Git worktree: $RepoPath"
    }

    $dirty = @(& git -C $RepoPath status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw "Cannot read $Label Git status." }
    if ($dirty.Count -gt 0) {
        Write-Host "$Label has local changes. Nothing was overwritten:" -ForegroundColor Red
        $dirty | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        throw "Commit or hand off these local changes first, then rerun. The script never resets or cleans a worktree."
    }

    Invoke-Git -RepoPath $RepoPath -GitArgs @('fetch', 'origin', '--prune')

    $mainBranch = @(& git -C $RepoPath branch --list main)
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $Label local branches." }
    if ($mainBranch.Count -eq 0) {
        Invoke-Git -RepoPath $RepoPath -GitArgs @('switch', '--track', '-c', 'main', 'origin/main')
    } else {
        Invoke-Git -RepoPath $RepoPath -GitArgs @('switch', 'main')
    }

    Invoke-Git -RepoPath $RepoPath -GitArgs @('pull', '--ff-only', 'origin', 'main')

    $branch = (& git -C $RepoPath branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
        throw "$Label is not on main after synchronization."
    }

    $commit = (& git -C $RepoPath rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') {
        throw "Cannot read $Label main commit."
    }

    $dirtyAfter = @(& git -C $RepoPath status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirtyAfter.Count -gt 0) {
        throw "$Label is not clean after synchronization; stop and inspect the worktree."
    }

    Write-Host "$Label main: $commit" -ForegroundColor Green
    return $commit
}

function Resolve-MatlabExecutable {
    if (-not [string]::IsNullOrWhiteSpace($MatlabExe)) {
        if (Test-Path -LiteralPath $MatlabExe -PathType Leaf) {
            return (Resolve-Path -LiteralPath $MatlabExe).Path
        }
        $resolved = Get-Command $MatlabExe -ErrorAction SilentlyContinue
        if ($resolved) { return $resolved.Source }
        throw "MATLAB executable not found: $MatlabExe"
    }

    $command = Get-Command matlab.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $matlabRoot = Join-Path $env:ProgramFiles 'MATLAB'
    if (Test-Path -LiteralPath $matlabRoot -PathType Container) {
        $candidates = @(Get-ChildItem -LiteralPath $matlabRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'bin\matlab.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        if ($candidates.Count -gt 0) { return $candidates[0] }
    }

    throw "Cannot find matlab.exe. Add MATLAB to PATH or rerun with -MatlabExe 'C:\Program Files\MATLAB\R2026b\bin\matlab.exe'."
}

function Get-FirstVersionLine([string]$Executable, [string[]]$Arguments) {
    try {
        $lines = @(& $Executable @Arguments 2>&1)
        if ($lines.Count -gt 0) { return [string]$lines[0] }
    } catch {}
    return 'UNAVAILABLE'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workspaceRoot = Split-Path -Parent $repoRoot
$flightRoot = Join-Path $workspaceRoot 'Flight'
$validationRoot = Join-Path $repoRoot 'work\validation'
$archiveRoot = Join-Path $validationRoot 'archives'

Write-Stage '0/6 预检本地工具与工作区'
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw 'git.exe is not available in PATH.'
}
$pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $pythonCommand) { throw 'python.exe is not available in PATH.' }
$pythonExe = $pythonCommand.Source
$pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $pwshCommand) { throw 'pwsh.exe is not available. Install PowerShell 7 or add pwsh to PATH.' }
$pwshExe = $pwshCommand.Source

$GccDir = (Resolve-Path -LiteralPath $GccDir).Path
foreach ($tool in @('gcc.exe', 'g++.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $GccDir $tool) -PathType Leaf)) {
        throw "Required Host SIL compiler is missing: $(Join-Path $GccDir $tool)"
    }
}
$matlabExecutable = Resolve-MatlabExecutable
if (-not (Test-Path -LiteralPath $flightRoot -PathType Container)) {
    throw "The sibling Flight repository is missing. Expected: $flightRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'Flight_Matalab.prj') -PathType Leaf)) {
    throw 'Flight_Matalab.prj was not found in the repository root.'
}

Write-Stage '1/6 同步 Flight_Matlab/main 与 Flight/main'
$projectCommit = Sync-MainRepository $repoRoot 'Flight_Matlab'
$flightCommit = Sync-MainRepository $flightRoot 'Flight'

New-Item -ItemType Directory -Force -Path $validationRoot,$archiveRoot | Out-Null
$runStarted = (Get-Date).ToUniversalTime()
$gccVersion = Get-FirstVersionLine (Join-Path $GccDir 'gcc.exe') @('--version')
$armGcc = Join-Path $ArmBin 'arm-none-eabi-gcc.exe'
$armGxx = Join-Path $ArmBin 'arm-none-eabi-g++.exe'
$armObjcopy = Join-Path $ArmBin 'arm-none-eabi-objcopy.exe'
$hostObjcopy = Join-Path $GccDir 'objcopy.exe'
$abiToolchainReady = (Test-Path -LiteralPath $armGcc -PathType Leaf) -and
    (Test-Path -LiteralPath $armGxx -PathType Leaf) -and
    (Test-Path -LiteralPath $armObjcopy -PathType Leaf) -and
    (Test-Path -LiteralPath $hostObjcopy -PathType Leaf)

$context = [ordered]@{
    started_at_utc = $runStarted.ToString('o')
    project_branch = 'main'
    project_commit = $projectCommit
    flight_branch = 'main'
    flight_commit = $flightCommit
    matlab_executable = $matlabExecutable
    operating_system = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    powershell_version = $PSVersionTable.PSVersion.ToString()
    python_executable = $pythonExe
    gcc_directory = $GccDir
    gcc_version = $gccVersion
    arm_compiler_directory = $ArmBin
    arm_toolchain_available = $abiToolchainReady
}
$context | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $validationRoot 'local_run_context.json') -Encoding utf8

Write-Stage '2/6 启动 MATLAB 完整验收'
$matlabRoot = $repoRoot.Replace('\', '/').Replace("'", "''")
$gccMatlab = $GccDir.Replace('\', '/').Replace("'", "''")
$diaryPath = (Join-Path $validationRoot 'matlab_acceptance_diary.txt').Replace('\', '/').Replace("'", "''")
$matlabScriptPath = Join-Path $env:TEMP ("flight_matlab_acceptance_" + [Guid]::NewGuid().ToString('N') + '.m')
$matlabScript = @"
cd('$matlabRoot');
reportDir = fullfile('$matlabRoot', 'work', 'validation');
if ~isfolder(reportDir)
    mkdir(reportDir);
end
diaryFile = '$diaryPath';
diary(diaryFile);
diary on;
try
    disp(['MATLAB release: ' version('-release')]);
    disp(['MATLAB version: ' version]);
    selectedMex = mex.getCompilerConfigurations('C', 'Selected');
    if isempty(selectedMex)
        disp('No selected MEX C compiler; invoking mex -setup C.');
        mex -setup C;
        selectedMex = mex.getCompilerConfigurations('C', 'Selected');
    end
    assert(~isempty(selectedMex), 'Flight:MexCompilerMissing', ...
        'No C MEX compiler is selected. Run mex -setup C in MATLAB Desktop once, then rerun this script.');
    disp(['Selected MEX C compiler: ' selectedMex(1).Name]);
    root = flight_startup;
    cd(root);
    run_component_checks('$gccMatlab');
catch ME
    disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    diary off;
    rethrow(ME);
end
diary off;
"@
Set-Content -LiteralPath $matlabScriptPath -Value $matlabScript -Encoding utf8

$matlabConsoleLog = Join-Path $validationRoot 'matlab_batch_console.txt'
$matlabExitCode = 9009
try {
    $matlabRunPath = $matlabScriptPath.Replace('\', '/').Replace("'", "''")
    $matlabOutput = @(& $matlabExecutable -batch "run('$matlabRunPath')" 2>&1)
    $matlabExitCode = $LASTEXITCODE
    $matlabOutput | ForEach-Object { Write-Host $_ }
    $matlabOutput | Out-File -LiteralPath $matlabConsoleLog -Encoding utf8
}
catch {
    $_ | Out-String | Set-Content -LiteralPath $matlabConsoleLog -Encoding utf8
    Write-Host $_ -ForegroundColor Red
}
finally {
    if (Test-Path -LiteralPath $matlabScriptPath) {
        Remove-Item -LiteralPath $matlabScriptPath -Force
    }
}
$context.matlab_exit_code = $matlabExitCode
$context | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $validationRoot 'local_run_context.json') -Encoding utf8
if ($matlabExitCode -eq 0) {
    Write-Host 'MATLAB process completed. The component report still determines PASS/PARTIAL/FAIL.' -ForegroundColor Green
} else {
    Write-Host "MATLAB exited with code $matlabExitCode. The script will archive the failure evidence before stopping." -ForegroundColor Yellow
}

Write-Stage '3/6 归档 MATLAB 本轮证据（即使测试失败也执行）'
$existingArchives = @()
if (Test-Path -LiteralPath $archiveRoot -PathType Container) {
    $existingArchives = @(Get-ChildItem -LiteralPath $archiveRoot -Filter '*.zip' -File | ForEach-Object Name)
}
& $pwshExe -NoProfile -File (Join-Path $repoRoot 'tools\archive_validation_run.ps1') -RepoRoot $repoRoot
$archiveExitCode = $LASTEXITCODE
if ($archiveExitCode -ne 0) {
    throw "MATLAB evidence archive failed (exit $archiveExitCode). Keep the entire work\validation folder and send it for diagnosis."
}
$newMatlabArchives = @(Get-ChildItem -LiteralPath $archiveRoot -Filter '*.zip' -File |
    Where-Object { $existingArchives -notcontains $_.Name -and $_.Name -notmatch '_ABI|_DELIVERY' } |
    Sort-Object LastWriteTime -Descending)
if ($newMatlabArchives.Count -eq 0) {
    throw "No new MATLAB archive was created in $archiveRoot."
}
$matlabZip = $newMatlabArchives[0]
$runId = [System.IO.Path]::GetFileNameWithoutExtension($matlabZip.Name)
$matlabChecksum = $matlabZip.FullName + '.sha256'
if (-not (Test-Path -LiteralPath $matlabChecksum -PathType Leaf)) {
    throw "MATLAB archive checksum is missing: $matlabChecksum"
}
Write-Host "MATLAB archive: $($matlabZip.FullName)" -ForegroundColor Green

Write-Stage '4/6 运行 FMAT-0018 ARM/Host ABI 检查'
$abiStatus = 'SKIPPED_TOOLCHAIN_MISSING'
$abiExitCode = $null
$abiZip = $null
$abiChecksum = $null
$abiConsole = @()
$evidenceDir = Join-Path $flightRoot 'tests\abi\evidence'
$backupEvidenceDir = Join-Path $env:TEMP ("flight_abi_evidence_backup_" + $runId)

if ($abiToolchainReady) {
    if (Test-Path -LiteralPath $backupEvidenceDir) {
        throw "Temporary ABI evidence backup already exists: $backupEvidenceDir"
    }
    if (Test-Path -LiteralPath $evidenceDir) {
        Move-Item -LiteralPath $evidenceDir -Destination $backupEvidenceDir
    }

    try {
        Push-Location $flightRoot
        try {
            $abiConsole = @(& $pythonExe -B 'tests\abi\abi_report.py' --arm-bin $ArmBin --host-bin $GccDir 2>&1)
            $abiExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $abiConsole | ForEach-Object { Write-Host $_ }
        $freshCompare = Join-Path $evidenceDir 'abi_compare.json'
        if (Test-Path -LiteralPath $freshCompare -PathType Leaf) {
            $compareData = Get-Content -LiteralPath $freshCompare -Raw | ConvertFrom-Json
            $abiStatus = [string]$compareData.status
            if ($abiExitCode -ne 0 -and $abiStatus -eq 'PASS') {
                $abiStatus = 'FAIL_PROCESS_EXIT'
            }
            if (Test-Path -LiteralPath $backupEvidenceDir) {
                Remove-Item -LiteralPath $backupEvidenceDir -Recurse -Force
            }
        } else {
            $abiStatus = 'FAIL_NO_FRESH_REPORT'
            if (Test-Path -LiteralPath $evidenceDir) {
                Remove-Item -LiteralPath $evidenceDir -Recurse -Force
            }
            if (Test-Path -LiteralPath $backupEvidenceDir) {
                Move-Item -LiteralPath $backupEvidenceDir -Destination $evidenceDir
            }
        }
    }
    catch {
        $abiStatus = 'FAIL_SCRIPT'
        $abiConsole += ($_ | Out-String)
        if ((Test-Path -LiteralPath $evidenceDir) -and
            -not (Test-Path -LiteralPath (Join-Path $evidenceDir 'abi_compare.json'))) {
            Remove-Item -LiteralPath $evidenceDir -Recurse -Force
        }
        if ((Test-Path -LiteralPath $backupEvidenceDir) -and
            -not (Test-Path -LiteralPath $evidenceDir)) {
            Move-Item -LiteralPath $backupEvidenceDir -Destination $evidenceDir
        }
    }

    $abiStage = Join-Path $archiveRoot ($runId + '_ABI_payload')
    New-Item -ItemType Directory -Force -Path $abiStage | Out-Null
    $abiLogPath = Join-Path $abiStage 'abi_console.txt'
    $abiConsole | Out-File -LiteralPath $abiLogPath -Encoding utf8
    $abiSummary = [ordered]@{
        run_id = $runId
        flight_commit = $flightCommit
        status = $abiStatus
        process_exit_code = $abiExitCode
        arm_bin = $ArmBin
        host_bin = $GccDir
        lock_regeneration = 'NOT_REQUESTED'
    }
    $abiSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $abiStage 'abi_summary.json') -Encoding utf8

    $abiFiles = @(
        'abi_arm.json', 'abi_host.json', 'abi_compare.json', 'abi_report.md',
        'commands.json', 'artifact_sha256.json', 'abi_probe.c',
        'abi_canonical_arm.txt', 'abi_canonical_host.txt'
    )
    foreach ($name in $abiFiles) {
        $source = Join-Path $evidenceDir $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $abiStage -Force
        }
    }

    $abiZip = Join-Path $archiveRoot ($runId + '_ABI.zip')
    if (Test-Path -LiteralPath $abiZip) { throw "ABI archive already exists: $abiZip" }
    Compress-Archive -Path (Join-Path $abiStage '*') -DestinationPath $abiZip -CompressionLevel Optimal
    Remove-Item -LiteralPath $abiStage -Recurse -Force
    $abiChecksum = $abiZip + '.sha256'
    $abiHash = (Get-FileHash -LiteralPath $abiZip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$abiHash  $(Split-Path $abiZip -Leaf)" | Set-Content -LiteralPath $abiChecksum -Encoding ascii
    $abiColor = 'Yellow'
    if ($abiStatus -eq 'PASS') { $abiColor = 'Green' }
    Write-Host "ABI evidence: $abiZip ($abiStatus)" -ForegroundColor $abiColor
} else {
    Write-Warning "ARM/Host ABI toolchain not found. MATLAB archive is complete; FMAT-0018 ABI check was skipped. Expected ARM tools in $ArmBin and objcopy in $GccDir."
}

Write-Stage '5/6 生成一个总交付包'
$flightWorktree = @(& git -C $flightRoot status --porcelain)
$projectWorktree = @(& git -C $repoRoot status --porcelain)
$componentStatus = 'REPORT_NOT_FOUND'
$componentPath = Join-Path $archiveRoot ($runId + '\component_checks.json')
if (Test-Path -LiteralPath $componentPath -PathType Leaf) {
    try {
        $componentStatus = [string]((Get-Content -LiteralPath $componentPath -Raw | ConvertFrom-Json).status)
    } catch { $componentStatus = 'INVALID_REPORT' }
}

$summaryPath = Join-Path $archiveRoot ($runId + '_DELIVERY.txt')
$summaryLines = @(
    "RUN_ID: $runId",
    "Flight_Matlab commit: $projectCommit",
    "Flight commit: $flightCommit",
    "MATLAB process exit code: $matlabExitCode",
    "MATLAB component_checks status: $componentStatus",
    "FMAT-0018 ABI status: $abiStatus",
    "ABI process exit code: $abiExitCode",
    "MATLAB archive: $($matlabZip.FullName)",
    "MATLAB SHA256 file: $matlabChecksum",
    "ABI archive: $(if ($abiZip) { $abiZip } else { 'NOT_CREATED' })",
    "ABI SHA256 file: $(if ($abiChecksum) { $abiChecksum } else { 'NOT_CREATED' })",
    "Flight worktree status after ABI check: $($flightWorktree -join '; ')",
    "Flight_Matlab worktree status after validation: $($projectWorktree -join '; ')",
    "Do not reset, clean, or commit generated ABI evidence. Send this delivery package to the maintainer for review."
)
$summaryLines | Set-Content -LiteralPath $summaryPath -Encoding utf8

$deliveryZip = Join-Path $archiveRoot ($runId + '_DELIVERY.zip')
$deliveryItems = @($matlabZip.FullName, $matlabChecksum, $summaryPath)
if ($abiZip -and (Test-Path -LiteralPath $abiZip)) {
    $deliveryItems += $abiZip
    $deliveryItems += $abiChecksum
}
if (Test-Path -LiteralPath $deliveryZip) { throw "Delivery package already exists: $deliveryZip" }
Compress-Archive -LiteralPath $deliveryItems -DestinationPath $deliveryZip -CompressionLevel Optimal
$deliveryChecksum = $deliveryZip + '.sha256'
$deliveryHash = (Get-FileHash -LiteralPath $deliveryZip -Algorithm SHA256).Hash.ToLowerInvariant()
"$deliveryHash  $(Split-Path $deliveryZip -Leaf)" | Set-Content -LiteralPath $deliveryChecksum -Encoding ascii

Write-Stage '6/6 完成：只需交付一个总包'
Write-Host "RUN_ID: $runId" -ForegroundColor Green
Write-Host "MATLAB status: $componentStatus (process exit $matlabExitCode)"
Write-Host "FMAT-0018 ABI status: $abiStatus"
Write-Host "ONE FILE TO SEND: $deliveryZip" -ForegroundColor Green
Write-Host "CHECKSUM: $deliveryChecksum" -ForegroundColor Green
Write-Host 'Do not commit or discard generated files. The maintainer will review them and update main/SPEC/Issues.'
