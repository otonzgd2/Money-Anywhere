# Reconnect the phone to the demo server without rebuilding (after Auto Blocker / unplugging the cable).
# Usage (repo root):  powershell -NoProfile -ExecutionPolicy Bypass -File tools\reconnect.ps1
# Writes contracts\.data\reconnect.log
$root = Split-Path -Parent $PSScriptRoot
$data = Join-Path $root 'contracts\.data'; New-Item -ItemType Directory -Force $data | Out-Null
$log = Join-Path $data 'reconnect.log'
function L($m) { $line = "[" + (Get-Date -Format HH:mm:ss) + "] " + $m; Add-Content -Encoding utf8 $log $line; Write-Output $line }
Set-Content -Encoding utf8 $log "reconnect start"
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\Android\Sdk' }
$adb = Join-Path $sdk 'platform-tools\adb.exe'

# 1. Server: start it if it is not answering
$up = $false
try { $up = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://127.0.0.1:8080/v1/health).StatusCode -eq 200 } catch {}
if (-not $up) {
  L "server not answering: starting it"
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -match 'mock-server.js' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Start-Process -FilePath node.exe -ArgumentList '--env-file-if-exists=../.env', 'mock-server.js' -WorkingDirectory (Join-Path $root 'contracts') -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $data 'server.log') -RedirectStandardError (Join-Path $data 'server.err.log')
  Start-Sleep 5
}
try { $h = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://127.0.0.1:8080/v1/health; L ("server OK: " + ($h.Content | ConvertFrom-Json).version) } catch { L "server still not answering, see contracts\.data\server.err.log" }

# 2. Phone: restart adb, check the device, re-apply the USB tunnel, open the app
& $adb kill-server 2>&1 | Out-Null
& $adb start-server 2>&1 | Out-Null
$dev = (& $adb devices 2>&1 | Select-String -Pattern '\tdevice$|\tunauthorized$|\toffline$' | ForEach-Object { $_.Line }) -join ', '
if (-not $dev) { L "PHONE NOT FOUND: unlock the phone, turn off Auto Blocker, replug the cable, tap Allow, then run this again"; exit 1 }
L "phone: $dev"
if ($dev -match 'unauthorized') { L "tap 'Allow USB debugging' on the phone screen, then run this again"; exit 1 }
& $adb reverse tcp:8080 tcp:8080 2>&1 | Out-Null
L ("adb reverse: " + ((& $adb reverse --list 2>&1) -join ' '))
& $adb shell am force-stop --user 0 com.moneyanywhere.money_anywhere 2>&1 | Out-Null
& $adb shell monkey -p com.moneyanywhere.money_anywhere -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
L "app restarted on the phone"
