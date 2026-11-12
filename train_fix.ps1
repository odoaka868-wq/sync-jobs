# train_fix.ps1: データセットが1264枚に増えたので繰り返し数を5->1に変更 (フォルダ名リネーム)
$ErrorActionPreference = 'Continue'
$data = Join-Path $env:USERPROFILE 'pc1-train\data'
$old = Join-Path $data '5_tegakisk'
$new = Join-Path $data '1_tegakisk'
if ((Test-Path $old) -and -not (Test-Path $new)) {
    Rename-Item $old $new
    Write-Output "renamed 5_tegakisk -> 1_tegakisk"
} elseif ((Test-Path $new) -and -not (Test-Path $old)) {
    Write-Output 'already renamed'
} else {
    Write-Output "UNEXPECTED STATE: old=$(Test-Path $old) new=$(Test-Path $new)"
    exit 1
}
$count = (Get-ChildItem $new -Filter '*.jpg' -ErrorAction SilentlyContinue).Count
Write-Output "images in 1_tegakisk: $count"
Write-Output 'TRAIN_FIX_DONE'
