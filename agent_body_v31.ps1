# pc1-agent v3: jobs.json を見て (1)モデル配置 (2)作業ファイル配置 (3)学習等のスクリプト実行 を行う常駐係
$ErrorActionPreference = 'Continue'
$dir = Join-Path $env:USERPROFILE 'pc1-agent'
$trainDir = Join-Path $env:USERPROFILE 'pc1-train'
$trainLogs = Join-Path $trainDir 'logs'
New-Item -ItemType Directory -Force -Path $trainDir, $trainLogs | Out-Null
$manifestUrl = 'https://raw.githubusercontent.com/odoaka868-wq/sync-jobs/main/jobs.json'
$statePath = Join-Path $dir 'state.json'
$logPath = Join-Path $dir 'agent.log'
$tokenPath = Join-Path $dir 'civitai_token.txt'
$configPath = Join-Path $dir 'config.json'
function Log($msg) { Add-Content -Path $logPath -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 }
try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -TimeoutSec 30
} catch { Log "manifest fetch failed: $($_.Exception.Message)"; return }
if (-not $manifest.jobs) { return }
$state = @{}
if (Test-Path $statePath) { try { $obj = Get-Content $statePath -Raw | ConvertFrom-Json; foreach ($p in $obj.PSObject.Properties) { $state[$p.Name] = [string]$p.Value } } catch { $state = @{} } }
# models フォルダの特定 (config にキャッシュ、無ければ探索)
$modelsDir = $null
if (Test-Path $configPath) { try { $modelsDir = (Get-Content $configPath -Raw | ConvertFrom-Json).modelsDir } catch {} }
if (-not $modelsDir -or -not (Test-Path $modelsDir)) {
    $candidates = @("$env:LOCALAPPDATA\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI\models", "$env:LOCALAPPDATA\Comfy-Desktop", "$env:USERPROFILE\Documents", "$env:USERPROFILE\ComfyUI")
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $hit = Get-ChildItem $c -Directory -Recurse -Depth 6 -Filter 'checkpoints' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { $modelsDir = $hit.Parent.FullName; break }
        }
    }
    if ($modelsDir) { @{ modelsDir = $modelsDir } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8 }
}
if (-not $modelsDir) { Log 'models dir not found'; return }
$comfyRoot = Split-Path $modelsDir -Parent
$agentLogOut = Join-Path $comfyRoot 'output\agentlogs'
New-Item -ItemType Directory -Force -Path $agentLogOut | Out-Null
$allowedDest = @('checkpoints','loras','vae','unet','controlnet','upscale_models','embeddings','clip')
$allowedHosts = @('huggingface.co','cdn-lfs.huggingface.co','civitai.com','raw.githubusercontent.com','github.com','codeload.github.com')
function Save-State { $state | ConvertTo-Json | Set-Content $statePath -Encoding UTF8 }
function Fetch-File($job, $dest) {
    $tmp = "$dest.part"
    $args = @('-L','--retry','3','-o',$tmp)
    if ($job.auth -eq 'civitai') {
        if (-not (Test-Path $tokenPath)) { throw 'no civitai token' }
        $tok = (Get-Content $tokenPath -Raw).Trim()
        $args += @('-H', "Authorization: Bearer $tok")
    }
    $args += [string]$job.url
    & curl.exe @args
    if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
    if ($job.size_bytes -and ((Get-Item $tmp).Length -ne [int64]$job.size_bytes)) { throw "size mismatch: $((Get-Item $tmp).Length) vs $($job.size_bytes)" }
    Move-Item -Force $tmp $dest
}
# 実行中 run ジョブの完了確認
foreach ($key in @($state.Keys)) {
    $val = [string]$state[$key]
    if ($val -like 'running:*') {
        $parts = $val.Split(':')
        $pidNum = [int]$parts[1]
        $logName = $parts[2]
        if (-not (Get-Process -Id $pidNum -ErrorAction SilentlyContinue)) {
            foreach ($ext in @('out','err')) {
                $src = Join-Path $trainLogs "$logName.$ext.txt"
                if (Test-Path $src) { Copy-Item $src (Join-Path $agentLogOut "$logName.$ext.txt") -Force }
            }
            $state[$key] = (Get-Date -Format 's')
            Log "run finished $key (pid $pidNum), logs copied"
        }
    }
}
Save-State
foreach ($job in $manifest.jobs) {
    if ($state.ContainsKey($job.id)) { continue }
    $kind = if ($job.kind) { [string]$job.kind } else { 'download' }
    try {
        if ($kind -eq 'download') {
            $fname = [IO.Path]::GetFileName([string]$job.filename)
            if ($allowedDest -notcontains [string]$job.dest) { Log "skip $($job.id): dest not allowed"; continue }
            $u = [Uri]([string]$job.url)
            if ($allowedHosts -notcontains $u.Host) { Log "skip $($job.id): host not allowed $($u.Host)"; continue }
            $destDir = Join-Path $modelsDir ([string]$job.dest)
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            $dest = Join-Path $destDir $fname
            Fetch-File $job $dest
            $state[$job.id] = (Get-Date -Format 's')
            Log "done $($job.id) -> $dest"
        } elseif ($kind -eq 'put') {
            $fname = [IO.Path]::GetFileName([string]$job.filename)
            $u = [Uri]([string]$job.url)
            if ($allowedHosts -notcontains $u.Host) { Log "skip $($job.id): host not allowed $($u.Host)"; continue }
            $base = if ([string]$job.dest -eq 'agent') { $dir } else { $trainDir }
            $dest = Join-Path $base $fname
            Fetch-File $job $dest
            $state[$job.id] = (Get-Date -Format 's')
            Log "put $($job.id) -> $dest"
        } elseif ($kind -eq 'run') {
            $script = Join-Path $trainDir ([IO.Path]::GetFileName([string]$job.script))
            if (-not (Test-Path $script)) { Log "skip $($job.id): script not found $script"; continue }
            $logName = if ($job.log) { [string]$job.log } else { [string]$job.id }
            $outLog = Join-Path $trainLogs "$logName.out.txt"
            $errLog = Join-Path $trainLogs "$logName.err.txt"
            $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $script) -WorkingDirectory $trainDir -RedirectStandardOutput $outLog -RedirectStandardError $errLog -WindowStyle Hidden -PassThru
            $state[$job.id] = "running:$($proc.Id):$logName"
            Log "run started $($job.id) pid $($proc.Id) script $script"
        } else {
            Log "skip $($job.id): unknown kind $kind"
        }
    } catch {
        Log "FAILED $($job.id): $($_.Exception.Message)"
    }
    Save-State
}
Save-State
