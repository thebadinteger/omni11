# omni11
# usage: irm <url> | iex
# relaunches elevated when needed

$BaseUrl = 'https://raw.githubusercontent.com/thebadinteger/omni11/refs/heads/main'
$SelfUrl = "$BaseUrl/omni11.ps1"

$WorkDir = 'C:\omni11'
$MountDir = 'C:\scratchdir'
$MinFreeGb = 20
$script:RunAll = $false
$script:Offline = $false
$script:HivesReady = $false
$script:Reg = @{
    SOFTWARE = 'HKLM\SOFTWARE\'
    SYSTEM   = 'HKLM\SYSTEM\'
    NTUSER   = 'HKCU\'
    DEFAULT  = 'HKCU\'
}

$Bloat = @(
    'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch',
    'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.Solitaire', 'Microsoft.OutlookForWindows',
    'Microsoft.Outlook', 'Microsoft.LinkedIn', 'Microsoft.LinkedInforWindows', 'Microsoft.People',
    'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos',
    'Microsoft.windowscommunicationsapps', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
    'Microsoft.YourPhone',
    'Microsoft.ZuneVideo', 'MicrosoftCorporationII.MicrosoftFamily',
    'MicrosoftCorporationII.QuickAssist', 'MicrosoftTeams', 'MSTeams', 'Microsoft.Copilot',
    'Microsoft.MicrosoftStickyNotes', 'MicrosoftWindows.Client.WebExperience',
    'MicrosoftWindows.CrossDevice', 'Microsoft.Windows.DevHome', 'Microsoft.StartExperiencesApp',
    'Microsoft.WidgetsPlatformRuntime'
)

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    if ($PSCommandPath) { $body = "& '$PSCommandPath'" }
    else { $body = "irm '$SelfUrl' | iex" }
    $cmd = "Write-Host '[*] loading omni11'; try { $body } catch { Write-Host `$_.Exception.Message -ForegroundColor Red; Write-Host -NoNewline 'press enter...'; [void](Read-Host) }"
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd -ErrorAction Stop
    } catch {
        Write-Host '[-] no admin get lost' -ForegroundColor Red
    }
    return
}

try {
    $Host.UI.RawUI.BackgroundColor = 'Black'
    $Host.UI.RawUI.ForegroundColor = 'Gray'
} catch {}

# helpers

function Report-Step {
    param([string]$Name, [string]$Type, [string]$Icon, [string]$Color)
    Write-Host "$Icon $Name $Type" -ForegroundColor $Color
}

function Show-Legend {
    Write-Host '[y] yes, do it'
    Write-Host '[n] no, skip it'
    Write-Host '[a] do it all (recommended)'
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action, [switch]$Critical, [switch]$NoPrompt)
    if (-not $script:RunAll -and -not $NoPrompt) {
        Write-Host -NoNewline "$Name [ Y / n / a ] "
        $answer = (Read-Host).Trim().ToLower()
        if ($answer -eq 'n') {
            Report-Step $Name 'skipped' '[*]' 'DarkGray'
            return
        }
        if ($answer -eq 'a') { $script:RunAll = $true }
    }
    try {
        & $Action
        Report-Step $Name 'done' '[+]' 'Green'
    } catch {
        Report-Step $Name "error: $($_.Exception.Message)" '[!]' 'Red'
        if ($Critical) { throw }
    }
}

function Pause-Here {
    Write-Host -NoNewline 'press enter...'
    [void](Read-Host)
}

function Remove-Tree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $Path)) { return }
    & takeown.exe /f $Path /r /d y *> $null
    & icacls.exe $Path /grant '*S-1-5-32-544:F' /t /c *> $null
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-RegRoot([string]$Path) {
    $index = $Path.IndexOf('\')
    if ($index -lt 1) { throw "bad registry path $Path" }
    switch ($Path.Substring(0, $index)) {
        'HKLM' { return [Microsoft.Win32.Registry]::LocalMachine }
        'HKCU' { return [Microsoft.Win32.Registry]::CurrentUser }
        'HKCR' { return [Microsoft.Win32.Registry]::ClassesRoot }
        default { throw "bad registry path $Path" }
    }
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value = 0, [string]$Type = 'DWord')
    $index = $Path.IndexOf('\')
    $root = Get-RegRoot $Path
    $sub = $Path.Substring($index + 1)
    try {
        $key = $root.CreateSubKey($sub, $true)
        if (-not $key) { throw 'key open failed' }
        try {
            if ($Name) {
                if ($Type -eq 'DWord') {
                    $key.SetValue($Name, [int]$Value, [Microsoft.Win32.RegistryValueKind]::DWord)
                } else {
                    $key.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::String)
                }
            } else {
                $key.SetValue('', [string]$Value, [Microsoft.Win32.RegistryValueKind]::String)
            }
        } finally {
            $key.Close()
        }
    } catch {
        Write-Host "[!] registry skip $Path" -ForegroundColor Yellow
    }
}

function Del-Reg {
    param([string]$Path, [string]$Name)
    $index = $Path.IndexOf('\')
    $root = Get-RegRoot $Path
    $sub = $Path.Substring($index + 1)
    try {
        if ($Name) {
            $key = $root.OpenSubKey($sub, $true)
            if ($key) {
                try { $key.DeleteValue($Name, $false) } finally { $key.Close() }
            }
        } else {
            $root.DeleteSubKeyTree($sub, $false)
        }
    } catch {
        Write-Host "[!] registry skip $Path" -ForegroundColor Yellow
    }
}

function Load-Hives {
    param([string]$Root, [switch]$User)
    $cfg = Join-Path $Root 'Windows\System32\config'
    & reg.exe load HKLM\zCOMPONENTS (Join-Path $cfg 'COMPONENTS') *> $null
    & reg.exe load HKLM\zDEFAULT (Join-Path $cfg 'default') *> $null
    & reg.exe load HKLM\zSOFTWARE (Join-Path $cfg 'SOFTWARE') *> $null
    & reg.exe load HKLM\zSYSTEM (Join-Path $cfg 'SYSTEM') *> $null
    if ($User) { & reg.exe load HKLM\zNTUSER (Join-Path $Root 'Users\Default\ntuser.dat') *> $null }
}

function Unload-Hives {
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    foreach ($hive in 'zCOMPONENTS', 'zDRIVERS', 'zDEFAULT', 'zNTUSER', 'zSCHEMA', 'zSOFTWARE', 'zSYSTEM') {
        & reg.exe unload "HKLM\$hive" *> $null
    }
    Start-Sleep -Milliseconds 300
    foreach ($hive in 'zCOMPONENTS', 'zDRIVERS', 'zDEFAULT', 'zNTUSER', 'zSCHEMA', 'zSOFTWARE', 'zSYSTEM') {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($hive, $false)
        if ($key) {
            $key.Close()
            & reg.exe unload "HKLM\$hive" *> $null
        }
    }
    $script:HivesReady = $false
}

function Get-Asset([string]$Name) {
    $cache = Join-Path $env:TEMP 'omni11'
    foreach ($path in @((Join-Path $cache $Name), (Join-Path $env:TEMP $Name))) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    $file = Join-Path $cache $Name
    New-Item -ItemType Directory $cache -Force | Out-Null
    Write-Host "[*] downloading $Name" -ForegroundColor Cyan
    Invoke-WebRequest "$($BaseUrl.TrimEnd('/'))/$Name" -OutFile $file -UseBasicParsing
    Unblock-File -LiteralPath $file -ErrorAction SilentlyContinue
    return $file
}

function Test-Oscdimg([string]$Path) {
    try {
        $out = & $Path -? 2>&1 | Out-String
        return $out -match 'OSCDIMG'
    } catch {
        return $false
    }
}

function Get-Oscdimg {
    $cache = Join-Path $env:TEMP 'omni11'
    $file = Join-Path $cache 'oscdimg.exe'
    $candidates = @()
    if ($PSScriptRoot) { $candidates += Join-Path $PSScriptRoot 'oscdimg.exe' }
    $candidates += Join-Path (Get-Location).Path 'oscdimg.exe'
    $candidates += $file
    $candidates += Join-Path $env:TEMP 'oscdimg.exe'
    foreach ($path in $candidates) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if (Test-Oscdimg $path) { return $path }
    }
    New-Item -ItemType Directory $cache -Force | Out-Null
    Write-Host '[*] downloading oscdimg.exe' -ForegroundColor Cyan
    Invoke-WebRequest "$($BaseUrl.TrimEnd('/'))/oscdimg.exe" -OutFile $file -UseBasicParsing
    Unblock-File -LiteralPath $file -ErrorAction SilentlyContinue
    if (-not (Test-Oscdimg $file)) {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        throw 'oscdimg invalid'
    }
    return $file
}

function Invoke-Dism {
    param([string[]]$Arguments, [switch]$AllowFail)
    & dism.exe /English @Arguments
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFail) { Write-Host "[!] dism warning $($Arguments[0])" -ForegroundColor Yellow }
        else { throw "dism failed $($Arguments[0])" }
    }
}

function Get-FreeGb([string]$Path) {
    $root = [IO.Path]::GetPathRoot($Path)
    if (-not $root -or $root.Length -lt 2 -or $root[1] -ne ':') { return -1 }
    $vol = Get-Volume -DriveLetter $root.Substring(0, 1) -ErrorAction SilentlyContinue
    if (-not $vol) { return -1 }
    return [math]::Round($vol.SizeRemaining / 1GB, 1)
}

function Get-WimIndices([string]$Wim) {
    $list = @()
    & dism.exe /English /Get-WimInfo "/WimFile:$Wim" 2> $null | ForEach-Object {
        if ($_ -match '^\s*Index\s*:\s*(\d+)') { $list += [int]$Matches[1] }
    }
    return $list
}

function Get-SetupIndex([string]$Wim) {
    $current = 0
    $setup = 0
    & dism.exe /English /Get-WimInfo "/WimFile:$Wim" 2> $null | ForEach-Object {
        if ($_ -match '^\s*Index\s*:\s*(\d+)') { $current = [int]$Matches[1] }
        if ($_ -match '^\s*Name\s*:\s*(.+)$') {
            if ($Matches[1] -match 'Setup') { $setup = $current }
        }
    }
    if ($setup -gt 0) { return $setup }
    return 2
}

function Mount-Iso([string]$Path) {
    $img = Get-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue
    if (-not $img -or -not $img.Attached) {
        $img = Mount-DiskImage -ImagePath $Path -PassThru -ErrorAction Stop
    }
    $drive = ''
    for ($i = 0; $i -lt 10; $i++) {
        $drive = ($img | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
        if ($drive) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $drive) { throw 'iso mount failed' }
    return "$drive`:"
}

function Get-MountedAppx {
    $list = @()
    & dism.exe /English "/image:$MountDir" /Get-ProvisionedAppxPackages 2> $null | ForEach-Object {
        if ($_ -match '^\s*PackageName\s*:\s*(.+?)\s*$') { $list += $Matches[1] }
    }
    return $list
}

function Remove-MountedAppx {
    param([string[]]$Packages, [string]$Filter)
    foreach ($pkg in $Packages) {
        if ($pkg -like "*$Filter*") {
            & dism.exe "/image:$MountDir" /Remove-ProvisionedAppxPackage "/PackageName:$pkg" *> $null
        }
    }
}

# shared tweaks

function Use-OfflineMode {
    $script:Offline = $true
    $script:HivesReady = $false
    $script:Reg = @{
        SOFTWARE = 'HKLM\zSOFTWARE\'
        SYSTEM   = 'HKLM\zSYSTEM\'
        NTUSER   = 'HKLM\zNTUSER\'
        DEFAULT  = 'HKLM\zDEFAULT\'
    }
}

function Use-OfflineReg {
    $script:Offline = $true
    $script:HivesReady = $true
    $script:Reg = @{
        SOFTWARE = 'HKLM\zSOFTWARE\'
        SYSTEM   = 'HKLM\zSYSTEM\'
        NTUSER   = 'HKLM\zNTUSER\'
        DEFAULT  = 'HKLM\zDEFAULT\'
    }
}

function Use-OnlineReg {
    $script:Offline = $false
    $script:HivesReady = $true
    $script:Reg = @{
        SOFTWARE = 'HKLM\SOFTWARE\'
        SYSTEM   = 'HKLM\SYSTEM\'
        NTUSER   = 'HKCU\'
        DEFAULT  = 'HKCU\'
    }
}

function Require-Hives {
    if ($script:Offline -and -not $script:HivesReady) { throw 'registry not loaded' }
}

function Set-Tweak {
    param([string]$Root, [string]$Path, [string]$Name, $Value = 0, [string]$Type = 'DWord')
    Require-Hives
    Set-Reg ($script:Reg[$Root] + $Path) $Name $Value $Type
}

function Del-Tweak {
    param([string]$Root, [string]$Path, [string]$Name)
    Require-Hives
    Del-Reg ($script:Reg[$Root] + $Path) $Name
}

function Set-Svc([string]$Name) {
    if ($script:Offline) {
        Require-Hives
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("zSYSTEM\ControlSet001\Services\$Name", $false)
        if ($key) {
            $key.Close()
            Set-Tweak SYSTEM "ControlSet001\Services\$Name" 'Start' 4
        }
    } else {
        Disable-Service $Name
    }
}

function Remove-OfflineTask([string]$Task) {
    $root = [Microsoft.Win32.Registry]::LocalMachine
    $tree = "zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\$Task"
    $id = $null
    try {
        $key = $root.OpenSubKey($tree, $false)
        if ($key) {
            $id = $key.GetValue('Id')
            $key.Close()
        }
    } catch {}
    if ($id) {
        try { $root.DeleteSubKeyTree("zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\$id", $false) } catch {}
    }
    try { $root.DeleteSubKeyTree($tree, $false) } catch {}
    $file = Join-Path $WorkDir "Windows\System32\Tasks\$Task"
    if (Test-Path -LiteralPath $file) {
        & takeown.exe /f $file *> $null
        & icacls.exe $file /grant '*S-1-5-32-544:F' /T /C *> $null
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}

function Set-TaskOff([string]$Name) {
    if ($script:Offline) {
        Require-Hives
        Remove-OfflineTask $Name
    } else {
        Disable-Task $Name
    }
}

function Invoke-PrivacyExtras {
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry' 0
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\DataCollection' 'LimitEnhancedDiagnosticData' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\DataCollection' 'LimitDumpCollection' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\DataCollection' 'LimitDiagnosticLogCollection' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
    Set-Tweak SOFTWARE 'Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    Set-Tweak SOFTWARE 'Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'MaxTelemetryAllowed' 0
    Set-Tweak SOFTWARE 'WOW6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform' 'NoGenTicket' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\AppCompat' 'AllowTelemetry' 0
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\AppCompat' 'DisablePCA' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    Set-Tweak SOFTWARE 'Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack' 'UploadEnabled' 0
    Set-Tweak SOFTWARE 'Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack' 'DiagTrackAuthorization' 0
    Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Tweak NTUSER 'Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
    Set-Tweak NTUSER 'Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
    Set-Tweak NTUSER 'Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
    Set-Tweak NTUSER 'Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
    Set-Tweak NTUSER 'Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
    Set-Tweak NTUSER 'Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
    Set-Tweak NTUSER 'Software\Microsoft\Input\TIPC' 'Enabled' 0
    Set-Tweak NTUSER 'Software\Microsoft\Clipboard' 'EnableCloudClipboard' 0
    Set-Tweak NTUSER 'Software\Microsoft\Clipboard' 'CloudClipboardAutomaticUpload' 0
    Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0
    Set-Tweak SYSTEM 'ControlSet001\Control\WMI\Autologger\Diagtrack-Listener' 'Start' 0
}

function Invoke-UiExtras {
    foreach ($name in 'ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SubscribedContent-314563Enabled', 'SystemPaneSuggestionsEnabled', 'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled') {
        Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $name 0
    }
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
    Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
}

function Invoke-AiExtras {
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-Tweak NTUSER 'Software\Policies\Microsoft\Notepad' 'PreventRewrite' 1
    Set-Tweak NTUSER 'Software\Policies\Microsoft\Paint' 'PreventCocreator' 1
}

function Invoke-DevicePerf {
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
    Set-Tweak SYSTEM 'ControlSet001\Control\Session Manager' 'DisableWpbtExecution' 1
}

function Invoke-GameDvr {
    Set-Tweak NTUSER 'System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Tweak NTUSER 'System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
    Set-Tweak SOFTWARE 'Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Set-Tweak NTUSER 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 0
}

function Invoke-StickyKeys {
    Set-Tweak NTUSER 'Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
    Set-Tweak NTUSER 'Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'
    Set-Tweak NTUSER 'Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String'
}

function Invoke-ServicesList {
    foreach ($name in 'DiagTrack', 'dmwappushservice', 'MapsBroker', 'srumsvc', 'CDPUserSvc', 'edgeupdate', 'edgeupdatem', 'MicrosoftEdgeElevationService') {
        Set-Svc $name
    }
}

function Invoke-TasksList {
    foreach ($task in 'Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser', 'Microsoft\Windows\Application Experience\ProgramDataUpdater', 'Microsoft\Windows\Application Experience\StartupAppTask', 'Microsoft\Windows\Autochk\Proxy', 'Microsoft\Windows\CloudExperienceHost\CreateObjectTask', 'Microsoft\Windows\Customer Experience Improvement Program\Consolidator', 'Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask', 'Microsoft\Windows\Customer Experience Improvement Program\UsbCeip', 'Microsoft\Windows\Device Information\Device', 'Microsoft\Windows\Device Information\Device User', 'Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector', 'Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver', 'Microsoft\Windows\Feedback\Siuf\DmClient', 'Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload', 'Microsoft\Windows\Maintenance\WinSAT', 'Microsoft\Windows\NetTrace\GatherNetworkInfo', 'Microsoft\Windows\PI\Sqm-Tasks', 'Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem', 'Microsoft\Windows\Maps\MapsToastTask', 'Microsoft\Windows\Maps\MapsUpdateTask', 'Microsoft\Windows\Windows Media Sharing\UpdateLibrary', 'Microsoft\Windows\Flighting\OneSettings\RefreshCache', 'Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing', 'Microsoft\Windows\DiskFootprint\Diagnostics', 'Microsoft\Windows\Speech\SpeechModelDownloadTask', 'Microsoft\Windows\Windows Error Reporting\QueueReporting', 'MicrosoftEdgeUpdateTaskMachineCore', 'MicrosoftEdgeUpdateTaskMachineUA') {
        Set-TaskOff $task
    }
}

function Get-FeatureNames {
    $target = if ($script:Offline) { "/Image:$MountDir" } else { '/Online' }
    $list = @()
    & dism.exe /English $target /Get-Features 2> $null | ForEach-Object {
        if ($_ -match '^\s*Feature Name\s*:\s*(.+?)\s*$') { $list += $Matches[1] }
    }
    return $list
}

function Invoke-LegacyFeatures {
    $target = if ($script:Offline) { "/image:$MountDir" } else { '/online' }
    $available = @(Get-FeatureNames)
    foreach ($feature in 'WindowsMediaPlayer', 'Recall', 'FaxService', 'WorkFolders-Client') {
        if ($feature -notin $available) { continue }
        Invoke-Dism @($target, '/Quiet', '/Disable-Feature', "/FeatureName:$feature", '/Remove', '/NoRestart') -AllowFail
    }
}

function Invoke-LegacyFeatures2 {
    $target = if ($script:Offline) { "/image:$MountDir" } else { '/online' }
    $available = @(Get-FeatureNames)
    foreach ($feature in 'StepsRecorder', 'Microsoft-Windows-WordPad-FoD') {
        if ($feature -notin $available) { continue }
        Invoke-Dism @($target, '/Quiet', '/Disable-Feature', "/FeatureName:$feature", '/Remove', '/NoRestart') -AllowFail
    }
}

function Invoke-PowerShellTelemetry {
    if ($script:Offline) {
        Set-Tweak SYSTEM 'ControlSet001\Control\Session Manager\Environment' 'POWERSHELL_TELEMETRY_OPTOUT' '1' 'String'
    } else {
        [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
    }
}

function Invoke-ComponentCleanup {
    $target = if ($script:Offline) { "/image:$MountDir" } else { '/online' }
    & dism.exe /English /Quiet $target /Cleanup-Image /StartComponentCleanup /ResetBase *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host '[*] cleanup skipped' -ForegroundColor Yellow }
}

function Invoke-InboxApps {
    $root = if ($script:Offline) { Join-Path $WorkDir 'Windows\InboxApps' } else { Join-Path $env:SystemRoot 'InboxApps' }
    if (-not $script:Offline) {
        Get-Process '*Widget*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    foreach ($name in 'Microsoft.Copilot', 'Microsoft.BingSearch', 'Microsoft.StartExperiencesApp', 'Microsoft.WidgetsPlatformRuntime') {
        Get-ChildItem -Path $root -Filter "$name*" -File -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $script:Offline) {
                & takeown.exe /f $_.FullName *> $null
                & icacls.exe $_.FullName /grant '*S-1-5-32-544:F' /C *> $null
            }
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-Shortcuts {
    if ($script:Offline) {
        $roots = @(
            (Join-Path $WorkDir 'ProgramData\Microsoft\Windows\Start Menu\Programs'),
            (Join-Path $WorkDir 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs'),
            (Join-Path $WorkDir 'Users\Public\Desktop')
        )
    } else {
        $roots = @(
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
            "$env:AppData\Microsoft\Windows\Start Menu\Programs",
            "$env:Public\Desktop"
        )
    }
    $patterns = @('*Solitaire*.lnk', '*Outlook*.lnk', '*LinkedIn*.lnk', '*Teams*.lnk', '*Bing*.lnk', '*Clipchamp*.lnk', '*Dev Home*.lnk', '*OneDrive*.lnk', 'Microsoft Edge.lnk')
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($pattern in $patterns) {
            Get-ChildItem -Path $root -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Invoke-EdgeRemove {
    Get-Process msedge, MicrosoftEdgeUpdate -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $setup = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($setup) {
        Start-Process -FilePath $setup.FullName -ArgumentList '--uninstall', '--system-level', '--force-uninstall', '--delete-profile' -Wait -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath "${env:ProgramFiles(x86)}\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$env:Public\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$env:AppData\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$env:LocalAppData\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$env:LocalAppData\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$env:SystemRoot\SystemApps" -Filter 'Microsoft.MicrosoftEdge*' -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-OneDriveRemove {
    Get-Process OneDrive, FileCoAuth, OneDriveStandaloneUpdater -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($setup in @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")) {
        if (Test-Path -LiteralPath $setup) {
            Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath "$env:LocalAppData\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$env:ProgramData\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
}

# iso patcher

function Invoke-IsoPatch {
    $Host.UI.RawUI.WindowTitle = '[iso] omni11'

    $free = Get-FreeGb $WorkDir
    if ($free -ge 0 -and $free -lt $MinFreeGb) {
        Report-Step 'free space' "error: need $MinFreeGb gb, have $free gb" '[!]' 'Red'
        return
    }
    if ($free -ge 0) { Write-Host "[*] free space $free gb" -ForegroundColor Cyan }

    Use-OfflineMode

    $S = @{ Iso = ''; Out = ''; Drive = ''; Install = ''; Index = ''; Hives = $false }

    Invoke-Step 'locate iso' {
        while (-not $S.Iso) {
            Write-Host -NoNewline 'path to .iso > '
            $raw = (Read-Host).Trim().Trim('"')
            if ($raw -and (Test-Path -LiteralPath $raw)) {
                $S.Iso = (Resolve-Path -LiteralPath $raw).Path
            } elseif ($raw -and (Test-Path -LiteralPath (Join-Path (Get-Location).Path $raw))) {
                $S.Iso = (Resolve-Path -LiteralPath (Join-Path (Get-Location).Path $raw)).Path
            } else {
                Write-Host '[-] iso not found' -ForegroundColor Red
            }
        }
        $S.Out = Join-Path (Split-Path $S.Iso) "$([IO.Path]::GetFileNameWithoutExtension($S.Iso))-omni11.iso"
    } -Critical -NoPrompt

    $script:RunAll = $false
    Show-Legend

    try {
        Invoke-Step 'mount iso' {
            $S.Drive = Mount-Iso $S.Iso
        } -Critical

        Invoke-Step 'check image' {
            if (-not (Test-Path -LiteralPath "$($S.Drive)\sources\boot.wim")) { throw 'boot.wim not found' }
            if (Get-ChildItem -Path "$($S.Drive)\sources" -Filter 'install*.swm' -File -ErrorAction SilentlyContinue) { throw 'split wim not supported' }
            $S.Install = 'install.wim'
            if (-not (Test-Path -LiteralPath "$($S.Drive)\sources\install.wim")) {
                if (Test-Path -LiteralPath "$($S.Drive)\sources\install.esd") { $S.Install = 'install.esd' }
                else { throw 'install image not found' }
            }
        } -Critical

        Invoke-Step 'copy image' {
            if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
            New-Item -ItemType Directory $WorkDir -Force | Out-Null
            & robocopy.exe "$($S.Drive)\" $WorkDir /e /copy:dt /dcopy:t /r:1 /w:1 /J /nfl /ndl /njh /njs *> $null
            if ($LASTEXITCODE -ge 8) { throw 'copy failed' }
            foreach ($file in 'install.wim', 'install.esd', 'boot.wim') {
                $path = Join-Path $WorkDir "sources\$file"
                if (Test-Path -LiteralPath $path) {
                    $item = Get-Item -LiteralPath $path -Force
                    $item.IsReadOnly = $false
                }
            }
        } -Critical

        Invoke-Step 'patch appraiserres' {
            $appraiser = Join-Path $WorkDir 'sources\appraiserres.dll'
            if (Test-Path -LiteralPath $appraiser) {
                Remove-Item -LiteralPath $appraiser -Force
                New-Item -ItemType File $appraiser | Out-Null
            }
        }

        Invoke-Step 'read image info' {
            Invoke-Dism @('/Get-WimInfo', "/WimFile:$WorkDir\sources\$($S.Install)")
            $valid = @(Get-WimIndices "$WorkDir\sources\$($S.Install)")
            while ($true) {
                Write-Host -NoNewline 'image index > '
                $S.Index = Read-Host
                if ($S.Index -notmatch '^\d+$') { Write-Host '[-] bad index' -ForegroundColor Red; continue }
                if ($valid.Count -gt 0 -and [int]$S.Index -notin $valid) { Write-Host '[-] no such index' -ForegroundColor Red; continue }
                break
            }
        } -Critical

        Invoke-Step 'mount image' {
            if (Test-Path -LiteralPath $MountDir) { Remove-Item -LiteralPath $MountDir -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory $MountDir -Force | Out-Null
            Invoke-Dism @('/Mount-Image', "/ImageFile:$WorkDir\sources\$($S.Install)", "/Index:$($S.Index)", "/MountDir:$MountDir")
        } -Critical

        Invoke-Step 'remove bloatware' {
            $packages = Get-MountedAppx
            foreach ($name in $Bloat) { Remove-MountedAppx -Packages $packages -Filter $name }
        }

        Invoke-Step 'remove inbox apps' {
            Invoke-InboxApps
        }

        Invoke-Step 'remove edge' {
            Remove-Item -LiteralPath "$MountDir\Program Files (x86)\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$MountDir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$MountDir\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$MountDir\Users\Public\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path "$MountDir\Windows\SystemApps" -Filter 'Microsoft.MicrosoftEdge*' -Directory -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        Invoke-Step 'clean image' {
            Unload-Hives
            $S.Hives = $false
            Invoke-ComponentCleanup
        }

        Invoke-Step 'remove legacy features' {
            Invoke-LegacyFeatures
        }

        Invoke-Step 'remove legacy features 2' {
            Invoke-LegacyFeatures2
        }

        Invoke-Step 'remove onedrive' {
            foreach ($file in @("$MountDir\Windows\System32\OneDriveSetup.exe", "$MountDir\Windows\SysWOW64\OneDriveSetup.exe")) {
                if (Test-Path -LiteralPath $file) {
                    & takeown.exe /f $file *> $null
                    & icacls.exe $file /grant '*S-1-5-32-544:F' /T /C *> $null
                    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                }
            }
            Remove-Item -LiteralPath "$MountDir\Program Files\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$MountDir\Program Files (x86)\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$MountDir\Windows\System32\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path "$MountDir\Windows\SystemApps" -Filter 'Microsoft.OneDrive*' -Directory -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$MountDir\Windows\System32\OneDrive*" -Recurse -Force -ErrorAction SilentlyContinue
        }

        Invoke-Step 'load registry' {
            Load-Hives $MountDir -User
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('zSOFTWARE', $false)
            if (-not $key) { throw 'hive load failed' }
            $key.Close()
            Use-OfflineReg
            $S.Hives = $true
        } -Critical

        Invoke-Step 'system requirements' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 0
            Set-Reg 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 0
            Set-Reg 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 0
            Set-Reg 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 0
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 1
        }

        Invoke-Step 'reserved storage' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 0
        }

        Invoke-Step 'teams and sponsored apps' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 0
            Set-Reg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0
            Set-Reg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 0
            Set-Reg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
            Set-Reg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 0
            Set-Reg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 0
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
        }

        Invoke-Step 'classic context menu' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zNTUSER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' ''
            Set-Reg 'HKLM\zNTUSER\Software\Classes\CLSID\{d93ed569-3b3e-4bff-8355-3c44f6a52bb5}\InprocServer32' '' ''
        }

        Invoke-Step 'oobe local accounts' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 1
            Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'HideOnlineAccountScreens' 1
            Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'HideOnlineAccountScreen' 1
            Set-Reg 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 1
        }

        Invoke-Step 'chat icon' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 3
            Set-Reg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
        }

        Invoke-Step 'onedrive tweaks' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSync' 1
            Set-Reg 'HKLM\zSOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
            Set-Reg 'HKLM\zSOFTWARE\Classes\CLSID\{04271989-C4D2-4048-A533-DE43BE352125}' 'System.IsPinnedToNameSpaceTree' 0
            Set-Reg 'HKLM\zSOFTWARE\Classes\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
            Set-Reg 'HKLM\zSOFTWARE\Classes\WOW6432Node\CLSID\{04271989-C4D2-4048-A533-DE43BE352125}' 'System.IsPinnedToNameSpaceTree' 0
            Del-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
            Del-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup'
            Del-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDrive'
        }

        Invoke-Step 'edge reinstall block' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zSOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1
            Set-Reg 'HKLM\zSYSTEM\ControlSet001\Services\edgeupdate' 'Start' 4
            Set-Reg 'HKLM\zSYSTEM\ControlSet001\Services\edgeupdatem' 'Start' 4
            Set-Reg 'HKLM\zSYSTEM\ControlSet001\Services\MicrosoftEdgeElevationService' 'Start' 4
        }

        Invoke-Step 'telemetry' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
            Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'MaxTelemetryAllowed' 0
            Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
            Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack' 'UploadEnabled' 0
            Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack' 'DiagTrackAuthorization' 0
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
        }

        Invoke-Step 'copilot and recall' {
            if (-not $S.Hives) { throw 'registry not loaded' }
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
            Set-Reg 'HKLM\zNTUSER\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
        }

        Invoke-Step 'privacy extras' {
            Invoke-PrivacyExtras
        }

        Invoke-Step 'powershell telemetry' {
            Invoke-PowerShellTelemetry
        }

        Invoke-Step 'ads and suggestions' {
            Invoke-UiExtras
        }

        Invoke-Step 'ai extras' {
            Invoke-AiExtras
        }

        Invoke-Step 'delivery and device' {
            Invoke-DevicePerf
        }

        Invoke-Step 'game dvr' {
            Invoke-GameDvr
        }

        Invoke-Step 'sticky keys' {
            Invoke-StickyKeys
        }

        Invoke-Step 'services' {
            Invoke-ServicesList
        }

        Invoke-Step 'telemetry tasks' {
            Invoke-TasksList
        }

        Invoke-Step 'clean shortcuts' {
            Invoke-Shortcuts
        }

        Invoke-Step 'unmount image' {
            Unload-Hives
            $S.Hives = $false
            Invoke-Dism @('/Unmount-Image', "/MountDir:$MountDir", '/Commit')
        } -Critical

        Invoke-Step 'export image' {
            $source = "$WorkDir\sources\$($S.Install)"
            $exported = "$WorkDir\sources\install2.wim"
            Invoke-Dism @('/Export-Image', "/SourceImageFile:$source", "/SourceIndex:$($S.Index)", "/DestinationImageFile:$exported", '/Compress:max')
            Remove-Item -LiteralPath $source -Force
            Move-Item -LiteralPath $exported -Destination "$WorkDir\sources\install.wim" -Force
        } -Critical

        Invoke-Step 'mount boot image' {
            $bootIndex = Get-SetupIndex "$WorkDir\sources\boot.wim"
            Write-Host "[*] boot index $bootIndex" -ForegroundColor Cyan
            Invoke-Dism @('/Mount-Image', "/ImageFile:$WorkDir\sources\boot.wim", "/Index:$bootIndex", "/MountDir:$MountDir")
        } -Critical

        Invoke-Step 'boot requirements' {
            Load-Hives $MountDir
            Set-Reg 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 0
            Set-Reg 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 0
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 1
            Set-Reg 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 1
            Unload-Hives
        }

        Invoke-Step 'unmount boot image' {
            Unload-Hives
            Invoke-Dism @('/Unmount-Image', "/MountDir:$MountDir", '/Commit')
        } -Critical

        Invoke-Step 'copy autounattend' {
            $answer = Get-Asset 'autounattend.xml'
            if (-not $answer) { throw 'autounattend.xml not found' }
            Copy-Item -LiteralPath $answer -Destination "$WorkDir\autounattend.xml" -Force
        }

        Invoke-Step 'create iso' {
            $oscdimg = Get-Oscdimg
            & $oscdimg -m -o -u2 -udfver102 "-bootdata:2#p0,e,b$WorkDir\boot\etfsboot.com#pEF,e,b$WorkDir\efi\microsoft\boot\efisys.bin" $WorkDir $S.Out
            if ($LASTEXITCODE -ne 0) { throw 'oscdimg failed' }
        }
    } catch {
        Write-Host '[-] aborted' -ForegroundColor Red
    } finally {
        Write-Host '[*] cleaning up' -ForegroundColor Cyan
        Unload-Hives
        & dism.exe /English /Cleanup-Wim *> $null
        if (Test-Path -LiteralPath $MountDir) {
            & dism.exe /English /Unmount-Image "/MountDir:$MountDir" /Discard *> $null
        }
        Start-Sleep -Milliseconds 500
        Remove-Tree $WorkDir
        Remove-Tree $MountDir
        if ($S.Iso) { Dismount-DiskImage -ImagePath $S.Iso -ErrorAction SilentlyContinue | Out-Null }
    }

    Write-Host 'do postsetup after installation'
}

# post setup tweaks

function Disable-Service([string]$Name) {
    & sc.exe config $Name start= disabled *> $null
    & sc.exe stop $Name *> $null
}

function Disable-Task([string]$Name) {
    & schtasks.exe /change /tn $Name /disable *> $null
}

function Remove-OnlineAppx([string[]]$Names) {
    foreach ($name in $Names) {
        $pattern = "*$name*"
        Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like $pattern -or $_.DisplayName -like $pattern } |
            Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }
}

function Invoke-PostSetup {
    $Host.UI.RawUI.WindowTitle = '[post] omni11'
    Use-OnlineReg

    $script:RunAll = $false
    Show-Legend

    Invoke-Step 'disable telemetry' {
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'MaxTelemetryAllowed' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitEnhancedDiagnosticData' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDumpCollection' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDiagnosticLogCollection' 1
        Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\Diagtrack-Listener' 'Start' 0
    }

    Invoke-Step 'defender samples' {
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue
        }
    }

    Invoke-Step 'disable bloat and sponsored' {
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-314563Enabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
    }

    Invoke-Step 'stop bloatware processes' {
        foreach ($proc in 'olk.exe', 'Solitaire.exe', 'SolitaireCollection.exe', 'LinkedIn.exe') {
            & taskkill.exe /f /im $proc *> $null
        }
    }

    Invoke-Step 'remove bloatware apps' {
        Remove-OnlineAppx -Names $Bloat
    }

    Invoke-Step 'clean bloatware shortcuts' {
        Invoke-Shortcuts
    }

    Invoke-Step 'remove inbox apps' {
        Invoke-InboxApps
    }

    Invoke-Step 'remove edge' {
        Invoke-EdgeRemove
    }

    Invoke-Step 'remove onedrive' {
        Invoke-OneDriveRemove
    }

    Invoke-Step 'clean components' {
        Invoke-ComponentCleanup
    }

    Invoke-Step 'remove legacy features' {
        Invoke-LegacyFeatures
    }

    Invoke-Step 'remove legacy features 2' {
        Invoke-LegacyFeatures2
    }

    Invoke-Step 'disable bing search' {
        Set-Reg 'HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
    }

    Invoke-Step 'disable ai features' {
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Set-Reg 'HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
        Set-Reg 'HKCU\Software\Policies\Microsoft\Notepad' 'PreventRewrite' 1
        Set-Reg 'HKCU\Software\Policies\Microsoft\Paint' 'PreventCocreator' 1
    }

    Invoke-Step 'privacy extras' {
        Invoke-PrivacyExtras
    }

    Invoke-Step 'powershell telemetry' {
        Invoke-PowerShellTelemetry
    }

    Invoke-Step 'ads and suggestions' {
        Invoke-UiExtras
    }

    Invoke-Step 'delivery and device' {
        Invoke-DevicePerf
    }

    Invoke-Step 'disable bloat autostart' {
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 3
        Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
    }

    Invoke-Step 'clean onedrive' {
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSync' 1
        Set-Reg 'HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
        Set-Reg 'HKCR\CLSID\{04271989-C4D2-4048-A533-DE43BE352125}' 'System.IsPinnedToNameSpaceTree' 0
        Set-Reg 'HKCR\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
        Set-Reg 'HKCR\WOW6432Node\CLSID\{04271989-C4D2-4048-A533-DE43BE352125}' 'System.IsPinnedToNameSpaceTree' 0
        Del-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
        Del-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup'
        Del-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDrive'
    }

    Invoke-Step 'block edge reinstall' {
        Set-Reg 'HKLM\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1
        Disable-Service 'edgeupdate'
        Disable-Service 'edgeupdatem'
        Disable-Service 'MicrosoftEdgeElevationService'
        Remove-Item -LiteralPath "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$env:Public\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
    }

    Invoke-Step 'disable hardware notifications' {
        Set-Reg 'HKCU\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 0
        Set-Reg 'HKCU\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 0
        Set-Reg 'HKLM\SYSTEM\Setup\LabConfig' 'BypassCPUCheck' 1
        Set-Reg 'HKLM\SYSTEM\Setup\LabConfig' 'BypassRAMCheck' 1
        Set-Reg 'HKLM\SYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 1
        Set-Reg 'HKLM\SYSTEM\Setup\LabConfig' 'BypassStorageCheck' 1
        Set-Reg 'HKLM\SYSTEM\Setup\LabConfig' 'BypassTPMCheck' 1
        Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 0
    }

    Invoke-Step 'reserved storage' {
        Invoke-Dism @('/online', '/Quiet', '/Set-ReservedStorageState', '/State:Disabled') -AllowFail
    }

    Invoke-Step 'disable tracking' {
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' 'PreventHandwritingErrorReports' 1
        Set-Reg 'HKCU\Software\Microsoft\Input\TIPC' 'Enabled' 0
        Set-Reg 'HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\System' 'AllowExperimentation' 0
    }

    Invoke-Step 'services' {
        Invoke-ServicesList
    }

    Invoke-Step 'telemetry tasks' {
        Invoke-TasksList
    }

    Invoke-Step 'restore classic context menu' {
        Set-Reg 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' ''
        Set-Reg 'HKCU\Software\Classes\CLSID\{d93ed569-3b3e-4bff-8355-3c44f6a52bb5}\InprocServer32' '' ''
    }

    Invoke-Step 'disable game dvr' {
        Invoke-GameDvr
    }

    Invoke-Step 'disable update auto reboot' {
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
    }

    Invoke-Step 'disable sticky keys popup' {
        Invoke-StickyKeys
    }

    Invoke-Step 'restart explorer' {
        & taskkill.exe /f /im explorer.exe *> $null
        Start-Process explorer.exe
    }

    Write-Host 'have a good day :3'
}

# main

:menu while ($true) {
    Clear-Host
    $Host.UI.RawUI.WindowTitle = '[menu] omni11'
    Write-Host '[omni11] no harm'
    Write-Host '[1] postsetup tweaks'
    Write-Host '[2] patch .iso'
    Write-Host '[0] exit'
    Write-Host '> ' -NoNewline

    $choice = (Read-Host).Trim().ToLower()
    if ($choice -eq '1') { Invoke-PostSetup; Pause-Here }
    if ($choice -eq '2') { Invoke-IsoPatch; Pause-Here }
    if ($choice -eq '0') { Clear-Host; break menu }
}
