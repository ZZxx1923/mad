#Requires -Version 5.1
<#
  إعداد هذا الجهاز (الوكيل) — بنقرة واحدة
  ---------------------------------------
  - يثبّت Python تلقائياً إذا كان ناقصاً.
  - يجهّز agent/config.json (يسألك الرابط والتوكن، أو يأخذهما من المعطيات).
  - يسجّل مهمة في Task Scheduler تشغّل الوكيل بالخلفية تلقائياً عند كل تشغيل للويندوز،
    وتعيد تشغيله لو توقف — بدون أي نافذة ظاهرة.
  - يشغّله فوراً.

  أمثلة:
     powershell -ExecutionPolicy Bypass -File .\install-agent.ps1
     powershell -ExecutionPolicy Bypass -File .\install-agent.ps1 -Remove   (لإزالة الوكيل)
#>

param(
    [string]$ServerUrl,
    [string]$AgentToken,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$TaskName = 'RemotePCControlAgent'

function Step($m) { Write-Host "`n==== $m ====" -ForegroundColor Cyan }
function Info($m) { Write-Host "  $m" -ForegroundColor Gray }
function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "`n[خطأ] $m" -ForegroundColor Red; exit 1 }
function Have($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($m, $u -join ';')
}

$agentDir = Join-Path $PSScriptRoot 'agent'
$agentPy  = Join-Path $agentDir 'agent.py'
$cfgPath  = Join-Path $agentDir 'config.json'

# ----------------------------- إزالة -----------------------------
if ($Remove) {
    Step "إزالة الوكيل من هذا الجهاز"
    try {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Ok "تمت إزالة المهمة المجدولة. لن يعمل الوكيل بعد الآن."
    } catch {
        Warn "لا توجد مهمة مسجّلة بهذا الاسم (ربما أُزيلت مسبقاً)."
    }
    exit 0
}

# ----------------------------- فحوصات -----------------------------
Step "فحص الملفات"
if (-not (Test-Path $agentPy)) { Die "لم أجد agent/agent.py بجانب هذا السكربت. شغّله من داخل مجلد المشروع." }
Ok "تم العثور على الوكيل"

# ----------------------------- Python -----------------------------
Step "التأكد من Python"
if (-not (Have 'python')) {
    Warn "Python غير مثبّت — جارِ التثبيت عبر winget…"
    if (-not (Have 'winget')) { Die "winget غير متاح. ثبّت Python من python.org ثم أعد التشغيل." }
    winget install --id Python.Python.3.12 -e --source winget --accept-source-agreements --accept-package-agreements
    Refresh-Path
    if (-not (Have 'python')) { Die "تعذّر العثور على Python بعد التثبيت. افتح نافذة جديدة وأعد المحاولة." }
}
Ok "Python جاهز"

# تحديد مسار pythonw (يشغّل بلا نافذة سوداء)
$pythonw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
if (-not $pythonw) {
    $python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
    if ($python) {
        $cand = Join-Path (Split-Path $python) 'pythonw.exe'
        if (Test-Path $cand) { $pythonw = $cand } else { $pythonw = $python }
    }
}
if (-not $pythonw) { Die "تعذّر تحديد مسار Python." }
Info "المشغّل: $pythonw"

# ----------------------------- الإعداد (config.json) -----------------------------
Step "إعداد الاتصال"

# أعد استخدام القيم الموجودة إن وُجدت
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
    $ServerUrl = Read-Host "رابط موقعك على Vercel (مثال: https://your-app.vercel.app)"
}
$ServerUrl = $ServerUrl.Trim().TrimEnd('/')
if ($ServerUrl -notmatch '^https?://') { Die "الرابط غير صحيح — لازم يبدأ بـ https://" }

if ([string]::IsNullOrWhiteSpace($AgentToken)) {
    Info "اكتب نفس قيمة AGENT_TOKEN الموجودة في إعدادات Vercel (Environment Variables)."
    $AgentToken = Read-Host "AGENT_TOKEN"
}
if ([string]::IsNullOrWhiteSpace($AgentToken)) { Die "AGENT_TOKEN مطلوب." }

$config = [ordered]@{
    server_url         = $ServerUrl
    agent_token        = $AgentToken
    poll_interval      = 2
    heartbeat_interval = 15
    wol_mac            = $wolMac
    wol_broadcast      = $wolBc
}
# كتابة JSON بترميز UTF-8 بدون BOM (مهم حتى يقرأه بايثون بشكل صحيح)
$json = ($config | ConvertTo-Json)
[System.IO.File]::WriteAllText($cfgPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Ok "تم حفظ الإعداد في agent/config.json"

# ----------------------------- مهمة التشغيل التلقائي -----------------------------
Step "تسجيل التشغيل التلقائي (يعمل بالخلفية دائماً)"

$action = New-ScheduledTaskAction -Execute $pythonw -Argument "`"$agentPy`"" -WorkingDirectory $agentDir
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force -Description "Remote PC Control Agent" | Out-Null
Ok "تم تسجيل المهمة: $TaskName"

# حذف سجل قديم ثم تشغيل
$logPath = Join-Path $agentDir 'agent.log'
Remove-Item $logPath -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $TaskName
Info "جارِ التشغيل…"
Start-Sleep -Seconds 5

# ----------------------------- التحقق -----------------------------
Step "التحقق من العمل"
$state = (Get-ScheduledTask -TaskName $TaskName).State
Info "حالة المهمة: $state"
if (Test-Path $logPath) {
    Write-Host "  --- آخر أسطر السجل ---" -ForegroundColor DarkGray
    Get-Content $logPath -Tail 6 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    $bad401  = Select-String -Path $logPath -Pattern '401' -Quiet -ErrorAction SilentlyContinue
    $started = Select-String -Path $logPath -Pattern 'server=' -Quiet -ErrorAction SilentlyContinue
    if ($bad401) {
        Warn "AGENT_TOKEN لا يطابق المضبوط في Vercel (خطأ 401). صحّح التوكن ثم أعد التشغيل."
    } elseif ($started) {
        Ok "الوكيل يعمل ✔  افتح موقعك من الجوال وستجد الجهاز 'متصل'."
    } else {
        Warn "اشتغل لكن راجع السجل أعلاه للتأكد (الرابط/التوكن/الشبكة)."
    }
} else {
    Warn "لم يُنشأ ملف السجل بعد. انتظر ثوانٍ ثم افحص agent/agent.log"
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  تم إعداد هذا الجهاز 🎉" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  الوكيل يعمل بالخلفية الآن وسيبدأ تلقائياً عند كل تشغيل للويندوز."
Write-Host "  السجل: $logPath"
Write-Host "  للإيقاف/الإزالة لاحقاً:" -ForegroundColor Cyan
Write-Host "     powershell -ExecutionPolicy Bypass -File .\install-agent.ps1 -Remove"
Write-Host ""
