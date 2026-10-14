#Requires -Version 5.1
<#
.SYNOPSIS
    Guided USB capture of SteelSeries GG talking to your device, for adding hardware support to ssgg.

.DESCRIPTION
    1. Installs Wireshark (tshark) and USBPcap with winget if they are missing.
    2. Lets you pick the connected SteelSeries device.
    3. Opens an always-on-top window that tells you which setting to change in GG, one step at a time,
       while USBPcap records the USB traffic. Every step is timestamped.
    4. Cuts the capture down to your SteelSeries device only, decodes the HID reports, groups them per
       step and writes a report folder plus a zip you can attach to a GitHub issue or PR.

    See docs/development/adding-hardware.md for what to do with the result.

    PRIVACY: everything the device sends is recorded, including key presses on a keyboard.
    Do not type passwords or private text while the capture runs.

.PARAMETER DeviceType
    keyboard, mouse, headset or other. Picks the built-in step list.

.PARAMETER StepsFile
    Optional text file with your own steps, one per line (blank lines and lines starting with # are
    ignored). A step starting with "Idle" waits IdleSeconds instead of waiting for a click.

.PARAMETER SkipStartup
    Do not stop and restart SteelSeries GG. Without this switch GG is closed before the capture so its
    startup (initialisation) traffic is recorded too.

.EXAMPLE
    .\scripts\capture-device.ps1 -DeviceType keyboard
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('keyboard', 'mouse', 'headset', 'other')]
    [string]$DeviceType,
    [string]$StepsFile,
    [string]$OutDir,
    [ValidateRange(3, 120)]
    [int]$IdleSeconds = 10,
    [ValidateRange(1, 30)]
    [int]$SettleSeconds = 4,
    [switch]$SkipStartup
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

if ($env:OS -ne 'Windows_NT') { throw 'This script needs Windows (SteelSeries GG and USBPcap are Windows-only).' }

# USBPcap needs admin to open the capture device; relaunch elevated with the same arguments.
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($kv.Value.IsPresent) { $argList += "-$($kv.Key)" }
        } else {
            $argList += "-$($kv.Key)", "`"$($kv.Value)`""
        }
    }
    Write-Host 'Administrator rights are needed for USB capture. Relaunching elevated...'
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    return
}

$tshark = Join-Path $env:ProgramFiles 'Wireshark\tshark.exe'
$usbpcap = Join-Path $env:ProgramFiles 'USBPcap\USBPcapCMD.exe'

function Install-IfMissing([string]$Path, [string]$WingetId) {
    if (Test-Path $Path) { return $false }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "$Path not found and winget is unavailable. Install '$WingetId' manually, then run this script again."
    }
    Write-Host "Installing $WingetId ..."
    winget install --id $WingetId -e --accept-package-agreements --accept-source-agreements
    if (-not (Test-Path $Path)) { throw "Installing $WingetId did not create $Path." }
    return $true
}

[void](Install-IfMissing $tshark 'WiresharkFoundation.Wireshark')
if (Install-IfMissing $usbpcap 'desowin.USBPcap') {
    Write-Host 'USBPcap was just installed. Reboot Windows, then run this script again.' -ForegroundColor Yellow
    return
}

$hubs = @(& $usbpcap --extcap-interfaces | ForEach-Object {
        if ($_ -match 'value=(\\\\\.\\USBPcap\d+)') { $Matches[1] }
    })
if ($hubs.Count -eq 0) { throw 'USBPcap found no root hubs. Reboot after installing USBPcap, then try again.' }

# --- pick the device --------------------------------------------------------------------------
$devices = @(Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^USB\\VID_1038&PID_([0-9A-F]{4})\\' } |
        ForEach-Object {
            $productId = $Matches[1]
            $desc = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc' -ErrorAction SilentlyContinue).Data
            [pscustomobject]@{ ProductId = $productId; Name = $(if ($desc) { $desc } else { $_.FriendlyName }); InstanceId = $_.InstanceId }
        })
if ($devices.Count -eq 0) { throw 'No SteelSeries USB device (VID 1038) is connected.' }

for ($i = 0; $i -lt $devices.Count; $i++) {
    Write-Host ('  [{0}] {1}  (PID 0x{2})' -f ($i + 1), $devices[$i].Name, $devices[$i].ProductId)
}
$choice = 1
if ($devices.Count -gt 1) { $choice = [int](Read-Host "Which device? (1-$($devices.Count))") }
if ($choice -lt 1 -or $choice -gt $devices.Count) { throw "Invalid choice: $choice" }
$device = $devices[$choice - 1]
$productId = $device.ProductId.ToLower()

# --- steps ------------------------------------------------------------------------------------
# One change per step, so each GG upload maps to exactly one setting.
$builtinSteps = @{
    keyboard = @(
        'Idle - do nothing',
        'Lighting: set the whole keyboard to static RED',
        'Lighting: set the whole keyboard to static GREEN',
        'Lighting: set the whole keyboard to static BLUE',
        'Lighting: set only the W key to WHITE (others stay blue)',
        'Lighting: BRIGHTNESS to 0',
        'Lighting: BRIGHTNESS to 100',
        'Lighting: BRIGHTNESS to 50',
        'Lighting: switch to a built-in EFFECT (wave / rainbow / breathing)',
        'Lighting: back to static RED',
        'Actuation: set W to the LOWEST value (skip if not available)',
        'Actuation: set W to the HIGHEST value',
        'Actuation: set W back to the default',
        'Performance: change the POLLING RATE (skip if not available)',
        'Profiles: switch to another on-board profile / config (skip if not available)',
        'Idle - do nothing'
    )
    mouse    = @(
        'Idle - do nothing',
        'Lighting: set all zones to static RED',
        'Lighting: set all zones to static GREEN',
        'Lighting: set all zones to static BLUE',
        'Lighting: BRIGHTNESS to 0',
        'Lighting: BRIGHTNESS to 100',
        'Lighting: switch to a built-in EFFECT',
        'DPI: set CPI to 400',
        'DPI: set CPI to 1600',
        'Performance: POLLING RATE to 125 Hz',
        'Performance: POLLING RATE to 1000 Hz',
        'Buttons: remap the side button to another action',
        'Buttons: reset the side button to default',
        'Idle - do nothing'
    )
    headset  = @(
        'Idle - do nothing',
        'Equalizer: switch to a different PRESET',
        'Equalizer: back to the default/flat preset',
        'Microphone: change MIC VOLUME',
        'Microphone: change SIDETONE level',
        'ChatMix: move the balance (skip if not available)',
        'Lighting: set to static RED (skip if not available)',
        'Lighting: set to static BLUE',
        'Power: change the auto-off / sleep timer (skip if not available)',
        'Idle - do nothing'
    )
    other    = @(
        'Idle - do nothing',
        'Change ONE setting in GG',
        'Change the same setting to a different value',
        'Change the same setting back',
        'Idle - do nothing'
    )
}
if ($StepsFile) {
    $steps = @(Get-Content -LiteralPath $StepsFile | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') })
    if ($steps.Count -eq 0) { throw "$StepsFile has no steps." }
} else {
    $steps = $builtinSteps[$DeviceType]
}
if (-not $SkipStartup) {
    $steps = @('Start SteelSeries GG from the Start menu. Click DONE once your device shows up in GG.') + $steps
}

if (-not $OutDir) {
    $OutDir = Join-Path $HOME ('ssgg-capture-{0}-{1}' -f $productId, (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$null = New-Item -ItemType Directory -Force -Path $OutDir
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$stepLog = Join-Path $OutDir 'steps.csv'

# --- guided capture window --------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-Epoch { ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0).ToString($inv) }
# Invariant culture: a German locale would write "1792006637,016" and split the CSV column.
function Write-StepLog([string]$Step, [string]$Status, [string]$Action) {
    Add-Content -LiteralPath $stepLog -Value ('{0},{1},{2},"{3}"' -f $Step, (Get-Epoch), $Status, $Action.Replace('"', "'"))
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "ssgg capture - $($device.Name)"
$form.TopMost = $true
$form.Width = 760
$form.Height = 300
$form.StartPosition = 'CenterScreen'
$label = New-Object System.Windows.Forms.Label
$label.Dock = 'Fill'
$label.TextAlign = 'MiddleCenter'
$label.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$startText = 'Click START. GG will be closed first if it is running.'
if ($SkipStartup) { $startText = 'Open GG on your device''s page, then click START.' }
$label.Text = "$startText`nThen do each action when shown and click DONE.`nDo not type passwords or private text until the end."
$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Dock = 'Bottom'
$panel.Height = 56
$panel.FlowDirection = 'RightToLeft'
$doneButton = New-Object System.Windows.Forms.Button
$doneButton.Text = 'START'
$doneButton.Width = 220
$doneButton.Height = 46
$skipButton = New-Object System.Windows.Forms.Button
$skipButton.Text = 'SKIP (not available)'
$skipButton.Width = 220
$skipButton.Height = 46
$skipButton.Enabled = $false
$panel.Controls.Add($doneButton)
$panel.Controls.Add($skipButton)
$form.Controls.Add($label)
$form.Controls.Add($panel)

$script:index = -1
$script:mode = 'ready'
$script:left = 0
$script:captures = @()
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000

function Stop-Capture {
    foreach ($p in $script:captures) {
        if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit(5000) }
    }
}

function Show-Step {
    $script:index++
    if ($script:index -ge $steps.Count) {
        $timer.Stop()
        Write-StepLog 'END' 'end' ''
        Start-Sleep -Seconds 2
        Stop-Capture
        $form.Close()
        return
    }
    $text = $steps[$script:index]
    Write-StepLog ($script:index + 1) 'shown' $text
    if ($text -like 'Idle*') {
        $script:mode = 'idle'
        $script:left = $IdleSeconds
        $doneButton.Enabled = $false
        $skipButton.Enabled = $false
    } else {
        $script:mode = 'wait'
        $doneButton.Enabled = $true
        $skipButton.Enabled = $true
    }
    Update-Label
}

function Update-Label {
    $text = $steps[$script:index]
    $suffix = switch ($script:mode) {
        'idle' { "`n$($script:left)s" }
        'settle' { "`nwaiting for GG to send it... $($script:left)s" }
        default { "`nClick DONE when GG shows the change." }
    }
    $label.Text = ('STEP {0}/{1}' -f ($script:index + 1), $steps.Count) + "`n$text$suffix"
}

$timer.Add_Tick({
        if ($script:mode -ne 'idle' -and $script:mode -ne 'settle') { return }
        $script:left--
        if ($script:left -le 0) { Show-Step } else { Update-Label }
    })

$doneButton.Add_Click({
        if ($script:mode -eq 'ready') {
            $doneButton.Text = 'DONE'
            if (-not $SkipStartup) {
                # Kill every SteelSeries process: the engine respawns if only GG's UI is closed.
                Get-Process -Name 'SteelSeries*' -ErrorAction SilentlyContinue | Stop-Process -Force
                Start-Sleep -Seconds 2
            }
            $script:captures = @(foreach ($hub in $hubs) {
                    $file = Join-Path $OutDir ('hub-{0}.pcap' -f ($hub -replace '\D', ''))
                    $captureArgs = @('-d', $hub, '-o', "`"$file`"", '-A', '--inject-descriptors')
                    Start-Process -FilePath $usbpcap -ArgumentList $captureArgs -PassThru -WindowStyle Hidden
                })
            Start-Sleep -Seconds 2
            Write-StepLog 'START' 'start' ''
            $timer.Start()
            Show-Step
            return
        }
        Write-StepLog ($script:index + 1) 'done' $steps[$script:index]
        $script:mode = 'settle'
        $script:left = $SettleSeconds
        $doneButton.Enabled = $false
        $skipButton.Enabled = $false
        Update-Label
    })

$skipButton.Add_Click({
        Write-StepLog ($script:index + 1) 'skipped' $steps[$script:index]
        Show-Step
    })

$form.Add_FormClosing({
        $timer.Stop()
        Stop-Capture
    })

'step,epoch,status,action' | Set-Content -LiteralPath $stepLog
Write-Host 'Follow the capture window (it stays on top).'
[void]$form.ShowDialog()

$hubFiles = @(Get-ChildItem -LiteralPath $OutDir -Filter 'hub-*.pcap')
if ($hubFiles.Count -eq 0) { throw 'No capture was recorded (the window was closed before START?).' }

# --- keep only the chosen device --------------------------------------------------------------
# --inject-descriptors puts the device descriptor (VID/PID + bus address) at the start of the capture.
Write-Host 'Filtering the capture to your device...'
$devicePcap = Join-Path $OutDir 'device.pcap'
$match = $null
foreach ($file in $hubFiles) {
    $hits = @(& $tshark -r $file.FullName -Y "usb.idVendor == 0x1038 && usb.idProduct == 0x$productId" `
            -T fields -E separator=, -e usb.bus_id -e usb.device_address | Where-Object { $_ } | Sort-Object -Unique)
    if ($hits.Count -gt 0) { $match = @{ File = $file; Hits = $hits }; break }
}
if (-not $match) {
    Write-Warning ("Could not find PID 0x$productId in the capture descriptors. The raw hub captures are kept in " +
        "$OutDir; attach them only if they hold no private traffic from other USB devices.")
    return
}
$filter = ($match.Hits | ForEach-Object {
        $bus, $address = $_.Split(',')
        "(usb.bus_id == $bus && usb.device_address == $address)"
    }) -join ' || '
& $tshark -r $match.File.FullName -Y $filter -F pcap -w $devicePcap
if ($LASTEXITCODE -ne 0) { throw "tshark failed to filter $($match.File.FullName)." }
# The hub captures also hold every other device on the same hub (other keyboards, webcams...).
$hubFiles | Remove-Item -Force

# --- decode reports ---------------------------------------------------------------------------
Write-Host 'Decoding HID reports...'
$fields = 'frame.time_epoch', 'usb.transfer_type', 'usb.endpoint_address', 'usb.bmRequestType', 'usb.setup.bRequest',
'usb.setup.wValue', 'usb.setup.wIndex', 'usb.data_fragment', 'usb.capdata', 'usb.control.Response'
$fieldArgs = foreach ($f in $fields) { '-e', $f }
$lines = & $tshark -r $devicePcap -Y 'usb.data_fragment || usb.capdata || usb.control.Response' -T fields `
    -E separator=, -E occurrence=f @fieldArgs

$shown = @(Import-Csv -LiteralPath $stepLog | Where-Object { $_.status -eq 'shown' } |
        ForEach-Object { [pscustomobject]@{ Step = $_.step; Epoch = [double]::Parse($_.epoch, $inv); Action = $_.action } })
$skipped = @{}
Import-Csv -LiteralPath $stepLog | Where-Object { $_.status -eq 'skipped' } | ForEach-Object { $skipped[$_.step] = $true }

$reportType = @{ 1 = 'input'; 2 = 'output'; 3 = 'feature' }
function Get-Channel([string[]]$c) {
    $transfer, $endpoint, $bm, $request, $wValue, $wIndex = $c[1..6]
    if ($transfer -eq '0x01') { return "interrupt ep $endpoint" }
    if ($bm -and $wValue) {
        $v = [Convert]::ToInt32($wValue, 16)
        $name = switch ("$bm/$request") { '0x21/9' { 'SET_REPORT' } '0xa1/1' { 'GET_REPORT' } default { "ctrl bm=$bm req=$request" } }
        return ('{0} {1} id=0x{2:x2} if={3}' -f $name, $reportType[$v -shr 8], ($v -band 0xFF), $wIndex)
    }
    return 'control response'
}

$reports = New-Object System.Collections.Generic.List[object]
$stepIndex = -1
foreach ($line in $lines) {
    $c = $line.Split(',')
    # shortcut: EP 0x81 is the standard OS input endpoint (key presses, mouse motion) on the devices seen so far;
    # dropped so typed keys never reach the shared files. Revisit if a device answers GG on 0x81.
    if ($c[1] -eq '0x01' -and $c[2] -eq '0x81') { continue }
    $epoch = [double]::Parse($c[0], $inv)
    while ($stepIndex + 1 -lt $shown.Count -and $shown[$stepIndex + 1].Epoch -le $epoch) { $stepIndex++ }
    $data = @($c[7], $c[8], $c[9]) | Where-Object { $_ } | Select-Object -First 1
    if (-not $data) { continue }
    $reports.Add([pscustomobject]@{
            step    = $(if ($stepIndex -ge 0) { $shown[$stepIndex].Step } else { 'before' })
            epoch   = $c[0]
            channel = Get-Channel $c
            bytes   = $data.Length / 2
            data    = $data
        })
}
$reports | Export-Csv -LiteralPath (Join-Path $OutDir 'reports.csv') -NoTypeInformation

# --- per-step summary -------------------------------------------------------------------------
$ggExe = Join-Path $env:ProgramFiles 'SteelSeries\GG\SteelSeriesGG.exe'
$ggVersion = if (Test-Path $ggExe) { (Get-Item $ggExe).VersionInfo.ProductVersion } else { 'unknown' }
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Capture: $($device.Name) (VID 0x1038, PID 0x$productId)")
$md.Add('')
$md.Add("Type: $DeviceType. Date: $(Get-Date -Format 'yyyy-MM-dd'). GG: $ggVersion. Windows: $([Environment]::OSVersion.Version).")
$md.Add('Unique payloads per step, trailing zero bytes trimmed, first 96 bytes shown. Full data: reports.csv.')
$byStep = $reports | Group-Object -Property step -AsHashTable -AsString
foreach ($s in @([pscustomobject]@{ Step = 'before'; Action = 'before the first step' }) + $shown) {
    $md.Add('')
    $status = if ($skipped[$s.Step]) { ' (skipped)' } else { '' }
    $md.Add("## Step $($s.Step): $($s.Action)$status")
    if (-not $byStep -or -not $byStep[$s.Step]) { $md.Add(''); $md.Add('No reports.'); continue }
    $groups = $byStep[$s.Step] | Group-Object -Property channel, { $_.data -replace '(00)+$', '' }
    $md.Add('')
    $md.Add('| count | channel | bytes | data |')
    $md.Add('|------:|---------|------:|------|')
    foreach ($g in ($groups | Select-Object -First 40)) {
        $first = $g.Group[0]
        $hex = $g.Values[1]
        if ($hex.Length -gt 192) { $hex = $hex.Substring(0, 192) + '...' }
        $md.Add("| $($g.Count) | $($first.channel) | $($first.bytes) | ``$hex`` |")
    }
    if ($groups.Count -gt 40) { $md.Add("| | $($groups.Count - 40) more unique payloads in reports.csv | | |") }
}
$md | Set-Content -LiteralPath (Join-Path $OutDir 'summary.md') -Encoding UTF8

# --- device info ------------------------------------------------------------------------------
$info = Join-Path $OutDir 'device-info.txt'
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match "VID_1038&PID_$productId" } |
    Sort-Object InstanceId | Format-Table -AutoSize -Property Class, FriendlyName, InstanceId |
    Out-String -Width 300 | Set-Content -LiteralPath $info
$ssgg = @((Join-Path $PSScriptRoot '..\target\release\ssgg.exe'), (Join-Path $PSScriptRoot '..\target\debug\ssgg.exe')) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ssgg) { $ssgg = (Get-Command ssgg -ErrorAction SilentlyContinue).Source }
if ($ssgg) { "`n# ssgg devices`n" + (& $ssgg devices 2>&1 | Out-String) | Add-Content -LiteralPath $info }

$zip = Join-Path $OutDir "ssgg-capture-$productId.zip"
Compress-Archive -Force -DestinationPath $zip -Path (Join-Path $OutDir '*.csv'), (Join-Path $OutDir 'summary.md'), $info

Write-Host ''
Write-Host "Done. Results in $OutDir" -ForegroundColor Green
Write-Host "  $zip  <- attach this to a GitHub issue or PR"
Write-Host "  $devicePcap  <- full capture; attach it too if under 25 MB, or share a link"
Write-Host 'Start SteelSeries GG again from the Start menu if it is not running.'
Write-Host 'Next steps: docs/development/adding-hardware.md'
Write-Host 'New issue: https://github.com/Ven0m0/steelseriesgg-rs/issues/new?template=device-capture.yml'
