# 유동인구에 영향을 줄 만한 오늘의 이벤트를 모아 저장합니다.
#  - 서울시 문화행사(축제·공연·전시·체험 등) 중 오늘 진행 중인 것
#  - 서울시 돌발정보: 오늘 걸쳐 있는 집회·행사·훈련 통제, 기상/재난, 지하철 사고
#  - 서울시설공단 경기장 공식 일정: 고척스카이돔·서울월드컵경기장·장충체육관 (야구·축구·배구·콘서트 등)
# 매일 아침 9시 실행용. 결과는 그날 데이터 폴더에 저장:
#   data\YYYY-MM-DD\이벤트_공식.csv (엑셀용 표) + data\YYYY-MM-DD\이벤트_공식_원본.json.gz (원본)
# 각 행사에서 가장 가까운 실시간 데이터 장소(121곳 중)와 거리도 함께 적어 둡니다.

param([string]$Date)   # 테스트용: -Date 2026-10-04 처럼 날짜 지정 (생략하면 오늘)

$ErrorActionPreference = 'Stop'
$Root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir   = Join-Path $Root 'logs'

$Utf8  = New-Object System.Text.UTF8Encoding($false)
$today = if ($Date) { [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null) } else { (Get-Date).Date }
# 날짜 폴더 이름에 요일 포함: 2026-10-17_토
$DayDir = Join-Path (Join-Path $Root 'data') ($today.ToString('yyyy-MM-dd') + '_' + $today.ToString('ddd', [Globalization.CultureInfo]::GetCultureInfo('ko-KR')))
New-Item -ItemType Directory -Force -Path $DayDir, $LogDir | Out-Null
$LogFile = Join-Path $LogDir ((Get-Date).ToString('yyyy-MM') + '.log')

function Write-Log($msg) {
    $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  [행사] ' + $msg
    [System.IO.File]::AppendAllText($LogFile, $line + "`r`n", $Utf8)
}

function Get-Text($url, $referer) {
    $wc = New-Object System.Net.WebClient
    if ($referer) { $wc.Headers.Add('Referer', $referer) }
    try { return $Utf8.GetString($wc.DownloadData($url)) }
    finally { $wc.Dispose() }
}

function Get-Date10($s) {
    if (-not $s -or $s.Length -lt 10) { return $null }
    try { return [datetime]::ParseExact($s.Substring(0, 10), 'yyyy-MM-dd', $null) } catch { return $null }
}

# 두 좌표 사이 거리 (m)
function Get-DistanceM($lat1, $lng1, $lat2, $lng2) {
    $r = 6371000.0
    $dLat = ($lat2 - $lat1) * [Math]::PI / 180
    $dLng = ($lng2 - $lng1) * [Math]::PI / 180
    $a = [Math]::Sin($dLat / 2) * [Math]::Sin($dLat / 2) +
         [Math]::Cos($lat1 * [Math]::PI / 180) * [Math]::Cos($lat2 * [Math]::PI / 180) *
         [Math]::Sin($dLng / 2) * [Math]::Sin($dLng / 2)
    return 2 * $r * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1 - $a))
}

try {
    # 1) API 키
    $ApiKey = Get-Content (Join-Path $Root 'config.txt') -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.Contains('=') } |
        Select-Object -First 1
    if (-not $ApiKey) { throw 'config.txt 에 API 키가 없습니다.' }

    # 2) 문화행사 전체를 1000건씩 받아 오늘 진행 중인 것만 고르기
    $all = New-Object System.Collections.Generic.List[object]
    $start = 1
    $total = $null
    do {
        $end = $start + 999
        # 서버가 가끔 JSON이 아닌 응답을 주므로 실패하면 최대 3번까지 다시 시도
        for ($try = 1; ; $try++) {
            try {
                $text = Get-Text "http://openapi.seoul.go.kr:8088/$ApiKey/json/culturalEventInfo/$start/$end/" $null
                $info = ($text | ConvertFrom-Json).culturalEventInfo
                if (-not $info -or $info.RESULT.CODE -ne 'INFO-000') {
                    throw ('API 오류 응답: ' + $text.Substring(0, [Math]::Min(200, $text.Length)))
                }
                break
            } catch {
                if ($try -ge 3) { throw }
                Start-Sleep -Seconds (10 * $try)
            }
        }
        $total = [int]$info.list_total_count
        foreach ($row in $info.row) { $all.Add($row) }
        $start = $end + 1
    } while ($start -le $total)

    $todays = @($all | Where-Object {
        $s = Get-Date10 $_.STRTDATE
        $e = Get-Date10 $_.END_DATE
        $s -and $e -and $s -le $today -and $e -ge $today
    })

    # 3) 실시간 데이터 장소 121곳 좌표 (실패해도 행사 저장은 계속)
    $spots = @()
    try {
        $listUrl = 'https://data.seoul.go.kr/SeoulRtd/api/hotspot-category?page=1&category=%EC%A0%84%EC%B2%B4%EB%B3%B4%EA%B8%B0&count=300'
        # 이 목록은 x 가 위도, y 가 경도입니다
        $spots = @((Get-Text $listUrl 'https://data.seoul.go.kr/SeoulRtd/list' | ConvertFrom-Json).row |
            ForEach-Object { [pscustomobject]@{ Name = $_.area_nm; Lat = [double]$_.x; Lng = [double]$_.y } })
    } catch {
        Write-Log "WARN 장소 좌표를 못 받아 가까운 장소 계산은 건너뜀: $($_.Exception.Message)"
    }

    # 4) 표로 정리
    $rows = foreach ($ev in $todays) {
        $near = ''; $dist = ''
        $lat = 0.0; $lng = 0.0
        if ($spots.Count -gt 0 -and [double]::TryParse($ev.LAT, [ref]$lat) -and [double]::TryParse($ev.LOT, [ref]$lng) -and $lat -gt 30) {
            $best = $spots | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; D = (Get-DistanceM $lat $lng $_.Lat $_.Lng) }
            } | Sort-Object D | Select-Object -First 1
            $near = $best.Name
            $dist = [int][Math]::Round($best.D)
        }
        [pscustomobject][ordered]@{
            '날짜'          = $today.ToString('yyyy-MM-dd')
            '출처'          = '서울시 문화행사'
            '분류'          = $ev.CODENAME
            '행사명'        = $ev.TITLE
            '자치구'        = $ev.GUNAME
            '장소'          = $ev.PLACE
            '기간'          = $ev.DATE
            '운영시간'      = $ev.PRO_TIME
            '무료여부'      = $ev.IS_FREE
            '이용요금'      = $ev.USE_FEE
            '이용대상'      = $ev.USE_TRGT
            '주최기관'      = $ev.ORG_NAME
            '가까운_관심장소' = $near
            '관심장소_거리m' = $dist
            '위도'          = $ev.LAT
            '경도'          = $ev.LOT
            '링크'          = $ev.HMPG_ADDR
        }
    }

    # 5) 서울시 돌발정보(TOPIS): 오늘 걸쳐 있는 집회·행사·훈련 통제, 기상/재난, 지하철 사고
    $accTypes = @{ 'A10' = '집회및행사'; 'A09' = '기상/재난'; 'A07' = '지하철사고' }
    $accRows = @()
    $accToday = @()
    try {
        $subNames = @{}
        $subXml = [xml](Get-Text "http://openapi.seoul.go.kr:8088/$ApiKey/xml/AccSubCode/1/200/" $null)
        foreach ($c in $subXml.SelectNodes('//row')) { $subNames[$c.ChildNodes[0].InnerText] = $c.ChildNodes[1].InnerText }

        $accXml = [xml](Get-Text "http://openapi.seoul.go.kr:8088/$ApiKey/xml/AccInfo/1/1000/" $null)
        $todayKey = $today.ToString('yyyyMMdd')
        $accToday = @($accXml.SelectNodes('//row') | Where-Object {
            $accTypes.ContainsKey($_.acc_type) -and $_.occr_date -le $todayKey -and $_.exp_clr_date -ge $todayKey
        })
        $accRows = foreach ($a in $accToday) {
            $t1 = $a.occr_time.PadRight(4, '0').Substring(0, 4).Insert(2, ':')
            $t2 = $a.exp_clr_time.PadRight(4, '0').Substring(0, 4).Insert(2, ':')
            [pscustomobject][ordered]@{
                '날짜'          = $today.ToString('yyyy-MM-dd')
                '출처'          = '서울시 돌발정보(교통통제)'
                '분류'          = $accTypes[$a.acc_type] + '-' + $subNames[$a.acc_dtype]
                '행사명'        = $a.acc_info.Trim()
                '자치구'        = ''
                '장소'          = ''
                '기간'          = "$($a.occr_date)~$($a.exp_clr_date)"
                '운영시간'      = "$t1~$t2"
                '무료여부'      = ''
                '이용요금'      = ''
                '이용대상'      = ''
                '주최기관'      = ''
                '가까운_관심장소' = ''
                '관심장소_거리m' = ''
                '위도'          = ''
                '경도'          = ''
                '링크'          = ''
            }
        }
    } catch {
        Write-Log "WARN 돌발정보(집회·행사 통제) 수집 실패: $($_.Exception.Message)"
    }

    # 6) 경기장 운영기관(서울시설공단) 공식 경기/행사 일정: 프로야구·K리그·배구·콘서트 등
    #    sisul.or.kr 의 공개 일정 페이지를 경기장당 하루 1번만 읽습니다. (robots.txt 허용 경로)
    #    KBO 등 수집을 금지한 사이트, 예매 사이트는 사용하지 않습니다.
    $venues = @(
        @{ Site = 'skydome';    Name = '고척스카이돔';     Gu = '구로구'; Lat = 37.4982; Lng = 126.8670 },
        @{ Site = 'worldcupst'; Name = '서울월드컵경기장'; Gu = '마포구'; Lat = 37.5683; Lng = 126.8972 },
        @{ Site = 'jangchung';  Name = '장충체육관';       Gu = '중구';   Lat = 37.5583; Lng = 127.0068 }
    )
    $venueRows = @()
    $venueRaw  = @()
    foreach ($v in $venues) {
        try {
            $url = 'https://sisul.or.kr/open_content/sub/schedule/detail.do?year={0}&month={1}&day={2}&site_div={3}' -f
                $today.ToString('yyyy'), $today.ToString('MM'), $today.ToString('dd'), $v.Site
            $html = Get-Text $url $null
            # 달력 칸(<td onclick="thisSchedule('2026','10','16',...)">) 중 오늘 칸의 일정 제목만 꺼냄
            $pattern = "thisSchedule\('{0}','{1}','{2}','[a-z_]+'\);`"[^>]*>(.*?)</td>" -f
                $today.ToString('yyyy'), $today.ToString('MM'), $today.ToString('dd')
            $cell = [regex]::Match($html, $pattern, 'Singleline')
            if (-not $cell.Success) { throw '오늘 날짜 칸을 찾지 못함 (페이지 구조 변경 가능성)' }
            $titles = [regex]::Matches($cell.Groups[1].Value, 'title="([^"]*)"') |
                ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value).Trim() } |
                Where-Object { $_ } | Select-Object -Unique
            $near = ''; $dist = ''
            if ($spots.Count -gt 0) {
                $best = $spots | ForEach-Object {
                    [pscustomobject]@{ Name = $_.Name; D = (Get-DistanceM $v.Lat $v.Lng $_.Lat $_.Lng) }
                } | Sort-Object D | Select-Object -First 1
                $near = $best.Name; $dist = [int][Math]::Round($best.D)
            }
            foreach ($t in $titles) {
                $venueRaw += [pscustomobject]@{ venue = $v.Name; date = $today.ToString('yyyy-MM-dd'); title = $t; url = $url }
                # 보기 좋게: 문의 안내 꼬리 제거, 항목 사이 구분자 넣기
                $clean = ($t -replace '[■\*]\s*\S*\s*관련 문의.*$', '').Trim()
                $clean = $clean -replace '\s*(대\s*진|일\s*정|장\s*소|시\s*간|경기일)\s*:', ' / $1:'
                $kind = switch -Regex ($t) {
                    'KBO|야구'               { '스포츠-야구'; break }
                    'K리그|WK리그|축구'      { '스포츠-축구'; break }
                    '배구|V-?리그|홈경기'    { '스포츠-배구 등 홈경기'; break }
                    '콘서트|공연|투어|TOUR|팬미팅' { '공연·콘서트'; break }
                    default                  { '경기장 행사' }
                }
                $venueRows += [pscustomobject][ordered]@{
                    '날짜'          = $today.ToString('yyyy-MM-dd')
                    '출처'          = '서울시설공단 경기장 공식 일정'
                    '분류'          = $kind
                    '행사명'        = $clean
                    '자치구'        = $v.Gu
                    '장소'          = $v.Name
                    '기간'          = ''
                    '운영시간'      = ''
                    '무료여부'      = ''
                    '이용요금'      = ''
                    '이용대상'      = ''
                    '주최기관'      = ''
                    '가까운_관심장소' = $near
                    '관심장소_거리m' = $dist
                    '위도'          = $v.Lat
                    '경도'          = $v.Lng
                    '링크'          = $url
                }
            }
        } catch {
            Write-Log "WARN $($v.Name) 일정 수집 실패: $($_.Exception.Message)"
        }
    }

    $csvFile = Join-Path $DayDir '이벤트_공식.csv'
    (@($venueRows) + @($accRows) + @(@($rows) | Sort-Object '분류', '자치구')) |
        Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

    # 원본도 압축 보관
    $rawFile = Join-Path $DayDir '이벤트_공식_원본.json.gz'
    $rawObj = [pscustomobject]@{
        culturalEventInfo = @($todays)
        VenueSchedule     = @($venueRaw)
        AccInfo           = @($accToday | ForEach-Object {
            $o = [ordered]@{}; foreach ($n in $_.ChildNodes) { $o[$n.Name] = $n.InnerText }; [pscustomobject]$o })
    }
    $bytes = $Utf8.GetBytes((ConvertTo-Json $rawObj -Depth 6 -Compress))
    $fs = [System.IO.File]::Create($rawFile)
    try {
        $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Compress)
        $gz.Write($bytes, 0, $bytes.Length)
        $gz.Dispose()
    } finally { $fs.Dispose() }

    Write-Log ("OK 문화행사 {0}건 중 오늘 {1}건, 집회·행사 통제 등 {2}건, 경기장 일정 {3}건 -> {4}" -f $all.Count, $todays.Count, @($accRows).Count, @($venueRows).Count, $csvFile)
} catch {
    Write-Log "ERROR $($_.Exception.Message)"
    exit 1
}
