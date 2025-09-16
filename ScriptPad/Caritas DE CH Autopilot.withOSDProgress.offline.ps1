<#
.SYNOPSIS
    OSDCloud Logic for PreOS, OS and PostOS Tasks
.DESCRIPTION
    This script is used to perform PreOS, OS and PostOS tasks for OSDCloud.
    It includes the following tasks:
    - Update OSD PowerShell Module
    - Import OSD PowerShell Module
    - Install and configure firmware updates
    - Define Autopilot attributes
    - Setup Unattend.xml for specialize phase
    - Execute OOBE and cleanup scripts
    - Move OSDCloud logs to IntuneManagementExtension
    - Restart the system if not in development mode

.NOTES
    Version:		0.1
    Creation Date:  16.09.2025
    Author:			Jorga Wetzel
    Company:        oneICT AG
    Contact:		wetzel@oneict.ch

    Copyright (c) 2025 oneICT AG

HISTORY:
Date			By				Comments
----------		---				----------------------------------------------------------
16.09.2025		Jorga Wetzel	Script created

#>

$ScriptName = 'Caritas.ps1'
$ScriptVersion = '16.09.2025'
Write-Host -ForegroundColor Green "$ScriptName $ScriptVersion"

if (-NOT (Test-Path 'X:\OSDCloud\Logs')) {
    New-Item -Path 'X:\OSDCloud\Logs' -ItemType Directory -Force -ErrorAction Stop | Out-Null
}

#Transport Layer Security (TLS) 1.2
Write-Host -ForegroundColor Green "Transport Layer Security (TLS) 1.2"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
#[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

$Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Start-OSDCloudLogic.log"
Start-Transcript -Path (Join-Path "X:\OSDCloud\Logs" $Transcript) -ErrorAction Ignore | Out-Null

#================================================
Write-Host -ForegroundColor DarkGray "========================================================================="
Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) " -NoNewline
Write-Host -ForegroundColor Cyan "[PreOS] Update Module"
#================================================
# Write-Host -ForegroundColor Green "Updating OSD PowerShell Module"
# Install-Module OSD -Force

Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) " -NoNewline
Write-Host -ForegroundColor Green "Importing OSD PowerShell Module"

# --- Hardened OSD module import to avoid hangs in WinPE/PSGallery ---
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))  [PreOS] Ensure NuGet provider / PSGallery trust"
try {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
    if (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue) {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
} catch { Write-Host -ForegroundColor Yellow "NuGet/PSGallery bootstrap warning: $($_.Exception.Message)" }

Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))  [PreOS] Import OSD module"
$osdLoaded = $false
try {
    if (-not (Get-Module -ListAvailable -Name OSD)) {
        Install-Module OSD -Force -Scope AllUsers -AllowClobber -ErrorAction Stop
    }
    Import-Module OSD -Force -ErrorAction Stop
    $osdLoaded = $true
    Write-Host -ForegroundColor Green "[+] OSD $((Get-Module OSD).Version) loaded"
} catch {
    Write-Host -ForegroundColor Yellow "OSD from PSGallery failed: $($_.Exception.Message)"
    # Fallback: bootstrap OSD via functions.osdcloud.com
    try {
        Write-Host -ForegroundColor DarkGray "Fallback: iex (irm functions.osdcloud.com)"
        iex (irm functions.osdcloud.com)
        Import-Module OSD -Force -ErrorAction Stop
        $osdLoaded = $true
        Write-Host -ForegroundColor Green "[+] OSD (bootstrap) loaded"
    } catch {
        Write-Host -ForegroundColor Red "[-] OSD could not be loaded."
    }
}
$ErrorActionPreference = 'Continue'
# -------------------------------------------------------------------
Import-Module OSD -Force

# ================= OSDProgress Start (Caritas) =================
# Ordner sicher erstellen
# --- Robust OSDProgress Loader for WinPE/OSD ---

# 1) TLS 1.2 sicherstellen
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 2) Uhrzeit grob korrigieren (best effort), damit Code-Signaturen nicht scheitern
try {
    $t = (Invoke-RestMethod -Uri 'https://worldtimeapi.org/api/ip' -TimeoutSec 5).utc_datetime
    if ($t) { Set-Date (Get-Date $t) -ErrorAction SilentlyContinue }
} catch {}

# 3) Execution Policy nur fuer diese Session lockern
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch {}

# 4) PSGallery vertrauen & NuGet-Provider sicherstellen
try {
    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Name PSGallery -InstallationPolicy Trusted `
            -SourceLocation 'https://www.powershellgallery.com/api/v2' `
            -ScriptSourceLocation 'https://www.powershellgallery.com/api/v2' `
            -PackageManagementProvider NuGet
    } else {
        Set-PSRepository PSGallery -InstallationPolicy Trusted
    }
} catch {}

# 5) OSDProgress installieren (mit Fallback)
$OSDProgLoaded = $false
try {
    Install-Module OSDProgress -Force -Scope AllUsers -AllowClobber -SkipPublisherCheck -ErrorAction Stop
    Import-Module  OSDProgress -Force -ErrorAction Stop
    $OSDProgLoaded = $true
} catch {
    Write-Host "Install-Module OSDProgress scheitert: $($_.Exception.Message)" -ForegroundColor Yellow
    # Fallback: Portable-Import direkt aus GitHub (ohne Katalogprüfung)
    try {
        $tmp = Join-Path $env:TEMP 'OSDProgress.Portable'
        New-Item $tmp -ItemType Directory -Force | Out-Null
        Invoke-WebRequest 'https://raw.githubusercontent.com/OSDeploy/OSDProgress/main/OSDProgress.psd1' -OutFile (Join-Path $tmp 'OSDProgress.psd1') -UseBasicParsing
        Invoke-WebRequest 'https://raw.githubusercontent.com/OSDeploy/OSDProgress/main/OSDProgress.psm1' -OutFile (Join-Path $tmp 'OSDProgress.psm1') -UseBasicParsing
        Import-Module (Join-Path $tmp 'OSDProgress.psd1') -Force
        $OSDProgLoaded = $true
        Write-Host "OSDProgress via Portable-Import geladen." -ForegroundColor Green
    } catch {
        Write-Host "Auch Portable-Import fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 6) Nur wenn geladen, dein Progress starten
if ($OSDProgLoaded) {
    $Template = 'C:\Service\OSDCaritas\Config\Caritas.OSDProgress.psd1'
    if (Test-Path $Template) {
        Invoke-OSDProgress -Style Win10 -TemplateFile $Template

# --- Phase compatibility wrapper (handles different OSDProgress versions) ---
$__upd = Get-Command Update-OSDProgress -ErrorAction SilentlyContinue
function Set-PhaseCompat {
    param([string]$text, [int]$stepInt = 1)
    if ($__upd -and $__upd.Parameters.ContainsKey('Phase')) {
        $phaseName = "Phase$stepInt"
        try { Update-OSDProgress -Phase $phaseName -DisplayBar -Text $text; return } catch {}
        $map = @{ 1='PreOS'; 2='OS'; 3='PostOS' }
        if ($map.ContainsKey($stepInt)) { try { Update-OSDProgress -Phase $map[$stepInt] -DisplayBar -Text $text; return } catch {} }
        try { Update-OSDProgress -DisplayBar -Text $text; return } catch {}
    } elseif ($__upd -and $__upd.Parameters.ContainsKey('Step')) {
        try { Update-OSDProgress -Step $stepInt -DisplayBar -Text $text; return } catch {}
    }
    try { Update-OSDProgress -DisplayBar -Text $text } catch {}
}
# ---------------------------------------------------------------------------
    } else {
        Invoke-OSDProgress -Style Win10
    }
    Set-PhaseCompat -stepInt 1 -text 'Vorbereitung...'
} else {
    Write-Host "OSDProgress steht nicht zur Verfuegung – fahre ohne Overlay fort." -ForegroundColor Yellow
}


# --- Caritas Assets (OFFLINE, no web) ---------------------------------
New-Item 'C:\Service\OSDCaritas\Config' -ItemType Directory -Force | Out-Null
$TemplatePath = 'C:\Service\OSDCaritas\Config\Caritas.OSDProgress.psd1'

if (-not (Test-Path $TemplatePath)) {
    @'
@{
    Title = 'Caritas Deployment'
    Subtitle = 'OSDCloud · oneICT'
    AccentColor = '#FFFFFF'
    TextColor = '#FFFFFF'
    BackgroundHex = '#1F4C7F'
    LogoPath = 'C:\Service\OSDCaritas\Config\Caritas_Schweiz_Logo_weiss.png'
    LogoWidth = 420
    LogoOpacity = 1.0
    LogoAlignment = 'Center'
    LogoMargin = '0,0,0,20'
    Phase1Text = 'Vorbereitung'
    Phase2Text = 'Windows wird installiert'
    Phase3Text = 'Nachbereitung'
    DefaultText = 'Starte Deployment...'
    IconPhase1 = 'MaterialTools'
    IconPhase2 = 'MaterialCloudDownloadOutline'
    IconPhase3 = 'MaterialCogOutline'
    ShowBar = $true
    Indeterminate = $false
    ShowUnlock = $true
    UnlockHint = 'unlock'
}
'@ | Set-Content -Path $TemplatePath -Encoding UTF8 -Force
    Write-Host -ForegroundColor Green "[+] Offline-Template geschrieben: $TemplatePath"
} else {
    Write-Host -ForegroundColor Green "[=] Template vorhanden: $TemplatePath"
}

# Hinweis: Logo optional. Wenn 'C:\Service\OSDCaritas\Config\Caritas_Schweiz_Logo_weiss.png' fehlt,
# zeigt OSDProgress einfach kein Logo an. Kein Netz-Zugriff hier.
# ----------------------------------------------------------------------



try {
    $TemplatePath = 'C:\Service\OSDCaritas\Config\Caritas.OSDProgress.psd1'
    if (-not (Get-Module -ListAvailable -Name OSDProgress)) {
        Install-Module OSDProgress -Force -Scope AllUsers -ErrorAction Stop
    }
    Import-Module OSDProgress -Force

    if (Test-Path $TemplatePath) {
        Invoke-OSDProgress -Style Win11 -TemplateFile $TemplatePath
    }
    else {
        Invoke-OSDProgress -Style Win11
    }
    $global:CaritasOSDProgressStarted = $true
    Set-PhaseCompat -stepInt 1 -text 'Vorbereitung...'
}
catch {
    Write-Host -ForegroundColor Yellow "OSDProgress konnte nicht gestartet werden: $($_.Exception.Message)"
    $global:CaritasOSDProgressStarted = $false
}
# ===============================================================


Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) " -NoNewline
Write-Host -ForegroundColor Green "PSCloudScript at functions.osdcloud.com"
Invoke-Expression (Invoke-RestMethod -Uri functions.osdcloud.com)

#region Helper Functions
function Write-DarkGrayDate {
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        [System.String]
        $Message
    )
    if ($Message) {
        Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) $Message"
    }
    else {
        Write-Host -ForegroundColor DarkGray "$((Get-Date).ToString('yyyy-MM-dd-HHmmss')) " -NoNewline
    }
}
function Write-DarkGrayHost {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $Message
    )
    Write-Host -ForegroundColor DarkGray $Message
}
function Write-DarkGrayLine {
    [CmdletBinding()]
    param ()
    Write-Host -ForegroundColor DarkGray "========================================================================="
}
function Write-SectionHeader {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $Message
    )
    Write-DarkGrayLine
    Write-DarkGrayDate
    Write-Host -ForegroundColor Cyan $Message
}
function Write-SectionSuccess {
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        [System.String]
        $Message = 'Success!'
    )
    Write-DarkGrayDate
    Write-Host -ForegroundColor Green $Message
}
#endregion

#region PreOS Tasks
#=======================================================================
Write-SectionHeader "[PreOS] Define OSDCloud Global And Customer Parameters"
#=======================================================================
$Global:WPNinjaCH   = $null
$Global:WPNinjaCH   = [ordered]@{
    Development     = [bool]$true
    TestGroup       = [bool]$true
}
Write-SectionHeader "WPNinjaCH variables"
Write-Host ($Global:WPNinjaCH | Out-String)

$Global:MyOSDCloud = [ordered]@{
    MSCatalogFirmware   = [bool]$true
    HPBIOSUpdate        = [bool]$true
    #IsOnBattery        = [bool]$false
}
Write-SectionHeader "MyOSDCloud variables"
Write-Host ($Global:MyOSDCloud | Out-String)

if ($Global:OSDCloud.ApplyCatalogFirmware -eq $true) {
    #=======================================================================
    Write-SectionHeader "[PreOS] Prepare Firmware Tasks"
    #=======================================================================
    #Register-PSRepository -Default -Verbose
    osdcloud-TrustPSGallery -Verbose
    #Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Verbose

    osdcloud-InstallPowerShellModule -Name 'MSCatalog'
    #Install-Module -Name MSCatalog -Force -Verbose -SkipPublisherCheck -AllowClobber -Repository PSGallery    
}

#endregion

#region OS Tasks
#=======================================================================
Write-SectionHeader "[OS] Params and Start-OSDCloud"
#=======================================================================
Import-Module OSD -Force
$wim = 'D:\OSDCloud\OS\Win11_24H2_MUI.wim'
$Global:MyOSDCloud = @{
	ImageFileFullName = $wim
	ImageFileItem     = Get-Item $wim
	ImageFileName     = [IO.Path]::GetFileName($wim)
	OSImageIndex      = 1
    ZTI         = $true
    Firmware    = $true
}
Write-Output ($Global:MyOSDCloud | Out-String)
if ($global:CaritasOSDProgressStarted) { Set-PhaseCompat -stepInt 2 -text 'Windows wird installiert...' }
Invoke-OSDCloud
if ($global:CaritasOSDProgressStarted) { Update-OSDProgress -Text 'Installation abgeschlossen. Starte Nachbereitung...' }
#endregion

#region Autopilot Tasks
#================================================
if ($global:CaritasOSDProgressStarted) { Set-PhaseCompat -stepInt 3 -text 'Nachbereitung (Autopilot, Treiber, Apps)...' }
Write-SectionHeader "[PostOS] Define Autopilot Attributes"
#================================================
Write-DarkGrayHost "Define Computername"
$Serial = Get-WmiObject Win32_bios | Select-Object -ExpandProperty SerialNumber
$lastFourChars = $serial.Substring($serial.Length - 4)
$AssignedComputerName = "CACH-2$lastFourChars"


# Device assignment
if ($Global:WPNinjaCH.TestGroup -eq $true){
    Write-DarkGrayHost "Adding device to Intune_DE_Device
 Group"
    $AddToGroup = "Intune_DE_Device"

}
else {
    Write-DarkGrayHost "Adding device to Intune_DE_Device Group"
    $AddToGroup = "Intune_DE_Device"
}

Write-Host -ForegroundColor Yellow "Computername: $AssignedComputerName"
Write-Host -ForegroundColor Yellow "AddToGroup: $AddToGroup"

#================================================
Write-SectionHeader "[PostOS] AutopilotOOBE Configuration"
#================================================
Write-DarkGrayHost "Create C:\ProgramData\OSDeploy\OSDeploy.AutopilotOOBE.json file"
$AutopilotOOBEJson = @"
{
        "AssignedComputerName" : "$AssignedComputerName",
        "AddToGroup":  "$AddToGroup",
        "Assign":  {
                    "IsPresent":  true
                },
        "GroupTag":  "",
        "Hidden":  [
                    "GroupTag",
                    "Assign"
                ],
        "PostAction":  "Quit",
        "Run":  "NetworkingWireless",
        "Docs":  "https://google.ch/",
        "Title":  "Autopilot Manual Register"
    }
"@

If (!(Test-Path "C:\ProgramData\OSDeploy")) {
    New-Item "C:\ProgramData\OSDeploy" -ItemType Directory -Force | Out-Null
}
$AutopilotOOBEJson | Out-File -FilePath "C:\ProgramData\OSDeploy\OSDeploy.AutopilotOOBE.json" -Encoding ascii -Force
#endregion

#region Specialize Tasks
#================================================
Write-SectionHeader "[PostOS] SetupComplete CMD Command Line"
#================================================
Write-DarkGrayHost "Cleanup SetupComplete Files from OSDCloud Module"
Get-ChildItem -Path 'C:\Windows\Setup\Scripts\SetupComplete*' -Recurse | Remove-Item -Force

#=================================================
Write-SectionHeader "[PostOS] Define Specialize Phase"
#=================================================
$UnattendXml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="specialize">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Description>Start Autopilot Import & Assignment Process</Description>
                    <Path>PowerShell -ExecutionPolicy Bypass C:\Windows\Setup\scripts\autopilot.ps1</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>de-CH</InputLocale>
            <SystemLocale>de-DE</SystemLocale>
            <UILanguage>de-DE</UILanguage>
            <UserLocale>de-CH</UserLocale>
        </component>
    </settings>
</unattend>
'@ 
# Get-OSDGather -Property IsWinPE
Block-WinOS

if (-NOT (Test-Path 'C:\Windows\Panther')) {
    New-Item -Path 'C:\Windows\Panther'-ItemType Directory -Force -ErrorAction Stop | Out-Null
}

$Panther = 'C:\Windows\Panther'
$UnattendPath = "$Panther\Unattend.xml"
$UnattendXml | Out-File -FilePath $UnattendPath -Encoding utf8 -Width 2000 -Force

Write-DarkGrayHost "Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath"
Use-WindowsUnattend -Path 'C:\' -UnattendPath $UnattendPath | Out-Null
#endregion

#region OOBE Tasks
#================================================
Write-SectionHeader "[PostOS] OOBE CMD Command Line"
#================================================
Write-DarkGrayHost "Downloading Scripts for OOBE and specialize phase"

Invoke-RestMethod https://raw.githubusercontent.com/oneictag/OSDPad/refs/heads/main/Autopilot.ps1 | Out-File -FilePath 'C:\Windows\Setup\scripts\autopilot.ps1' -Encoding ascii -Force
Invoke-RestMethod https://raw.githubusercontent.com/oneictag/OSDPad/refs/heads/main/OOBE.ps1 | Out-File -FilePath 'C:\Windows\Setup\scripts\oobe.ps1' -Encoding ascii -Force
Invoke-RestMethod https://raw.githubusercontent.com/oneictag/OSDPad/refs/heads/main/CleanUp.ps1 | Out-File -FilePath 'C:\Windows\Setup\scripts\cleanup.ps1' -Encoding ascii -Force
Invoke-RestMethod https://raw.githubusercontent.com/oneictag/OSDPad/refs/heads/main/AP-Prereq.ps1 | Out-File -FilePath 'C:\Windows\Setup\scripts\cleanup.ps1' -Encoding ascii -Force
Invoke-RestMethod https://raw.githubusercontent.com/oneictag/OSDPad/refs/heads/main/start-autopilotoobe.ps1 | Out-File -FilePath 'C:\Windows\Setup\scripts\cleanup.ps1' -Encoding ascii -Force
#Invoke-RestMethod http://osdgather.osdcloud.ch | Out-File -FilePath 'C:\Windows\Setup\scripts\osdgather.ps1' -Encoding ascii -Force

$OOBEcmdTasks = @'
@echo off

REM Wait for Network 10 seconds
REM ping 127.0.0.1 -n 10 -w 1  >NUL 2>&1

REM Execute OOBE Tasks
start /wait powershell.exe -NoL -ExecutionPolicy Bypass -F C:\Windows\Setup\Scripts\oobe.ps1

REM Execute OOBE Tasks
start /wait powershell.exe -NoL -ExecutionPolicy Bypass -F C:\Windows\Setup\Scripts\AP-Prereq.ps1

REM Execute OOBE Tasks
REM start /wait powershell.exe -NoL -ExecutionPolicy Bypass -F C:\Windows\Setup\Scripts\start-autopilotoobe.ps1

REM Execute OSD Gather Script
REM start /wait powershell.exe -NoL -ExecutionPolicy Bypass -F C:\Windows\Setup\Scripts\osdgather.ps1

REM Execute Cleanup Script
REM start /wait powershell.exe -NoL -ExecutionPolicy Bypass -F C:\Windows\Setup\Scripts\cleanup.ps1

REM Below a PS session for debug and testing in system context, # when not needed 
REM start /wait powershell.exe -NoL -ExecutionPolicy Bypass

exit 
'@
$OOBEcmdTasks | Out-File -FilePath 'C:\Windows\Setup\scripts\oobe.cmd' -Encoding ascii -Force

Write-DarkGrayHost "Copying PFX file"
Copy-Item X:\OSDCloud\Config\Scripts C:\OSDCloud\ -Recurse -Force
#endregion

# Write-DarkGrayHost "Disabling Shift F10 in OOBE for security Reasons"
$Tagpath = "C:\Windows\Setup\Scripts\DisableCMDRequest.TAG"
New-Item -ItemType file -Force -Path $Tagpath | Out-Null
Write-DarkGrayHost "Shift F10 disabled now!"

#region Development
if ($Global:WPNinjaCH.Development -eq $true){
    #================================================
    Write-SectionHeader "[WINPE] DEVELOPMENT - Activate some debugging features"
    #================================================
    Write-DarkGrayHost "Enabling Shift+F10 in OOBE for security Reasons"
    $Tagpath = "C:\Windows\Setup\Scripts\DisableCMDRequest.TAG"
    Remove-Item -Force -Path $Tagpath | Out-Null
    Write-DarkGrayHost "Shift F10 enabled now!"

    Write-DarkGrayHost "Disable Cursor Suppression"
    #cmd.exe /c reg load HKLM\Offline c:\windows\system32\config\software & cmd.exe /c REG ADD "HKLM\Offline\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableCursorSuppression /t REG_DWORD /d 0 /f & cmd.exe /c reg unload HKLM\Offline
    Invoke-Exe cmd.exe -Arguments "/c reg load HKLM\Offline c:\windows\system32\config\software" | Out-Null
    New-ItemProperty -Path HKLM:\Offline\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableCursorSuppression -Value 0 -Force | Out-Null
    #Invoke-Exe cmd.exe -Arguments "/c REG ADD 'HKLM\Offline\Microsoft\Windows\CurrentVersion\Policies\System' /v EnableCursorSuppression /t REG_DWORD /d 0 /f "
    Invoke-Exe cmd.exe -Arguments "/c reg unload HKLM\Offline" | Out-Null
}
#endregion

#=======================================================================	
Write-SectionHeader "Moving OSDCloud Logs to IntuneManagementExtension\Logs\OSD"	
#=======================================================================	
if (-NOT (Test-Path 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD')) {	
    New-Item -Path 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD' -ItemType Directory -Force -ErrorAction Stop | Out-Null	
}	
Get-ChildItem -Path X:\OSDCloud\Logs\ | Copy-Item -Destination 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD' -Force

if ($Global:WPNinjaCH.Development -eq $false){
    Write-DarkGrayHost "Restarting in 20 seconds!"
    Start-Sleep -Seconds 20

    wpeutil reboot

    Stop-Transcript | Out-Null
}
else {
    Write-DarkGrayHost "Development Mode - No reboot!"
	Start-Sleep -Seconds 20
	wpeutil reboot
    Stop-Transcript | Out-Null
}

# ===== Stop OSDProgress =====
try {
    if ($global:CaritasOSDProgressStarted) { 
        Update-OSDProgress -Text 'Fertig. Neustart...'
        Stop-OSDProgress 
    }
} catch {}
