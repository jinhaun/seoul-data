# 사이트(index.html)가 읽는 요약 파일 site/data.json 을 만듭니다. 수집이 끝날 때마다 실행됩니다.

. "$PSScriptRoot/common.ps1"

$now = Get-KstNow
function Num($v) { $x = 0.0; if ([double]::TryParse("$v", [ref]$x)) { return $x } else { return 0.0 } }
function Days-Back([string]$folder, [int]$n, [string]$suffix = '') {
    # data/<folder>/YYYY-MM/YYYY-MM-DD<suffix>.csv 중 최근 n개 (날짜순)
    $root = Join-Path $RepoRoot "data/$folder"
    if (-not (Test-Path $root)) { return @() }
    $pat = '^\d{4}-\d{2}-\d{2}' + [regex]::Escape($suffix) + '\.csv$'
    return @(Get-ChildItem $root -Recurse -File -Filter '*.csv' | Where-Object { $_.Name -match $pat } | Sort-Object Name | Select-Object -Last $n)
}

$out = [ordered]@{ updated_at = $now.ToString('yyyy-MM-dd HH:mm') }

# ---------------- 수집 현황 (최근 30일) + 서울 121곳 인구 흐름 (최근 7일)
$status = New-Object System.Collections.Generic.List[object]
$flow = New-Object System.Collections.Generic.List[object]
$rtFiles = Days-Back 'realtime' 30
$latestRows = @()
foreach ($f in $rtFiles) {
    $rows = @(Read-Csv $f.FullName)
    $d = [datetime]::ParseExact($f.BaseName, 'yyyy-MM-dd', $null)
    $snaps = @($rows | Group-Object '인구기준시각')
    $hours = @($snaps | ForEach-Object { if ($_.Name.Length -ge 13) { $_.Name.Substring(11, 2) } } | Select-Object -Unique)
    $status.Add([ordered]@{ date = $f.BaseName; wd = (Get-WeekdayKo $d); hours = $hours.Count; snaps = $snaps.Count; places = $(if ($snaps.Count) { [int](($snaps | ForEach-Object { $_.Count } | Measure-Object -Average).Average) } else { 0 }) })
    if ($f -in @($rtFiles | Select-Object -Last 7)) {
        foreach ($g in ($snaps | Sort-Object Name)) {
            $sum = 0.0; foreach ($r in $g.Group) { $sum += (Num $r.'인구_최대') }
            $flow.Add([ordered]@{ t = $g.Name; pop = [int]$sum; n = $g.Count })
        }
    }
    $latestRows = $rows
}
$out.status = $status
$out.flow = $flow
$log = @(Read-Csv (Join-Path $RepoRoot 'data/status/수집기록.csv') | Select-Object -Last 1)
$out.last_run = $(if ($log.Count) { [ordered]@{ at = $log[0].'수집시각'; base = $log[0].'인구기준시각'; ok = [int](Num $log[0].'성공'); fail = [int](Num $log[0].'실패') } } else { $null })

# ---------------- 지금 붐비는 곳 (가장 최근 기준시각)
if ($latestRows.Count) {
    $lastStamp = @($latestRows | Sort-Object '인구기준시각' | Select-Object -Last 1)[0].'인구기준시각'
    $snap = @($latestRows | Where-Object { $_.'인구기준시각' -eq $lastStamp })
    $out.now = [ordered]@{
        base = $lastStamp
        congest = @($snap | Group-Object '혼잡도' | ForEach-Object { [ordered]@{ lvl = $_.Name; n = $_.Count } })
        top = @($snap | Sort-Object { Num $_.'인구_최대' } -Descending | Select-Object -First 15 | ForEach-Object { [ordered]@{ place = $_.'장소'; lvl = $_.'혼잡도'; min = [int](Num $_.'인구_최소'); max = [int](Num $_.'인구_최대'); temp = $_.'기온' } })
    }
    # 지도용: 121곳 전부 (위도·경도·혼잡도·인구)
    $metaPath = Join-Path $RepoRoot 'data/meta/장소_121곳.csv'
    $spots = @(if (Test-Path $metaPath) { Read-Csv $metaPath } else { Get-Hotspots })
    $geo = @{}; foreach ($s in $spots) { $geo[$s.'장소'] = $s }
    $out.now.all = @($snap | Where-Object { $geo[$_.'장소'] } | ForEach-Object {
        $g = $geo[$_.'장소']
        [ordered]@{ p = $_.'장소'; c = $g.'분류'; lvl = $_.'혼잡도'; max = [int](Num $_.'인구_최대'); lat = [Math]::Round([decimal](Num $g.'위도'), 5); lng = [Math]::Round([decimal](Num $g.'경도'), 5) }
    })
}

# ---------------- 외국인 동향 (단기체류, 올해 1월 1일부터)
$fFiles = @(Days-Back 'foreigner/단기' 400 | Where-Object { $_.BaseName -ge "$($now.Year)-01-01" })
$skip = @('날짜', '시간', '자치구코드', '자치구', '생활인구합계')
# 날짜마다 한 번만 계산해서 일별요약 표에 쌓아 둠 (매번 300일치를 다시 읽지 않게)
$sumPath = Join-Path $RepoRoot 'data/foreigner/일별요약_단기.csv'
$summary = @{}; foreach ($s in (Read-Csv $sumPath)) { $summary[$s.'날짜'] = $s }
$added = 0
foreach ($f in $fFiles) {
    if ($summary.ContainsKey($f.BaseName)) { continue }
    $rows = @(Read-Csv $f.FullName); if (-not $rows.Count) { continue }
    $o = [ordered]@{ '날짜' = $f.BaseName }
    $tot = 0.0; foreach ($r in $rows) { $tot += (Num $r.'생활인구합계') }; $o['합계'] = [int]($tot / 24)
    foreach ($n in @($rows[0].PSObject.Properties.Name | Where-Object { $_ -notin $skip })) { $s = 0.0; foreach ($r in $rows) { $s += (Num $r.$n) }; $o[$n] = [int]($s / 24) }
    $summary[$f.BaseName] = [pscustomobject]$o; $added++
}
if ($added) { Write-CsvBom $sumPath @($summary.Keys | Sort-Object | ForEach-Object { $summary[$_] }) }
$natTotals = New-Object System.Collections.Generic.List[object]
$natSum = @{}
foreach ($k in ($summary.Keys | Where-Object { $_ -ge "$($now.Year)-01-01" } | Sort-Object)) {
    $s = $summary[$k]; $byNat = [ordered]@{}
    foreach ($n in @($s.PSObject.Properties.Name | Where-Object { $_ -notin @('날짜', '합계') })) { $byNat[$n] = [int](Num $s.$n); $natSum[$n] = [double]$natSum[$n] + (Num $s.$n) }
    $natTotals.Add([ordered]@{ date = $k; wd = (Get-WeekdayKo ([datetime]::ParseExact($k, 'yyyy-MM-dd', $null))); total = [int](Num $s.'합계'); nat = $byNat })
}
# 자치구는 최근 7일 원본만 읽음
$guAcc = @{}; $guDays = 0
foreach ($f in @($fFiles | Select-Object -Last 7)) {
    $guDays++
    foreach ($r in (Read-Csv $f.FullName)) { $guAcc[$r.'자치구'] = [double]$guAcc[$r.'자치구'] + (Num $r.'생활인구합계') }
}
$topNat = @($natSum.Keys | Where-Object { $_ -ne '기타' } | Sort-Object { $natSum[$_] } -Descending | Select-Object -First 6)
# 상위 6개국만 담아서 용량 줄이기
$days = foreach ($d in $natTotals) {
    $sel = [ordered]@{}; foreach ($n in $topNat) { $sel[$n] = $d.nat[$n] }
    [ordered]@{ date = $d.date; wd = $d.wd; total = $d.total; nat = $sel }
}
$out.foreigner = [ordered]@{
    top_nat = $topNat
    days = @($days)
    gu7 = @($guAcc.Keys | Where-Object { $_ } | Sort-Object { $guAcc[$_] } -Descending | ForEach-Object { [ordered]@{ gu = $_; avg = [int]($guAcc[$_] / 24 / [Math]::Max(1, $guDays)) } })
    range7 = $(if ($fFiles.Count) { (@($fFiles | Select-Object -Last 7)[0].BaseName + ' ~ ' + $fFiles[-1].BaseName) } else { '' })
}

# ---------------- 오늘의 행사 (가장 최근 날짜)
$evFile = @(Days-Back 'events' 1 '_공식')
if ($evFile.Count) {
    $ev = @(Read-Csv $evFile[0].FullName)
    $date = $evFile[0].BaseName.Substring(0, 10)
    $web = @(Read-Csv (Join-Path $evFile[0].DirectoryName "$($date)_웹검색.csv"))
    $pick = @($ev | Where-Object { $_.'출처' -ne '서울시 문화행사' -or $_.'분류' -match '축제|콘서트|클래식|뮤지컬|연극|국악|무용' } | Select-Object -First 60)
    $out.events = [ordered]@{
        date = $date
        counts = @($ev | Group-Object '출처' | ForEach-Object { [ordered]@{ src = $_.Name; n = $_.Count } })
        by_kind = @($ev | Where-Object { $_.'출처' -eq '서울시 문화행사' } | Group-Object '분류' | Sort-Object Count -Descending | ForEach-Object { [ordered]@{ kind = $_.Name; n = $_.Count } })
        list = @($pick | ForEach-Object { [ordered]@{ src = $_.'출처'; kind = $_.'분류'; name = $_.'행사명'; gu = $_.'자치구'; place = $_.'장소'; time = $_.'운영시간'; near = $_.'가까운_관심장소'; link = $_.'링크' } })
        web = @($web | ForEach-Object { [ordered]@{ kind = $_.'분류'; name = $_.'행사명'; place = $_.'장소'; start = $_.'시작시간'; level = $_.'확인수준'; link = $_.'근거1_URL'; src = $_.'근거1_출처' } })
    }
}

# ---------------- 하늘길 (김포·인천 여객기, 공동운항 중복 줄은 빼고 실제 운항편만)
$Region = @{}
function Add-Region([string]$name, [string]$codes) { foreach ($c in ($codes -split '\s+')) { if ($c) { $Region[$c] = $name } } }
Add-Region '일본' 'NRT HND KIX ITM UKB FUK CTS NGO OKA KMQ KOJ KKJ HIJ TAK MYJ SDJ KIJ OIT FSZ AOJ UBJ TOY HSG NGS KMJ OKJ YGJ IBR AXT ISG MMB AKJ KCZ IZO HKD OBO KUH SHM TKS SHI KMI'
Add-Region '중국' 'PEK PKX PVG SHA CAN SZX TAO SHE DLC YNJ CGQ HRB WEH YNT TSN XIY CKG CTU TFU HGH NKG XMN KMG CSX WUH SJW TNA NGB HAK SYX DYG ZUH JMU MDG LYI HFE FOC KWE KWL NNG TYN URC WUX CGO WNZ YIH YTY WDS LJG TXN WUS YNZ'
Add-Region '홍콩·대만·마카오' 'HKG MFM TPE TSA KHH RMQ'
Add-Region '동남아' 'BKK DMK HKT CNX USM SGN HAN DAD CXR PQC HPH VCA DLI MNL CEB CRK KLO TAG SIN KUL BKI PEN CGK DPS PNH REP KOS VTE LPQ RGN BWN KTI MDC'
Add-Region '미주·대양주' 'LAX SFO JFK EWR IAD ORD ATL DFW SEA LAS HNL YVR YYZ BOS IAH DTW MSP SLC ANC GUM SPN SYD MEL BNE AKL PDX MIA PHX DEN SAN MEX MTY YYC'
Add-Region '유럽' 'CDG LHR FRA MUC AMS FCO MXP BCN MAD IST VIE PRG ZRH HEL WAW BUD LIS ATH CPH ARN DUB OSL BRU'
function Get-Region([string]$code, [string]$line) { if ($line -eq '국내') { return '국내' }; if ($Region.ContainsKey($code)) { return $Region[$code] }; return '기타' }

$fFlights = @(Days-Back 'flights' 60)
if ($fFlights.Count) {
    $fDays = New-Object System.Collections.Generic.List[object]
    $latestReal = @()
    foreach ($f in $fFlights) {
        $real = @(Read-Csv $f.FullName | Where-Object { $_.'코드쉐어' -notin 'Slave', 'Y' })
        $intl = @($real | Where-Object { $_.'국내국제' -ne '국내' })
        $fDays.Add([ordered]@{
            date = $f.BaseName; wd = (Get-WeekdayKo ([datetime]::ParseExact($f.BaseName, 'yyyy-MM-dd', $null)))
            intl = $intl.Count; japan = @($intl | Where-Object { (Get-Region $_.'상대공항코드' $_.'국내국제') -eq '일본' }).Count
            icn = @($intl | Where-Object { $_.'공항' -eq '인천' }).Count; gmp_intl = @($intl | Where-Object { $_.'공항' -eq '김포' }).Count
        })
        $latestReal = $real
    }
    $li = @($latestReal | Where-Object { $_.'국내국제' -ne '국내' })
    $out.flights = [ordered]@{
        date = $fFlights[-1].BaseName
        stat = [ordered]@{
            icn_intl = @($li | Where-Object { $_.'공항' -eq '인천' }).Count
            gmp_intl = @($li | Where-Object { $_.'공항' -eq '김포' }).Count
            gmp_dom = @($latestReal | Where-Object { $_.'공항' -eq '김포' -and $_.'국내국제' -eq '국내' }).Count
            japan = @($li | Where-Object { (Get-Region $_.'상대공항코드' '국제') -eq '일본' }).Count
            delay = @($latestReal | Where-Object { $_.'현황' -match '지연' }).Count
            cancel = @($latestReal | Where-Object { $_.'현황' -match '결항' }).Count
        }
        regions = @($li | Group-Object { Get-Region $_.'상대공항코드' '국제' } | Sort-Object Count -Descending | ForEach-Object { [ordered]@{ r = $_.Name; n = $_.Count } })
        top = @($li | Group-Object '상대공항코드' | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
            [ordered]@{ city = ($_.Group[0].'상대공항' -replace '/\s+', '/'); code = $_.Name; region = (Get-Region $_.Name '국제'); n = $_.Count } })
        days = $fDays
    }
}

# ---------------- 환율 (최근 120 고시일)
$fxAll = @(Read-Csv (Join-Path $RepoRoot 'data/exchange/환율_일별.csv') | Where-Object { $_.'고시여부' -eq 'Y' })
$fx = @($fxAll | Select-Object -Last 120)
$out.exchange = @($fx | ForEach-Object { [ordered]@{ date = $_.'날짜'; USD = (Num $_.'원_달러'); JPY100 = (Num $_.'원_100엔'); CNY = (Num $_.'원_위안'); THB = (Num $_.'원_바트'); INR = (Num $_.'원_루피'); EUR = (Num $_.'원_유로') } })
# 비교 기준 3가지: 전날(직전 고시일), 한 달 전(달력 기준 같은 날 또는 그 전 마지막 고시일), 올해 최고
if ($fxAll.Count -ge 2) {
    $last = $fxAll[-1]; $prev = $fxAll[-2]
    $mDay = ([datetime]::ParseExact($last.'날짜', 'yyyy-MM-dd', $null)).AddMonths(-1).ToString('yyyy-MM-dd')
    $month = @($fxAll | Where-Object { $_.'날짜' -le $mDay } | Select-Object -Last 1)[0]
    $year = @($fxAll | Where-Object { $_.'날짜'.StartsWith($last.'날짜'.Substring(0, 4)) })
    $stat = [ordered]@{}
    foreach ($c in @(@('USD', '원_달러'), @('JPY100', '원_100엔'), @('CNY', '원_위안'), @('THB', '원_바트'))) {
        $col = $c[1]; $mx = @($year | Sort-Object { Num $_.$col } -Descending | Select-Object -First 1)[0]
        $stat[$c[0]] = [ordered]@{
            now = [ordered]@{ v = (Num $last.$col); date = $last.'날짜' }
            prev = [ordered]@{ v = (Num $prev.$col); date = $prev.'날짜' }
            month = $(if ($month) { [ordered]@{ v = (Num $month.$col); date = $month.'날짜' } } else { $null })
            max = [ordered]@{ v = (Num $mx.$col); date = $mx.'날짜' }
        }
    }
    $out.exchange_stat = $stat
}

# ---------------- 숙박 (최근 30일 기록 + 최근 신규)
$lg = @(Read-Csv (Join-Path $RepoRoot 'data/status/숙박기록.csv') | Select-Object -Last 90)
$newList = New-Object System.Collections.Generic.List[object]
$chRoot = Join-Path $RepoRoot 'data/lodging/changes'
if (Test-Path $chRoot) {
    foreach ($f in (Get-ChildItem $chRoot -Recurse -File -Filter '*.csv' | Sort-Object Name -Descending | Select-Object -First 21)) {
        foreach ($c in (Read-Csv $f.FullName | Where-Object { $_.'구분' -eq '신규' })) {
            if ($newList.Count -ge 30) { break }
            $newList.Add([ordered]@{ date = $f.BaseName.Substring(0, 10); kind = $f.BaseName.Substring(11); name = $c.'업소명'; gu = $c.'자치구' })
        }
    }
}
$out.lodging = [ordered]@{
    log = @($lg | ForEach-Object { [ordered]@{ date = $_.'날짜'; kind = $_.'종류'; total = [int](Num $_.'전체'); open = [int](Num $_.'영업중'); new = [int](Num $_.'신규'); chg = [int](Num $_.'변경'); del = [int](Num $_.'삭제') } })
    recent_new = $newList
}

$json = $out | ConvertTo-Json -Depth 8 -Compress
$dst = Join-Path $RepoRoot 'site/data.json'
New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
[IO.File]::WriteAllText($dst, $json, $Utf8)
Write-Host "사이트 데이터: $dst ($([int]($json.Length / 1KB))KB)"
