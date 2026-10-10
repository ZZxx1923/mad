// Returns a self-contained PowerShell installer for the Windows agent.
// The agent is pure PowerShell (no Python needed). Scoped to the logged-in account.
// Usage from the site: irm "https://<host>/api/installer?s=<session>" | iex
import { userFromSession, getUserToken } from "./_lib/kv.js";

const TEMPLATE = `$ErrorActionPreference='Stop'
Write-Host 'Installing Remote PC Control agent...' -ForegroundColor Cyan
$dir = Join-Path $env:LOCALAPPDATA 'RemotePCControlAgent'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$agent = @'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ServerUrl = '__SERVER_URL__'
$AgentToken = '__AGENT_TOKEN__'
$WolMac = '__WOL_MAC__'
$headers = @{ 'x-agent-token' = $AgentToken }
$hostName = $env:COMPUTERNAME
$deviceId = ($env:COMPUTERNAME -replace '[^A-Za-z0-9_-]','_')
$logFile = Join-Path $env:LOCALAPPDATA 'RemotePCControlAgent\\agent.log'
function Log($m){ try{ Add-Content -LiteralPath $logFile -Value ((Get-Date).ToString('s') + ' ' + $m) }catch{} }
function Send-WOL {
  if(-not $WolMac){ return }
  $m = ($WolMac -replace '[^0-9A-Fa-f]','')
  if($m.Length -ne 12){ return }
  $mb = for($i=0;$i -lt 12;$i+=2){ [Convert]::ToByte($m.Substring($i,2),16) }
  $packet = @(); for($i=0;$i -lt 6;$i++){ $packet += [byte]255 }
  for($i=0;$i -lt 16;$i++){ $packet += $mb }
  $u = New-Object System.Net.Sockets.UdpClient
  $u.EnableBroadcast = $true
  $u.Connect([System.Net.IPAddress]::Broadcast, 9)
  $u.Send([byte[]]$packet, $packet.Length) | Out-Null
  $u.Close()
}
Log 'agent started'
$lastHb = (Get-Date).AddSeconds(-999)
while($true){
  try{
    if((((Get-Date) - $lastHb)).TotalSeconds -ge 15){
      Invoke-RestMethod -Uri ($ServerUrl + '/api/heartbeat') -Method Post -Headers $headers -ContentType 'application/json' -Body (@{deviceId=$deviceId;hostname=$hostName;os='Windows'} | ConvertTo-Json) -TimeoutSec 20 | Out-Null
      $lastHb = Get-Date
    }
    $r = Invoke-RestMethod -Uri ($ServerUrl + '/api/poll?deviceId=' + $deviceId) -Method Get -Headers $headers -TimeoutSec 20
    if($r.command){
      $a = $r.command.action; $id = $r.command.id; $delay = [int]$r.command.delay
      Log ('command: ' + $a)
      try{ Invoke-RestMethod -Uri ($ServerUrl + '/api/ack') -Method Post -Headers $headers -ContentType 'application/json' -Body (@{id=$id;status='accepted';message='executing'} | ConvertTo-Json) -TimeoutSec 20 | Out-Null }catch{}
      try{
        switch($a){
          'shutdown' { Start-Process 'shutdown' -ArgumentList ('/s /t ' + $delay) -WindowStyle Hidden }
          'restart'  { Start-Process 'shutdown' -ArgumentList ('/r /t ' + $delay) -WindowStyle Hidden }
          'logoff'   { Start-Process 'shutdown' -ArgumentList '/l' -WindowStyle Hidden }
          'cancel'   { Start-Process 'shutdown' -ArgumentList '/a' -WindowStyle Hidden }
          'lock'     { rundll32.exe user32.dll,LockWorkStation }
          'sleep'    { rundll32.exe powrprof.dll,SetSuspendState 0,1,0 }
          'wake'     { Send-WOL }
        }
        try{ Invoke-RestMethod -Uri ($ServerUrl + '/api/ack') -Method Post -Headers $headers -ContentType 'application/json' -Body (@{id=$id;status='done';message='ok'} | ConvertTo-Json) -TimeoutSec 20 | Out-Null }catch{}
      }catch{
        Log ('error: ' + $_)
        try{ Invoke-RestMethod -Uri ($ServerUrl + '/api/ack') -Method Post -Headers $headers -ContentType 'application/json' -Body (@{id=$id;status='error';message=("" + $_)} | ConvertTo-Json) -TimeoutSec 20 | Out-Null }catch{}
      }
    }
  }catch{ Start-Sleep -Seconds 1 }
  Start-Sleep -Seconds 2
}
'@

[System.IO.File]::WriteAllText((Join-Path $dir 'agent.ps1'), $agent, (New-Object System.Text.UTF8Encoding($false)))

$ps1 = Join-Path $dir 'agent.ps1'
$arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ps1 + '"'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\\' + $env:USERNAME) -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
Register-ScheduledTask -TaskName 'RemotePCControlAgent' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName 'RemotePCControlAgent'

Write-Host ''
Write-Host 'Done! The agent is installed and running.' -ForegroundColor Green
Write-Host 'It starts automatically at every Windows logon.'
Write-Host 'Open your site on your phone - this PC should show as online in a few seconds.'
`;

export default async function handler(req, res) {
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  const session = (req.query && (req.query.s || req.query.k)) || req.headers["x-session"];
  const user = await userFromSession(session);
  if (!user) {
    res.status(401).send("# Unauthorized: open the site, log in, then use the install button.");
    return;
  }
  const token = await getUserToken(user);
  if (!token) {
    res.status(401).send("# Unauthorized.");
    return;
  }

  const host = (req.headers["x-forwarded-host"] || req.headers.host || "").split(",")[0].trim();
  const proto = (req.headers["x-forwarded-proto"] || "https").split(",")[0].trim();
  const serverUrl = `${proto}://${host}`;

  const script = TEMPLATE
    .split("__SERVER_URL__").join(serverUrl)
    .split("__AGENT_TOKEN__").join(token)
    .split("__WOL_MAC__").join("");

  res.status(200).send(script);
}
