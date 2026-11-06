@echo off
setlocal
title XION PC CHECK
set "XION_SELF=%~f0"
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath $env:XION_SELF -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:XION_SELF); $i=$s.IndexOf('##XION'+'PS##'); iex ($s.Substring($i))"
exit /b
##XIONPS##
# ============================================================================
#  XION PC CHECK - local, read-only Windows PC inspection tool
#  Nothing is uploaded, nothing is changed, nothing is saved on this PC.
#  Results are sent to the admin via Discord only. Tool deletes itself after use.
# ============================================================================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
try { $Host.UI.RawUI.WindowTitle = 'XION PC CHECK' } catch {}

$script:Sections    = New-Object System.Collections.ArrayList
$script:SigCache    = @{}
$script:ExecMissing = New-Object System.Collections.ArrayList
$script:Started     = Get-Date

# ---------------------------------------------------------------- helpers ---
function Say($t, $c) { if (-not $c) { $c = 'Gray' }; Write-Host $t -ForegroundColor $c }
function Step($t) { }  # silent — findings go to Discord only
function Esc($s) {
    if ($s -eq $null) { return '' }
    return ([string]$s).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
function Row($sev, $cells) { New-Object PSObject -Property @{ Sev = $sev; Cells = @($cells) } }
function AddRow($list, $sev, $cells) { [void]$list.Add((Row $sev $cells)) }
function SortRows($rows) {
    $o = New-Object System.Collections.ArrayList
    foreach ($s in @('high', 'review', 'info')) {
        foreach ($r in @($rows)) { if ($r -ne $null -and $r.Sev -eq $s) { [void]$o.Add($r) } }
    }
    return ,$o
}
function AddSection($id, $title, $note, $cols, $list) {
    $sorted = SortRows $list
    [void]$script:Sections.Add((New-Object PSObject -Property @{ Id = $id; Title = $title; Note = $note; Cols = @($cols); Rows = @($sorted) }))
}
function Fd($d) {
    if ($d -eq $null) { return '' }
    try { return ([datetime]$d).ToString('yyyy-MM-dd HH:mm:ss') } catch { return '' }
}
function Trunc($s, $n) {
    if ($s -eq $null) { return '' }
    $s = [string]$s
    if ($s.Length -gt $n) { return ($s.Substring(0, $n) + '...') }
    return $s
}
function SidName($sid) {
    try { return (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount]).Value } catch { return $sid }
}
function Sig($path) {
    try {
        $s = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        if ($s.Status -eq 'Valid') {
            $n = ''
            if ($s.SignerCertificate) { $n = $s.SignerCertificate.GetNameInfo('SimpleName', $false) }
            return ('Signed: ' + $n)
        }
        elseif ($s.Status -eq 'NotSigned') { return 'NOT SIGNED' }
        else { return ('Signature ' + $s.Status) }
    } catch { return 'n/a' }
}
function SigC($p) {
    if (-not $script:SigCache.ContainsKey($p)) { $script:SigCache[$p] = Sig $p }
    return $script:SigCache[$p]
}
function UW($p) { return ($p -match '(?i)\\(Users|ProgramData|Temp|AppData|Downloads|Desktop)\\') }

# Indicator lists (names of well known Roblox executors / injectors / cheat tools)
$HighRx = '(?i)(jjsploit|solara|krnl|fluxus|wearedevs|kdmapper|extreme.?injector|cheat.?engine|cheatengine|aimbot|trigger.?bot|spoofer|macsploit|scriptware|synapse.?x|seliware|zorara|ronix|valex|roblox.?(executor|exploit|hack)|(^|[^a-z])xeno([^a-z]|$)|volcano.?(exec|v?[0-9])|delta.?exec|swift.?exec|wave.?exec|oxygen.?u|xenos(64|32)?\.exe|manual.?map|bootstrappernew|(^|[\\/ ])(pluto|hydrogen|delta|wave|swift|celery|nihon|volcano)\.(exe|zip|rar|7z))'
$ReviewRx = '(?i)(inject|exploit|executor|cheat|hack|crack|bypass|auto.?click|clicker|process.?hacker|system.?informer|x64dbg|ollydbg|dnspy|fiddler|bloxstrap|fps.?unlock|rbxfps|clumsy|keygen|hwid|ragebot|no.?recoil|skin.?changer|windivert)'
$DrvHighRx = '(?i)(dbk64|dbk32|kdmapper|mimidrv|iqvw64e|capcom)'
$DrvReviewRx = '(?i)(gdrv|rtcore|asrdrv|dbutil|winring0|cpuz|physmem|atillk|glckio|asio3|asmmap|ntiolib|phymem|procexp|mhyprot|zam64|throttlestop|amdryzenmaster|speedfan|gmer|hwrwdrv|piddrv|bsmem|netfilterdrv|windivert)'
$RemoteRx = '(?i)(anydesk|teamviewer|rustdesk|parsec|ultraviewer|supremo|chrome remote|vnc|splashtop|ammyy|radmin)'

function Classify($t) {
    if (-not $t) { return '' }
    if ($t -match $HighRx) { return 'high' }
    if ($t -match $ReviewRx) { return 'review' }
    return ''
}

function Run-Module($name, $sb) {
    Step $name
    try { & $sb }
    catch {
        $e = New-Object System.Collections.ArrayList
        AddRow $e 'info' @('Module error', $_.Exception.Message)
        AddSection ('err' + $script:Sections.Count) ('Module failed: ' + $name) '' @('Item', 'Detail') $e
    }
}

# ----------------------------------------------------------------- banner ---
try { Clear-Host } catch {}
Say ''
Say '   __  __ ___ ___  _  _ ' 'Magenta'
Say '   \ \/ /|_ _/ _ \| \| |' 'Magenta'
Say '    >  <  | | (_) | .` |' 'Magenta'
Say '   /_/\_\|___\___/|_|\_|' 'Magenta'
Say ''
Say '   X I O N   P C   C H E C K' 'White'
Say '   Read-only scan. Nothing is uploaded or changed.' 'DarkGray'
Say '   Results are sent securely to the admin. Nothing is saved on this PC.' 'DarkGray'
Say ''

$isAdmin = $false
try { $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
if (-not $isAdmin) { Say '  ! Not running as administrator - some checks will be limited.' 'Yellow' }

# ================================================================ ACCESS KEY =====
# Change XION-XXXX-XXXX to any secret passphrase you want.
# Share this key only with the person you want to run the check.
$XION_UNLOCK_KEY = 'xion-703744-1040'

Say ''
Say '  --------------------------------------------------' 'DarkGray'
Say '  This tool is authorised staff use only.' 'Yellow'
Say '  Enter the key provided by the admin to continue.' 'Yellow'
Say '  --------------------------------------------------' 'DarkGray'
Say ''
$keyInput = Read-Host '  Enter unlock key'
if ($keyInput.ToLower() -ne $XION_UNLOCK_KEY) {
    Say ''
    Say '  ACCESS DENIED  —  Invalid key.' 'Red'
    Say '  Contact the server admin for access.' 'Red'
    Say ''
    Start-Sleep 4
    exit
}
Say ''
Say '  Key accepted.' 'Green'
Say ''
Say '  Scanning your PC, please wait...' 'Cyan'
Say '  Do not close this window.' 'DarkGray'
Say ''
Start-Sleep 1

# ------------------------------------------------------- shared lookups ----
$script:DevMap = @{}
try {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class XionNative {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern uint QueryDosDevice(string lpDeviceName, StringBuilder lpTargetPath, int ucchMax);
}
'@
    foreach ($l in [char[]]'CDEFGHIJKLMNOPQRSTUVWXYZ') {
        $sbq = New-Object System.Text.StringBuilder(520)
        $n = [XionNative]::QueryDosDevice(([string]$l + ':'), $sbq, 520)
        if ($n -gt 0) {
            $t = $sbq.ToString()
            $z = $t.IndexOf([char]0)
            if ($z -ge 0) { $t = $t.Substring(0, $z) }
            if ($t) { $script:DevMap[$t] = ([string]$l + ':') }
        }
    }
} catch {}

function Dev2Path($p) {
    foreach ($k in $script:DevMap.Keys) {
        if ($p.StartsWith(($k + '\'), [StringComparison]::OrdinalIgnoreCase)) { return ($script:DevMap[$k] + $p.Substring($k.Length)) }
    }
    return $p
}

$script:FixedDrives = @(Get-WmiObject Win32_LogicalDisk -Filter 'DriveType=3')
$script:FixedLetters = @($script:FixedDrives | ForEach-Object { $_.DeviceID })
function IsGone($path) {
    if (-not $path) { return $false }
    if ($path -notmatch '^[A-Za-z]:\\') { return $false }
    $d = $path.Substring(0, 2).ToUpper()
    if ($script:FixedLetters -notcontains $d) { return $false }
    return (-not (Test-Path -LiteralPath $path))
}
function NoteExec($src, $path, $time) {
    if (IsGone $path) { [void]$script:ExecMissing.Add((New-Object PSObject -Property @{ Src = $src; Path = $path; Time = $time })) }
}

$script:UserHives = @()
foreach ($k in @(Get-ChildItem 'Registry::HKEY_USERS')) {
    $sid = $k.PSChildName
    if ($sid -notmatch '^S-1-5-21-[0-9-]+$') { continue }
    $prof = (Get-ItemProperty ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $sid)).ProfileImagePath
    $script:UserHives += New-Object PSObject -Property @{ Sid = $sid; Name = (SidName $sid); Path = ('Registry::HKEY_USERS\' + $sid); Prof = $prof }
}

$script:Profiles = @()
$usersDir = $env:SystemDrive + '\Users'
foreach ($d in @(Get-ChildItem -LiteralPath $usersDir -Force)) {
    if (-not $d.PSIsContainer) { continue }
    if ($d.Name -match '^(All Users|Default|Default User|Public|desktop\.ini)$') { continue }
    $script:Profiles += $d.FullName
}

$KF = @{
    '1AC14E77-02E7-4E5D-B744-2EB1AE5198B7' = 'SYSTEM32'
    'D65231B0-B2F1-4857-A4CE-A8E7C6EA7D27' = 'SYSWOW64'
    'F38BF404-1D43-42F2-9305-67DE0B28FC23' = 'WINDOWS'
    '6D809377-6AF0-444B-8957-A3773F02200E' = 'PF64'
    '7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E' = 'PF86'
    'B4BFCC3A-DB2C-424C-B029-7FE99A87C641' = 'Desktop'
    '374DE290-123F-4565-9164-39C4925E467B' = 'Downloads'
    'FDD39AD0-238F-46AF-ADB4-6C85480369C7' = 'Documents'
    'F1B32785-6FBA-4FCF-9D55-7B8E7F157091' = 'AppData\Local'
    '3EB685DB-65F9-4CF6-A03A-E3EF65729F3D' = 'AppData\Roaming'
    '5E6C858F-0E22-4760-9AFE-EA3317B67173' = ''
}
function ResolveKF($name, $prof) {
    if ($name -match '^\{([0-9A-Fa-f-]{36})\}\\?(.*)$') {
        $g = $Matches[1].ToUpper(); $rest = $Matches[2]
        if ($KF.ContainsKey($g)) {
            $b = $KF[$g]
            switch ($b) {
                'SYSTEM32' { $base = $env:SystemRoot + '\System32' }
                'SYSWOW64' { $base = $env:SystemRoot + '\SysWOW64' }
                'WINDOWS'  { $base = $env:SystemRoot }
                'PF64'     { $base = $env:ProgramFiles }
                'PF86'     { $base = ${env:ProgramFiles(x86)} }
                default    { if ($prof) { if ($b) { $base = $prof + '\' + $b } else { $base = $prof } } else { $base = '' } }
            }
            if ($base) { return ($base + '\' + $rest) }
        }
    }
    return $name
}
function Rot13($s) {
    $o = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($c -ge 65 -and $c -le 90) { $c = (($c - 65 + 13) % 26) + 65 }
        elseif ($c -ge 97 -and $c -le 122) { $c = (($c - 97 + 13) % 26) + 97 }
        [void]$o.Append([char]$c)
    }
    return $o.ToString()
}

# ============================================================== MODULES =====

Run-Module 'System information' {
    $os   = Get-WmiObject Win32_OperatingSystem
    $cs   = Get-WmiObject Win32_ComputerSystem
    $bios = Get-WmiObject Win32_BIOS
    $cpu  = @(Get-WmiObject Win32_Processor)[0]
    $enc  = Get-WmiObject Win32_SystemEnclosure
    $gpus = @(Get-WmiObject Win32_VideoController)
    $bat  = @(Get-WmiObject Win32_Battery)
    $boot = $null; try { $boot = [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime) } catch {}
    $inst = $null; try { $inst = [Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate) } catch {}
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $dispVer = $cv.DisplayVersion; if (-not $dispVer) { $dispVer = $cv.ReleaseId }

    $laptopTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    $isLaptop = $false
    foreach ($t in @($enc.ChassisTypes)) { if ($t -ne $null -and ($laptopTypes -contains [int]$t)) { $isLaptop = $true } }
    if ($bat.Count -gt 0 -and $bat[0] -ne $null) { $isLaptop = $true }
    $dev = 'Desktop / other'; if ($isLaptop) { $dev = 'Laptop / notebook' }

    $rows = New-Object System.Collections.ArrayList
    AddRow $rows 'info' @('Computer name', $env:COMPUTERNAME)
    AddRow $rows 'info' @('Logged-in user', ($env:USERDOMAIN + '\' + $env:USERNAME))
    AddRow $rows 'info' @('Windows', ($os.Caption + ' ' + $dispVer + ' (build ' + $os.BuildNumber + ', ' + $os.OSArchitecture + ')'))
    AddRow $rows 'info' @('Windows installed', (Fd $inst))
    AddRow $rows 'info' @('Last boot', (Fd $boot))
    AddRow $rows 'info' @('Current PC time', ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  (' + [TimeZoneInfo]::Local.DisplayName + ')'))
    AddRow $rows 'info' @('Device type', $dev)
    AddRow $rows 'info' @('Manufacturer / model', ($cs.Manufacturer + ' ' + $cs.Model))
    $biosDate = ''; try { $biosDate = Fd ([Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate)) } catch {}
    AddRow $rows 'info' @('BIOS', ($bios.Manufacturer + ' ' + $bios.SMBIOSBIOSVersion + ' (' + $biosDate + ')'))
    AddRow $rows 'info' @('CPU', ($cpu.Name.Trim() + ' - ' + $cpu.NumberOfCores + ' cores / ' + $cpu.NumberOfLogicalProcessors + ' threads'))
    AddRow $rows 'info' @('RAM', ([string][math]::Round($cs.TotalPhysicalMemory / 1GB, 1) + ' GB'))
    foreach ($g in $gpus) { AddRow $rows 'info' @('Graphics', ($g.Name + ' (driver ' + $g.DriverVersion + ')')) }
    foreach ($dk in @(Get-WmiObject Win32_DiskDrive)) { AddRow $rows 'info' @('Disk', ($dk.Model + ' - ' + [math]::Round($dk.Size / 1GB) + ' GB - ' + $dk.InterfaceType)) }
    foreach ($v in $script:FixedDrives) { AddRow $rows 'info' @(('Volume ' + $v.DeviceID), ($v.FileSystem + ' - ' + [math]::Round($v.FreeSpace / 1GB) + ' GB free of ' + [math]::Round($v.Size / 1GB) + ' GB')) }
    AddRow $rows 'info' @('PowerShell version', $PSVersionTable.PSVersion.ToString())
    $adm = 'No (limited checks)'; if ($isAdmin) { $adm = 'Yes' }
    AddRow $rows 'info' @('Scan ran as administrator', $adm)

    if (($cs.Manufacturer + ' ' + $cs.Model) -match '(?i)(vmware|virtualbox|qemu|kvm|virtual machine|xen|parallels|hyper-v)') {
        AddRow $rows 'review' @('Virtual machine', 'This PC looks like a virtual machine')
    }
    $av = @(Get-WmiObject -Namespace 'root\SecurityCenter2' -Class AntiVirusProduct)
    foreach ($a in $av) { if ($a -ne $null) { AddRow $rows 'info' @('Antivirus product', $a.displayName) } }
    AddSection 'sys' 'System information' 'Hardware, Windows version and device type (laptop or desktop).' @('Item', 'Value') $rows
}

Run-Module 'Security settings and tampering signs' {
    $rows = New-Object System.Collections.ArrayList

    # Secure boot
    $sb = $null; try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch {}
    if ($sb -eq $true) { AddRow $rows 'info' @('Secure Boot', 'Enabled') }
    elseif ($sb -eq $false) { AddRow $rows 'review' @('Secure Boot', 'DISABLED') }
    else { AddRow $rows 'info' @('Secure Boot', 'Not supported / legacy BIOS / could not read') }

    # Boot configuration (test signing, integrity checks off, kernel debug)
    $bcd = ''
    try { $bcd = (& bcdedit /enum '{current}' 2>&1 | Out-String) } catch {}
    if ($bcd -match '(?im)^\s*testsigning\s+Yes') { AddRow $rows 'high' @('Test signing mode', 'ON - allows unsigned kernel drivers') }
    if ($bcd -match '(?im)^\s*nointegritychecks\s+Yes') { AddRow $rows 'high' @('Driver integrity checks', 'DISABLED (nointegritychecks)') }
    if ($bcd -match '(?im)^\s*debug\s+Yes') { AddRow $rows 'review' @('Kernel debugging', 'ON') }
    if ($bcd -match '(?i)DDISABLE_INTEGRITY_CHECKS') { AddRow $rows 'high' @('Boot option', 'DDISABLE_INTEGRITY_CHECKS present') }
    if ($bcd -and $bcd -notmatch '(?i)(testsigning\s+Yes|nointegritychecks\s+Yes|DDISABLE_INTEGRITY)') { AddRow $rows 'info' @('Boot configuration', 'No test-signing / integrity-check bypass found') }

    # Vulnerable driver blocklist / memory integrity
    $bl = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config').VulnerableDriverBlocklistEnable
    if ($bl -eq 0) { AddRow $rows 'review' @('Vulnerable driver blocklist', 'OFF (lets known-bad drivers load)') }
    $hv = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity').Enabled
    if ($hv -eq 1) { AddRow $rows 'info' @('Memory integrity (HVCI)', 'Enabled') }

    # Defender
    $mp = $null; try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch {}
    if ($mp) {
        $rt = 'info'; if (-not $mp.RealTimeProtectionEnabled) { $rt = 'review' }
        AddRow $rows $rt @('Defender real-time protection', [string]$mp.RealTimeProtectionEnabled)
        $av2 = 'info'; if (-not $mp.AntivirusEnabled) { $av2 = 'review' }
        AddRow $rows $av2 @('Defender antivirus enabled', [string]$mp.AntivirusEnabled)
        AddRow $rows 'info' @('Defender signatures updated', (Fd $mp.AntivirusSignatureLastUpdated))
        if ($mp.IsTamperProtected -ne $null) { AddRow $rows 'info' @('Defender tamper protection', [string]$mp.IsTamperProtected) }
    } else { AddRow $rows 'info' @('Microsoft Defender', 'Status not readable (another antivirus may be in control)') }
    $pref = $null; try { $pref = Get-MpPreference -ErrorAction Stop } catch {}
    if ($pref) {
        foreach ($x in @($pref.ExclusionPath)) { if ($x) { AddRow $rows 'review' @('Defender exclusion (folder/file)', $x) } }
        foreach ($x in @($pref.ExclusionProcess)) { if ($x) { AddRow $rows 'review' @('Defender exclusion (process)', $x) } }
        foreach ($x in @($pref.ExclusionExtension)) { if ($x) { AddRow $rows 'review' @('Defender exclusion (extension)', $x) } }
    }

    # Services that keep execution history
    $svcs = @(
        @('SysMain', 'SysMain / Superfetch (feeds Prefetch)', $true),
        @('PcaSvc', 'Program Compatibility Assistant (execution traces)', $true),
        @('DPS', 'Diagnostic Policy Service', $true),
        @('EventLog', 'Windows Event Log', $true),
        @('WinDefend', 'Microsoft Defender service', $false),
        @('Appinfo', 'Application Information (UAC)', $false)
    )
    foreach ($s in $svcs) {
        $sv = Get-WmiObject Win32_Service -Filter ("Name='" + $s[0] + "'")
        if ($sv -eq $null) { AddRow $rows 'info' @($s[1], 'Service not present'); continue }
        $ok = ($sv.State -eq 'Running' -and $sv.StartMode -ne 'Disabled')
        $sev = 'info'; if (-not $ok -and $s[2]) { $sev = 'review' }
        AddRow $rows $sev @($s[1], ($sv.State + ' / start mode: ' + $sv.StartMode))
    }

    # Prefetch
    $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters').EnablePrefetcher
    if ($pf -eq 0) { AddRow $rows 'review' @('Prefetch', 'DISABLED in registry (EnablePrefetcher = 0)') }
    elseif ($pf -ne $null) { AddRow $rows 'info' @('Prefetch', ('Enabled (EnablePrefetcher = ' + $pf + ')')) }

    # Per-user tracking switches
    foreach ($h in $script:UserHives) {
        $adv = Get-ItemProperty ($h.Path + '\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced')
        if ($adv.Start_TrackDocs -eq 0) { AddRow $rows 'review' @(('Recent documents tracking - ' + $h.Name), 'DISABLED (Start_TrackDocs = 0)') }
        if ($adv.Start_TrackProgs -eq 0) { AddRow $rows 'review' @(('Program tracking (UserAssist) - ' + $h.Name), 'DISABLED (Start_TrackProgs = 0)') }
        $pol = Get-ItemProperty ($h.Path + '\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer')
        if ($pol.NoRecentDocsHistory -eq 1) { AddRow $rows 'review' @(('Recent documents history policy - ' + $h.Name), 'DISABLED by policy') }
        $bb = $h.Path + '\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume'
        foreach ($vk in @(Get-ChildItem -LiteralPath $bb)) {
            $nk = (Get-ItemProperty $vk.PSPath).NukeOnDelete
            if ($nk -eq 1) { AddRow $rows 'review' @(('Recycle Bin bypass - ' + $h.Name), 'Files are deleted permanently (NukeOnDelete = 1)') }
        }
    }

    # Hosts file
    $hostsFile = $env:SystemRoot + '\System32\drivers\etc\hosts'
    foreach ($ln in @(Get-Content -LiteralPath $hostsFile)) {
        $t = ([string]$ln).Trim()
        if ($t -and $t -notmatch '^#') { AddRow $rows 'review' @('Hosts file entry', $t) }
    }

    AddSection 'sec' 'Security settings and tampering signs' 'Things that cheats or cleaners commonly change. REVIEW means "look at this", not "guilty".' @('Check', 'Result') $rows
}

Run-Module 'Running processes' {
    $rows = New-Object System.Collections.ArrayList
    $groups = @{}
    $skipped = 0
    $sigChecks = 0
    foreach ($p in @(Get-WmiObject Win32_Process)) {
        $path = $p.ExecutablePath
        $name = $p.Name
        $sev = Classify ($name + ' ' + $path)
        if (-not $path -and -not $sev) { continue }
        if ($path -match '(?i)^[A-Za-z]:\\Windows\\(System32|SysWOW64|WinSxS|SystemApps|ImmersiveControlPanel)' -and -not $sev) { $skipped++; continue }
        $key = ([string]$path).ToLower() + '|' + $name.ToLower()
        if ($groups.ContainsKey($key)) { $groups[$key].Count++; continue }
        $sig = ''
        if ($path -and $sigChecks -lt 160) { $sig = SigC $path; $sigChecks++ }
        if (-not $sev -and $sig -eq 'NOT SIGNED' -and (UW $path)) { $sev = 'review' }
        $started = ''
        try { $started = Fd ([Management.ManagementDateTimeConverter]::ToDateTime($p.CreationDate)) } catch {}
        $groups[$key] = New-Object PSObject -Property @{ Sev = $sev; Name = $name; Pid2 = $p.ProcessId; Path = $path; Sig = $sig; Started = $started; Count = 1 }
    }
    foreach ($g in ($groups.Values | Sort-Object Name)) {
        $sv = $g.Sev; if (-not $sv) { $sv = 'info' }
        AddRow $rows $sv @($g.Name, $g.Count, $g.Path, $g.Sig, $g.Started)
    }
    AddSection 'proc' 'Running programs' ('User-level programs currently running (' + $skipped + ' standard Windows system processes hidden). Unsigned programs running from user folders are marked REVIEW.') @('Name', 'Instances', 'Path', 'Signature', 'Started') $rows

    # Window titles
    $w = New-Object System.Collections.ArrayList
    foreach ($gp in @(Get-Process)) {
        $t = $gp.MainWindowTitle
        if ($t) {
            $s = Classify $t
            if ($s) { AddRow $w $s @($gp.ProcessName, $t) }
        }
    }
    if ($w.Count -eq 0) { AddRow $w 'info' @('(none)', 'No open window title matched a known cheat / executor name') }
    AddSection 'win' 'Open window titles' 'Catches renamed executables whose window still shows the real tool name.' @('Process', 'Window title') $w
}

Run-Module 'Injected modules in game processes' {
    $rows = New-Object System.Collections.ArrayList
    $gameRx = '(?i)^(RobloxPlayerBeta|RobloxStudioBeta|Windows10Universal|javaw|FiveM.*|GTA5|csgo|cs2|VALORANT-Win64-Shipping|FortniteClient-Win64-Shipping|RustClient|r5apex|TslGame)$'
    $found = 0; $checks = 0
    foreach ($gp in @(Get-Process)) {
        if ($gp.ProcessName -notmatch $gameRx) { continue }
        $found++
        $isRoblox = ($gp.ProcessName -match '(?i)roblox|Windows10Universal')
        $exeDir = ''
        try { $exeDir = Split-Path $gp.MainModule.FileName } catch {}
        $mods = @()
        try { $mods = @($gp.Modules) } catch {}
        if ($mods.Count -eq 0) { AddRow $rows 'info' @($gp.ProcessName, '', 'Modules could not be read (run as administrator / protected process)', ''); continue }
        $bad = 0
        foreach ($m in $mods) {
            $fn = $m.FileName
            if (-not $fn) { continue }
            if ($fn -match '(?i)^[A-Za-z]:\\Windows\\') { continue }
            if ($exeDir -and $fn.StartsWith($exeDir, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($fn -match '(?i)^[A-Za-z]:\\Program Files') { continue }
            $sev = Classify $fn
            $sig = ''
            if ($checks -lt 60) { $sig = SigC $fn; $checks++ }
            if (-not $sev -and $sig -eq 'NOT SIGNED' -and (UW $fn)) { if ($isRoblox) { $sev = 'high' } else { $sev = 'review' } }
            if ($sev) { AddRow $rows $sev @($gp.ProcessName, $gp.Id, $fn, $sig); $bad++ }
        }
        if ($bad -eq 0) { AddRow $rows 'info' @($gp.ProcessName, $gp.Id, ('Checked ' + $mods.Count + ' modules - nothing unusual'), '') }
    }
    if ($found -eq 0) { AddRow $rows 'info' @('(none)', '', 'No Roblox / Minecraft / common game process is running. Start the game and scan again to check for injected DLLs.', '') }
    AddSection 'inj' 'Injected modules in game processes' 'Looks for unsigned or unusual DLLs loaded into running games (classic executor / injector behaviour). Manually-mapped DLLs do not appear here.' @('Game', 'PID', 'Module', 'Signature') $rows
}

Run-Module 'Drivers and services' {
    $rows = New-Object System.Collections.ArrayList
    foreach ($d in @(Get-WmiObject Win32_SystemDriver)) {
        $path = [string]$d.PathName
        $sev = ''
        if (($d.Name + ' ' + $path) -match $DrvHighRx) { $sev = 'high' }
        elseif (($d.Name + ' ' + $path) -match $DrvReviewRx) { $sev = 'review' }
        elseif ((Classify ($d.Name + ' ' + $path)) -ne '') { $sev = Classify ($d.Name + ' ' + $path) }
        $odd = ($path -and $path -notmatch '(?i)(\\SystemRoot\\|^\\\?\?\\C:\\Windows\\|^[A-Za-z]:\\Windows\\|system32\\drivers)')
        if ($odd -and $d.State -eq 'Running' -and -not $sev) { if (UW $path) { $sev = 'review' } else { $sev = 'info' } }
        if ($sev) { AddRow $rows $sev @('Driver', $d.Name, $d.State, $path) }
    }
    foreach ($s in @(Get-WmiObject Win32_Service)) {
        $path = [string]$s.PathName
        $sev = Classify ($s.Name + ' ' + $path)
        if (-not $sev -and $path -match '(?i)\\(Users|Temp|AppData)\\') { $sev = 'review' }
        if ($sev) { AddRow $rows $sev @('Service', $s.Name, $s.State, $path) }
    }
    # driver files lying around in user folders
    foreach ($r in @(($env:SystemRoot + '\Temp'), $env:TEMP)) {
        if (-not $r) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $r -Filter *.sys -Force)) { AddRow $rows 'review' @('Driver file in temp folder', $f.Name, (Fd $f.LastWriteTime), $f.FullName) }
    }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('(none)', '', '', 'No suspicious drivers or services found') }
    AddSection 'drv' 'Drivers and services' 'Known abused kernel drivers (used by kernel-level cheats), unusual driver paths, and services running from user folders.' @('Type', 'Name', 'State', 'Path') $rows
}

Run-Module 'Prefetch (recently run programs)' {
    $rows = New-Object System.Collections.ArrayList
    $dir = $env:SystemRoot + '\Prefetch'
    $files = @(Get-ChildItem -LiteralPath $dir -Filter *.pf -Force | Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) {
        AddRow $rows 'review' @('', '', '(no Prefetch files)', 'Prefetch folder is empty or missing - may have been cleared or disabled')
    } else {
        $shown = 0
        foreach ($f in $files) {
            $exe = ($f.Name -replace '-[0-9A-Fa-f]{8}\.pf$', '')
            $sev = Classify $exe
            if ($sev -or $shown -lt 150) {
                $sv = $sev; if (-not $sv) { $sv = 'info' }
                AddRow $rows $sv @((Fd $f.LastWriteTime), (Fd $f.CreationTime), $exe, $f.Name)
                $shown++
            }
        }
        AddRow $rows 'info' @('', '', ('Total Prefetch files: ' + $files.Count), ('Oldest entry: ' + (Fd ($files | Sort-Object CreationTime | Select-Object -First 1).CreationTime)))
    }
    AddSection 'pf' 'Prefetch - programs that were run' 'Windows keeps a small file for each program that ran. "Last run" is the last execution time, "First seen" is when it first ran.' @('Last run', 'First seen', 'Program', 'Prefetch file') $rows
}

Run-Module 'Background Activity Monitor (BAM)' {
    $rows = New-Object System.Collections.ArrayList
    $list = New-Object System.Collections.ArrayList
    foreach ($root in @('HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings', 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings')) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($sk in @(Get-ChildItem -LiteralPath $root)) {
            $uname = SidName $sk.PSChildName
            foreach ($vn in $sk.GetValueNames()) {
                $b = $sk.GetValue($vn)
                if ($b -isnot [byte[]] -or $b.Length -lt 8 -or $vn -notmatch '\\') { continue }
                $ft = [BitConverter]::ToInt64($b, 0)
                if ($ft -le 0) { continue }
                $when = $null; try { $when = [DateTime]::FromFileTime($ft) } catch { continue }
                $p = Dev2Path $vn
                [void]$list.Add((New-Object PSObject -Property @{ When = $when; Path = $p; User = $uname }))
            }
        }
    }
    $sorted = @($list | Sort-Object When -Descending)
    $shown = 0
    foreach ($x in $sorted) {
        $gone = IsGone $x.Path
        if ($gone) { NoteExec 'BAM' $x.Path $x.When }
        $sev = Classify $x.Path
        if ($gone -and -not $sev) { $sev = 'review' }
        $status = 'exists'; if ($gone) { $status = 'DELETED / MISSING' }
        if ($sev -or $shown -lt 150) {
            $sv = $sev; if (-not $sv) { $sv = 'info' }
            AddRow $rows $sv @((Fd $x.When), $x.Path, $status, $x.User)
            $shown++
        }
    }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('', 'No BAM data (needs Windows 10 1709+ and administrator rights)', '', '') }
    AddSection 'bam' 'BAM - last execution times' 'Windows 10/11 records the last time each program was run, even after the file is deleted.' @('Last run', 'Program', 'File status', 'User') $rows
}

Run-Module 'UserAssist, MUICache and compatibility traces' {
    $rows = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($h in $script:UserHives) {
        # UserAssist
        foreach ($g in @('{CEBFF5CD-ACE2-4F4F-9178-9926F41749EA}', '{F4E57C4B-2036-45F0-A9AB-443BCFE33D9F}')) {
            $k = $h.Path + '\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\' + $g + '\Count'
            if (-not (Test-Path -LiteralPath $k)) { continue }
            $key = Get-Item -LiteralPath $k
            foreach ($vn in $key.GetValueNames()) {
                $b = $key.GetValue($vn)
                if ($b -isnot [byte[]] -or $b.Length -lt 68) { continue }
                $name = ResolveKF (Rot13 $vn) $h.Prof
                if ($name -notmatch '(?i)\.(exe|bat|jar)$') { continue }
                $cnt = [BitConverter]::ToInt32($b, 4)
                $ft = [BitConverter]::ToInt64($b, 60)
                $when = $null; if ($ft -gt 0) { try { $when = [DateTime]::FromFileTime($ft) } catch {} }
                $gone = IsGone $name
                if ($gone) { NoteExec 'UserAssist' $name $when }
                $sev = Classify $name
                if ($gone -and -not $sev -and (UW $name)) { $sev = 'review' }
                if ($sev -or $gone -or (UW $name)) {
                    $sv = $sev; if (-not $sv) { $sv = 'info' }
                    $st = 'exists'; if ($gone) { $st = 'DELETED / MISSING' }
                    AddRow $rows $sv @('UserAssist', (Fd $when), $name, ('runs: ' + $cnt + ', ' + $st))
                }
            }
        }
        # MUICache + Compatibility Assistant store
        foreach ($k in @(($h.Path + '\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'), ($h.Path + '\Software\Microsoft\Windows\ShellNoRoam\MUICache'))) {
            if (-not (Test-Path -LiteralPath $k)) { continue }
            $key = Get-Item -LiteralPath $k
            foreach ($vn in $key.GetValueNames()) {
                if ($vn -notmatch '\.FriendlyAppName$') { continue }
                $path = $vn -replace '\.FriendlyAppName$', ''
                if ($seen.ContainsKey($path.ToLower())) { continue }
                $seen[$path.ToLower()] = 1
                $gone = IsGone $path
                if ($gone) { NoteExec 'MUICache' $path $null }
                $sev = Classify ($path + ' ' + $key.GetValue($vn))
                if ($gone -and -not $sev -and (UW $path)) { $sev = 'review' }
                if ($sev -or $gone -or (UW $path)) {
                    $sv = $sev; if (-not $sv) { $sv = 'info' }
                    $st = 'exists'; if ($gone) { $st = 'DELETED / MISSING' }
                    AddRow $rows $sv @('MUICache', '', $path, $st)
                }
            }
        }
        $k = $h.Path + '\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'
        if (Test-Path -LiteralPath $k) {
            $key = Get-Item -LiteralPath $k
            foreach ($vn in $key.GetValueNames()) {
                if ($vn -notmatch '^[A-Za-z]:\\') { continue }
                if ($seen.ContainsKey($vn.ToLower())) { continue }
                $seen[$vn.ToLower()] = 1
                $gone = IsGone $vn
                if ($gone) { NoteExec 'Compat Store' $vn $null }
                $sev = Classify $vn
                if ($gone -and -not $sev -and (UW $vn)) { $sev = 'review' }
                if ($sev -or $gone -or (UW $vn)) {
                    $sv = $sev; if (-not $sv) { $sv = 'info' }
                    $st = 'exists'; if ($gone) { $st = 'DELETED / MISSING' }
                    AddRow $rows $sv @('Compat Store', '', $vn, $st)
                }
            }
        }
    }
    $rows = SortRows $rows
    if ($rows.Count -gt 400) { $rows.RemoveRange(400, ($rows.Count - 400)) }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('', '', '(nothing found for loaded user profiles)', '') }
    AddSection 'trace' 'Program traces (UserAssist / MUICache / Compatibility Store)' 'Registry traces of programs started by the user. Shown: anything missing from disk, suspicious by name, or run from user folders.' @('Source', 'Last run', 'Program', 'Details') $rows
}

Run-Module 'Recent files (shortcuts)' {
    $rows = New-Object System.Collections.ArrayList
    $wsh = $null; try { $wsh = New-Object -ComObject WScript.Shell } catch {}
    $all = New-Object System.Collections.ArrayList
    foreach ($p in $script:Profiles) {
        $rd = $p + '\AppData\Roaming\Microsoft\Windows\Recent'
        foreach ($f in @(Get-ChildItem -LiteralPath $rd -Filter *.lnk -Force)) { [void]$all.Add($f) }
    }
    $sorted = @($all | Sort-Object LastWriteTime -Descending | Select-Object -First 250)
    foreach ($f in $sorted) {
        $target = ''
        if ($wsh) { try { $target = $wsh.CreateShortcut($f.FullName).TargetPath } catch {} }
        $gone = IsGone $target
        if ($gone) { NoteExec 'Recent file' $target $f.LastWriteTime }
        $sev = Classify ($f.Name + ' ' + $target)
        $st = 'exists'
        if ($gone) { $st = 'TARGET DELETED / MISSING'; if (-not $sev) { $sev = 'review' } }
        elseif ($target -and $target -notmatch '^[A-Za-z]:\\') { $st = 'network / special' }
        elseif ($target -and $script:FixedLetters -notcontains $target.Substring(0, 2).ToUpper()) { $st = 'on removable / offline drive' }
        $sv = $sev; if (-not $sv) { $sv = 'info' }
        AddRow $rows $sv @((Fd $f.LastWriteTime), $f.Name, $target, $st)
    }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('', '(no recent-file shortcuts found - history may have been cleared)', '', '') }
    AddSection 'lnk' 'Recent files' 'Windows keeps a shortcut for files you opened. Shortcuts whose target is gone point to deleted files.' @('Opened', 'Shortcut', 'Target', 'Status') $rows
}

Run-Module 'Recycle Bin (recently deleted items)' {
    $rows = New-Object System.Collections.ArrayList
    $items = New-Object System.Collections.ArrayList
    foreach ($d in $script:FixedLetters) {
        $rb = $d + '\$Recycle.Bin'
        if (-not (Test-Path -LiteralPath $rb)) { continue }
        foreach ($sd in @(Get-ChildItem -LiteralPath $rb -Force)) {
            if (-not $sd.PSIsContainer) { continue }
            $owner = SidName $sd.Name
            $files = @(Get-ChildItem -LiteralPath $sd.FullName -Force | Where-Object { $_.Name -like '$I*' })
            if ($files.Count -eq 0) {
                if (((Get-Date) - $sd.LastWriteTime).TotalDays -lt 3) {
                    AddRow $rows 'review' @((Fd $sd.LastWriteTime), ('Recycle Bin on ' + $d + ' is EMPTY but changed recently - it may have just been emptied'), '', $owner)
                }
                continue
            }
            foreach ($f in $files) {
                try {
                    $b = [IO.File]::ReadAllBytes($f.FullName)
                    if ($b.Length -lt 28) { continue }
                    $ver = [BitConverter]::ToInt64($b, 0)
                    $size = [BitConverter]::ToInt64($b, 8)
                    $ft = [BitConverter]::ToInt64($b, 16)
                    if ($ver -eq 2) {
                        $len = [BitConverter]::ToInt32($b, 24)
                        if ($len -lt 0 -or (($len * 2) + 28) -gt $b.Length) { $len = [int](($b.Length - 28) / 2) }
                        $orig = [Text.Encoding]::Unicode.GetString($b, 28, ([int]$len * 2))
                    } else {
                        $orig = [Text.Encoding]::Unicode.GetString($b, 24, ($b.Length - 24))
                    }
                    $orig = $orig.TrimEnd([char]0)
                    $when = [DateTime]::FromFileTime($ft)
                    [void]$items.Add((New-Object PSObject -Property @{ When = $when; Orig = $orig; Size = $size; Owner = $owner }))
                } catch {}
            }
        }
    }
    foreach ($x in @($items | Sort-Object When -Descending | Select-Object -First 300)) {
        $sev = Classify $x.Orig
        if ($sev) { NoteExec 'Recycle Bin' $x.Orig $x.When }
        $sv = $sev; if (-not $sv) { $sv = 'info' }
        AddRow $rows $sv @((Fd $x.When), $x.Orig, ([string][math]::Round($x.Size / 1KB) + ' KB'), $x.Owner)
    }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('', '(Recycle Bin is empty)', '', '') }
    AddSection 'rb' 'Recycle Bin' 'Files deleted normally (not permanently) with their original location and the exact deletion time.' @('Deleted at', 'Original path', 'Size', 'User') $rows
}

Run-Module 'NTFS change journal (permanently deleted files)' {
    $rows = New-Object System.Collections.ArrayList
    $interestRx = '(?i)\.(exe|dll|sys|bat|cmd|ps1|vbs|jar|py|lua|zip|rar|7z|iso|pf|lnk|evtx|msi|scr)$'
    $lineRx = '^(?<usn>[^,]*),(?<name>.*),(?<nlen>\d+),(?<reason>0x[0-9A-Fa-f]+[^,]*FILE_DELETE[^,]*),(?<time>[^,]*),'
    $anyRx = ',(0x[0-9A-Fa-f]+[^,]*),([^,]+),'
    foreach ($dr in $script:FixedDrives) {
        if ($dr.FileSystem -ne 'NTFS') { continue }
        $d = $dr.DeviceID
        $q = & fsutil usn queryjournal $d 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            AddRow $rows 'review' @('', $d, 'USN journal is not active or not readable (it may have been deleted, or administrator rights are missing)', '')
            continue
        }
        # when does the journal start?
        $firstTime = ''
        try {
            $psi2 = New-Object System.Diagnostics.ProcessStartInfo
            $psi2.FileName = 'cmd.exe'
            $psi2.Arguments = '/c fsutil usn readjournal ' + $d + ' csv'
            $psi2.RedirectStandardOutput = $true; $psi2.UseShellExecute = $false; $psi2.CreateNoWindow = $true
            $p2 = [System.Diagnostics.Process]::Start($psi2)
            for ($i = 0; $i -lt 4; $i++) {
                $l2 = $p2.StandardOutput.ReadLine()
                if ($l2 -eq $null) { break }
                if ($l2 -match $anyRx) { $firstTime = $Matches[2]; break }
            }
            try { $p2.Kill() } catch {}
            try { $p2.StandardOutput.Close() } catch {}
        } catch {}
        # all delete records
        $tmp = $env:SystemRoot + '\Temp\xion_usn_' + $d.Substring(0, 1) + '.txt'
        Remove-Item -LiteralPath $tmp -Force
        $total = 0; $pfDel = 0; $evtxDel = 0
        $keep = New-Object System.Collections.ArrayList
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'cmd.exe'
            $psi.Arguments = '/c fsutil usn readjournal ' + $d + ' csv | findstr /C:FILE_DELETE > "' + $tmp + '"'
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $pr = [System.Diagnostics.Process]::Start($psi)
            if (-not $pr.WaitForExit(180000)) { try { $pr.Kill() } catch {}; AddRow $rows 'info' @('', $d, 'Journal read stopped after 3 minutes (very large journal) - results are partial', '') }
        } catch {}
        if (Test-Path -LiteralPath $tmp) {
            $sr = $null
            try {
                $sr = New-Object System.IO.StreamReader($tmp, [System.Text.Encoding]::Default)
                while (($line = $sr.ReadLine()) -ne $null) {
                    if ($line -match $lineRx) {
                        $total++
                        $tm = $Matches['time']; $rs = $Matches['reason']
                        $nm = $Matches['name'].Trim('"')
                        if ($nm -match '(?i)\.pf$') { $pfDel++ }
                        if ($nm -match '(?i)\.evtx$') { $evtxDel++ }
                        if ($nm -match $interestRx -or (Classify $nm)) {
                            [void]$keep.Add((New-Object PSObject -Property @{ Name = $nm; Time = $tm; Reason = $rs }))
                        }
                    }
                }
            } catch {}
            if ($sr) { $sr.Close() }
            Remove-Item -LiteralPath $tmp -Force
        }
        $cover = 'Journal on ' + $d + ' starts at: ' + $firstTime + '. Deleted-file records seen: ' + $total
        $sevc = 'info'
        $dt = [datetime]::MinValue
        if ($firstTime -and [datetime]::TryParse($firstTime, [ref]$dt)) {
            if (((Get-Date) - $dt).TotalHours -lt 24) { $sevc = 'review'; $cover = $cover + '  <-- journal is less than 24 hours old: it may have been reset (fsutil usn deletejournal) or the disk is very busy' }
        }
        AddRow $rows $sevc @('', $d, $cover, '')
        if ($pfDel -ge 20) { AddRow $rows 'review' @('', $d, ([string]$pfDel + ' Prefetch (.pf) files were deleted - can be normal cleanup, or someone wiping run history'), '') }
        if ($evtxDel -gt 0) { AddRow $rows 'review' @('', $d, ([string]$evtxDel + ' event log (.evtx) file deletions recorded'), '') }
        $newest = @($keep)
        [array]::Reverse($newest)
        $n = 0
        foreach ($k in $newest) {
            if ($n -ge 250) { break }
            $sev = Classify $k.Name
            $sv = $sev; if (-not $sv) { $sv = 'info' }
            AddRow $rows $sv @($k.Time, $d, $k.Name, ($k.Reason -replace '^0x[0-9A-Fa-f]+:\s*', ''))
            $n++
        }
    }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('', '', 'No NTFS drives with a readable journal (needs administrator and Windows 10 or newer)', '') }
    AddSection 'usn' 'Permanently deleted files (NTFS journal)' 'Even files deleted with Shift+Delete or by a cleaner leave a record here. Only the file NAME is stored. Newest first; programs, scripts, archives, shortcuts and logs only.' @('Time', 'Drive', 'Deleted file name', 'Reason') $rows
}

Run-Module 'Scanning folders for cheat / executor files' {
    $rows = New-Object System.Collections.ArrayList
    $seen = @{}
    $flagged = New-Object System.Collections.ArrayList
    $recent = New-Object System.Collections.ArrayList
    $extRx = '^\.(exe|dll|sys|jar|bat|cmd|ps1|vbs|zip|rar|7z|lua|msi|scr)$'
    $cut = (Get-Date).AddDays(-14)
    $roots = New-Object System.Collections.ArrayList
    foreach ($p in $script:Profiles) {
        foreach ($sub in @('Desktop', 'Downloads', 'Documents', 'AppData\Roaming', 'AppData\Local\Temp', 'AppData\Local\Programs', 'OneDrive\Desktop', 'OneDrive\Downloads', 'OneDrive\Documents')) {
            $r = $p + '\' + $sub
            if (Test-Path -LiteralPath $r) { [void]$roots.Add($r) }
        }
    }
    [void]$roots.Add(($env:SystemRoot + '\Temp'))
    if ($env:ProgramData) { [void]$roots.Add($env:ProgramData) }

    foreach ($r in $roots) {
        $recentRoot = ($r -match '(?i)\\(Downloads|Desktop|Temp)$')
        foreach ($f in @(Get-ChildItem -LiteralPath $r -Recurse -Force | Where-Object { -not $_.PSIsContainer })) {
            $ext = $f.Extension.ToLower()
            $isExt = ($ext -match $extRx)
            if (-not $isExt -and $f.Name -notmatch $HighRx) { continue }
            $key = $f.FullName.ToLower()
            if ($seen.ContainsKey($key)) { continue }
            $sev = Classify ($f.Name + ' ' + $f.DirectoryName)
            if (-not $sev -and $ext -eq '.sys') { $sev = 'review' }
            if ($sev) { $seen[$key] = 1; [void]$flagged.Add((New-Object PSObject -Property @{ F = $f; Sev = $sev })) }
            elseif ($recentRoot -and $ext -ne '.dll' -and $f.LastWriteTime -gt $cut) { $seen[$key] = 1; [void]$recent.Add($f) }
        }
    }
    # shallow look at the top 3 levels of every fixed drive (catches loose tool folders like D:\Xeno)
    foreach ($d in $script:FixedLetters) {
        foreach ($pat in @(($d + '\*'), ($d + '\*\*'), ($d + '\*\*\*'))) {
            foreach ($f in @(Get-ChildItem -Path $pat -Force)) {
                $key = $f.FullName.ToLower()
                if ($seen.ContainsKey($key)) { continue }
                $sev = Classify $f.Name
                if ($sev) { $seen[$key] = 1; [void]$flagged.Add((New-Object PSObject -Property @{ F = $f; Sev = $sev })) }
            }
        }
    }
    $sigN = 0
    foreach ($x in @($flagged | Sort-Object { $_.F.LastWriteTime } -Descending | Select-Object -First 300)) {
        $f = $x.F
        $sig = ''
        if (-not $f.PSIsContainer -and $f.Extension -match '(?i)^\.(exe|dll|sys)$' -and $sigN -lt 60) { $sig = SigC $f.FullName; $sigN++ }
        $kind = ''; $size = ''
        if ($f.PSIsContainer) { $kind = '[folder] ' } else { $size = [string][math]::Round($f.Length / 1KB) + ' KB' }
        $dirn = $f.DirectoryName; if (-not $dirn) { $dirn = Split-Path $f.FullName }
        AddRow $rows $x.Sev @((Fd $f.LastWriteTime), (Fd $f.CreationTime), ($kind + $f.Name), $dirn, $size, $sig)
    }
    foreach ($f in @($recent | Sort-Object LastWriteTime -Descending | Select-Object -First 120)) {
        $sig = ''
        if ($f.Extension -match '(?i)^\.(exe)$' -and $sigN -lt 120) { $sig = SigC $f.FullName; $sigN++ }
        AddRow $rows 'info' @((Fd $f.LastWriteTime), (Fd $f.CreationTime), $f.Name, $f.DirectoryName, ([string][math]::Round($f.Length / 1KB) + ' KB'), $sig)
    }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('', '', '(nothing found)', '', '', '') }
    AddSection 'files' 'Suspicious files and recent downloads' 'Name-based search for known executors / injectors / cheat tools in user folders, plus programs and archives added to Downloads, Desktop or Temp in the last 14 days (grey rows).' @('Modified', 'Created', 'Name', 'Folder', 'Size', 'Signature') $rows
}

Run-Module 'Event logs' {
    $rows = New-Object System.Collections.ArrayList
    $now = Get-Date
    function GetEv($filter, $max) { try { return @(Get-WinEvent -FilterHashtable $filter -MaxEvents $max -ErrorAction Stop) } catch { return @() } }
    function FirstLine($m) { if (-not $m) { return '' }; return (([string]$m -split "`r?`n")[0]) }
    function OneLine($m) { if (-not $m) { return '' }; return (([string]$m) -replace "[`r`n]+", ' ') }

    # logs cleared
    $ev = @()
    $ev += GetEv @{ LogName = 'Security'; Id = 1102 } 20
    $ev += GetEv @{ LogName = 'System'; Id = 104 } 20
    foreach ($e in @($ev)) {
        if ($e -eq $null) { continue }
        $sev = 'review'; if ($e.TimeCreated -gt $now.AddDays(-30)) { $sev = 'high' }
        AddRow $rows $sev @((Fd $e.TimeCreated), 'LOG CLEARED', ('Event ' + $e.Id), (Trunc (OneLine $e.Message) 200))
    }
    # oldest events
    foreach ($ln in @('System', 'Application')) {
        $o = $null
        try { $o = @(Get-WinEvent -LogName $ln -Oldest -MaxEvents 1 -ErrorAction Stop)[0] } catch {}
        if ($o) {
            $sev = 'info'
            if (((Get-Date) - $o.TimeCreated).TotalDays -lt 3) { $sev = 'review' }
            $note = ''; if ($sev -eq 'review') { $note = ' <-- this log only goes back a few days; it may have been cleared' }
            AddRow $rows $sev @((Fd $o.TimeCreated), ($ln + ' log - oldest event'), '', ('The ' + $ln + ' log starts at this time.' + $note))
        }
    }
    # system time changes
    foreach ($e in (GetEv @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 1; StartTime = $now.AddDays(-30) } 60)) {
        if ($e -eq $null) { continue }
        try {
            $newT = [datetime]$e.Properties[0].Value; $oldT = [datetime]$e.Properties[1].Value
            $diff = [math]::Abs(($newT - $oldT).TotalSeconds)
            if ($diff -gt 120) { AddRow $rows 'review' @((Fd $e.TimeCreated), 'SYSTEM TIME CHANGED', ('by ' + [math]::Round($diff / 60) + ' minutes'), ('from ' + (Fd $oldT.ToLocalTime()) + ' to ' + (Fd $newT.ToLocalTime()))) }
        } catch {}
    }
    # services installed
    foreach ($e in (GetEv @{ LogName = 'System'; Id = 7045; StartTime = $now.AddDays(-30) } 80)) {
        if ($e -eq $null) { continue }
        $nm = [string]$e.Properties[0].Value; $img = [string]$e.Properties[1].Value
        $sev = Classify ($nm + ' ' + $img)
        if (-not $sev -and $img -match '(?i)\\(Users|Temp|AppData)\\') { $sev = 'review' }
        $sv = $sev; if (-not $sv) { $sv = 'info' }
        AddRow $rows $sv @((Fd $e.TimeCreated), 'Service installed', $nm, $img)
    }
    # defender
    foreach ($e in (GetEv @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = @(1116, 1117, 5001, 5007, 5010, 5012); StartTime = $now.AddDays(-30) } 100)) {
        if ($e -eq $null) { continue }
        $msg = OneLine $e.Message
        $sev = ''; $what = ''
        switch ($e.Id) {
            1116 { $sev = 'review'; $what = 'Defender: threat detected'; if (Classify $msg) { $sev = 'high' } }
            1117 { $sev = 'info'; $what = 'Defender: action taken' }
            5001 { $sev = 'review'; $what = 'Defender: real-time protection DISABLED' }
            5010 { $sev = 'review'; $what = 'Defender: scanning disabled' }
            5012 { $sev = 'review'; $what = 'Defender: scanning disabled' }
            5007 { if ($msg -match '(?i)exclusion') { $sev = 'review'; $what = 'Defender: exclusion changed' } }
        }
        if ($sev) { AddRow $rows $sev @((Fd $e.TimeCreated), $what, ('Event ' + $e.Id), (Trunc $msg 240)) }
    }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('', '(nothing notable)', '', '') }
    AddSection 'evt' 'Event logs' 'Cleared logs, changed system clock, newly installed services and Defender detections / changes (last 30 days).' @('Time', 'What', 'Detail', 'Message') $rows
}

Run-Module 'Startup, tasks, installed software, USB' {
    # startup entries
    $rows = New-Object System.Collections.ArrayList
    $runKeys = New-Object System.Collections.ArrayList
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run')) { [void]$runKeys.Add($k) }
    foreach ($h in $script:UserHives) {
        [void]$runKeys.Add(($h.Path + '\Software\Microsoft\Windows\CurrentVersion\Run'))
        [void]$runKeys.Add(($h.Path + '\Software\Microsoft\Windows\CurrentVersion\RunOnce'))
    }
    foreach ($k in $runKeys) {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        $key = Get-Item -LiteralPath $k
        foreach ($vn in $key.GetValueNames()) {
            $cmd = [string]$key.GetValue($vn)
            $sev = Classify ($vn + ' ' + $cmd)
            if (-not $sev -and $cmd -match '(?i)(powershell|wscript|mshta|cscript).*(-enc|hidden|http)') { $sev = 'review' }
            $sv = $sev; if (-not $sv) { $sv = 'info' }
            AddRow $rows $sv @('Run key', $vn, $cmd)
        }
    }
    $sfolders = New-Object System.Collections.ArrayList
    [void]$sfolders.Add(($env:ProgramData + '\Microsoft\Windows\Start Menu\Programs\Startup'))
    foreach ($p in $script:Profiles) { [void]$sfolders.Add(($p + '\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')) }
    foreach ($sf in $sfolders) {
        foreach ($f in @(Get-ChildItem -LiteralPath $sf -Force)) {
            if ($f.Name -eq 'desktop.ini') { continue }
            $sev = Classify $f.Name
            $sv = $sev; if (-not $sv) { $sv = 'info' }
            AddRow $rows $sv @('Startup folder', $f.Name, $f.FullName)
        }
    }
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        foreach ($t in @(Get-ScheduledTask)) {
            if ($t.TaskPath -like '\Microsoft\*') { continue }
            $a = @($t.Actions)[0]
            $cmd = ([string]$a.Execute + ' ' + [string]$a.Arguments).Trim()
            $sev = Classify ($t.TaskName + ' ' + $cmd)
            if (-not $sev -and $cmd -match '(?i)(powershell|wscript|mshta|cscript|cmd).*(-enc|hidden|http)') { $sev = 'review' }
            $sv = $sev; if (-not $sv) { $sv = 'info' }
            AddRow $rows $sv @('Scheduled task', ($t.TaskPath + $t.TaskName), $cmd)
        }
    }
    if ($rows.Count -eq 0) { AddRow $rows 'info' @('', '(nothing found)', '') }
    AddSection 'startup' 'Startup entries and scheduled tasks' 'Programs that start with Windows (non-Microsoft scheduled tasks included).' @('Type', 'Name', 'Command / path') $rows

    # installed software
    $sw = New-Object System.Collections.ArrayList
    $ur = New-Object System.Collections.ArrayList
    [void]$ur.Add('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    [void]$ur.Add('HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($h in $script:UserHives) { [void]$ur.Add(($h.Path + '\Software\Microsoft\Windows\CurrentVersion\Uninstall')) }
    $names = @{}
    $tmpList = New-Object System.Collections.ArrayList
    foreach ($u in $ur) {
        foreach ($k in @(Get-ChildItem -LiteralPath $u)) {
            $pp = Get-ItemProperty $k.PSPath
            if (-not $pp.DisplayName) { continue }
            if ($names.ContainsKey($pp.DisplayName)) { continue }
            $names[$pp.DisplayName] = 1
            [void]$tmpList.Add($pp)
        }
    }
    foreach ($pp in @($tmpList | Sort-Object DisplayName | Select-Object -First 400)) {
        $sev = Classify ($pp.DisplayName + ' ' + $pp.InstallLocation)
        $note = ''
        if (-not $sev -and $pp.DisplayName -match $RemoteRx) { $note = ' (remote access software)' }
        $sv = $sev; if (-not $sv) { $sv = 'info' }
        AddRow $sw $sv @(($pp.DisplayName + $note), $pp.DisplayVersion, $pp.Publisher, $pp.InstallDate)
    }
    AddSection 'soft' 'Installed software' 'From the Windows uninstall registry.' @('Name', 'Version', 'Publisher', 'Install date') $sw

    # USB
    $usb = New-Object System.Collections.ArrayList
    foreach ($k in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR')) {
        foreach ($i in @(Get-ChildItem $k.PSPath)) {
            $pp = Get-ItemProperty $i.PSPath
            $fn = $pp.FriendlyName; if (-not $fn) { $fn = $k.PSChildName }
            AddRow $usb 'info' @($fn, $i.PSChildName)
        }
    }
    if ($usb.Count -eq 0) { AddRow $usb 'info' @('(none recorded)', '') }
    AddSection 'usb' 'USB storage devices ever connected' 'USB drives / phones that have been plugged into this PC.' @('Device', 'Serial / instance') $usb
}

Run-Module 'Browser history (keyword scan)' {
    $rows = New-Object System.Collections.ArrayList
    $kw = '(solara|wearedevs|xeno\.onl|xeno-?executor|jjsploit|krnl|fluxus|valex|volcano-?exec|hydrogenm|ronix|delta-?executor|roblox-?(executor|exploit|exploits|script)|executor|exploits?|cheat|aimbot|spoofer|injector|cheatengine|scriptblox|rscripts|synapse|macsploit|zorara|seliware)'
    $urlRx = '(?i)https?://[^\x00-\x20"<>\\|^`]{0,200}' + $kw + '[^\x00-\x20"<>\\|^`]{0,200}'
    $files = New-Object System.Collections.ArrayList
    foreach ($p in $script:Profiles) {
        foreach ($b in @('AppData\Local\Google\Chrome\User Data', 'AppData\Local\Microsoft\Edge\User Data', 'AppData\Local\BraveSoftware\Brave-Browser\User Data')) {
            $ud = $p + '\' + $b
            foreach ($pd in @(Get-ChildItem -LiteralPath $ud -Force)) {
                if (-not $pd.PSIsContainer) { continue }
                $h = $pd.FullName + '\History'
                if (Test-Path -LiteralPath $h) { [void]$files.Add((New-Object PSObject -Property @{ Path = $h; Label = ($b.Split('\')[2] + ' / ' + $pd.Name) })) }
            }
        }
        foreach ($pd in @(Get-ChildItem -LiteralPath ($p + '\AppData\Roaming\Mozilla\Firefox\Profiles') -Force)) {
            $h = $pd.FullName + '\places.sqlite'
            if (Test-Path -LiteralPath $h) { [void]$files.Add((New-Object PSObject -Property @{ Path = $h; Label = ('Firefox / ' + $pd.Name) })) }
        }
        $op = $p + '\AppData\Roaming\Opera Software\Opera Stable\History'
        if (Test-Path -LiteralPath $op) { [void]$files.Add((New-Object PSObject -Property @{ Path = $op; Label = 'Opera' })) }
    }
    $latin = [System.Text.Encoding]::GetEncoding(28591)
    $hits = @{}
    foreach ($f in $files) {
        $fs = $null
        try {
            $fs = [System.IO.File]::Open($f.Path, 'Open', 'Read', 'ReadWrite')
            $buf = New-Object byte[] ([int]$fs.Length)
            $off = 0
            while ($off -lt $buf.Length) { $rd = $fs.Read($buf, $off, ($buf.Length - $off)); if ($rd -le 0) { break }; $off += $rd }
            $fs.Close()
            $txt = $latin.GetString($buf)
            foreach ($m in [regex]::Matches($txt, $urlRx)) {
                $u = $m.Value
                if (-not $hits.ContainsKey($u) -and $hits.Count -lt 120) {
                    $hits[$u] = 1
                    $sev = 'review'; if ($u -match $HighRx) { $sev = 'high' }
                    AddRow $rows $sev @($f.Label, $u)
                }
            }
        } catch { if ($fs) { try { $fs.Close() } catch {} } }
    }
    if ($files.Count -eq 0) { AddRow $rows 'info' @('(no browser history files found)', '') }
    elseif ($rows.Count -eq 0) { AddRow $rows 'info' @(('Scanned ' + $files.Count + ' history files'), 'No cheat / executor related addresses found') }
    AddSection 'web' 'Browser history matches' 'Addresses in Chrome / Edge / Brave / Firefox / Opera history that contain executor, exploit or cheat keywords. Cleared history leaves nothing to find.' @('Browser / profile', 'Address') $rows
}

Run-Module 'Executed programs that no longer exist' {
    $rows = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($x in @($script:ExecMissing | Sort-Object Time -Descending)) {
        $k = ([string]$x.Path).ToLower()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = 1
        $sev = Classify $x.Path
        if (-not $sev -and $x.Path -match '(?i)\\(Downloads|Desktop|Documents|Temp)\\') { $sev = 'review' }
        if (-not $sev) { $sev = 'info' }
        AddRow $rows $sev @((Fd $x.Time), $x.Path, $x.Src)
    }
    $sorted = SortRows $rows
    if ($sorted.Count -gt 300) { $sorted.RemoveRange(300, ($sorted.Count - 300)) }
    if ($sorted.Count -eq 0) { AddRow $sorted 'info' @('', '(none found)', '') }
    AddSection 'missing' 'Programs that were run but are now deleted' 'Combined from BAM, UserAssist, MUICache, Compatibility Store, Recent files and the Recycle Bin. This is the "deleted executor" check: the program ran, then the file was removed.' @('Last run / seen', 'Path', 'Found in') $sorted
}

# ============================================================== REPORT ======
Step 'Building report'
$pcName = $env:COMPUTERNAME
$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$reportPath = $env:TEMP + '\XION_PC_CHECK_' + $pcName + '_' + $stamp + '.html'

$order = @('missing', 'usn', 'rb', 'sec', 'inj', 'drv', 'proc', 'win', 'files', 'bam', 'pf', 'trace', 'lnk', 'evt', 'web', 'startup', 'soft', 'usb', 'sys')
$ordered = New-Object System.Collections.ArrayList
foreach ($id in $order) { foreach ($s in $script:Sections) { if ($s.Id -eq $id) { [void]$ordered.Add($s) } } }
foreach ($s in $script:Sections) { if ($order -notcontains $s.Id) { [void]$ordered.Add($s) } }

$hiTotal = 0; $rvTotal = 0
$summaryRows = New-Object System.Text.StringBuilder
$findings = New-Object System.Text.StringBuilder
$body = New-Object System.Text.StringBuilder
$fcount = 0
foreach ($s in $ordered) {
    $hi = 0; $rv = 0
    foreach ($r in @($s.Rows)) {
        if ($r.Sev -eq 'high') { $hi++ } elseif ($r.Sev -eq 'review') { $rv++ }
    }
    $hiTotal += $hi; $rvTotal += $rv
    if ($s.Id -ne 'sys') {
        [void]$summaryRows.Append('<tr><td><a href="#' + $s.Id + '">' + (Esc $s.Title) + '</a></td><td>' + $hi + '</td><td>' + $rv + '</td></tr>')
    }
    foreach ($r in @($s.Rows)) {
        if ($r.Sev -eq 'high' -and $fcount -lt 80) {
            $fcount++
            $txt = (@($r.Cells) | Where-Object { $_ -ne $null -and [string]$_ -ne '' }) -join '  |  '
            [void]$findings.Append('<li><b>' + (Esc $s.Title) + '</b><br>' + (Esc (Trunc $txt 300)) + '</li>')
        }
    }
    $open = ''; if ($hi -gt 0 -or $rv -gt 0 -or $s.Id -eq 'sys') { $open = ' open' }
    [void]$body.Append('<details id="' + $s.Id + '"' + $open + '><summary>' + (Esc $s.Title))
    if ($hi -gt 0) { [void]$body.Append(' <span class="b hi">' + $hi + ' high</span>') }
    if ($rv -gt 0) { [void]$body.Append(' <span class="b rv">' + $rv + ' review</span>') }
    [void]$body.Append('</summary>')
    if ($s.Note) { [void]$body.Append('<p class="note">' + (Esc $s.Note) + '</p>') }
    [void]$body.Append('<div class="tw"><table><thead><tr><th></th>')
    foreach ($c in @($s.Cols)) { [void]$body.Append('<th>' + (Esc $c) + '</th>') }
    [void]$body.Append('</tr></thead><tbody>')
    $n = 0
    foreach ($r in @($s.Rows)) {
        if ($n -ge 700) { break }
        $badge = ''
        if ($r.Sev -eq 'high') { $badge = '<span class="b hi">HIGH</span>' } elseif ($r.Sev -eq 'review') { $badge = '<span class="b rv">REVIEW</span>' }
        [void]$body.Append('<tr class="sev-' + $r.Sev + '"><td>' + $badge + '</td>')
        foreach ($c in @($r.Cells)) { [void]$body.Append('<td>' + (Esc $c) + '</td>') }
        [void]$body.Append('</tr>')
        $n++
    }
    [void]$body.Append('</tbody></table></div>')
    if (@($s.Rows).Count -gt 700) { [void]$body.Append('<p class="note">Showing the first 700 of ' + @($s.Rows).Count + ' rows.</p>') }
    [void]$body.Append('</details>')
}

if ($hiTotal -gt 0) {
    $vClass = 'bad'; $vText = 'HIGH-RISK INDICATORS FOUND: ' + $hiTotal
    $vSub = 'Check the list below. These are strong indicators, but still verify each one before deciding.'
} elseif ($rvTotal -gt 0) {
    $vClass = 'warn'; $vText = 'No high-risk indicators - ' + $rvTotal + ' items to review'
    $vSub = 'Open the sections marked REVIEW and judge them. Many are normal (installers, cleaners, updates).'
} else {
    $vClass = 'ok'; $vText = 'Nothing suspicious found by these checks'
    $vSub = 'This does not prove the PC is clean - see the limits at the bottom.'
}

$css = @'
:root{--bg:#0b0b12;--card:#14141f;--line:#262638;--tx:#e8e8f2;--mut:#8b8ba3;--ac:#a855f7;--hi:#ef4444;--rv:#f59e0b;--ok:#22c55e}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:14px/1.45 Segoe UI,Arial,sans-serif}
.wrap{max-width:1250px;margin:0 auto;padding:24px 16px 60px}
h1{margin:0;font-size:30px;letter-spacing:6px;background:linear-gradient(90deg,#60a5fa,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent}
.sub{color:var(--mut);margin:4px 0 18px}
.verdict{border-radius:12px;padding:18px 20px;margin:12px 0 18px;border:1px solid var(--line)}
.verdict.bad{background:#2a1115;border-color:#7f1d1d}.verdict.warn{background:#2a2111;border-color:#78531a}.verdict.ok{background:#10241a;border-color:#14532d}
.verdict h2{margin:0 0 4px;font-size:20px}.verdict p{margin:0;color:var(--mut)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:10px;margin-bottom:18px}
.tile{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}.tile small{color:var(--mut);display:block}.tile b{font-size:15px}
.box{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 18px;margin-bottom:18px}
.box h3{margin:0 0 8px}.box ul{margin:0;padding-left:18px}.box li{margin:6px 0;word-break:break-all}
.tools{position:sticky;top:0;background:var(--bg);padding:10px 0;z-index:5;display:flex;gap:14px;align-items:center;flex-wrap:wrap}
.tools input[type=text]{background:var(--card);border:1px solid var(--line);color:var(--tx);padding:8px 12px;border-radius:8px;min-width:260px}
details{background:var(--card);border:1px solid var(--line);border-radius:12px;margin:10px 0;padding:0 14px}
summary{cursor:pointer;padding:12px 0;font-weight:600}
.note{color:var(--mut);margin:0 0 10px}.tw{overflow-x:auto;padding-bottom:12px}
table{border-collapse:collapse;width:100%}th{text-align:left;color:var(--mut);font-weight:600;border-bottom:1px solid var(--line);padding:6px 8px;white-space:nowrap}
td{padding:6px 8px;border-bottom:1px solid #1d1d2c;vertical-align:top;word-break:break-word}
tr.sev-high td{background:#2a1115}tr.sev-review td{background:#2a2111}
.b{display:inline-block;font-size:11px;font-weight:700;border-radius:6px;padding:2px 7px;margin-left:6px;color:#000}.b.hi{background:var(--hi);color:#fff}.b.rv{background:var(--rv)}
td .b{margin-left:0}a{color:#93c5fd}.foot{color:var(--mut);font-size:12.5px;margin-top:26px}
'@

$js = @'
function f(){var q=document.getElementById('q').value.toLowerCase();var only=document.getElementById('only').checked;
var rows=document.querySelectorAll('tbody tr');for(var i=0;i<rows.length;i++){var r=rows[i];var t=r.textContent.toLowerCase();
var ok=(!q||t.indexOf(q)>-1)&&(!only||r.className.indexOf('sev-high')>-1||r.className.indexOf('sev-review')>-1);r.style.display=ok?'':'none';}
if(q||only){var d=document.querySelectorAll('details');for(var j=0;j<d.length;j++){d[j].open=true;}}}
'@

$os2 = Get-WmiObject Win32_OperatingSystem
$cs2 = Get-WmiObject Win32_ComputerSystem
$secs = [int]((Get-Date) - $script:Started).TotalSeconds
$html = New-Object System.Text.StringBuilder
[void]$html.Append('<!DOCTYPE html><html><head><meta charset="utf-8"><title>XION PC CHECK - ' + (Esc $pcName) + '</title><meta name="viewport" content="width=device-width,initial-scale=1"><style>' + $css + '</style></head><body><div class="wrap">')
[void]$html.Append('<h1>XION PC CHECK</h1><div class="sub">Scan finished ' + (Fd (Get-Date)) + ' &middot; took ' + $secs + ' s &middot; local scan, nothing was uploaded</div>')
[void]$html.Append('<div class="verdict ' + $vClass + '"><h2>' + (Esc $vText) + '</h2><p>' + (Esc $vSub) + '</p></div>')
$dtype = 'Desktop / other'; if ($cs2.PCSystemType -eq 2) { $dtype = 'Laptop / notebook' }
[void]$html.Append('<div class="grid"><div class="tile"><small>PC name</small><b>' + (Esc $pcName) + '</b></div><div class="tile"><small>User</small><b>' + (Esc $env:USERNAME) + '</b></div><div class="tile"><small>Windows</small><b>' + (Esc $os2.Caption) + ' (' + (Esc $os2.BuildNumber) + ')</b></div><div class="tile"><small>Model</small><b>' + (Esc ($cs2.Manufacturer + ' ' + $cs2.Model)) + '</b></div><div class="tile"><small>High</small><b style="color:var(--hi)">' + $hiTotal + '</b></div><div class="tile"><small>Review</small><b style="color:var(--rv)">' + $rvTotal + '</b></div></div>')
if ($findings.Length -gt 0) { [void]$html.Append('<div class="box"><h3>High-risk indicators</h3><ul>' + $findings.ToString() + '</ul></div>') }
[void]$html.Append('<div class="box"><h3>Summary by check</h3><table><thead><tr><th>Check</th><th>High</th><th>Review</th></tr></thead><tbody>' + $summaryRows.ToString() + '</tbody></table></div>')
[void]$html.Append('<div class="tools"><input type="text" id="q" placeholder="Search the report..." oninput="f()"><label><input type="checkbox" id="only" onchange="f()"> only show HIGH / REVIEW rows</label></div>')
[void]$html.Append($body.ToString())
[void]$html.Append('<div class="foot"><b>Limits.</b> This tool reads what Windows itself records (deleted-file journal, Recycle Bin, Prefetch, BAM, registry traces, event logs, files, drivers, loaded modules, browser history text). It cannot see kernel-level or manually-mapped cheats, hardware (DMA) cheats, a fully reinstalled or wiped Windows, or anything done outside Windows. Every HIGH / REVIEW row is an indicator to verify - not proof. Names are matched against a list of well-known tools, so renamed tools can slip through (check the signature / path columns).</div>')
[void]$html.Append('<script>' + $js + '</script></div></body></html>')

# (local HTML report disabled — results go to Discord only)

# ============================================================= DISCORD WEBHOOK =====
Step 'Sending report to admin Discord'
function Send-XionDiscord {
    param($hiTotal, $rvTotal, $ordered, $pcName, $stamp)

    # ---- webhook URL (do not share this file publicly) ----
    $wh = 'https://discord.com/api/webhooks/1568156796974010450/on_mWH_NA-Yuba1FxSP5n59FRvok11ai3J8jgxojvUJRJkx_yjbNxcqAebd7W2hYtRqQ'

    # collect up to 20 HIGH findings for the embed
    $highLines = New-Object System.Collections.ArrayList
    foreach ($s in $ordered) {
        foreach ($r in @($s.Rows)) {
            if ($r.Sev -eq 'high' -and $highLines.Count -lt 20) {
                $txt = (@($r.Cells) | Where-Object { $_ -ne $null -and [string]$_ -ne '' }) -join ' | '
                [void]$highLines.Add('`[' + $s.Title + ']` ' + (Trunc $txt 100))
            }
        }
    }

    # extra system info for the embed
    $osObj   = Get-WmiObject Win32_OperatingSystem
    $winInfo = $osObj.Caption + ' (Build ' + $osObj.BuildNumber + ')'

    # embed colour: red = high, orange = review only, green = clean
    $embedColor = 3866471          # green  #3BA55D
    if ($rvTotal -gt 0) { $embedColor = 16744272 }   # orange #FF8800
    if ($hiTotal -gt 0) { $embedColor = 15548997 }   # red    #ED4245

    $verdict = ''
    if ($hiTotal -gt 0)      { $verdict = ':red_circle: **HIGH-RISK INDICATORS FOUND — ' + $hiTotal + '**' }
    elseif ($rvTotal -gt 0)  { $verdict = ':yellow_circle: No high-risk items — ' + $rvTotal + ' to review' }
    else                      { $verdict = ':green_circle: Nothing suspicious found' }

    $flaggedText = '*(none)*'
    if ($highLines.Count -gt 0) {
        $flaggedText = ($highLines -join "`n")
        if ($flaggedText.Length -gt 1024) { $flaggedText = $flaggedText.Substring(0, 1020) + '...' }
    }

    # build Discord embed payload
    $embed = [ordered]@{
        title       = 'XION PC Check — ' + $pcName
        description = $verdict
        color       = $embedColor
        fields      = @(
            [ordered]@{ name = 'PC Name';     value = $pcName;           inline = $true  }
            [ordered]@{ name = 'User';        value = $env:USERNAME;     inline = $true  }
            [ordered]@{ name = 'Windows';     value = $winInfo;          inline = $false }
            [ordered]@{ name = ':x: HIGH';    value = "$hiTotal";        inline = $true  }
            [ordered]@{ name = ':eyes: REVIEW'; value = "$rvTotal";      inline = $true  }
            [ordered]@{ name = 'Flagged items'; value = $flaggedText;    inline = $false }
        )
        footer      = [ordered]@{ text = 'XION PC Check  |  Scan: ' + $stamp }
        timestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    $payload = ([ordered]@{ username = 'XION PC Check'; embeds = @($embed) } | ConvertTo-Json -Depth 10)

    try {
        Invoke-RestMethod -Uri $wh -Method Post -Body $payload -ContentType 'application/json' -ErrorAction Stop | Out-Null
        Say '  Report delivered to admin Discord.' 'Green'
    } catch {
        Say ('  ! Discord delivery failed: ' + $_.Exception.Message) 'Yellow'
        Say '    Please contact the admin and let them know the report failed to send.' 'DarkGray'
    }
}
Send-XionDiscord -hiTotal $hiTotal -rvTotal $rvTotal -ordered $ordered -pcName $pcName -stamp $stamp

# ------------------------------------------------------------ console end ---
Say ''
Say '  Scan complete. Results sent to admin.' 'Green'
Say '  This window will close shortly.' 'DarkGray'
Say ''

# --------------------------------------------------------- self-delete ----
# Deletes the tool after use so it cannot be run again
$me = $env:XION_SELF
if ($me -and (Test-Path -LiteralPath $me)) {
    Start-Process cmd -ArgumentList "/c ping 127.0.0.1 -n 4 >nul & del /f /q `"$me`"" -WindowStyle Hidden
}
Start-Sleep 3
