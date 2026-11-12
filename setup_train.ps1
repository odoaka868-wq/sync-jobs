# setup_train.ps1: pc1 に LoRA 学習環境 (kohya sd-scripts + 依存) を構築する
$ErrorActionPreference = 'Continue'
$train = Join-Path $env:USERPROFILE 'pc1-train'
$pkgs = Join-Path $train 'pkgs'
$sds = Join-Path $train 'sd-scripts'
New-Item -ItemType Directory -Force -Path $train, $pkgs | Out-Null

function Find-Python {
    $roots = @("$env:LOCALAPPDATA\Comfy-Desktop")
    foreach ($r in $roots) {
        if (Test-Path $r) {
            $hit = Get-ChildItem $r -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch 'node' } | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}
$py = Find-Python
if (-not $py) { Write-Output 'PYTHON NOT FOUND'; exit 1 }
Write-Output "python: $py"
& $py --version
& $py -c "import torch; print('torch', torch.__version__); print('cuda_avail', torch.cuda.is_available()); print('device', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')"
& $py -m pip --version
if ($LASTEXITCODE -ne 0) { Write-Output 'pip missing, trying ensurepip'; & $py -m ensurepip --default-pip; & $py -m pip --version }

if (-not (Test-Path (Join-Path $sds 'sdxl_train_network.py'))) {
    $zip = Join-Path $train 'sd-scripts.zip'
    Write-Output 'downloading sd-scripts...'
    & curl.exe -L --retry 3 -o $zip 'https://codeload.github.com/kohya-ss/sd-scripts/zip/refs/heads/main'
    if ($LASTEXITCODE -ne 0) { Write-Output 'SD-SCRIPTS DOWNLOAD FAILED'; exit 1 }
    $tmp = Join-Path $train 'sds_tmp'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (Test-Path $sds) { Remove-Item $sds -Recurse -Force }
    Move-Item $inner.FullName $sds
    Remove-Item $tmp -Recurse -Force
    Write-Output "sd-scripts extracted: $sds"
}
$req = Join-Path $sds 'requirements.txt'
$filtered = Join-Path $train 'requirements_filtered.txt'
$lines = Get-Content $req | Where-Object {
    $_ -notmatch '^(torch|torchvision|xformers|bitsandbytes)' -and $_ -notmatch '^-' -and $_.Trim() -ne ''
} | ForEach-Object { $_ -replace '^diffusers\[.*?\](==|>=|<=|~=)?.*$', 'diffusers' }
$lines | Set-Content $filtered -Encoding UTF8
Write-Output 'filtered requirements:'
$lines | ForEach-Object { Write-Output "  $_" }
& $py -m pip install --target $pkgs -r $filtered
Write-Output "pip install exit: $LASTEXITCODE"

$env:PYTHONPATH = "$pkgs;$sds"
Push-Location $sds
& $py sdxl_train_network.py --help 2>&1 | Select-Object -First 15
Write-Output "help exit: $LASTEXITCODE"
Pop-Location
Write-Output 'SETUP_DONE'
