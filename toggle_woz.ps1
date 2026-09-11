<#
.SYNOPSIS
    Switch the Apple-II Quartus project between the Disk II (.nib) and WOZ
    (.woz) disk variants. Rewrites files.qip and Apple-II.qsf in place.

    Byte-safe: reads/writes whole files as raw text (no line-ending or
    encoding normalization; both files are CRLF and stay CRLF).
    Close Quartus before running (it rewrites the qsf on exit).

.EXAMPLE
    .\toggle_woz.ps1 woz      # project builds Apple-II_woz.sv + WOZ stack
    .\toggle_woz.ps1 diskii   # project builds Apple-II.sv + Disk II stack

SEE ALSO
    savestates\WOZ_MERGE.md - what the variants change and how to re-sync them.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('woz', 'diskii')]
    [string]$Mode
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition

$diskiiTop = 'set_global_assignment -name VERILOG_FILE rtl/apple2_top.v'
$wozTop    = 'set_global_assignment -name VERILOG_FILE rtl/apple2_top_woz.v'
$diskiiEmu = 'set_global_assignment -name SYSTEMVERILOG_FILE "Apple-II.sv"'
$wozEmu    = 'set_global_assignment -name SYSTEMVERILOG_FILE "Apple-II_woz.sv"'
$lineDiskii  = 'set_global_assignment -name VERILOG_FILE rtl/disk_ii.v'
$lineDriveii = 'set_global_assignment -name VERILOG_FILE rtl/drive_ii.v'
$lineFt      = 'set_global_assignment -name SYSTEMVERILOG_FILE rtl/floppy_track.sv'
$lineJoyKey  = 'set_global_assignment -name VERILOG_FILE rtl/osk/joy_to_key.v'
$wozBlock = @(
    'set_global_assignment -name SYSTEMVERILOG_FILE rtl/woz/disk_ii_woz.sv',
    'set_global_assignment -name SYSTEMVERILOG_FILE rtl/woz/woz_floppy_controller.sv',
    'set_global_assignment -name SYSTEMVERILOG_FILE rtl/woz/flux_drive.v',
    'set_global_assignment -name SYSTEMVERILOG_FILE rtl/woz/woz_bram.sv',
    'set_global_assignment -name SYSTEMVERILOG_FILE rtl/woz/woz_cell525.sv',
    'set_global_assignment -name VERILOG_FILE rtl/woz/disk_ii_rom.v'
)
$CRLF = "`r`n"

foreach ($path in @("$root\files.qip", "$root\Apple-II.qsf")) {
    $text = [System.IO.File]::ReadAllText($path)

    if ($Mode -eq 'woz') {
        if ($text.Contains('rtl/woz/disk_ii_woz.sv')) {
            Write-Host "Already in WOZ mode, skipping: $path" -ForegroundColor Yellow
            continue
        }
        # Remove the two lines the WOZ block supersedes (drive_ii, floppy_track).
        $text = $text.Replace("$CRLF$lineDriveii$CRLF", $CRLF)
        $text = $text.Replace("$CRLF$lineFt$CRLF", $CRLF)
        # The disk_ii line becomes the 6-line WOZ block, in the same position.
        $text = $text.Replace($lineDiskii, ($wozBlock -join $CRLF))
        # Variant files.
        $text = $text.Replace($diskiiTop, $wozTop)
        $text = $text.Replace($diskiiEmu, $wozEmu)

        $mustHave  = @('rtl/woz/disk_ii_woz.sv', 'rtl/apple2_top_woz.v', '"Apple-II_woz.sv"')
        $mustNot   = @('rtl/disk_ii.v', 'rtl/drive_ii.v', 'rtl/floppy_track.sv')
    }
    else {
        if (-not $text.Contains('rtl/woz/disk_ii_woz.sv')) {
            Write-Host "Already in Disk II mode, skipping: $path" -ForegroundColor Yellow
            continue
        }
        # The 6-line WOZ block becomes disk_ii + drive_ii, in the same position.
        $text = $text.Replace(($wozBlock -join $CRLF), "$lineDiskii$CRLF$lineDriveii")
        # floppy_track is restored after the joy_to_key line (its original spot).
        $text = $text.Replace($lineJoyKey, "$lineJoyKey$CRLF$lineFt")
        # Variant files.
        $text = $text.Replace($wozTop, $diskiiTop)
        $text = $text.Replace($wozEmu, $diskiiEmu)

        $mustHave  = @('rtl/disk_ii.v', 'rtl/drive_ii.v', 'rtl/floppy_track.sv',
                       'rtl/apple2_top.v', '"Apple-II.sv"')
        $mustNot   = @('rtl/woz/', 'rtl/apple2_top_woz.v', '"Apple-II_woz.sv"')
    }

    foreach ($m in $mustHave) {
        if (-not $text.Contains($m)) {
            throw "Toggle verification failed for $path : missing '$m'"
        }
    }
    foreach ($m in $mustNot) {
        if ($text.Contains($m)) {
            throw "Toggle verification failed for $path : still contains '$m'"
        }
    }

    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Updated: $path"
}

Write-Host ""
Write-Host "Project is now in $Mode disk mode." -ForegroundColor Green
Write-Host "Next: run Analysis & Synthesis to prove binding, then a full compile."
