# pc1-agent v4: (1) GitHub jobs.json (2) ComfyUI input inbox (musejob_*.png) の2経路でジョブを受ける常駐係
# v4変更点: inbox経路の追加 (GitHub書き込み不要化), state読み書きの堅牢化 (PS5.1互換・アトミック保存),
#           curl --fail, run起動の引用符とStartTime併用生存判定, ジョブIDの文字列統一
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

# ---------- state ----------
function Load-State {
    $h = @{}
    if (-not (Test-Path $statePath)) { return $h }
    $raw = Get-Content $statePath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $h }
    $obj = $raw | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) { $h[[string]$p.Name] = [string]$p.Value }
    return $h
}
function Save-State {
    $tmp = "$statePath.tmp"
    [IO.File]::WriteAllText($tmp, ($script:state | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding $false))
    if (Test-Path $statePath) { [IO.File]::Replace($tmp, $statePath, "$statePath.bak") }
    else { [IO.File]::Move($tmp, $statePath) }
}
try { $script:state = Load-State } catch {
    Log "state.json parse failed, abort tick: $($_.Exception.Message)"
    try { Move-Item $statePath ("$statePath.bad-" + (Get-Date -Format 'yyyyMMddHHmmss')) -Force } catch {}
    return
}

# ---------- models フォルダ特定 ----------
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

function Fetch-File($job, $dest) {
    $tmp = "$dest.part"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $curlArgs = @('-L', '--fail', '--retry', '3', '-o', $tmp)
    if ($job.auth -eq 'civitai') {
        if (-not (Test-Path $tokenPath)) { throw 'no civitai token' }
        $tok = (Get-Content $tokenPath -Raw).Trim()
        $curlArgs += @('-H', "Authorization: Bearer $tok")
    }
    $curlArgs += [string]$job.url
    & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
    if ($job.size_bytes -and ((Get-Item $tmp -ErrorAction Stop).Length -ne [int64]$job.size_bytes)) { throw "size mismatch: $((Get-Item $tmp).Length) vs $($job.size_bytes)" }
    Move-Item -Force $tmp $dest -ErrorAction Stop
}

# ---------- run ジョブの完了確認 (PID + StartTime) ----------
foreach ($key in @($script:state.Keys)) {
    $val = [string]$script:state[$key]
    if ($val -notlike 'running:*') { continue }
    $parts = $val.Split([char]':', 4)
    $pidNum = 0; [void][int]::TryParse($parts[1], [ref]$pidNum)
    $logName = $parts[$parts.Length - 1]
    $alive = $false
    if ($pidNum -gt 0) {
        $p = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
        if ($p) {
            if ($parts.Length -ge 4) {
                try { $alive = [math]::Abs($p.StartTime.ToUniversalTime().Ticks - [int64]$parts[2]) -lt 10000000 } catch { $alive = $true }
            } else { $alive = $true }
        }
    }
    if ($alive) { continue }
    $ok = $true
    foreach ($ext in @('out','err')) {
        $src = Join-Path $trainLogs "$logName.$ext.txt"
        if (Test-Path $src) {
            try { Copy-Item $src (Join-Path $agentLogOut "$logName.$ext.txt") -Force -ErrorAction Stop }
            catch { $ok = $false; Log "copy failed ${src}: $($_.Exception.Message)" }
        }
    }
    if ($ok) { $script:state[$key] = 'done:' + (Get-Date -Format 's'); Log "run finished $key (pid $pidNum), logs copied" }
}
Save-State

# ---------- ジョブ処理 ----------
function Process-Job($job) {
    $jid = [string]$job.id
    if ([string]::IsNullOrWhiteSpace($jid)) { Log 'skip: job without id'; return }
    if ($script:state.ContainsKey($jid)) { return }
    $kind = if ($job.kind) { [string]$job.kind } else { 'download' }
    try {
        if ($kind -eq 'download') {
            $fname = [IO.Path]::GetFileName([string]$job.filename)
            if ($allowedDest -notcontains [string]$job.dest) { Log "skip $jid`: dest not allowed"; return }
            $u = [Uri]([string]$job.url)
            if ($allowedHosts -notcontains $u.Host) { Log "skip $jid`: host not allowed $($u.Host)"; return }
            $destDir = Join-Path $modelsDir ([string]$job.dest)
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            $dest = Join-Path $destDir $fname
            Fetch-File $job $dest
            $script:state[$jid] = (Get-Date -Format 's')
            Log "done $jid -> $dest"
        } elseif ($kind -eq 'put') {
            $fname = [IO.Path]::GetFileName([string]$job.filename)
            $u = [Uri]([string]$job.url)
            if ($allowedHosts -notcontains $u.Host) { Log "skip $jid`: host not allowed $($u.Host)"; return }
            $base = if ([string]$job.dest -eq 'agent') { $dir } else { $trainDir }
            $dest = Join-Path $base $fname
            Fetch-File $job $dest
            $script:state[$jid] = (Get-Date -Format 's')
            Log "put $jid -> $dest"
        } elseif ($kind -eq 'run') {
            $script = Join-Path $trainDir ([IO.Path]::GetFileName([string]$job.script))
            if (-not (Test-Path $script)) { Log "skip $jid`: script not found $script"; return }
            $rawLog = if ($job.log) { [string]$job.log } else { $jid }
            $logName = [IO.Path]::GetFileName($rawLog) -replace '[:\s]', '_'
            $outLog = Join-Path $trainLogs "$logName.out.txt"
            $errLog = Join-Path $trainLogs "$logName.err.txt"
            $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $script
            $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -WorkingDirectory $trainDir -RedirectStandardOutput $outLog -RedirectStandardError $errLog -WindowStyle Hidden -PassThru -ErrorAction Stop
            if (-not $proc -or -not $proc.Id) { throw 'Start-Process returned no process' }
            $startTicks = $proc.StartTime.ToUniversalTime().Ticks
            $script:state[$jid] = "running:$($proc.Id):${startTicks}:$logName"
            Log "run started $jid pid $($proc.Id) script $script"
        } else {
            Log "skip $jid`: unknown kind $kind"
        }
    } catch {
        Log "FAILED $jid`: $($_.Exception.Message)"
    }
    Save-State
}

# ---------- 経路1: GitHub manifest ----------
try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -TimeoutSec 30
    if ($manifest.jobs) { foreach ($job in $manifest.jobs) { Process-Job $job } }
} catch { Log "manifest fetch failed: $($_.Exception.Message)" }

# ---------- 経路2: ComfyUI input inbox (musejob_*.png = JSONバンドル) ----------
$inboxDir = Join-Path $comfyRoot 'input'
$doneDir = Join-Path $trainDir 'inbox_done'
New-Item -ItemType Directory -Force -Path $doneDir | Out-Null
foreach ($file in @(Get-ChildItem $inboxDir -Filter 'musejob_*.png' -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $bundle = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($f in @($bundle.files)) {
            if (-not $f) { continue }
            $fname = [IO.Path]::GetFileName([string]$f.name)
            $base = if ([string]$f.dest -eq 'agent') { $dir } else { $trainDir }
            $bytes = [Convert]::FromBase64String([string]$f.content_b64)
            [IO.File]::WriteAllBytes((Join-Path $base $fname), $bytes)
            Log "inbox file $($file.Name) -> $fname"
        }
        foreach ($job in @($bundle.jobs)) { if ($job) { Process-Job $job } }
        Move-Item $file.FullName (Join-Path $doneDir $file.Name) -Force
        Log "inbox processed $($file.Name)"
    } catch {
        Log "inbox FAILED $($file.Name): $($_.Exception.Message)"
        try { Move-Item $file.FullName (Join-Path $doneDir ($file.Name + '.bad')) -Force } catch {}
    }
    Save-State
}
Save-State
