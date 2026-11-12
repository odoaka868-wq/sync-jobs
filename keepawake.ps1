# keepawake.ps1: このプロセスが生きている間、Windowsのスリープを抑止する (設定変更なし)
$ErrorActionPreference = 'Continue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Power {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@
$ES_CONTINUOUS = [uint32]2147483648
$ES_SYSTEM_REQUIRED = [uint32]1
$r = [Power]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)
Write-Output "keepawake set, prev state: $r"
Write-Output "holding for 6 hours from $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Start-Sleep -Seconds 21600
[Power]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
Write-Output 'keepawake released'
