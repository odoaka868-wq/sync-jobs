# probe.ps1: readback channel test - writes marker files directly and exits
$ErrorActionPreference = 'Continue'
$modelsDir = $null
$cfgPath = Join-Path $env:USERPROFILE 'pc1-agent\config.json'
if (Test-Path $cfgPath) { try { $modelsDir = (Get-Content $cfgPath -Raw | ConvertFrom-Json).modelsDir } catch {} }
if (-not $modelsDir) { Write-Output 'NO MODELS DIR'; exit 1 }
$comfyRoot = Split-Path $modelsDir -Parent
$outDir = Join-Path $comfyRoot 'output'
$logDir = Join-Path $outDir 'agentlogs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Set-Content -Path (Join-Path $logDir 'probe.txt') -Value "PROBE TXT $stamp" -Encoding UTF8
Set-Content -Path (Join-Path $logDir 'probe.txt.png') -Value "PROBE TXTPNG $stamp" -Encoding UTF8
$png64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
[IO.File]::WriteAllBytes((Join-Path $outDir 'probe_root.png'), [Convert]::FromBase64String($png64))
Write-Output "PROBE WROTE FILES at $stamp comfyRoot=$comfyRoot"
