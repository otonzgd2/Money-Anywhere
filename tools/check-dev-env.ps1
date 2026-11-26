# Compare this machine with the versions the team uses (docs/guide/dev-setup.md). Prints OK / DIFF / MISSING.
# Usage (repo root):  powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-dev-env.ps1
$expect = [ordered]@{
  'Flutter'     = '3.50.1'
  'Dart'        = '3.14.0'
  'Node'        = 'v24'
  'Java (JBR)'  = '25'
  'adb'         = '1.0.41'
  'android-36'  = 'android-36'
  'build-tools' = '36.0.0'
}
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\Android\Sdk' }
$flutter = if ($env:FLUTTER_BIN) { $env:FLUTTER_BIN } else { 'flutter' }
$java = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\java.exe' } else { 'java' }
function Try($f) { try { & $f } catch { '' } }
$fv = (Try { & $flutter --version 2>&1 | Out-String })
$have = [ordered]@{
  'Flutter'     = if ($fv -match 'Flutter (\d+\.\d+\.\d+)') { $Matches[1] } else { '' }
  'Dart'        = if ($fv -match 'Dart (\d+\.\d+\.\d+)') { $Matches[1] } else { '' }
  'Node'        = (Try { node --version 2>&1 | Out-String }).Trim()
  'Java (JBR)'  = $(if ((Try { & $java -version 2>&1 | Out-String }) -match 'version "(\d+)') { $Matches[1] } else { '' })
  'adb'         = $(if ((Try { & (Join-Path $sdk 'platform-tools\adb.exe') version 2>&1 | Out-String }) -match 'version (\d+\.\d+\.\d+)') { $Matches[1] } else { '' })
  'android-36'  = $(if (Test-Path (Join-Path $sdk 'platforms\android-36')) { 'android-36' } else { '' })
  'build-tools' = $(if (Test-Path (Join-Path $sdk 'build-tools\36.0.0')) { '36.0.0' } else { '' })
}
foreach ($k in $expect.Keys) {
  $e = $expect[$k]; $h = $have[$k]
  $s = if (-not $h) { 'MISSING' } elseif ($h.StartsWith($e)) { 'OK' } else { 'DIFF' }
  '{0,-8} {1,-12} expected {2,-10} have {3}' -f $s, $k, $e, $h
}
if (-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'))) { 'MISSING  .env         copy .env.example to .env and set AI_API_KEY (ask the Owner)' } else { 'OK       .env         present (never commit it)' }
