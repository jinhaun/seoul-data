# 매일 아침(09시쯤): 행사 정리, 숙박 목록, 외국인 생활인구, 환율을 받아 저장합니다.
# 각 부분은 따로 실행되어 하나가 실패해도 나머지는 저장됩니다.
#   -Only events|lodging|foreigner|exchange 로 일부만 실행 가능, -Date 2026-11-03 로 날짜 지정(행사만)

param([string]$Only, [string]$Date)

. "$PSScriptRoot/common.ps1"

$key   = Get-ApiKey
$today = if ($Date) { [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null) } else { (Get-KstNow).Date }
$todayStr = $today.ToString('yyyy-MM-dd')
$log = New-Object System.Collections.Generic.List[string]
function Note([string]$m) { Write-Host $m; $script:log.Add($m) }
$hadError = $false

function Get-Date10($v) {
    $s = To-Str $v 'yyyy-MM-dd'
    if ($s.Length -lt 10) { return $null }
    try { return [datetime]::ParseExact($s.Substring(0, 10), 'yyyy-MM-dd', $null) } catch { return $null }
}

# ---------------------------------------------------------------- 1) 오늘의 행사 (공식)
if (-not $Only -or $Only -eq 'events') { try {
    $spots = @(Get-Hotspots)
    # 서울시 문화행사 전체에서 오늘 진행 중인 것
    $all = New-Object System.Collections.Generic.List[object]
    $start = 1; $total = 1
    while ($start -le $total) {
        $info = (Get-Json "http://openapi.seoul.go.kr:8088/$key/json/culturalEventInfo/$start/$($start + 999)/").culturalEventInfo
        if (-not $info -or $info.RESULT.CODE -ne 'INFO-000') { throw '문화행사 API 오류' }
        $total = [int]$info.list_total_count
        foreach ($r in $info.row) { $all.Add($r) }
        $start += 1000
    }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($ev in $all) {
        $s = Get-Date10 $ev.STRTDATE; $e = Get-Date10 $ev.END_DATE
        if (-not ($s -and $e -and $s -le $today -and $e -ge $today)) { continue }
        $lat = 0.0; $lng = 0.0; $near = @('', '')
        if ([double]::TryParse("$($ev.LAT)", [ref]$lat) -and [double]::TryParse("$($ev.LOT)", [ref]$lng) -and $lat -gt 30) { $near = Get-NearestSpot $lat $lng $spots }
        $rows.Add([pscustomobject][ordered]@{
            '날짜' = $todayStr; '출처' = '서울시 문화행사'; '분류' = (To-Str $ev.CODENAME); '행사명' = (To-Str $ev.TITLE)
            '자치구' = (To-Str $ev.GUNAME); '장소' = (To-Str $ev.PLACE); '기간' = (To-Str $ev.DATE); '운영시간' = (To-Str $ev.PRO_TIME)
            '무료여부' = (To-Str $ev.IS_FREE); '이용요금' = (To-Str $ev.USE_FEE); '가까운_관심장소' = $near[0]; '관심장소_거리m' = $near[1]
            '위도' = (To-Str $ev.LAT); '경도' = (To-Str $ev.LOT); '링크' = (To-Str $ev.HMPG_ADDR)
        })
    }
    $cultureCount = $rows.Count

    # 서울시 돌발정보: 집회·행사 통제, 기상/재난, 지하철 사고
    $accCount = 0
    try {
        $accTypes = @{ 'A10' = '집회및행사'; 'A09' = '기상/재난'; 'A07' = '지하철사고' }
        $subNames = @{}
        foreach ($c in ([xml](Get-Text "http://openapi.seoul.go.kr:8088/$key/xml/AccSubCode/1/200/" $null)).SelectNodes('//row')) { $subNames[$c.ChildNodes[0].InnerText] = $c.ChildNodes[1].InnerText }
        $k = $today.ToString('yyyyMMdd')
        foreach ($a in ([xml](Get-Text "http://openapi.seoul.go.kr:8088/$key/xml/AccInfo/1/1000/" $null)).SelectNodes('//row')) {
            if (-not ($accTypes.ContainsKey($a.acc_type) -and $a.occr_date -le $k -and $a.exp_clr_date -ge $k)) { continue }
            $t1 = $a.occr_time.PadRight(4, '0').Substring(0, 4).Insert(2, ':'); $t2 = $a.exp_clr_time.PadRight(4, '0').Substring(0, 4).Insert(2, ':')
            $rows.Add([pscustomobject][ordered]@{
                '날짜' = $todayStr; '출처' = '서울시 돌발정보(교통통제)'; '분류' = $accTypes[$a.acc_type] + '-' + $subNames[$a.acc_dtype]; '행사명' = $a.acc_info.Trim()
                '자치구' = ''; '장소' = ''; '기간' = "$($a.occr_date)~$($a.exp_clr_date)"; '운영시간' = "$t1~$t2"; '무료여부' = ''; '이용요금' = ''
                '가까운_관심장소' = ''; '관심장소_거리m' = ''; '위도' = ''; '경도' = ''; '링크' = ''
            })
            $accCount++
        }
    } catch { Note "WARN 교통통제 정보 실패: $($_.Exception.Message)" }

    # 서울시설공단 경기장 공식 일정 (고척스카이돔·서울월드컵경기장·장충체육관), 경기장당 하루 1번
    $venueCount = 0
    $venues = @(
        @{ Site = 'skydome'; Name = '고척스카이돔'; Gu = '구로구'; Lat = 37.4982; Lng = 126.8670 },
        @{ Site = 'worldcupst'; Name = '서울월드컵경기장'; Gu = '마포구'; Lat = 37.5683; Lng = 126.8972 },
        @{ Site = 'jangchung'; Name = '장충체육관'; Gu = '중구'; Lat = 37.5583; Lng = 127.0068 }
    )
    foreach ($v in $venues) {
        try {
            $url = 'https://sisul.or.kr/open_content/sub/schedule/detail.do?year={0}&month={1}&day={2}&site_div={3}' -f $today.ToString('yyyy'), $today.ToString('MM'), $today.ToString('dd'), $v.Site
            $html = Get-Text $url $null
            $pattern = "thisSchedule\('{0}','{1}','{2}','[a-z_]+'\);`"[^>]*>(.*?)</td>" -f $today.ToString('yyyy'), $today.ToString('MM'), $today.ToString('dd')
            $cell = [regex]::Match($html, $pattern, 'Singleline')
            if (-not $cell.Success) { continue }
            $near = Get-NearestSpot $v.Lat $v.Lng $spots
            foreach ($t in ([regex]::Matches($cell.Groups[1].Value, 'title="([^"]*)"') | ForEach-Object { [Net.WebUtility]::HtmlDecode($_.Groups[1].Value).Trim() } | Where-Object { $_ } | Select-Object -Unique)) {
                $clean = ($t -replace '[■\*]\s*\S*\s*관련 문의.*$', '').Trim() -replace '\s*(대\s*진|일\s*정|장\s*소|시\s*간|경기일)\s*:', ' / $1:'
                $kind = switch -Regex ($t) { 'KBO|야구' { '스포츠-야구'; break } 'K리그|WK리그|축구' { '스포츠-축구'; break } '배구|V-?리그|홈경기' { '스포츠-배구 등 홈경기'; break } '콘서트|공연|투어|TOUR|팬미팅' { '공연·콘서트'; break } default { '경기장 행사' } }
                $rows.Add([pscustomobject][ordered]@{
                    '날짜' = $todayStr; '출처' = '서울시설공단 경기장 공식 일정'; '분류' = $kind; '행사명' = $clean; '자치구' = $v.Gu; '장소' = $v.Name
                    '기간' = ''; '운영시간' = ''; '무료여부' = ''; '이용요금' = ''; '가까운_관심장소' = $near[0]; '관심장소_거리m' = $near[1]
                    '위도' = $v.Lat; '경도' = $v.Lng; '링크' = $url
                })
                $venueCount++
            }
        } catch { Note "WARN $($v.Name) 일정 실패: $($_.Exception.Message)" }
    }
    $sorted = @($rows | Sort-Object @{ e = { switch ($_.'출처') { '서울시설공단 경기장 공식 일정' { 0 } '서울시 돌발정보(교통통제)' { 1 } default { 2 } } } }, '분류', '자치구')
    Write-CsvBom (Join-Path $RepoRoot ("data/events/" + (Get-DayPath $today) + '_공식.csv')) $sorted
    Note "OK 행사: 문화행사 $cultureCount, 교통통제 $accCount, 경기장 $venueCount"
} catch { $hadError = $true; Note "ERROR 행사: $($_.Exception.Message)" } }

# ---------------------------------------------------------------- 2) 숙박 목록 (호텔·외국인민박·숙박업)
if (-not $Only -or $Only -eq 'lodging') {
    $kinds = @(@{ Svc = 'LOCALDATA_031101'; Name = '호텔' }, @{ Svc = 'LOCALDATA_031104'; Name = '외국인민박' }, @{ Svc = 'LOCALDATA_031103'; Name = '숙박업' })
    foreach ($kd in $kinds) { try {
        $svc = $kd.Svc
        $total = [int](Get-Json "http://openapi.seoul.go.kr:8088/$key/json/$svc/1/1/").$svc.list_total_count
        $raw = New-Object System.Collections.Generic.List[object]
        for ($s = 1; $s -le $total; $s += 1000) {
            $pg = Get-Json "http://openapi.seoul.go.kr:8088/$key/json/$svc/$s/$($s + 999)/"
            if ($pg.$svc.RESULT.CODE -ne 'INFO-000') { throw "API 오류 $($pg.$svc.RESULT.CODE)" }
            foreach ($r in $pg.$svc.row) { $raw.Add($r) }
        }
        if ($raw.Count -ne $total) { throw "건수 불일치 $($raw.Count)/$total" }
        $rows = foreach ($r in $raw) {
            $tx = (To-Str $r.X); $ty = (To-Str $r.Y); $lat = ''; $lng = ''; $dx = 0.0; $dy = 0.0
            if ([double]::TryParse($tx, [ref]$dx) -and [double]::TryParse($ty, [ref]$dy) -and $dx -gt 0) { $ll = Convert-TmToWgs84 $dx $dy; $lat = $ll[0]; $lng = $ll[1] }
            $road = To-Str $r.RDNWHLADDR
            $jibun = if ($r.PSObject.Properties['SITEWHLADDR']) { To-Str $r.SITEWHLADDR } else { To-Str $r.LOTNO_ADDR }
            $gu = ''; if ("$road $jibun" -match '서울특별시\s+(\S+구)') { $gu = $Matches[1] }
            $o = [ordered]@{
                '자치단체코드' = (To-Str $r.OPNSFTEAMCODE); '관리번호' = (To-Str $r.MGTNO); '업소명' = (To-Str $r.BPLCNM)
                '영업상태' = (To-Str $r.TRDSTATENM); '상세영업상태' = (To-Str $r.DTLSTATENM)
                '인허가일자' = (To-Str $r.APVPERMYMD 'yyyy-MM-dd'); '폐업일자' = $(if ($r.PSObject.Properties['DCBYMD']) { To-Str $r.DCBYMD 'yyyy-MM-dd' } else { '' })
                '자치구' = $gu; '도로명주소' = $road; '지번주소' = $jibun
            }
            switch ($kd.Name) {
                '호텔' { $o['숙박업종'] = (To-Str $r.TRSTLODGCLNM); $o['영문명'] = (To-Str $r.ENGSTNTRNMNM); $o['객실수'] = (To-Str $r.STROOMCNT); $o['시설면적'] = (To-Str $r.FACILAR) }
                '외국인민박' { $o['객실수'] = (To-Str $r.STROOMCNT); $o['시설면적'] = (To-Str $r.FACILAR) }
                '숙박업' { $o['업태'] = (To-Str $r.SNTUPTAENM); $o['한실수'] = (To-Str $r.HANSHILCNT); $o['양실수'] = (To-Str $r.YANGSILCNT); $o['시설면적'] = (To-Str $r.SITEAREA) }
            }
            $o['최종수정일시'] = (To-Str $r.LASTMODTS 'yyyy-MM-dd HH:mm:ss'); $o['위도'] = $lat; $o['경도'] = $lng
            [pscustomobject]$o
        }
        $rows = @($rows | Sort-Object '자치단체코드', '관리번호')
        $latest = Join-Path $RepoRoot "data/lodging/latest/숙박_$($kd.Name).csv"
        $old = @(Read-Csv $latest)
        $newLines = (@($rows | ConvertTo-Csv -NoTypeInformation) -join "`n") -replace "`r`n", "`n"
        $oldText = if (Test-Path $latest) { ([IO.File]::ReadAllText($latest, $Utf8) -replace "`r`n", "`n").TrimStart([char]0xFEFF).TrimEnd("`n") } else { '' }
        $open = @($raw | Where-Object { "$($_.TRDSTATEGBN)" -eq '01' }).Count
        $cnt = @{ '신규' = 0; '변경' = 0; '삭제' = 0 }
        if ($newLines.TrimEnd("`n") -ceq $oldText) {
            Note "OK 숙박-$($kd.Name): 변화없음 (전체 $total, 영업중 $open)"
        } else {
            if ($old.Count -gt 0) {
                $oldMap = @{}; foreach ($o in $old) { $oldMap["$($o.'자치단체코드')|$($o.'관리번호')"] = $o }
                $props = $rows[0].PSObject.Properties.Name; $seen = @{}
                $changes = New-Object System.Collections.Generic.List[object]
                foreach ($n in $rows) {
                    $id = "$($n.'자치단체코드')|$($n.'관리번호')"; $seen[$id] = $true; $o = $oldMap[$id]
                    if (-not $o) { $changes.Add([pscustomobject][ordered]@{ '구분' = '신규'; '자치단체코드' = $n.'자치단체코드'; '관리번호' = $n.'관리번호'; '업소명' = $n.'업소명'; '자치구' = $n.'자치구'; '영업상태' = $n.'영업상태'; '바뀐항목' = '' }); continue }
                    $diff = @($props | Where-Object { ("$($n.$_)" -replace "`r", '') -cne ("$($o.$_)" -replace "`r", '') })
                    if ($diff.Count) { $changes.Add([pscustomobject][ordered]@{ '구분' = '변경'; '자치단체코드' = $n.'자치단체코드'; '관리번호' = $n.'관리번호'; '업소명' = $n.'업소명'; '자치구' = $n.'자치구'; '영업상태' = $n.'영업상태'; '바뀐항목' = (($diff | ForEach-Object { "$_`: $($o.$_) -> $($n.$_)" }) -join ' / ') }) }
                }
                foreach ($id in $oldMap.Keys) { if (-not $seen[$id]) { $o = $oldMap[$id]; $changes.Add([pscustomobject][ordered]@{ '구분' = '삭제'; '자치단체코드' = $o.'자치단체코드'; '관리번호' = $o.'관리번호'; '업소명' = $o.'업소명'; '자치구' = $o.'자치구'; '영업상태' = $o.'영업상태'; '바뀐항목' = '' }) } }
                foreach ($c in $changes) { $cnt[$c.'구분']++ }
                if ($changes.Count) { Write-CsvBom (Join-Path $RepoRoot ("data/lodging/changes/" + (Get-DayPath $today) + "_$($kd.Name).csv")) $changes }
            }
            Write-CsvBom $latest $rows
            Note ("OK 숙박-{0}: 신규 {1}, 변경 {2}, 삭제 {3} (전체 {4}, 영업중 {5})" -f $kd.Name, $cnt['신규'], $cnt['변경'], $cnt['삭제'], $total, $open)
        }
        Add-CsvRows (Join-Path $RepoRoot 'data/status/숙박기록.csv') @([pscustomobject][ordered]@{ '날짜' = $todayStr; '종류' = $kd.Name; '전체' = $total; '영업중' = $open; '신규' = $cnt['신규']; '변경' = $cnt['변경']; '삭제' = $cnt['삭제'] })
    } catch { $hadError = $true; Note "ERROR 숙박-$($kd.Name): $($_.Exception.Message)" } }
}

# ---------------------------------------------------------------- 3) 외국인 생활인구 (자치구 x 시간, 약 4일 지연)
if (-not $Only -or $Only -eq 'foreigner') {
    foreach ($t in @(@{ Svc = 'Spop250mFornTempJachi'; Name = '단기' }, @{ Svc = 'Spop250mFornLongJachi'; Name = '장기' })) { try {
        $saved = 0; $missing = 0
        for ($d = New-Object DateTime($today.Year, 1, 1); $d -lt $today; $d = $d.AddDays(1)) {
            $file = Join-Path $RepoRoot ("data/foreigner/$($t.Name)/" + (Get-DayPath $d) + '.csv')
            if (Test-Path $file) { continue }
            $svc = $t.Svc
            $res = Get-Json "http://openapi.seoul.go.kr:8088/$key/json/$svc/1/1000/$($d.ToString('yyyyMMdd'))"
            if (-not $res.$svc) { if ($res.RESULT.CODE -eq 'INFO-200') { $missing++; continue }; throw "API 오류 $($res.RESULT.CODE)" }
            $rows = foreach ($r in ($res.$svc.row | Sort-Object TT, H_DNG_CD)) {
                $o = [ordered]@{ '날짜' = $d.ToString('yyyy-MM-dd'); '시간' = [int]"$($r.TT)"; '자치구코드' = "$($r.H_DNG_CD)"; '자치구' = $GuNames["$($r.H_DNG_CD)"] }
                foreach ($code in $NatNames.Keys) { if ($r.PSObject.Properties[$code]) { $v = "$($r.$code)"; $o[$NatNames[$code]] = $(if ($v -eq '*') { '' } else { $v }) } }
                [pscustomobject]$o
            }
            Write-CsvBom $file $rows; $saved++
        }
        Note "OK 외국인생활인구-$($t.Name): 새로 $saved 일 (아직 안 올라온 날 $missing 일)"
    } catch { $hadError = $true; Note "ERROR 외국인생활인구-$($t.Name): $($_.Exception.Message)" } }
}

# ---------------------------------------------------------------- 4) 환율 (ECB 기준환율, 인증키 불필요)
if (-not $Only -or $Only -eq 'exchange') { try {
    $cur = [ordered]@{ 'USD' = @('미국', '원_달러', 1); 'JPY' = @('일본', '원_100엔', 100); 'CNY' = @('중국', '원_위안', 1); 'THB' = @('태국', '원_바트', 1); 'INR' = @('인도', '원_루피', 1); 'EUR' = @('프랑스', '원_유로', 1) }
    $res = Get-Json ("https://api.frankfurter.dev/v1/$($today.Year)-01-01..$todayStr" + '?from=USD&to=KRW,JPY,CNY,THB,INR,EUR')
    $posted = @{}
    foreach ($p in $res.rates.PSObject.Properties) {
        $krw = [double]$p.Value.KRW; $row = @{}
        foreach ($c in $cur.Keys) { $per = if ($c -eq 'USD') { 1.0 } else { [double]$p.Value.$c }; $row[$c] = [Math]::Round($krw / $per * $cur[$c][2], 2) }
        $posted[$p.Name] = $row
    }
    $dates = @($posted.Keys | Sort-Object)
    $last = $null; $lastDate = $null
    $before = @($dates | Where-Object { $_ -lt "$($today.Year)-01-01" }) | Select-Object -Last 1
    if ($before) { $last = $posted[$before]; $lastDate = $before }
    $daily = New-Object System.Collections.Generic.List[object]
    for ($d = New-Object DateTime($today.Year, 1, 1); $d -le $today; $d = $d.AddDays(1)) {
        $k = $d.ToString('yyyy-MM-dd'); if ($posted.ContainsKey($k)) { $last = $posted[$k]; $lastDate = $k }
        if (-not $last) { continue }
        $o = [ordered]@{ '날짜' = $k; '월' = $d.ToString('yyyy-MM'); '요일' = (Get-WeekdayKo $d); '고시일' = $lastDate; '고시여부' = $(if ($lastDate -eq $k) { 'Y' } else { 'N' }) }
        foreach ($c in $cur.Keys) { $o[$cur[$c][1]] = $last[$c] }
        $daily.Add([pscustomobject]$o)
    }
    Write-CsvBom (Join-Path $RepoRoot 'data/exchange/환율_일별.csv') $daily
    Note "OK 환율: 고시일 $($dates.Count)일, 마지막 고시 $lastDate"
} catch { $hadError = $true; Note "ERROR 환율: $($_.Exception.Message)" } }

Add-CsvRows (Join-Path $RepoRoot 'data/status/매일작업기록.csv') @([pscustomobject][ordered]@{ '실행시각' = (Get-KstNow).ToString('yyyy-MM-dd HH:mm'); '날짜' = $todayStr; '결과' = ($log -join ' | ') })
if ($hadError) { exit 1 }
