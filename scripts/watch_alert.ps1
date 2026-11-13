# 수집 문제 알림 (문제가 있을 때만 슬랙 #test 로)
#  - ⚠️ 이미 지나가서 더는 받을 수 없게 된 시간대가 비어 있으면 한 번 알림
#    (서울시 실시간 자료는 약 1시간 반 뒤 다음 시각으로 넘어가 다시 받을 수 없음)
#  - ✅ 그 뒤 새 시간대를 다시 받기 시작하면 한 번 알림
#  - 보낸 알림은 data/status/알림기록.csv 에 남겨 같은 내용을 두 번 보내지 않음
#  이어달리기(run_loop.ps1)가 10분마다 부름. 슬랙 주소는 GitHub 비밀값 SLACK_WEBHOOK_TEST.
#  사용: ./scripts/watch_alert.ps1            (확인하고 필요하면 보냄)
#        ./scripts/watch_alert.ps1 -Test      (시험 알림 한 통)
#        ./scripts/watch_alert.ps1 -At '2026-11-10 15:20' -DryRun   (그 시각이라고 치고, 보내지 않고 내용만)

param([switch]$Test, [string]$At, [switch]$DryRun, [string]$From = '2026-11-10 12:00')

. "$PSScriptRoot/common.ps1"
. "$PSScriptRoot/collection_quality.ps1"

$AlertFrom = [datetime]::ParseExact($From, 'yyyy-MM-dd HH:mm', $null)   # 이 시각 이전 시간대는 알리지 않음 (알림을 만든 때)
$logPath = Join-Path $RepoRoot 'data/status/알림기록.csv'
$kst = if ($At) { [datetime]::ParseExact($At, 'yyyy-MM-dd HH:mm', $null) } else { Get-KstNow }

function Send-Alert([string]$text) {
    if ($DryRun) { Write-Host "[보내지 않음] $text"; return $true }
    $py = @(Get-Command python3, python -ErrorAction SilentlyContinue | Select-Object -First 1)[0]
    if (-not $py) { Write-Host "::warning::파이썬이 없어 알림을 못 보냄"; return $false }
    & $py.Source -X utf8 (Join-Path $RepoRoot 'bots/post_slack.py') --text $text test | Write-Host
    return ($LASTEXITCODE -eq 0)
}
function Add-AlertLog([string]$kind, [string[]]$slots) {
    if ($DryRun) { return }
    Add-CsvRows $logPath @([pscustomobject][ordered]@{ '보낸시각' = $kst.ToString('yyyy-MM-dd HH:mm'); '종류' = $kind; '시간대' = ($slots -join ' ') })
}
function Show-Slot([string]$s) { "$([int]$s.Substring(5,2))/$([int]$s.Substring(8,2)) $($s.Substring(11,2))시" }

if ($Test) {
    $ok = Send-Alert "🔔 [서울 데이터] 시험 알림이에요. 앞으로 GitHub 자동 수집에서 시간대를 놓치면 ⚠️, 다시 받기 시작하면 ✅ 알림이 여기로 와요. ($($kst.ToString('M/d HH:mm')))"
    if ($ok) { Write-Host "시험 알림 보냄" }
    return
}

# 저장된 시간대 (노트북·GitHub 모두, 받은 곳 1곳 이상)
# 재시도 시간을 준 뒤 장소 단위 누락도 한 번만 알립니다. 새 검사표가 있는 시간만 대상입니다.
$checks = @(Read-Csv (Join-Path $RepoRoot 'data/status/수집완료검사.csv'))
$partialLog = @(Read-Csv $logPath)
$partialGaps = @(Get-FinalPartialGaps $checks $partialLog $kst)
if ($partialGaps.Count) {
    if (Send-Alert (Get-PartialAlertText $partialGaps)) {
        foreach ($gap in $partialGaps) { Add-AlertLog '부분누락' @($gap.'시간대') }
    }
}
$saved = @{}
foreach ($r in (Read-Csv (Join-Path $RepoRoot 'data/status/수집기록.csv'))) {
    if ("$($r.'인구기준시각')".Length -ge 13 -and [int]"0$($r.'성공')" -gt 0) { $saved[$r.'인구기준시각'.Substring(0, 13)] = $true }
}
$log = @(Read-Csv $logPath)
$alerted = @{}; foreach ($r in $log) { if ($r.'종류' -eq '누락') { foreach ($s in ("$($r.'시간대'.Trim())" -split '\s+(?=\d{4}-)')) { if ($s) { $alerted[$s] = $true } } } }

# 이미 알렸지만 아직 '복구' 알림을 안 보낸 시간대 (문제가 이어지는 중)
$open = New-Object System.Collections.Generic.List[string]
foreach ($r in $log) {
    if ($r.'종류' -eq '복구') { $open.Clear() }
    elseif ($r.'종류' -eq '누락') { foreach ($s in ("$($r.'시간대'.Trim())" -split '\s+(?=\d{4}-)')) { if ($s) { $open.Add($s) } } }
}
$latest = @($saved.Keys | Sort-Object | Select-Object -Last 1)[0]   # 가장 최근에 저장한 시간대

# 1) 새로 놓친 시간대: 1~8시간 전 시간대 중 비어 있고 아직 기록 안 한 것.
#    끝난 지 1시간 50분이 지났거나, 그보다 늦은 시간대를 이미 받았으면 더는 받을 수 없으니 '놓침'으로 봄
$missing = @(@(foreach ($h in 1..8) {
    $t = $kst.Date.AddHours($kst.Hour - $h)
    $slot = $t.ToString('yyyy-MM-dd HH')
    if ($t -ge $AlertFrom -and -not $saved[$slot] -and -not $alerted[$slot] -and ($kst -ge $t.AddMinutes(110) -or $latest -gt $slot)) { $slot }
}) | Sort-Object)
$allMissed = @(@($open) + $missing | Sort-Object -Unique)
$recovered = $allMissed.Count -and $latest -gt $allMissed[-1]   # 놓친 시간 뒤로 새 시간대를 받음
$names = ($allMissed | ForEach-Object { Show-Slot $_ }) -join ', '

if ($open.Count -and $recovered) {
    # 앞서 ⚠️를 보낸 문제가 끝남 → 놓친 시간을 모아 ✅ 한 통
    $txt = "✅ [서울 데이터] 다시 정상으로 받고 있어요. $(Show-Slot $latest) 자료까지 저장했어요. (못 받은 시간: $names — 노트북이 켜져 있으면 노트북 자료로 채울 수 있어요)"
    if (Send-Alert $txt) { if ($missing.Count) { Add-AlertLog '누락' $missing }; Add-AlertLog '복구' @($latest); Write-Host "복구 알림 보냄: $names" }
} elseif ($missing.Count -and $recovered) {
    # 2) 놓쳤지만 이미 다시 받고 있음 → 한 통
    $txt = "⚠️ [서울 데이터] GitHub 자동 수집이 $names 자료를 놓쳤어요. 지금은 다시 정상으로 받고 있어요 ($(Show-Slot $latest)까지 저장). 노트북이 켜져 있으면 놓친 시간은 노트북 자료로 채울 수 있어요."
    if (Send-Alert $txt) { Add-AlertLog '누락' $missing; Add-AlertLog '복구' @($latest); Write-Host "누락(이미 복구) 알림 보냄: $names" }
} elseif ($missing.Count -and -not $open.Count) {
    # 3) 문제가 처음 생김 → 한 통 (이어지는 동안은 조용히 기록만)
    $txt = "⚠️ [서울 데이터] GitHub 자동 수집이 $names 자료를 받지 못했어요. 10분마다 계속 다시 시도하고 있고, 다시 받기 시작하면 알려 드릴게요. 노트북이 켜져 있으면 노트북 자료로 채울 수 있어요."
    if (Send-Alert $txt) { Add-AlertLog '누락' $missing; Write-Host "누락 알림 보냄: $names" }
} elseif ($missing.Count) {
    Add-AlertLog '누락' $missing; Write-Host "문제가 이어지는 중 (조용히 기록): $($missing -join ', ')"
} elseif ($recovered) {
    # 4) 앞서 알린 문제 뒤로 새 시간대를 다시 받기 시작함 → 놓친 시간을 모아 한 통
    $txt = "✅ [서울 데이터] 다시 정상으로 받고 있어요. $(Show-Slot $latest) 자료까지 저장했어요. (못 받은 시간: $names)"
    if (Send-Alert $txt) { Add-AlertLog '복구' @($latest); Write-Host "복구 알림 보냄" }
} else {
    Write-Host "수집 문제 없음"
}
