# run_train2.ps1: tegakisk 作風LoRA学習 (1264枚版: 繰り返し1, 2エポック, 約2528ステップ)
# v1の失敗修正: --output_dir は変数を事前計算して渡す (引数モードで (Join-Path ...) は評価されない)
$ErrorActionPreference = 'Continue'
$train = Join-Path $env:USERPROFILE 'pc1-train'
$pkgs = Join-Path $train 'pkgs'
$sds = Join-Path $train 'sd-scripts'

$py = $null
$hit = Get-ChildItem "$env:LOCALAPPDATA\Comfy-Desktop" -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'node' } | Select-Object -First 1
if ($hit) { $py = $hit.FullName }
if (-not $py) { Write-Output 'PYTHON NOT FOUND'; exit 1 }

$modelsDir = $null
$cfgPath = Join-Path $env:USERPROFILE 'pc1-agent\config.json'
if (Test-Path $cfgPath) { try { $modelsDir = (Get-Content $cfgPath -Raw | ConvertFrom-Json).modelsDir } catch {} }
if (-not $modelsDir) {
    $h = Get-ChildItem "$env:LOCALAPPDATA\Comfy-Desktop" -Directory -Recurse -Depth 6 -Filter 'checkpoints' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($h) { $modelsDir = $h.Parent.FullName }
}
if (-not $modelsDir) { Write-Output 'MODELS DIR NOT FOUND'; exit 1 }
$base = Join-Path $modelsDir 'checkpoints\waiNSFWIllustrious_v14.safetensors'
if (-not (Test-Path $base)) { Write-Output "BASE MODEL NOT FOUND: $base"; exit 1 }
$outDir = Join-Path $modelsDir 'loras'
$dataDir = Join-Path $train 'data'
$imgCount = (Get-ChildItem (Join-Path $dataDir '1_tegakisk') -Filter '*.jpg' -ErrorAction SilentlyContinue).Count
Write-Output "python: $py"
Write-Output "models: $modelsDir"
Write-Output "dataset images (1_tegakisk): $imgCount"
if ($imgCount -lt 10) { Write-Output 'DATASET TOO SMALL'; exit 1 }

$env:PYTHONPATH = "$pkgs;$sds"
Push-Location $sds
& $py sdxl_train_network.py `
  --pretrained_model_name_or_path=$base `
  --train_data_dir=$dataDir `
  --resolution=1024,1024 --enable_bucket --min_bucket_reso=512 --max_bucket_reso=1536 --bucket_reso_steps=64 `
  --output_dir=$outDir --output_name=tegakisk `
  --network_module=networks.lora --network_dim=32 --network_alpha=16 `
  --learning_rate=1e-4 --unet_lr=1e-4 `
  --lr_scheduler=cosine --lr_warmup_steps=50 `
  --optimizer_type=adamw --mixed_precision=fp16 --gradient_checkpointing `
  --cache_latents --cache_text_encoder_outputs --network_train_unet_only `
  --max_train_epochs=2 --save_every_n_epochs=1 --seed=42 `
  --full_fp16 --sdpa `
  --save_model_as=safetensors --flip_aug
$code = $LASTEXITCODE
Pop-Location
Write-Output "train exit: $code"
Get-ChildItem $outDir -Filter 'tegakisk*' | ForEach-Object { Write-Output "OUT: $($_.FullName) $($_.Length)" }
Write-Output 'TRAIN_SCRIPT_DONE'
