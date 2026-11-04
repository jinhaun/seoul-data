# 서울 실시간 도시데이터 121곳을 1시간에 한 번씩 저장합니다.
# GitHub이 예약 실행을 자주 건너뛰어서 10분마다 시도하고, 그 시간대(인구기준시각의 '시')가 이미 저장돼 있으면 바로 끝냅니다.
#  - data/realtime/YYYY-MM/YYYY-MM-DD.csv   : 장소별 요약 한 줄씩 (한 시간대에 한 묶음만)
#  - data/status/수집기록.csv               : 저장한 실행마다 성공/실패 기록
#  - tmp/raw/YYYY-MM-DD_HHmm.json.gz        : 원본 (워크플로가 Releases에 보관하고 저장소에는 넣지 않음)

. "$PSScriptRoot/common.ps1"

# 멈추면 이유를 GitHub 알림(누구나 볼 수 있음)으로 남김. 인증키는 *** 로 가림
function Hide-Key([string]$m) { if ($env:SEOUL_API_KEY) { $m = $m.Replace($env:SEOUL_API_KEY.Trim(), '***') }; return $m }
trap {
    Write-Host ("::error::수집 중단: " + (Hide-Key "$($_.Exception.Message) (collect_hourly.ps1 $($_.InvocationInfo.ScriptLineNumber)번째 줄)"))
    exit 1
}

$key  = Get-ApiKey
if ($env:GITHUB_ACTIONS) { Write-Host "::notice::인증키 확인 (길이 $($key.Length)자)" }
$now  = Get-KstNow
$collected = $now.ToString('yyyy-MM-dd HH:mm')
function Set-Saved([string]$v) { if ($env:GITHUB_OUTPUT) { "saved=$v" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8 } }
function Get-DayFile([datetime]$d) { Join-Path $RepoRoot ("data/realtime/" + (Get-DayPath $d) + '.csv') }
function Test-SlotSaved([string]$slot) {
    # slot = 'yyyy-MM-dd HH' : 그 시간대 묶음을 이미 저장했는지.
    # 표의 줄이 아니라 수집기록(묶음의 대표 기준시각)으로 판단함.
    # 서울시가 갱신하는 순간 받으면 13:55·14:00이 한 묶음에 섞이는데, 줄로 보면 14시를 이미 받은 것처럼 보이기 때문.
    return @(Read-Csv (Join-Path $RepoRoot 'data/status/수집기록.csv') |
        Where-Object { "$($_.'인구기준시각')".StartsWith($slot) -and [int]"0$($_.'성공')" -gt 0 } | Select-Object -First 1).Count -gt 0
}
Set-Saved 'false'

$spots = @(Get-Hotspots)
if ($spots.Count -eq 0) { throw '장소 목록이 비어 있습니다.' }

# 먼저 한 곳만 받아서 지금 자료가 몇 시 자료인지 확인
$probe = Get-Text ("http://openapi.seoul.go.kr:8088/$key/json/citydata/1/5/" + [Uri]::EscapeDataString("$($spots[0].'장소')")) $null
if ($probe -match '"PPLTN_TIME"\s*:\s*"(\d{4}-\d{2}-\d{2} \d{2}):\d{2}"') {
    $slot = $Matches[1]
    if (Test-SlotSaved $slot) { Write-Host "$($slot)시 자료는 이미 저장돼 있어서 끝냅니다."; exit 0 }
    Write-Host "$($slot)시 자료가 없어서 121곳을 받습니다."
}

$rawParts = New-Object System.Collections.Generic.List[string]
$rows     = New-Object System.Collections.Generic.List[object]
$failed   = New-Object System.Collections.Generic.List[string]
foreach ($s in $spots) {
    $name = "$($s.'장소')"
    try {
        $text = Get-Text ("http://openapi.seoul.go.kr:8088/$key/json/citydata/1/5/" + [Uri]::EscapeDataString($name)) $null
        if ($text -notmatch '"INFO-000"') { throw ('API 응답 오류: ' + $text.Substring(0, [Math]::Min(120, $text.Length))) }
        $j = $text | ConvertFrom-Json
        $rows.Add((New-RealtimeRow $j.CITYDATA $collected))
        $rawParts.Add($text)
    } catch {
        $failed.Add($name)
        $msg = Hide-Key "$($_.Exception.Message)"
        Write-Host "실패: $name - $msg"
        if ($failed.Count -le 3 -and $env:GITHUB_ACTIONS) { Write-Host "::warning::장소 실패 ($name): $msg" }
    }
}

# 서울시가 가끔 '정상'이라면서 인구 칸만 비워 보냄(일시적 공백). 1분 쉬고 그 장소만 다시 받음 (최대 2번)
for ($round = 1; $round -le 2; $round++) {
    $empty = @(for ($i = 0; $i -lt $rows.Count; $i++) { if (-not $rows[$i].'인구기준시각') { $i } })
    if ($empty.Count -eq 0) { break }
    Write-Host ("인구가 빈 곳 {0}곳, 1분 뒤 다시 받기 ({1}번째): {2}" -f $empty.Count, $round, (($empty | ForEach-Object { $rows[$_].'장소' }) -join ', '))
    Start-Sleep -Seconds 60
    foreach ($i in $empty) {
        $name = "$($rows[$i].'장소')"
        try {
            $text = Get-Text ("http://openapi.seoul.go.kr:8088/$key/json/citydata/1/5/" + [Uri]::EscapeDataString($name)) $null
            if ($text -notmatch '"INFO-000"') { continue }
            $r = New-RealtimeRow ($text | ConvertFrom-Json).CITYDATA $collected
            if ($r.'인구기준시각') { $rows[$i] = $r; $rawParts[$i] = $text; Write-Host "채움: $name ($($r.'인구기준시각'))" }
        } catch { Write-Host "다시 받기 실패: $name - $(Hide-Key "$($_.Exception.Message)")" }
    }
}
$stillEmpty = @($rows | Where-Object { -not $_.'인구기준시각' } | ForEach-Object { $_.'장소' })
if ($stillEmpty.Count -and $env:GITHUB_ACTIONS) { Write-Host "::notice::서울시가 인구를 비워 보낸 곳 (다시 받아도 빔): $($stillEmpty -join ', ')" }

# 인구 기준 시각(가장 많은 값)으로 날짜·파일 이름을 정함
$stampText = @($rows | Group-Object '인구기준시각' | Sort-Object Count -Descending | Select-Object -First 1).Name
$stamp = $null
if ($stampText) { try { $stamp = [datetime]::ParseExact($stampText, 'yyyy-MM-dd HH:mm', $null) } catch {} }
if (-not $stamp) { $stamp = $now.AddMinutes(-30) }

$status = [pscustomobject][ordered]@{
    '수집시각' = $collected; '인구기준시각' = $stamp.ToString('yyyy-MM-dd HH:mm')
    '성공' = $rows.Count; '실패' = $failed.Count; '실행' = $(if ($env:GITHUB_ACTIONS) { 'github' } else { 'laptop' })
    '실패장소' = (($failed | Select-Object -First 10) -join ' / ')
}

if ($rows.Count -gt 0) {
    $dayFile = Get-DayFile $stamp
    $slot = $stamp.ToString('yyyy-MM-dd HH')
    if (Test-SlotSaved $slot) {
        Write-Host "$($slot)시 자료가 이미 있어서 표에는 추가하지 않음"
        exit 0
    }
    Add-CsvRows $dayFile $rows
    Set-Saved 'true'
    Write-Host "저장: $dayFile (+$($rows.Count)줄)"
    # 원본
    $rawDir = Join-Path $RepoRoot 'tmp/raw'
    New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
    $rawFile = Join-Path $rawDir ($stamp.ToString('yyyy-MM-dd_HHmm') + '.json.gz')
    $body = '{"collected_at":"' + $collected + '","count":' + $rows.Count + ',"places":[' + ($rawParts -join ',') + ']}'
    $fs = [IO.File]::Create($rawFile)
    try {
        $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Compress)
        $b = $Utf8.GetBytes($body); $gz.Write($b, 0, $b.Length); $gz.Dispose()
    } finally { $fs.Dispose() }
}

Add-CsvRows (Join-Path $RepoRoot 'data/status/수집기록.csv') @($status)
Write-Host ("완료: 성공 {0}곳, 실패 {1}곳, 기준시각 {2}" -f $rows.Count, $failed.Count, $status.'인구기준시각')
if ($rows.Count -eq 0) { exit 1 }
