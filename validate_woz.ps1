<#
.SYNOPSIS
    Run the WOZ integration checks in one command.

.DESCRIPTION
    Verifies Quartus source selection and required files, checks the mirrored
    save-state hotkey RTL, runs its focused Verilator test, runs Quartus
    Analysis & Synthesis, summarizes Quartus artifacts, and checks Git/EOL
    hygiene. Use -FullCompile explicitly to run fitting, timing, and assembly.

.EXAMPLE
    .\validate_woz.bat
    .\validate_woz.bat -SkipMap
    .\validate_woz.bat -FullCompile
#>
param(
    [switch]$SkipMap,
    [switch]$SkipHotkeys,
    [switch]$FullCompile,
    [string]$QuartusBin
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$workspaceRoot = Split-Path -Parent $projectRoot
$verilogRoot = Join-Path $workspaceRoot 'Apple-II-Verilog_MiSTer'
$bashPath = 'C:\msys64\usr\bin\bash.exe'

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "== $Message ==" -ForegroundColor Cyan
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Convert-ToMsysPath([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    Assert-True ($fullPath -match '^([A-Za-z]):\\(.*)$') "Cannot convert path to MSYS form: $fullPath"
    return '/' + $matches[1].ToLowerInvariant() + '/' + ($matches[2] -replace '\\', '/')
}

function Resolve-QuartusExecutable([string]$Name) {
    if ($QuartusBin) {
        $candidate = Join-Path $QuartusBin "$Name.exe"
        Assert-True (Test-Path -LiteralPath $candidate) "Quartus executable not found: $candidate"
        return $candidate
    }

    $command = Get-Command "$Name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { return $command.Source }

    foreach ($base in @('C:\intelFPGA_lite\17.0\quartus\bin64', 'C:\intelFPGA\17.0\quartus\bin64', 'C:\altera\17.0\quartus\bin64')) {
        $candidate = Join-Path $base "$Name.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "Unable to find $Name.exe. Add Quartus to PATH or pass -QuartusBin."
}

Write-Step 'WOZ source selection'
$requiredFiles = @(
    'Apple-II_woz.sv',
    'rtl/apple2_top_woz.v',
    'rtl/woz/disk_ii_woz.sv',
    'rtl/woz/woz_floppy_controller.sv',
    'rtl/woz/flux_drive.v',
    'rtl/woz/woz_bram.sv',
    'rtl/woz/woz_cell525.sv',
    'rtl/woz/disk_ii_rom.v',
    'rtl/savestate_hotkeys.sv'
)
foreach ($relativePath in $requiredFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath)) "Missing required WOZ file: $relativePath"
}

$requiredAssignments = @(
    'rtl/woz/disk_ii_woz.sv',
    'rtl/woz/woz_floppy_controller.sv',
    'rtl/woz/flux_drive.v',
    'rtl/woz/woz_bram.sv',
    'rtl/woz/woz_cell525.sv',
    'rtl/woz/disk_ii_rom.v',
    'rtl/apple2_top_woz.v',
    '"Apple-II_woz.sv"',
    'rtl/savestate_hotkeys.sv'
)
$forbiddenAssignments = @(
    'rtl/disk_ii.v',
    'rtl/drive_ii.v',
    'rtl/floppy_track.sv',
    'rtl/apple2_top.v',
    '"Apple-II.sv"'
)
foreach ($sourceList in @('files.qip', 'Apple-II.qsf')) {
    $text = [IO.File]::ReadAllText((Join-Path $projectRoot $sourceList), [Text.Encoding]::UTF8)
    foreach ($assignment in $requiredAssignments) {
        Assert-True $text.Contains($assignment) "$sourceList is missing '$assignment'. Run toggle_woz.ps1 woz."
    }
    foreach ($assignment in $forbiddenAssignments) {
        Assert-True (-not $text.Contains($assignment)) "$sourceList still contains Disk II assignment '$assignment'."
    }
    Write-Host "PASS $sourceList"
}

Write-Step 'Save-state hotkey parity'
$fpgaHotkeys = Join-Path $projectRoot 'rtl\savestate_hotkeys.sv'
$simHotkeys = Join-Path $verilogRoot 'rtl\savestate_hotkeys.sv'
Assert-True (Test-Path -LiteralPath $simHotkeys) "Missing simulator hotkey RTL: $simHotkeys"
$fpgaHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fpgaHotkeys).Hash
$simHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $simHotkeys).Hash
Assert-True ($fpgaHash -eq $simHash) 'FPGA and Verilator savestate_hotkeys.sv copies differ.'
Write-Host 'PASS mirrored savestate_hotkeys.sv files are byte-identical'

if (-not $SkipHotkeys) {
    Assert-True (Test-Path -LiteralPath $bashPath) "MSYS2 bash not found: $bashPath"
    $levelDirMsys = Convert-ToMsysPath (Join-Path $verilogRoot 'unit_tests\level_1b')
    $verilogRootMsys = Convert-ToMsysPath $verilogRoot
    $hotkeyCommand = "export PATH=/ucrt64/bin:`$PATH TMP=/c/msys64/tmp TEMP=/c/msys64/tmp TMPDIR=/c/msys64/tmp; cd '$levelDirMsys' && /ucrt64/bin/mingw32-make.exe hotkeys && cd '$verilogRootMsys' && ./unit_tests/level_1b/build/hotkey_obj_dir/Vtb_savestate_hotkeys.exe"
    & $bashPath -lc $hotkeyCommand
    Assert-True ($LASTEXITCODE -eq 0) "Save-state hotkey test failed with exit code $LASTEXITCODE."
}

if ($FullCompile -and $SkipMap) {
    throw '-FullCompile and -SkipMap cannot be used together.'
}

if (-not $SkipMap) {
    if ($FullCompile) {
        Write-Step 'Quartus full compile'
        $quartus = Resolve-QuartusExecutable 'quartus_sh'
        Push-Location $projectRoot
        try { & $quartus --flow compile Apple-II } finally { Pop-Location }
        Assert-True ($LASTEXITCODE -eq 0) "Quartus full compile failed with exit code $LASTEXITCODE."
    } else {
        Write-Step 'Quartus Analysis & Synthesis'
        $quartus = Resolve-QuartusExecutable 'quartus_map'
        Push-Location $projectRoot
        try { & $quartus Apple-II --read_settings_files=on --write_settings_files=off } finally { Pop-Location }
        Assert-True ($LASTEXITCODE -eq 0) "Quartus Analysis & Synthesis failed with exit code $LASTEXITCODE."
    }
}

Write-Step 'Quartus reports'
$reportParameters = @{
    Revision = 'Apple-II'
    RequireFresh = $true
    RequireStages = if ($FullCompile) { @('map', 'fit', 'sta', 'asm') } else { @('map') }
}
& (Join-Path $projectRoot 'quartus_reports.ps1') @reportParameters

$mapReport = Join-Path $projectRoot 'output_files\Apple-II.map.rpt'
if (Test-Path -LiteralPath $mapReport) {
    $wozWarnings = Select-String -Path $mapReport -Pattern '^Warning .*?(Apple-II_woz\.sv|apple2_top_woz\.v|rtl[/\\]woz[/\\])' | ForEach-Object { $_.Line.Trim() }
    if ($wozWarnings.Count -gt 0) {
        Write-Host ''
        Write-Host 'WOZ-specific Quartus warnings:' -ForegroundColor Yellow
        $wozWarnings | ForEach-Object { Write-Host "  $_" }
    }
}

Write-Step 'Repository hygiene'
Push-Location $projectRoot
try {
    & git -c core.whitespace=cr-at-eol diff --check
    Assert-True ($LASTEXITCODE -eq 0) 'git diff --check failed.'
} finally { Pop-Location }
Write-Host 'PASS git diff --check (CRLF-aware)'

Assert-True (Test-Path -LiteralPath $bashPath) "MSYS2 bash not found: $bashPath"
$workspaceRootMsys = Convert-ToMsysPath $workspaceRoot
$projectRootMsys = Convert-ToMsysPath $projectRoot
$eolPaths = @(
    'Apple-II_woz.sv',
    'Apple-II.qsf',
    'files.qip',
    'rtl/apple2_top_woz.v',
    'rtl/woz/',
    'rtl/savestate_hotkeys.sv',
    'quartus_reports.ps1',
    'validate_woz.ps1',
    'validate_woz.bat'
) -join ' '
$eolCommand = "cd '$projectRootMsys' && bash '$workspaceRootMsys/eol_guard.sh' $eolPaths"
& $bashPath -lc $eolCommand
Assert-True ($LASTEXITCODE -eq 0) 'EOL guard detected unintended CR-count drift.'

Write-Host ''
Write-Host 'WOZ VALIDATION PASS' -ForegroundColor Green
