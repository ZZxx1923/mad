#Requires -Version 5.1
<#
  Remote PC Control - Full Setup
  ------------------------------
  Menu:
    [1] Full setup: push to GitHub + deploy to Vercel + set variables + set up this device.
    [2] Set up this device only (the agent).
    [3] Remove the agent from this device.

  Run (from inside the project folder):
      powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>

$ErrorActionPreference = 'Stop'

# If anything fails, show it and keep the window open instead of closing instantly
trap {
    Write-Host ("`n[ERROR] " + $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo) { Write-Host ("  Line: " + $_.InvocationInfo.Line.Trim()) -ForegroundColor DarkGray }
    Read-Host "`nPress Enter to close" | Out-Null
    exit 1
}
try { Set-Location -LiteralPath $PSScriptRoot } catch {}

# ----------------------------- helpers -----------------------------
function Step($m) { Write-Host "`n==== $m ====" -ForegroundColor Cyan }
function Info($m) { Write-Host "  $m" -ForegroundColor Gray }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "`n[ERROR] $m" -ForegroundColor Red; Read-Host "Press Enter to close" | Out-Null; exit 1 }
function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user -join ';')
}
function Ensure-Tool($cmd, $wingetId, $name) {
    if (Have $cmd) { Ok "$name found"; return }
    Warn "$name is not installed - installing via winget..."
    if (-not (Have 'winget')) { Die "$name not found and winget is unavailable. Install $name manually then re-run." }
    winget install --id $wingetId -e --source winget --accept-source-agreements --accept-package-agreements
    Refresh-Path
    if (-not (Have $cmd)) { Die "Could not find $name after install. Open a new PowerShell window and re-run." }
    Ok "$name installed"
}
function New-Secret([int]$bytes = 32) {
    $buf = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    return ([Convert]::ToBase64String($buf) -replace '\+', '-' -replace '/', '_' -replace '=', '')
}

# -------------------------- cloud setup (GitHub + Vercel) --------------------------
function Invoke-CloudSetup {
    Step "Checking required tools"
    Ensure-Tool 'git'  'Git.Git'           'Git'
    Ensure-Tool 'node' 'OpenJS.NodeJS.LTS' 'Node.js'
    Ensure-Tool 'gh'   'GitHub.cli'        'GitHub CLI'
    if (-not (Have 'vercel')) {
        Warn "Vercel CLI is not installed - installing via npm..."
        npm install -g vercel | Out-Null
        Refresh-Path
        if (-not (Have 'vercel')) { Die "Could not install Vercel CLI. Try: npm install -g vercel" }
    }
    Ok "Vercel CLI ready"

    Step "Settings"
    $repoName = Read-Host "Repository/project name [default: remote-pc-control]"
    if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = 'remote-pc-control' }
    $repoName = ($repoName -replace '[^a-zA-Z0-9_-]', '-').ToLower()

    $uiPass = Read-Host "Control page password (you type this on your phone) - leave empty to auto-generate"
    if ([string]::IsNullOrWhiteSpace($uiPass)) {
        $uiPass = New-Secret 9
        Warn "Generated password: $uiPass   (save it!)"
    }
    $agentToken = New-Secret 32
    Ok "AGENT_TOKEN generated automatically"

    Step "Pushing files to GitHub"
    if (-not (Test-Path '.git')) { git init | Out-Null; Info "Initialized Git" }
    if (-not (git config user.email 2>$null)) {
        git config user.email "$env:USERNAME@local"
        git config user.name  "$env:USERNAME"
    }
    git add -A
    git commit -m "Remote PC control" --allow-empty | Out-Null
    git branch -M main

    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Info "Signing in to GitHub (a browser will open)..."; gh auth login }
    $ghUser = (gh api user --jq .login).Trim()

    gh repo view "$ghUser/$repoName" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Warn "Repository already exists - pushing to it"
        git remote remove origin 2>$null
        git remote add origin "https://github.com/$ghUser/$repoName.git"
        git push -u origin main --force
    } else {
        gh repo create $repoName --private --source=. --remote=origin --push
    }
    Ok "Pushed: https://github.com/$ghUser/$repoName"

    Step "Setting up the Vercel project"
    $who = (& vercel whoami 2>$null)
    if (-not $who) { Info "Signing in to Vercel (a browser will open)..."; vercel login }
    vercel link --yes --project $repoName | Out-Null
    Ok "Project linked"

    foreach ($name in @('UI_PASSWORD', 'AGENT_TOKEN')) {
        $val = if ($name -eq 'UI_PASSWORD') { $uiPass } else { $agentToken }
        foreach ($t in @('production', 'preview', 'development')) {
            & vercel env rm $name $t --yes 2>$null | Out-Null
            $val | & vercel env add $name $t 2>$null | Out-Null
        }
        Ok "Set variable: $name"
    }
    vercel git connect --yes 2>$null | Out-Null

    Step "Connect storage (Vercel KV)"
    Write-Host @"
  One manual step:
   1) The Vercel dashboard will open now.
   2) Open your project '$repoName' -> Storage tab -> Create Database -> choose KV (free).
   3) Click Connect to Project.
"@ -ForegroundColor Yellow
    Start-Process "https://vercel.com/dashboard/stores"
    Read-Host "  After connecting KV, press Enter to continue"

    Step "Deploying to Vercel"
    $raw = & vercel deploy --prod --yes 2>&1
    $raw | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    $serverUrl = $null
    if (Test-Path '.vercel/project.json') {
        try {
            $pj = Get-Content '.vercel/project.json' -Raw | ConvertFrom-Json
            if ($pj.projectName) { $serverUrl = "https://$($pj.projectName).vercel.app" }
        } catch {}
    }
    if (-not $serverUrl) {
        $m = [regex]::Matches(($raw | Out-String), 'https://[A-Za-z0-9._-]+\.vercel\.app')
        if ($m.Count -gt 0) { $serverUrl = $m[$m.Count - 1].Value }
    }
    if (-not $serverUrl) { $serverUrl = Read-Host "  Paste your site URL" }
    Ok "Site URL: $serverUrl"

    Write-Host "`n  Site (open on your phone): $serverUrl" -ForegroundColor Green
    Write-Host "  Login password (UI_PASSWORD): $uiPass" -ForegroundColor Green
    Write-Host "  Repository: https://github.com/$ghUser/$repoName" -ForegroundColor Green

    return @{ Url = $serverUrl; Token = $agentToken }
}

# -------------------------- menu --------------------------
Step "Checking project folder"
foreach ($p in @('package.json', 'api', 'index.html', 'agent')) {
    if (-not (Test-Path $p)) { Die "Run this from inside the project folder (missing: $p)." }
}
Ok "Folder OK"

Write-Host "`n Choose an option:" -ForegroundColor Cyan
Write-Host "   [1] Full setup (GitHub + Vercel + this device)"
Write-Host "   [2] Set up this device only (the agent)"
Write-Host "   [3] Remove the agent from this device"
$choice = Read-Host " Option number [default 1]"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }

$installer = Join-Path $PSScriptRoot 'install-agent.ps1'

switch ($choice) {
    '1' {
        $res = Invoke-CloudSetup
        Step "Setting up this device (the agent)"
        & $installer -ServerUrl $res.Url -AgentToken $res.Token
    }
    '2' {
        & $installer
    }
    '3' {
        & $installer -Remove
    }
    default { Die "Unknown option." }
}
