# 김포·인천 공항의 하루치 여객기 운항정보(출발·도착)를 받아 표로 저장합니다.
#  - 김포: 한국공항공사_실시간 항공기 운항정보 조회_GW   (B551178/flight-status)
#  - 인천: 인천국제공항공사_여객기 운항 현황 상세 조회 서비스 (B551177/StatusOfPassengerFlightsDeOdp)
#  - 두 API 모두 조회일 기준 3일 전 ~ 6일 후만 제공 → 지난 날 기록은 매일 모아 둬야 남음
#  - data/flights/YYYY-MM/YYYY-MM-DD.csv (같은 날짜를 다시 받으면 최신 상태로 덮어씀)
#  사용: ./scripts/flights.ps1            (오늘)
#        ./scripts/flights.ps1 -Date 2026-11-03

param([string]$Date)

. "$PSScriptRoot/common.ps1"

# 공공데이터포털 인증키: GitHub에서는 DATA_GO_KR_KEY, 노트북에서는 config.txt 의 64자리 키
function Get-DataGoKey {
    if ($env:DATA_GO_KR_KEY) { return $env:DATA_GO_KR_KEY.Trim() }
    $k = Get-ConfigLine { $_ -match '^[0-9a-fA-F]{64}$' }
    if ($k) { return $k }
    throw 'DATA_GO_KR_KEY 가 없습니다. (노트북에서는 수집 폴더의 config.txt 에 64자리 공공데이터포털 키)'
}
$key = Get-DataGoKey
$ek  = [Uri]::EscapeDataString($key)
function Hide-Key([string]$m) { return $m.Replace($key, '***').Replace($ek, '***') }

$day = if ($Date) { [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null) } else { (Get-KstNow).Date }
$ymd = $day.ToString('yyyyMMdd')
$collected = (Get-KstNow).ToString('yyyy-MM-dd HH:mm')
function To-Time([string]$v) { if ($v -match '^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})') { return "$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5])" } return $v }

# 페이지를 넘기며 전부 받기
function Get-AllItems([string]$base, [int]$size) {
    # 한 번에 받는 줄 수: 김포는 100까지(넘으면 HTTP_ERROR), 인천은 500까지
    $all = New-Object System.Collections.Generic.List[object]
    for ($page = 1; $page -le 40; $page++) {
        $text = Get-Text "$base&serviceKey=$ek&type=json&numOfRows=$size&pageNo=$page" $null
        $j = $text | ConvertFrom-Json
        if ("$($j.response.header.resultCode)" -ne '00') { throw "응답 오류: $($j.response.header.resultMsg)$($j.OpenAPI_ServiceResponse.cmmMsgHeader.returnAuthMsg)" }
        $items = $j.response.body.items
        if ($items -and $items.PSObject.Properties['item']) { $items = $items.item }   # 김포는 items.item, 인천은 items
        foreach ($it in @($items)) { if ($it) { $all.Add($it) } }
        if ($all.Count -ge [int]$j.response.body.totalCount -or @($items).Count -eq 0) { break }
    }
    return $all
}

$rows = New-Object System.Collections.Generic.List[object]
$log  = New-Object System.Collections.Generic.List[string]

# 김포
foreach ($op in @(@{ Path = 'depart'; Kind = '출발' }, @{ Path = 'arrival'; Kind = '도착' })) { try {
    $items = Get-AllItems "https://apis.data.go.kr/B551178/flight-status/$($op.Path)?searchday=$ymd&from_time=0000&to_time=2359&airport_code=GMP" 100
    foreach ($it in $items) {
        $out = $op.Kind -eq '출발'
        $rows.Add([pscustomobject][ordered]@{
            '날짜' = $day.ToString('yyyy-MM-dd'); '공항' = '김포'; '구분' = $op.Kind
            '국내국제' = (To-Str $it.line); '항공사' = (To-Str $it.airline); '편명' = (To-Str $it.flightid)
            '상대공항' = $(if ($out) { To-Str $it.arrAirport } else { To-Str $it.depAirport })
            '상대공항코드' = $(if ($out) { To-Str $it.arrvAirportCode } else { To-Str $it.depAirportCode })
            '예정시각' = (To-Time (To-Str $it.scheduledatetime)); '변경시각' = (To-Time (To-Str $it.estimateddatetime))
            '현황' = (To-Str $it.rmkKor); '코드쉐어' = (To-Str $it.codeshare); '마스터편명' = (To-Str $it.masterflightid)
            '터미널' = ''; '탑승구' = ''; '수집시각' = $collected
        })
    }
    $log.Add("김포 $($op.Kind) $(@($items).Count)편")
} catch { $log.Add("김포 $($op.Kind) 실패: " + (Hide-Key $_.Exception.Message)) } }

# 인천 (예정시각 기준으로 하루 전체)
foreach ($op in @(@{ Path = 'getPassengerDeparturesDeOdp'; Kind = '출발' }, @{ Path = 'getPassengerArrivalsDeOdp'; Kind = '도착' })) { try {
    $items = Get-AllItems "https://apis.data.go.kr/B551177/StatusOfPassengerFlightsDeOdp/$($op.Path)?searchday=$ymd&from_time=0000&to_time=2359&lang=K&inqtimechcd=S" 500
    foreach ($it in $items) {
        $rows.Add([pscustomobject][ordered]@{
            '날짜' = $day.ToString('yyyy-MM-dd'); '공항' = '인천'; '구분' = $op.Kind
            '국내국제' = $(switch ("$($it.typeOfFlight)") { 'I' { '국제' } 'D' { '국내' } default { '국제' } })
            '항공사' = (To-Str $it.airline); '편명' = (To-Str $it.flightId)
            '상대공항' = (To-Str $it.airport); '상대공항코드' = (To-Str $it.airportCode)
            '예정시각' = (To-Time (To-Str $it.scheduleDateTime)); '변경시각' = (To-Time (To-Str $it.estimatedDateTime))
            '현황' = (To-Str $it.remark); '코드쉐어' = (To-Str $it.codeshare); '마스터편명' = (To-Str $it.masterflightid)
            '터미널' = (To-Str $it.terminalid); '탑승구' = (To-Str $it.gatenumber); '수집시각' = $collected
        })
    }
    $log.Add("인천 $($op.Kind) $(@($items).Count)편")
} catch { $log.Add("인천 $($op.Kind) 실패: " + (Hide-Key $_.Exception.Message)) } }

if ($rows.Count) {
    $dst = Join-Path $RepoRoot ("data/flights/" + (Get-DayPath $day) + '.csv')
    Write-CsvBom $dst @($rows | Sort-Object '공항', '구분', '예정시각', '편명')
    $log.Add("저장: $dst")
}
$log | ForEach-Object { Write-Host $_ }
Add-CsvRows (Join-Path $RepoRoot 'data/status/항공기록.csv') @([pscustomobject][ordered]@{ '수집시각' = $collected; '날짜' = $day.ToString('yyyy-MM-dd'); '결과' = ($log -join ' | ') })
if ($log -match '실패') { exit 1 }
