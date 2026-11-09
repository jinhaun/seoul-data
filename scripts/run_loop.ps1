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

# 저장소를 GitHub 최신 상태로 맞춤. 노트북에서 같은 파일을 고쳐 올려 부딪혀도 여기서 정리됨.
# (이 바퀴에 받은 자료가 버려져도 수집기록에 남지 않으므로 다음 바퀴에 그 시간대를 다시 받음)
function Reset-ToRemote {
    if (Test-Path (Join-Path $RepoRoot '.git/rebase-merge')) { Invoke-Git @('rebase', '--abort') | Out-Null }
    if (Test-Path (Join-Path $RepoRoot '.git/rebase-apply')) { Invoke-Git @('rebase', '--abort') | Out-Null }
    Invoke-Git @('fetch', '-q', 'origin', 'main') | Out-Null
    Invoke-Git @('reset', '-q', '--hard', 'origin/main') | Out-Null
}

function Invoke-Cycle {
    Reset-ToRemote

    # 2) 실시간 (실패하면 바퀴 수를 셈 → 아래에서 연속 실패면 일찍 바통 넘김)
    & "$PSScriptRoot/collect_hourly.ps1"
    if ($LASTEXITCODE -ne 0) { $script:fails++ } else { $script:fails = 0 }

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

    # 3-1) 오늘 매일 작업이 이미 저장소에 올라가 있는데(= 이번 바퀴 시작 때 $done) 슬랙 게시를 아직 안 했으면
    #      → 슬랙 게시 워크플로 실행 (주자마다 한 번만). 올릴지 여부는 slack.yml이 bots/게시기록.csv를 보고 다시 판단함
    if ($done -and -not $script:slackAsked) {
        $plog = Join-Path $RepoRoot 'bots/게시기록.csv'
        $need = @('서울브리핑'); if ($now.DayOfWeek -eq 'Monday') { $need += '국가대항전', '주간리포트' }
        $left = @($need | Where-Object { -not ((Test-Path $plog) -and (Select-String -Path $plog -Pattern "`"$today`",`"$_`",`"(게시|보류)`"" -Quiet)) })
        if ($left) {
            gh workflow run slack.yml --ref main *> $null
            if ($LASTEXITCODE -eq 0) { Write-Host "슬랙 게시 실행 요청 ($($left -join ', '))"; $script:slackAsked = $true }
            else { Write-Host "::warning::슬랙 게시 실행 요청 실패 → 다음 바퀴에 다시" }
        }
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
        if ((Invoke-Git @('pull', '--rebase', '-q')) -ne 0) { break }   # 같은 파일이 부딪힘 → 아래에서 정리
        if ((Invoke-Git @('push', '-q')) -eq 0) { Write-Host "저장소에 올림"; return }
        Start-Sleep -Seconds 10
    }
    Write-Host "::warning::저장소에 올리기 실패 → 최신 상태로 되돌리고 다음 바퀴에 그 시간대를 다시 받음"
    Reset-ToRemote
}

$fails = 0
$slackAsked = $false
while ($true) {
    try { Invoke-Cycle } catch { $fails++; Write-Host "::warning::한 바퀴 실패: $($_.Exception.Message)" }
    # 같은 서버에서 서울시 접속이 두 바퀴 연속 안 되면 이 서버는 그만 쓰고 새 서버(다음 주자)로 넘김
    # (11/5 밤: 한 서버에서 5시간 반 동안 시간 초과만 반복해 20~0시를 못 받음)
    if ($fails -ge 2) { Write-Host "::warning::두 바퀴 연속 실패 → 일찍 다음 주자에게 넘김"; break }
    if ((Get-Date).AddMinutes(10) -ge $end) { break }
    Start-Sleep -Seconds 600
}
Write-Host "이번 주자 끝"
