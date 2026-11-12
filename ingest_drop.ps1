# ingest_drop.ps1: ComfyUI同梱Pythonで ingest_drop.py を実行する
$ErrorActionPreference = 'Continue'
$train = Join-Path $env:USERPROFILE 'pc1-train'
$py = $null
$hit = Get-ChildItem "$env:LOCALAPPDATA\Comfy-Desktop" -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'node' } | Select-Object -First 1
if ($hit) { $py = $hit.FullName }
if (-not $py) { Write-Output 'PYTHON NOT FOUND'; exit 1 }
Write-Output "python: $py"
New-Item -ItemType Directory -Force -Path (Join-Path $train 'drop') | Out-Null
& $py (Join-Path $train 'ingest_drop.py')
Write-Output "exit: $LASTEXITCODE"
