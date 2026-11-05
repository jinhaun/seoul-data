# GitHub Actions 이어달리기: 정해진 시간(분) 동안 10분마다 한 바퀴씩 돌고 끝냅니다.
# (끝난 뒤 다음 주자를 실행하는 건 워크플로의 마지막 단계가 함)
# GitHub 예약 실행은 붐비면 건너뛰어서(11/3~11/5 하루 몇 번만 실행됨), 한 번 실행되면 오래 켜 두는 방식으로 바꿈.
#
# 한 바퀴:
#  1) 최신 저장소 받기
#  2) 실시간 121곳 (그 시간대가 이미 있으면 바로 끝남)
#  3) 아침 9시 이후 오늘 매일 작업을 아직 안 했으면: 행사·숙박·외국인·환율 + 항공(어제·오늘)
#  4) 바뀐 게 있으면: 사이트 요약 → 원본을 Releases에 보관 → 저장소에 올리기

param([int]$Minutes = 330)

. "$PSScriptRoot/common.ps1"
Set-Location $RepoRoot
$end = (Get-Date).AddMinutes($Minutes)

function Invoke-Git([string[]]$a) { & git @a 2>&1 | ForEach-Object { "$_" } | Write-Host; return $LASTEXITCODE }

function Invoke-Cycle {
    Invoke-Git @('pull', '--rebase', '-q') | Out-Null

    # 2) 실시간
    & "$PSScriptRoot/collect_hourly.ps1"

    # 3) 매일 작업 (9시 이후, 오늘 기록이 없을 때만)
    $now = Get-KstNow; $today = $now.ToString('yyyy-MM-dd')
    $log = Join-Path $RepoRoot 'data/status/매일작업기록.csv'
    $done = (Test-Path $log) -and (Select-String -Path $log -Pattern ",`"$today`"," -SimpleMatch -Quiet)
    if ($now.Hour -ge 9 -and -not $done) {
        Write-Host "매일 작업 시작 ($today)"
        & "$PSScriptRoot/daily.ps1"
        & "$PSScriptRoot/flights.ps1" -Date $now.Date.AddDays(-1).ToString('yyyy-MM-dd')
        & "$PSScriptRoot/flights.ps1" -Date $today
    }

    # 4) 바뀐 게 있을 때만 사이트 요약·보관·올리기
    if (-not (git status --porcelain -- data)) { Write-Host "바뀐 자료 없음"; return }
    & "$PSScriptRoot/build_site_data.ps1"

    $rawDir = Join-Path $RepoRoot 'tmp/raw'
    if (Test-Path $rawDir) {
        foreach ($f in (Get-ChildItem $rawDir -Filter '*.json.gz')) {
            $month = $f.Name.Substring(0, 7); $tag = "raw-$month"
            gh release view $tag *> $null
            if ($LASTEXITCODE -ne 0) { gh release create $tag --title "원본 $month" --notes "1시간마다 받은 서울 실시간 도시데이터 원본 (gzip JSON, 121곳)" *> $null }
            gh release upload $tag $f.FullName --clobber *> $null
            if ($LASTEXITCODE -eq 0) { Remove-Item $f.FullName } else { Write-Host "::warning::원본 보관 실패: $($f.Name)" }
        }
    }

    git add data site
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { return }
    git commit -q -m ("실시간 수집 " + (Get-KstNow).ToString('yyyy-MM-dd HH:mm'))
    for ($i = 1; $i -le 3; $i++) {
        if ((Invoke-Git @('pull', '--rebase', '-q')) -eq 0 -and (Invoke-Git @('push', '-q')) -eq 0) { Write-Host "저장소에 올림"; return }
        Start-Sleep -Seconds 10
    }
    Write-Host "::warning::저장소에 올리기 실패 (다음 바퀴에 다시 시도)"
}

while ($true) {
    try { Invoke-Cycle } catch { Write-Host "::warning::한 바퀴 실패: $($_.Exception.Message)" }
    if ((Get-Date).AddMinutes(10) -ge $end) { break }
    Start-Sleep -Seconds 600
}
Write-Host "이번 주자 끝 ($Minutes 분)"
