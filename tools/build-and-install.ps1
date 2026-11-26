# Analyze, test, build a debug APK, (re)start the demo server, and install + launch on the USB phone.
# Usage (repo root):  powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-and-install.ps1
# Log: contracts\.data\build-app.log   Versions and setup: docs\guide\dev-setup.md
# Override paths with env vars if your machine differs: FLUTTER_BIN, ANDROID_HOME, JAVA_HOME, GRADLE_USER_HOME, PUB_CACHE.
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$data = Join-Path $root 'contracts\.data'; New-Item -ItemType Directory -Force $data | Out-Null
$log = Join-Path $data 'build-app.log'
function L($m) { Add-Content -Encoding utf8 $log ("[" + (Get-Date -Format HH:mm:ss) + "] " + $m) }
Set-Content -Encoding utf8 $log "build start"

if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = 'D:\Android\Sdk' }
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr' }
if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = 'D:\gradle-home' }
if (-not $env:PUB_CACHE) { $env:PUB_CACHE = 'D:\pub-cache' }
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME; $env:CI = 'true'
$flutter = if ($env:FLUTTER_BIN) { $env:FLUTTER_BIN } else { 'C:\src\flutter\bin\flutter.bat' }
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
$env:Path = (Split-Path $flutter) + ";" + (Split-Path $adb) + ";$env:JAVA_HOME\bin;" + $env:Path

Set-Location (Join-Path $root 'app')
L "flutter analyze"
& $flutter analyze 2>&1 | ForEach-Object { L "  $_" }
L "flutter test"
& $flutter test 2>&1 | Select-Object -Last 6 | ForEach-Object { L "  $_" }
L "flutter build apk --debug (first build downloads Gradle + NDK, ~4 min; later ~15-60 s)"
& $flutter build apk --debug 2>&1 | Where-Object { $_ -notmatch '^\s*$' } | Select-Object -Last 25 | ForEach-Object { L "  $_" }
$apk = Join-Path $root 'app\build\app\outputs\flutter-apk\app-debug.apk'
L ("apk: " + (Test-Path $apk) + $(if (Test-Path $apk) { ' ' + [math]::Round((Get-Item $apk).Length / 1MB, 1) + ' MB' } else { '' }))

if (Test-Path $apk) {
  # Restart the demo server so the newest code, policy and .env are used. Keeps running after this script.
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -match 'mock-server.js' } | ForEach-Object { L ("stop old server pid " + $_.ProcessId); Stop-Process -Id $_.ProcessId -Force }
  Start-Sleep 1
  Start-Process -FilePath node.exe -ArgumentList '--env-file-if-exists=../.env', 'mock-server.js' -WorkingDirectory (Join-Path $root 'contracts') -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $data 'server.log') -RedirectStandardError (Join-Path $data 'server.err.log')
  Start-Sleep 5
  try { $h = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://127.0.0.1:8080/v1/health; L ("server: " + $h.Content.Substring(0, [Math]::Min(160, $h.Content.Length))) } catch { L ("server not reachable: " + $_.Exception.Message) }
  L "adb reverse tcp:8080 tcp:8080 (phone 127.0.0.1:8080 -> laptop server over USB)"
  & $adb reverse tcp:8080 tcp:8080 2>&1 | ForEach-Object { L "  $_" }
  L "adb install (--user 0: Samsung Secure Folder is a separate user)"
  & $adb install -r --user 0 $apk 2>&1 | ForEach-Object { L "  $_" }
  & $adb shell monkey -p com.moneyanywhere.money_anywhere -c android.intent.category.LAUNCHER 1 2>&1 | Select-Object -Last 1 | ForEach-Object { L "  launch: $_" }
}
L "build end"
