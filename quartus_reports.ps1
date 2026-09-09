<#
.SYNOPSIS
    Summarize Quartus map, fit, timing, and assembler artifacts.

.DESCRIPTION
    Reads existing Quartus reports without starting a compile. Downstream
    stages older than Analysis & Synthesis are marked stale so results from a
    previous source variant are not mistaken for current results.

.EXAMPLE
    .\quartus_reports.ps1
    .\quartus_reports.ps1 -RequireStages map,fit,sta,asm -RequireFresh
#>
param(
    [string]$Revision = 'Apple-II',
    [string]$OutputDirectory = 'output_files',
    [ValidateSet('map', 'fit', 'sta', 'asm')]
    [string[]]$RequireStages = @(),
    [switch]$RequireFresh
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$outputRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
} else {
    Join-Path $root $OutputDirectory
}

function Read-Utf8Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Get-FirstMatch([string]$Text, [string[]]$Patterns) {
    if ($null -eq $Text) { return $null }
    foreach ($pattern in $Patterns) {
        $match = [regex]::Match($Text, $pattern, 'IgnoreCase, Multiline')
        if ($match.Success) { return $match.Groups[1].Value.Trim() }
    }
    return $null
}

function Get-MessageCount([string]$Text, [string]$Kind) {
    if ($null -eq $Text) { return $null }
    $total = Get-FirstMatch $Text @(
        ";\s*Total $Kind\s*;\s*([0-9,]+)\s*;",
        "Total $Kind\s*:\s*([0-9,]+)",
        "(?:successful|failed)[^\r\n]*?\b([0-9,]+)\s+$Kind\b"
    )
    if ($null -ne $total) { return [int]($total -replace ',', '') }
    $messageKind = $Kind.TrimEnd('s')
    return ([regex]::Matches($Text, "(?i)\b$messageKind(?: \([0-9]+\))?:")).Count
}

function Get-StageStatus([string]$Stage, [string]$SummaryText, [string]$ReportText) {
    $patterns = switch ($Stage) {
        'map' { @('Analysis & Synthesis Status\s*:\s*([^\r\n]+)') }
        'fit' { @('Fitter Status\s*:\s*([^\r\n]+)') }
        'sta' { @('Timing Analyzer Status\s*:\s*([^\r\n]+)', 'Timing Analyzer was (successful)') }
        'asm' { @('Assembler Status\s*:\s*([^\r\n]+)', 'Assembler was (successful)') }
    }
    $status = Get-FirstMatch $SummaryText $patterns
    if ($null -eq $status) { $status = Get-FirstMatch $ReportText $patterns }
    if ($null -eq $status) { return 'Unknown' }
    if ($status -match '(?i)successful') { return 'Successful' }
    if ($status -match '(?i)failed|error') { return 'Failed' }
    return $status
}

$stageDefinitions = @(
    @{ Name = 'map'; Label = 'Analysis & Synthesis'; Summary = "$Revision.map.summary"; Report = "$Revision.map.rpt" },
    @{ Name = 'fit'; Label = 'Fitter'; Summary = "$Revision.fit.summary"; Report = "$Revision.fit.rpt" },
    @{ Name = 'sta'; Label = 'Timing'; Summary = "$Revision.sta.summary"; Report = "$Revision.sta.rpt" },
    @{ Name = 'asm'; Label = 'Assembler'; Summary = $null; Report = "$Revision.asm.rpt" }
)

$results = @()
$mapTimestamp = $null
foreach ($definition in $stageDefinitions) {
    $summaryPath = if ($null -ne $definition.Summary) { Join-Path $outputRoot $definition.Summary } else { $null }
    $reportPath = Join-Path $outputRoot $definition.Report
    $artifactPath = if (($null -ne $summaryPath) -and (Test-Path -LiteralPath $summaryPath)) { $summaryPath } elseif (Test-Path -LiteralPath $reportPath) { $reportPath } else { $null }
    $summaryText = if ($null -ne $summaryPath) { Read-Utf8Text $summaryPath } else { $null }
    $reportText = Read-Utf8Text $reportPath
    $timestamp = if ($null -ne $artifactPath) { (Get-Item -LiteralPath $artifactPath).LastWriteTime } else { $null }
    if ($definition.Name -eq 'map') { $mapTimestamp = $timestamp }
    $stale = ($definition.Name -ne 'map') -and ($null -ne $timestamp) -and ($null -ne $mapTimestamp) -and ($timestamp -lt $mapTimestamp)

    $results += [pscustomobject]@{
        Stage = $definition.Name
        Label = $definition.Label
        Present = $null -ne $artifactPath
        Status = Get-StageStatus $definition.Name $summaryText $reportText
        Timestamp = $timestamp
        Stale = $stale
        Errors = Get-MessageCount $reportText 'errors'
        Warnings = Get-MessageCount $reportText 'warnings'
        SummaryText = $summaryText
        ReportText = $reportText
    }
}

Write-Host "Quartus report summary: $Revision" -ForegroundColor Cyan
foreach ($result in $results) {
    if (-not $result.Present) {
        Write-Host ("  {0,-20} MISSING" -f $result.Label) -ForegroundColor Yellow
        continue
    }
    $freshness = if ($result.Stale) { 'STALE' } else { 'current' }
    $counts = if (($null -ne $result.Errors) -and ($null -ne $result.Warnings)) {
        "errors=$($result.Errors) warnings=$($result.Warnings)"
    } else { 'message counts unavailable' }
    $color = if ($result.Status -eq 'Failed') { 'Red' } elseif ($result.Stale) { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-20} {1,-10} {2,-7} {3:yyyy-MM-dd HH:mm:ss}  {4}" -f $result.Label, $result.Status, $freshness, $result.Timestamp, $counts) -ForegroundColor $color
}

$map = $results | Where-Object { $_.Stage -eq 'map' }
if ($map.Present) {
    $resourceText = $map.SummaryText
    Write-Host ''
    Write-Host 'Map resources:' -ForegroundColor Cyan
    foreach ($label in @('Logic utilization \(in ALMs\)', 'Total registers', 'Total block memory bits', 'Total DSP Blocks', 'Total PLLs')) {
        $value = Get-FirstMatch $resourceText @("$label\s*:\s*([^\r\n]+)")
        if ($null -ne $value) { Write-Host ("  {0}: {1}" -f ($label -replace '\\', ''), $value) }
    }
}

$sta = $results | Where-Object { $_.Stage -eq 'sta' }
if ($sta.Present) {
    $setupSlack = Get-FirstMatch $sta.SummaryText @("Type\s*:\s*Setup[^\r\n]*[\r\n]+Slack\s*:\s*([-+0-9.]+)")
    $holdSlack = Get-FirstMatch $sta.SummaryText @("Type\s*:\s*Hold[^\r\n]*[\r\n]+Slack\s*:\s*([-+0-9.]+)")
    if (($null -ne $setupSlack) -or ($null -ne $holdSlack)) {
        Write-Host ''
        Write-Host "Timing summary: setup slack=$setupSlack ns, hold slack=$holdSlack ns" -ForegroundColor Cyan
    }
}

$rbfPath = Join-Path $outputRoot "$Revision.rbf"
if (Test-Path -LiteralPath $rbfPath) {
    $rbf = Get-Item -LiteralPath $rbfPath
    $rbfStale = ($null -ne $mapTimestamp) -and ($rbf.LastWriteTime -lt $mapTimestamp)
    $rbfState = if ($rbfStale) { 'STALE' } else { 'current' }
    Write-Host ("RBF: {0} ({1}, {2:yyyy-MM-dd HH:mm:ss})" -f $rbf.FullName, $rbfState, $rbf.LastWriteTime) -ForegroundColor $(if ($rbfStale) { 'Yellow' } else { 'Green' })
} else {
    Write-Host 'RBF: missing' -ForegroundColor Yellow
}

$failed = $false
foreach ($required in $RequireStages) {
    $result = $results | Where-Object { $_.Stage -eq $required }
    if ((-not $result.Present) -or ($result.Status -ne 'Successful')) {
        Write-Error "Required Quartus stage '$required' is missing or unsuccessful."
        $failed = $true
    } elseif ($RequireFresh -and $result.Stale) {
        Write-Error "Required Quartus stage '$required' is stale relative to Analysis & Synthesis."
        $failed = $true
    }
}

if ($failed) { throw 'One or more required Quartus stages failed validation.' }
