# setup_fix.ps1: pkgs内の素のtorchがvenvのROCm torchを隠している問題を直し、学習環境を再検証する
$ErrorActionPreference = 'Continue'
$train = Join-Path $env:USERPROFILE 'pc1-train'
$pkgs = Join-Path $train 'pkgs'
$scripts = Join-Path $train 'sd-scripts'

$py = $null
$hit = Get-ChildItem "$env:LOCALAPPDATA\Comfy-Desktop" -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'node' } | Select-Object -First 1
if ($hit) { $py = $hit.FullName }
if (-not $py) { Write-Output 'PYTHON NOT FOUND'; exit 1 }
Write-Output "python: $py"

$env:PYTHONPATH = "$pkgs;$scripts"
Write-Output '--- torch BEFORE fix ---'
& $py -c "import torch; print('ver:', torch.__version__); print('file:', torch.__file__); print('cuda:', torch.cuda.is_available())"
Write-Output "torch-before exit: $LASTEXITCODE"

Write-Output '--- removing shadowing torch dirs from pkgs ---'
foreach ($name in @('torch','torchvision','torchgen','functorch')) {
    $p = Join-Path $pkgs $name
    if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue; Write-Output "removed $name" }
}
Get-ChildItem $pkgs -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(torch|torchvision)' } |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; Write-Output "removed $($_.Name)" }

Write-Output '--- torch AFTER fix ---'
& $py -c "import torch; print('ver:', torch.__version__); print('file:', torch.__file__); print('cuda:', torch.cuda.is_available()); print('device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')"
Write-Output "torch-after exit: $LASTEXITCODE"

Write-Output '--- sdxl_train_network.py --help (full output) ---'
& $py (Join-Path $scripts 'sdxl_train_network.py') --help
Write-Output "help exit: $LASTEXITCODE"
Write-Output 'SETUP_FIX_DONE'
