# 수집한 실시간 도시데이터(data\*\HHmm.json.gz)를 장소별·자치구별로 묶고
# KB 구별 아파트값(2026년 9월)과 나란히 놓은 표 두 개를 만듭니다.
#   장소별_실시간지표.csv : 장소 하나 = 한 줄 (수집 회차 평균)
#   구별_실시간지표.csv   : 자치구 하나 = 한 줄 (+ 아파트값)
# 데이터가 쌓일수록 다시 실행하면 결과가 갱신됩니다.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root 'data'

# KB부동산 「아파트 ㎡당 매매평균가격」 2026년 9월 (전용면적 기준, 만원/㎡)
$AptM2 = [ordered]@{
    '종로구'=1686; '중구'=1868; '용산구'=2700; '성동구'=2420; '광진구'=2164; '동대문구'=1538
    '중랑구'=1022; '성북구'=1349; '강북구'=1026; '도봉구'=894;  '노원구'=1124; '은평구'=1251
    '서대문구'=1559; '마포구'=2223; '양천구'=2105; '강서구'=1480; '구로구'=1142; '금천구'=938
    '영등포구'=1904; '동작구'=1958; '관악구'=1267; '서초구'=3498; '강남구'=3722; '송파구'=2898; '강동구'=2263
}
$GuNames = @($AptM2.Keys)

function Read-Gz($path) {
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Decompress)
        $sr = New-Object System.IO.StreamReader($gz, [System.Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } finally { $fs.Dispose() }
}
function Num($v) { if ($null -eq $v -or "$v" -eq '') { return $null }; return [double]$v }
function Mid($a, $b) { $x = Num $a; $y = Num $b; if ($null -eq $x -or $null -eq $y) { return $null }; return ($x + $y) / 2 }
function Avg($list) { $v = @($list | Where-Object { $null -ne $_ }); if ($v.Count -eq 0) { return $null }; return ($v | Measure-Object -Average).Average }

# 장소가 속한 구: 주변 지하철역·주차장 주소에 가장 많이 나온 구
# 주소가 없거나 경계에 걸쳐 투표가 틀리는 곳은 아래 표가 우선합니다. ($null = 서울 밖이라 제외)
$GuOverride = @{
    '고척돔' = '구로구'; '아차산' = '광진구'; '청계산' = '서초구'; '홍제폭포' = '서대문구'
    '잠원한강공원' = '서초구'; '창동 신경제 중심지' = '도봉구'; '서울대공원' = $null
}
function Find-Gu($d) {
    if ($GuOverride.ContainsKey($d.AREA_NM)) {
        $g = $GuOverride[$d.AREA_NM]
        return @($g, $(if ($g) { '직접 지정' } else { '서울 밖(경기 과천) - 제외' }))
    }
    $addrs = @()
    $addrs += @($d.SUB_STTS | ForEach-Object { $_.SUB_STN_RADDR })
    $addrs += @($d.PRK_STTS | ForEach-Object { $_.ADDRESS; $_.ROAD_ADDR })
    $votes = @{}
    foreach ($a in $addrs) {
        if (-not $a) { continue }
        foreach ($m in [regex]::Matches($a, '([가-힣]{1,4}구)(?=\s|$)')) {
            $g = $m.Groups[1].Value
            if ($GuNames -contains $g) { $votes[$g] = 1 + $votes[$g] }
        }
    }
    if ($votes.Count -eq 0) { return @($null, '') }
    $sorted = $votes.GetEnumerator() | Sort-Object Value -Descending
    $detail = ($sorted | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', '
    return @($sorted[0].Key, $detail)
}

$files = Get-ChildItem $DataDir -Recurse -Filter '*.json.gz' |
    Where-Object { $_.Name -match '^\d{4}(_\d{4})?\.json\.gz$' } | Sort-Object FullName
if ($files.Count -eq 0) { throw '수집 파일이 없습니다.' }

$byPlace = @{}   # 장소코드 -> 회차별 값 목록
$info    = @{}   # 장소코드 -> 이름, 구, 시설 수 등
foreach ($file in $files) {
    $snap = Read-Gz $file.FullName | ConvertFrom-Json
    foreach ($place in $snap.places) {
        $d = $place.CITYDATA
        $cd = $d.AREA_CD
        $p = $d.LIVE_PPLTN_STTS | Select-Object -First 1
        $c = $d.LIVE_CMRCL_STTS
        $s = $d.LIVE_SUB_PPLTN
        if (-not $info.ContainsKey($cd)) {
            $gu = Find-Gu $d
            $info[$cd] = [ordered]@{ name = $d.AREA_NM; gu = $gu[0]; votes = $gu[1] }
            $byPlace[$cd] = New-Object System.Collections.Generic.List[object]
        }
        $merchants = $null
        if ($c -and $c.CMRCL_RSB) { $merchants = ($c.CMRCL_RSB | ForEach-Object { Num $_.RSB_MCT_CNT } | Measure-Object -Sum).Sum }
        $byPlace[$cd].Add([pscustomobject]@{
            time      = $p.PPLTN_TIME
            ppl       = Mid $p.AREA_PPLTN_MIN $p.AREA_PPLTN_MAX
            nonres    = Num $p.NON_RESNT_PPLTN_RATE
            age3040   = $(if ($p) { (Num $p.PPLTN_RATE_30) + (Num $p.PPLTN_RATE_40) } else { $null })
            payAmt    = $(if ($c) { Mid $c.AREA_SH_PAYMENT_AMT_MIN $c.AREA_SH_PAYMENT_AMT_MAX } else { $null })
            payCnt    = $(if ($c) { Num $c.AREA_SH_PAYMENT_CNT } else { $null })
            corpRate  = $(if ($c) { Num $c.CMRCL_CORPORATION_RATE } else { $null })
            merchants = $merchants
            subOff    = $(if ($s) { Mid $s.SUB_ACML_GTOFF_PPLTN_MIN $s.SUB_ACML_GTOFF_PPLTN_MAX } else { $null })
            subOn     = $(if ($s) { Mid $s.SUB_ACML_GTON_PPLTN_MIN $s.SUB_ACML_GTON_PPLTN_MAX } else { $null })
            subStn    = $(if ($s) { Num $s.SUB_STN_CNT } else { $null })
            busStn    = $(if ($d.LIVE_BUS_PPLTN) { Num $d.LIVE_BUS_PPLTN.BUS_STN_CNT } else { $null })
        })
    }
}

$placeRows = foreach ($cd in $byPlace.Keys) {
    $v = $byPlace[$cd]; $last = $v | Sort-Object time | Select-Object -Last 1
    $gu = $info[$cd].gu
    [pscustomobject][ordered]@{
        '장소코드'          = $cd
        '장소'              = $info[$cd].name
        '자치구'            = $gu
        '구_판정근거'       = $info[$cd].votes
        '수집회차'          = $v.Count
        '평균인구'          = [math]::Round((Avg $v.ppl), 0)
        '비상주인구비율'    = [math]::Round((Avg $v.nonres), 1)
        '30_40대비율'       = [math]::Round((Avg $v.age3040), 1)
        '10분결제금액_만원' = $(if ($null -ne (Avg $v.payAmt)) { [math]::Round((Avg $v.payAmt) / 10000, 0) } else { $null })
        '10분결제건수'      = $(if ($null -ne (Avg $v.payCnt)) { [math]::Round((Avg $v.payCnt), 0) } else { $null })
        '법인결제비율'      = $(if ($null -ne (Avg $v.corpRate)) { [math]::Round((Avg $v.corpRate), 1) } else { $null })
        '가맹점수'          = $last.merchants
        '지하철_누적하차'   = $last.subOff
        '지하철_누적승차'   = $last.subOn
        '지하철역수'        = $last.subStn
        '버스정류장수'      = $last.busStn
        '마지막기준시각'    = $last.time
        '아파트_m2당_만원'  = $(if ($gu) { $AptM2[$gu] } else { $null })
    }
}
$placeRows = $placeRows | Sort-Object '자치구', '장소'
$placeRows | Export-Csv -Path (Join-Path $Root '장소별_실시간지표.csv') -NoTypeInformation -Encoding UTF8

$guRows = foreach ($g in $GuNames) {
    $rows = @($placeRows | Where-Object { $_.'자치구' -eq $g })
    $pplSum = ($rows | Measure-Object '평균인구' -Sum).Sum
    $wNonres = $null; $w3040 = $null
    if ($pplSum -gt 0) {
        $wNonres = ($rows | ForEach-Object { $_.'평균인구' * $_.'비상주인구비율' } | Measure-Object -Sum).Sum / $pplSum
        $w3040   = ($rows | ForEach-Object { $_.'평균인구' * $_.'30_40대비율' } | Measure-Object -Sum).Sum / $pplSum
    }
    $pay = @($rows | Where-Object { $null -ne $_.'10분결제금액_만원' })
    [pscustomobject][ordered]@{
        '자치구'               = $g
        '아파트_m2당_만원'     = $AptM2[$g]
        '아파트_84m2환산_억'   = [math]::Round($AptM2[$g] * 84 / 10000, 1)
        '핫스팟수'             = $rows.Count
        '핫스팟'               = ($rows | ForEach-Object { $_.'장소' }) -join ' / '
        '평균인구_합계'        = $pplSum
        '비상주인구비율_가중'  = $(if ($null -ne $wNonres) { [math]::Round($wNonres, 1) } else { $null })
        '30_40대비율_가중'     = $(if ($null -ne $w3040) { [math]::Round($w3040, 1) } else { $null })
        '10분결제금액_합_만원' = ($pay | Measure-Object '10분결제금액_만원' -Sum).Sum
        '법인결제비율_평균'    = $(if ($pay.Count) { [math]::Round(($pay | Measure-Object '법인결제비율' -Average).Average, 1) } else { $null })
        '가맹점수_합'          = ($rows | Measure-Object '가맹점수' -Sum).Sum
        '지하철_누적하차_합'   = ($rows | Measure-Object '지하철_누적하차' -Sum).Sum
    }
}
$guRows | Export-Csv -Path (Join-Path $Root '구별_실시간지표.csv') -NoTypeInformation -Encoding UTF8

# 보고서(집값_실시간_연결분석.html)가 읽는 데이터 파일. 브라우저에서 파일로 열어도 읽히도록 .js 로 저장합니다.
$times = @($byPlace.Values | ForEach-Object { $_ } | ForEach-Object { $_.time } | Where-Object { $_ } | Sort-Object -Unique)
$meta = [ordered]@{
    files = $files.Count; places = @($placeRows).Count
    first = $times[0]; last = $times[-1]; generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    times = $times
}
$json = '{"meta":' + ($meta | ConvertTo-Json -Compress) +
        ',"gu":' + (ConvertTo-Json @($guRows) -Compress -Depth 3) +
        ',"places":' + (ConvertTo-Json @($placeRows) -Compress -Depth 3) + '}'
[System.IO.File]::WriteAllText((Join-Path $Root '집값_연결분석_data.js'), "window.DATA = $json;", (New-Object System.Text.UTF8Encoding($false)))

$noGu = @($placeRows | Where-Object { -not $_.'자치구' })
"수집 파일 $($files.Count)개, 장소 $($placeRows.Count)곳 -> 장소별_실시간지표.csv, 구별_실시간지표.csv"
if ($noGu.Count) { "구를 못 찾은 장소: " + (($noGu | ForEach-Object { $_.'장소' }) -join ', ') }
