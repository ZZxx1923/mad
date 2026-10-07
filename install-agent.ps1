#Requires -Version 5.1
<#
  Set up this device (the agent) - one click
  ------------------------------------------
  - Installs Python automatically if missing.
  - Prepares agent/config.json (asks for the URL and token, or takes them from params).
  - Registers a Scheduled Task that runs the agent in the background automatically at
    every Windows logon, and restarts it if it stops - with no visible window.
  - Starts it immediately.

  Examples:
     powershell -ExecutionPolicy Bypass -File .\install-agent.ps1
     powershell -ExecutionPolicy Bypass -File .\install-agent.ps1 -Remove   (to remove the agent)
#>

param(
    [string]$ServerUrl,
    [string]$AgentToken,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$TaskName = 'RemotePCControlAgent'

# If anything fails, show it and keep the window open instead of closing instantly
trap {
    Write-Host ("`n[ERROR] " + $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo) { Write-Host ("  Line: " + $_.InvocationInfo.Line.Trim()) -ForegroundColor DarkGray }
    Read-Host "`nPress Enter to close" | Out-Null
    exit 1
}
try { Set-Location -LiteralPath $PSScriptRoot } catch {}

function Step($m) { Write-Host "`n==== $m ====" -ForegroundColor Cyan }
function Info($m) { Write-Host "  $m" -ForegroundColor Gray }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "`n[ERROR] $m" -ForegroundColor Red; Read-Host "Press Enter to close" | Out-Null; exit 1 }
function Have($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($m, $u -join ';')
}

$agentDir = Join-Path $PSScriptRoot 'agent'
$agentPy  = Join-Path $agentDir 'agent.py'
$cfgPath  = Join-Path $agentDir 'config.json'

# ----------------------------- remove -----------------------------
if ($Remove) {
    Step "Removing the agent from this device"
    try {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Ok "Scheduled task removed. The agent will no longer run."
    } catch {
        Warn "No task registered with this name (maybe already removed)."
    }
    Read-Host "Press Enter to close" | Out-Null
    exit 0
}

# ----------------------------- checks -----------------------------
Step "Checking files"
if (-not (Test-Path $agentPy)) { Die "Could not find agent/agent.py next to this script. Run it from inside the project folder." }
Ok "Agent found"

# ----------------------------- Python -----------------------------
Step "Checking Python"
if (-not (Have 'python')) {
    Warn "Python is not installed - installing via winget..."
    if (-not (Have 'winget')) { Die "winget is unavailable. Install Python from python.org then re-run." }
    winget install --id Python.Python.3.12 -e --source winget --accept-source-agreements --accept-package-agreements
    Refresh-Path
    if (-not (Have 'python')) { Die "Could not find Python after install. Open a new window and try again." }
}
Ok "Python ready"

# Resolve pythonw path (runs with no black console window)
$pythonw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
if (-not $pythonw) {
    $python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
    if ($python) {
        $cand = Join-Path (Split-Path $python) 'pythonw.exe'
        if (Test-Path $cand) { $pythonw = $cand } else { $pythonw = $python }
    }
}
if (-not $pythonw) { Die "Could not resolve the Python path." }
Info "Launcher: $pythonw"

# ----------------------------- config.json -----------------------------
Step "Connection settings"

# Reuse existing values if present
$wolMac = 'AA:BB:CC:DD:EE:FF'; $wolBc = '255.255.255.255'
if (Test-Path $cfgPath) {
    try {
        $old = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($old.wol_mac)       { $wolMac = $old.wol_mac }
        if ($old.wol_broadcast) { $wolBc  = $old.wol_broadcast }
        if (-not $ServerUrl  -and $old.server_url)  { $ServerUrl  = $old.server_url }
        if (-not $AgentToken -and $old.agent_token) { $AgentToken = $old.agent_token }
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
    $ServerUrl = Read-Host "Your Vercel site URL (e.g. https://your-app.vercel.app)"
}
$ServerUrl = $ServerUrl.Trim().TrimEnd('/')
if ($ServerUrl -notmatch '^https?://') { Die "Invalid URL - it must start with https://" }

if ([string]::IsNullOrWhiteSpace($AgentToken)) {
    Info "Enter the SAME AGENT_TOKEN value you set in Vercel (Environment Variables)."
    $AgentToken = Read-Host "AGENT_TOKEN"
}
if ([string]::IsNullOrWhiteSpace($AgentToken)) { Die "AGENT_TOKEN is required." }

$config = [ordered]@{
    server_url         = $ServerUrl
    agent_token        = $AgentToken
    poll_interval      = 2
    heartbeat_interval = 15
    wol_mac            = $wolMac
    wol_broadcast      = $wolBc
}
# Write JSON as UTF-8 without BOM (so Python reads it correctly)
$json = ($config | ConvertTo-Json)
[System.IO.File]::WriteAllText($cfgPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Ok "Saved settings to agent/config.json"

# ----------------------------- auto-start task -----------------------------
Step "Registering auto-start (always runs in background)"

$action = New-ScheduledTaskAction -Execute $pythonw -Argument "`"$agentPy`"" -WorkingDirectory $agentDir
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force -Description "Remote PC Control Agent" | Out-Null
Ok "Task registered: $TaskName"

# Clear old log, then start
$logPath = Join-Path $agentDir 'agent.log'
Remove-Item $logPath -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $TaskName
Info "Starting..."
Start-Sleep -Seconds 5

# ----------------------------- verify -----------------------------
Step "Verifying"
$state = (Get-ScheduledTask -TaskName $TaskName).State
Info "Task state: $state"
if (Test-Path $logPath) {
    Write-Host "  --- last log lines ---" -ForegroundColor DarkGray
    Get-Content $logPath -Tail 6 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    $bad401  = Select-String -Path $logPath -Pattern '401' -Quiet -ErrorAction SilentlyContinue
    $started = Select-String -Path $logPath -Pattern 'server=' -Quiet -ErrorAction SilentlyContinue
    if ($bad401) {
        Warn "AGENT_TOKEN does not match the one in Vercel (error 401). Fix the token and re-run."
    } elseif ($started) {
        Ok "Agent is running. Open your site on your phone - the device will show 'online'."
    } else {
        Warn "Started, but check the log above (URL / token / network)."
    }
} else {
    Warn "Log file not created yet. Wait a few seconds then check agent/agent.log"
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  This device is set up" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  The agent runs in the background now and starts automatically at every Windows logon."
Write-Host "  Log: $logPath"
Write-Host "  To stop / remove later: double-click uninstall-device.bat" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to close" | Out-Null
