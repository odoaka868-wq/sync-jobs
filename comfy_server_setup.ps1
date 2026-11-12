# comfy_server_setup.ps1: ComfyUI を Desktop アプリから切り離し、常駐サーバーとして登録する
# ランチャーはポート8188が空くのを待ってサーバーを起動し、落ちたら5秒後に自動再起動する。
# このタスクは ONLOGON でも起動するので、再起動後も自動で復帰する。
$ErrorActionPreference = 'Continue'
$train = Join-Path $env:USERPROFILE 'pc1-train'
$logs = Join-Path $train 'logs'
New-Item -ItemType Directory -Force -Path $train, $logs | Out-Null

# ComfyUI ルート (main.py のある場所) を特定
$modelsDir = $null
$cfgPath = Join-Path $env:USERPROFILE 'pc1-agent\config.json'
if (Test-Path $cfgPath) { try { $modelsDir = (Get-Content $cfgPath -Raw | ConvertFrom-Json).modelsDir } catch {} }
if (-not $modelsDir) {
    $h = Get-ChildItem "$env:LOCALAPPDATA\Comfy-Desktop" -Directory -Recurse -Depth 6 -Filter 'checkpoints' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($h) { $modelsDir = $h.Parent.FullName }
}
if (-not $modelsDir) { Write-Output 'MODELS DIR NOT FOUND'; exit 1 }
$comfyRoot = Split-Path $modelsDir -Parent
if (-not (Test-Path (Join-Path $comfyRoot 'main.py'))) { Write-Output "main.py NOT FOUND under $comfyRoot"; exit 1 }
Write-Output "comfyRoot: $comfyRoot"

$py = $null
$hit = Get-ChildItem "$env:LOCALAPPDATA\Comfy-Desktop" -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'node' } | Select-Object -First 1
if ($hit) { $py = $hit.FullName }
if (-not $py) { Write-Output 'PYTHON NOT FOUND'; exit 1 }
Write-Output "python: $py"

$launcher = Join-Path $train 'comfy_launcher.ps1'
$body = @"
`$py = '$py'
`$root = '$comfyRoot'
`$log = Join-Path `$env:USERPROFILE 'pc1-train\logs\comfy_server.log'
while (`$true) {
    `$busy = Get-NetTCPConnection -LocalPort 8188 -State Listen -ErrorAction SilentlyContinue
    if (`$busy) { Start-Sleep -Seconds 60; continue }
    Add-Content `$log "`$(Get-Date -Format s) starting comfy server"
    Push-Location `$root
    & `$py 'main.py' --listen 0.0.0.0 --port 8188 >> `$log 2>&1
    Pop-Location
    Add-Content `$log "`$(Get-Date -Format s) server exited; restart in 5s"
    Start-Sleep -Seconds 5
}
"@
Set-Content -Path $launcher -Value $body -Encoding UTF8
Write-Output "launcher written: $launcher"

$action = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
schtasks /Create /F /TN 'comfy-server' /TR $action /SC ONLOGON | Out-Null
Write-Output 'scheduled task comfy-server registered (ONLOGON)'

$already = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*comfy_launcher*' }
if (-not $already) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $launcher) -WindowStyle Hidden
    Write-Output 'launcher started now'
} else {
    Write-Output 'launcher already running'
}
Write-Output 'COMFY_SERVER_SETUP_DONE'
