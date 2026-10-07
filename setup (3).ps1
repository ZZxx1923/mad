#Requires -Version 5.1
<#
  الإعداد الكامل لمشروع "التحكم بالجهاز عن بُعد"
  ----------------------------------------------
  قائمة خيارات:
    [1] إعداد كامل: رفع على GitHub + نشر على Vercel + رفع المتغيّرات + إعداد هذا الجهاز.
    [2] إعداد هذا الجهاز فقط (الوكيل) — بدون لمس بايثون يدوياً.
    [3] إزالة الوكيل من هذا الجهاز.

  التشغيل (من داخل مجلد المشروع):
      powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>

$ErrorActionPreference = 'Stop'

# ----------------------------- أدوات مساعدة -----------------------------
function Step($m) { Write-Host "`n==== $m ====" -ForegroundColor Cyan }
function Info($m) { Write-Host "  $m" -ForegroundColor Gray }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "`n[خطأ] $m" -ForegroundColor Red; exit 1 }
function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user -join ';')
}
function Ensure-Tool($cmd, $wingetId, $name) {
    if (Have $cmd) { Ok "$name موجود"; return }
    Warn "$name غير مثبّت — محاولة التثبيت عبر winget…"
    if (-not (Have 'winget')) { Die "$name غير موجود و winget غير متاح. ثبّت $name يدوياً ثم أعد التشغيل." }
    winget install --id $wingetId -e --source winget --accept-source-agreements --accept-package-agreements
    Refresh-Path
    if (-not (Have $cmd)) { Die "تعذّر العثور على $name بعد التثبيت. افتح PowerShell جديدة وأعد المحاولة." }
    Ok "$name تم تثبيته"
}
function New-Secret([int]$bytes = 32) {
    $buf = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    return ([Convert]::ToBase64String($buf) -replace '\+', '-' -replace '/', '_' -replace '=', '')
}

# -------------------------- الإعداد السحابي (GitHub + Vercel) --------------------------
function Invoke-CloudSetup {
    Step "التأكد من الأدوات اللازمة"
    Ensure-Tool 'git'  'Git.Git'           'Git'
    Ensure-Tool 'node' 'OpenJS.NodeJS.LTS' 'Node.js'
    Ensure-Tool 'gh'   'GitHub.cli'        'GitHub CLI'
    if (-not (Have 'vercel')) {
        Warn "Vercel CLI غير مثبّت — جارِ التثبيت عبر npm…"
        npm install -g vercel | Out-Null
        Refresh-Path
        if (-not (Have 'vercel')) { Die "تعذّر تثبيت Vercel CLI. جرّب: npm install -g vercel" }
    }
    Ok "Vercel CLI جاهز"

    Step "الإعدادات"
    $repoName = Read-Host "اسم المستودع/المشروع [افتراضي: remote-pc-control]"
    if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = 'remote-pc-control' }
    $repoName = ($repoName -replace '[^a-zA-Z0-9_-]', '-').ToLower()

    $uiPass = Read-Host "كلمة سر صفحة التحكم (تكتبها في جوالك) — اتركها فارغة لتوليد واحدة"
    if ([string]::IsNullOrWhiteSpace($uiPass)) {
        $uiPass = New-Secret 9
        Warn "تم توليد كلمة سر: $uiPass   (احفظها!)"
    }
    $agentToken = New-Secret 32
    Ok "تم توليد AGENT_TOKEN تلقائياً"

    Step "رفع الملفات على GitHub"
    if (-not (Test-Path '.git')) { git init | Out-Null; Info "تم تهيئة Git" }
    if (-not (git config user.email 2>$null)) {
        git config user.email "$env:USERNAME@local"
        git config user.name  "$env:USERNAME"
    }
    git add -A
    git commit -m "Remote PC control" --allow-empty | Out-Null
    git branch -M main

    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Info "تسجيل الدخول في GitHub (سيفتح المتصفح)…"; gh auth login }
    $ghUser = (gh api user --jq .login).Trim()

    gh repo view "$ghUser/$repoName" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Warn "المستودع موجود مسبقاً — سيتم الرفع إليه"
        git remote remove origin 2>$null
        git remote add origin "https://github.com/$ghUser/$repoName.git"
        git push -u origin main --force
    } else {
        gh repo create $repoName --private --source=. --remote=origin --push
    }
    Ok "تم الرفع: https://github.com/$ghUser/$repoName"

    Step "إعداد مشروع Vercel"
    $who = (& vercel whoami 2>$null)
    if (-not $who) { Info "تسجيل الدخول في Vercel (سيفتح المتصفح)…"; vercel login }
    vercel link --yes --project $repoName | Out-Null
    Ok "تم ربط المشروع"

    foreach ($name in @('UI_PASSWORD', 'AGENT_TOKEN')) {
        $val = if ($name -eq 'UI_PASSWORD') { $uiPass } else { $agentToken }
        foreach ($t in @('production', 'preview', 'development')) {
            & vercel env rm $name $t --yes 2>$null | Out-Null
            $val | & vercel env add $name $t 2>$null | Out-Null
        }
        Ok "تم ضبط المتغيّر: $name"
    }
    vercel git connect --yes 2>$null | Out-Null

    Step "ربط قاعدة التخزين (Vercel KV)"
    Write-Host @"
  الخطوة اليدوية الوحيدة:
   1) ستُفتح لوحة Vercel الآن.
   2) افتح مشروعك '$repoName' → تبويب Storage → Create Database → اختر KV (مجاني).
   3) اضغط Connect to Project.
"@ -ForegroundColor Yellow
    Start-Process "https://vercel.com/dashboard/stores"
    Read-Host "  بعد ربط KV، اضغط Enter للمتابعة"

    Step "النشر على Vercel"
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
    if (-not $serverUrl) { $serverUrl = Read-Host "  الصق رابط الموقع" }
    Ok "رابط الموقع: $serverUrl"

    Write-Host "`n  الموقع (افتحه في جوالك): $serverUrl" -ForegroundColor Green
    Write-Host "  كلمة سر الدخول (UI_PASSWORD): $uiPass" -ForegroundColor Green
    Write-Host "  المستودع: https://github.com/$ghUser/$repoName" -ForegroundColor Green

    return @{ Url = $serverUrl; Token = $agentToken }
}

# -------------------------- القائمة --------------------------
Step "فحص مجلد المشروع"
foreach ($p in @('package.json', 'api', 'index.html', 'agent')) {
    if (-not (Test-Path $p)) { Die "شغّل السكربت من داخل مجلد المشروع (الملف الناقص: $p)." }
}
Ok "المجلد صحيح"

Write-Host "`n اختر ما تريد:" -ForegroundColor Cyan
Write-Host "   [1] إعداد كامل (GitHub + Vercel + هذا الجهاز)"
Write-Host "   [2] إعداد هذا الجهاز فقط (الوكيل)"
Write-Host "   [3] إزالة الوكيل من هذا الجهاز"
$choice = Read-Host " رقم الخيار [افتراضي 1]"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }

$installer = Join-Path $PSScriptRoot 'install-agent.ps1'

switch ($choice) {
    '1' {
        $res = Invoke-CloudSetup
        Step "إعداد هذا الجهاز (الوكيل)"
        & $installer -ServerUrl $res.Url -AgentToken $res.Token
    }
    '2' {
        & $installer
    }
    '3' {
        & $installer -Remove
    }
    default { Die "خيار غير معروف." }
}
