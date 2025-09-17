<# 
    Caritas Splash After OSDPad (WinPE-safe)
    - Shows a fullscreen splash image AFTER Start-OSDPad returns
    - Keeps splash visible during Invoke-OSDCloud and post tasks
    - Closes splash at the end (or on error) without blocking the main script
#>

#region === CONFIG ===
# Path to your splash image (JPG/PNG). Make sure the file exists before running.
$CaritasSplashImage = 'C:\Service\OSDCaritas\Config\splash.jpg'
# Opacity in percent (100 = fully opaque)
$CaritasSplashOpacity = 100
#endregion === CONFIG ===

#region === Fullscreen Splash (WinForms, no WPF required) ===
function Start-CaritasSplash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ImagePath,
        [int]$Opacity = 100
    )
    if (-not (Test-Path $ImagePath)) {
        Write-Host -ForegroundColor Yellow "[!] Splash image not found: $ImagePath"
        return $null
    }

    # Inline WinForms app shown in a separate PowerShell process to avoid blocking
    $inline = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

\$f = New-Object System.Windows.Forms.Form
\$f.FormBorderStyle = 'None'
\$f.WindowState = 'Maximized'
\$f.TopMost = \$true
\$f.BackColor = [System.Drawing.Color]::Black
\$f.Opacity = $([math]::Max(0,[math]::Min(100,$Opacity)))/100.0

\$pb = New-Object System.Windows.Forms.PictureBox
\$pb.Dock = 'Fill'
\$pb.SizeMode = 'StretchImage'
\$pb.Image = [System.Drawing.Image]::FromFile('$($ImagePath.Replace("'","''"))')
\$f.Controls.Add(\$pb)

# Graceful close via global named event
\$evtName = 'Global\\CARITAS_SPLASH_STOP'
try { \$reset = New-Object System.Threading.EventWaitHandle(\$false,[System.Threading.EventResetMode]::AutoReset,\$evtName,[ref]\$created) } catch {}

# Keep UI responsive without blocking the parent process
\$timer = New-Object System.Windows.Forms.Timer
\$timer.Interval = 250
\$timer.Add_Tick({
    try {
        if (\$reset -and \$reset.WaitOne(0)) { \$timer.Stop(); \$f.Close() }
    } catch {}
})
\$timer.Start()

[System.Windows.Forms.Application]::Run(\$f)
"@

    $psi = New-Object System.Diagnostics.ProcessStartInfo -Property @{
        FileName        = (Get-Process -Id $PID).Path
        Arguments       = "-NoProfile -ExecutionPolicy Bypass -Command $inline"
        WindowStyle     = 'Hidden'
        CreateNoWindow  = $true
        UseShellExecute = $false
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($p) { Write-Host -ForegroundColor Green ("[+] Splash started (PID: {0})" -f $p.Id) }
    return $p
}

function Stop-CaritasSplash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$false)][System.Diagnostics.Process]$Process)

    # First, signal the splash to close gracefully
    try {
        $evt = New-Object System.Threading.EventWaitHandle($false,[System.Threading.EventResetMode]::AutoReset,'Global\CARITAS_SPLASH_STOP',[ref]$created)
        [void]$evt.Set()
    } catch {}
    Start-Sleep -Milliseconds 500

    # If still running, terminate the process
    try { if ($Process -and -not $Process.HasExited) { $Process.Kill() | Out-Null } } catch {}
    Write-Host -ForegroundColor DarkGray "[=] Splash stopped."
}
#endregion === Fullscreen Splash ===

#region === Example integration ===
# 1) Show your OSDPad UI first
#    (Replace this line with your real call; kept here for clarity)
# Start-OSDPad -RepoOwner oneictag -RepoName OSDPad -RepoFolder ScriptPad -BrandingTitle 'Caritas Deployment'

# 2) Immediately after OSDPad returns, start the splash
$global:CaritasSplashProc = Start-CaritasSplash -ImagePath $CaritasSplashImage -Opacity $CaritasSplashOpacity

try {
    # 3) Do your actual deployment while the splash stays on top
    # Set-PhaseCompat -stepInt 2 -text 'Windows wird installiert...'
    # Invoke-OSDCloud
    # ... your post tasks here ...
}
finally {
    # 4) Always stop splash at the end (even if an error happened)
    Stop-CaritasSplash -Process $global:CaritasSplashProc
}
#endregion
