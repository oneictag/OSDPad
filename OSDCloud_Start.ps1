Write-Host -ForegroundColor Green "Starting OSDCloud ZTI"
Start-Sleep -Seconds 5

# Make sure I have the latest OSD Content
# Write-Host -ForegroundColor Green "Updating OSD PowerShell Module"
# Install-Module OSD -Force

Write-Host  -ForegroundColor Green "Importing OSD PowerShell Module"
Import-Module OSD -Force


<# Caritas Autopilot – OSDPad zuerst, danach Fullscreen-Splash (WinPE-tauglich) #>

# --- Basispfad unter ProgramData/IMExt/Logs/OSD ---------------------------------
$CaritasDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\OSD'
New-Item -Path $CaritasDir -ItemType Directory -Force | Out-Null

# Quellen
$SplashScriptUrl = 'https://raw.githubusercontent.com/oneictag/OSDPad/refs/heads/main/Caritas_Splash_After_OSDPad.ps1'
$LogoUrl         = 'https://raw.githubusercontent.com/oneictag/OSDPad/main/Caritas_Schweiz_Logo_rot-weiss.png'

# Zielpfade
$global:CaritasSplashScript = Join-Path $CaritasDir 'Caritas_Splash_After_OSDPad.ps1'
$global:CaritasSplashImage  = Join-Path $CaritasDir 'Caritas_Schweiz_Logo_rot-weiss.png'

# Downloads (robust, ohne UI)
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-CaritasAsset {
    param([string]$Url,[string]$Dest)
    if (Test-Path $Dest) { return }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -Headers @{ 'User-Agent'='OSDCaritas' } -TimeoutSec 30 -ErrorAction Stop
    } catch {
        Write-Host -ForegroundColor Yellow "[!] Download fehlgeschlagen: $Url -> $Dest : $($_.Exception.Message)"
    }
}

Get-CaritasAsset -Url $SplashScriptUrl -Dest $global:CaritasSplashScript
Get-CaritasAsset -Url $LogoUrl         -Dest $global:CaritasSplashImage

# Splash-Funktionen laden (dot-source)
if (Test-Path $global:CaritasSplashScript) {
    . $global:CaritasSplashScript
} else {
    Write-Host -ForegroundColor Yellow "[!] Splash-Skript nicht vorhanden: $global:CaritasSplashScript (fahre ohne Splash fort)"
}

# ====================================================================
# >>>> AB HIER: dein bisheriger Ablauf <<<<
# ====================================================================

# 1) ZUERST OSDPad anzeigen
Start-OSDPad -RepoOwner oneictag -RepoName OSDPad -RepoFolder ScriptPad -BrandingTitle 'Caritas Deployment'

# 2) Danach Splash starten (nur wenn Funktionsdefinition verfuegbar)
if (Get-Command Start-CaritasSplash -ErrorAction SilentlyContinue) {
    $global:CaritasSplashProc = Start-CaritasSplash -ImagePath $global:CaritasSplashImage -Opacity 100
} else {
    Write-Host -ForegroundColor Yellow "[!] Start-CaritasSplash nicht verfuegbar – Splash wird uebersprungen."
}

try {
    # 3) >>> Hier deine eigentliche Logik (nichts geaendert) <<<
    # Beispiel:
    # Update: Vorbereitungsphase etc. (nur Logging, optional)
    # Write-Host "[i] Vorbereitung..."
    
    # Windows Deployment
    Invoke-OSDCloud

    # Nachbereitung (Autopilot, Treiber, Apps, etc.)
    # ... dein bestehender Code ...
}
finally {
    # 4) Splash immer sauber schliessen
    if (Get-Command Stop-CaritasSplash -ErrorAction SilentlyContinue) {
        Stop-CaritasSplash -Process $global:CaritasSplashProc
    }
}


#Start OSDCloudScriptPad
Write-Host -ForegroundColor Green "Start OSDPad"
Start-OSDPad -RepoOwner oneictag -RepoName OSDPad -RepoFolder ScriptPad -BrandingTitle 'Caritas Deployment'