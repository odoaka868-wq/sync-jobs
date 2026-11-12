# setup_fix2.ps1: accelerate を kohya 実績バージョンに固定し、落ちた箇所を単体で再現テストする
$ErrorActionPreference = 'Continue'
$train = Join-Path $env:USERPROFILE 'pc1-train'
$pkgs = Join-Path $train 'pkgs'
$sds = Join-Path $train 'sd-scripts'

$py = $null
$hit = Get-ChildItem "$env:LOCALAPPDATA\Comfy-Desktop" -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'node' } | Select-Object -First 1
if ($hit) { $py = $hit.FullName }
if (-not $py) { Write-Output 'PYTHON NOT FOUND'; exit 1 }
Write-Output "python: $py"

Write-Output '--- pip install accelerate==1.10.1 into pkgs ---'
& $py -m pip install --target $pkgs --upgrade 'accelerate==1.10.1'
Write-Output "pip exit: $LASTEXITCODE"

$env:PYTHONPATH = "$pkgs;$sds"
Write-Output '--- accelerate version + PartialState smoke test ---'
& $py -c "import accelerate; print('accelerate:', accelerate.__version__); from accelerate import Accelerator; a = Accelerator(mixed_precision='fp16'); print('device:', a.device); print('num_processes:', a.num_processes); print('SMOKE_OK')"
Write-Output "smoke exit: $LASTEXITCODE"
Write-Output 'SETUP_FIX2_DONE'
