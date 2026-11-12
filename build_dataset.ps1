# build_dataset.ps1: ComfyUI同梱Pythonで build_dataset.py を実行する
$ErrorActionPreference = 'Continue'
$train = Join-Path $env:USERPROFILE 'pc1-train'
$py = $null
$roots = @("$env:LOCALAPPDATA\Comfy-Desktop")
foreach ($r in $roots) {
    if (Test-Path $r) {
        $hit = Get-ChildItem $r -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch 'node' } | Select-Object -First 1
        if ($hit) { $py = $hit.FullName; break }
    }
}
if (-not $py) { Write-Output 'PYTHON NOT FOUND'; exit 1 }
Write-Output "python: $py"
& $py (Join-Path $train 'build_dataset.py')
Write-Output "exit: $LASTEXITCODE"
