# 2026년 1월 1일 ~ 오늘의 원화 환율을 8개 통화로 받아 환율 폴더에 저장합니다.
# 출처: 유럽중앙은행(ECB) 기준환율 (frankfurter.dev 공개 API, 인증키 불필요)
#   - ECB는 영업일(평일)에만 고시합니다. 주말·휴일은 직전 고시값을 그대로 이어 붙이고 "고시일" 열에 실제 날짜를 남깁니다.
#   - 한국은행 매매기준율과는 0.5~1% 정도 차이가 날 수 있습니다 (기준 시각·기관이 다름).
# 결과:
#   환율_일별.csv        : 날짜별 한 줄 (원/달러, 원/100엔, 원/위안, 원/바트, 원/루피, 원/유로, 원/100루피아, 원/캐나다달러)
#   환율_일별_국가별.csv : 날짜 x 국적 (국적 이름이 국적별_분석 파일과 같아서 Tableau에서 바로 연결 가능)
#   환율_월별.csv        : 월 평균 + 1월 대비 변화율

param([string]$Start = '2026-01-01')

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out  = Join-Path $Root '환율'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$ko = [Globalization.CultureInfo]::GetCultureInfo('ko-KR')

# 통화 -> (국적, 열 이름, 단위)
$cur = [ordered]@{
    'USD' = @{ Nat = '미국';   Col = '원_달러';  Unit = 1; Name = '달러' }
    'JPY' = @{ Nat = '일본';   Col = '원_100엔'; Unit = 100; Name = '엔' }
    'CNY' = @{ Nat = '중국';   Col = '원_위안';  Unit = 1; Name = '위안' }
    'THB' = @{ Nat = '태국';   Col = '원_바트';  Unit = 1; Name = '바트' }
    'INR' = @{ Nat = '인도';   Col = '원_루피';  Unit = 1; Name = '루피' }
    'EUR' = @{ Nat = '프랑스'; Col = '원_유로';  Unit = 1; Name = '유로' }
    'IDR' = @{ Nat = '인도네시아'; Col = '원_100루피아'; Unit = 100; Name = '루피아' }   # 1루피아가 0.1원도 안 돼서 100루피아 단위
    'CAD' = @{ Nat = '캐나다'; Col = '원_캐나다달러'; Unit = 1; Name = '캐나다달러' }
}

$end = (Get-Date).Date
$url = "https://api.frankfurter.dev/v1/$Start..$($end.ToString('yyyy-MM-dd'))?from=USD&to=KRW,JPY,CNY,THB,INR,EUR,IDR,CAD"
$res = Invoke-RestMethod -Uri $url -TimeoutSec 60

# 고시일별 원화 환율 계산: (원/달러) / (해당 통화/달러) x 단위
$posted = @{}
foreach ($p in $res.rates.PSObject.Properties) {
    $r = $p.Value
    $krw = [double]$r.KRW
    $row = @{}
    foreach ($c in $cur.Keys) {
        $perUsd = if ($c -eq 'USD') { 1.0 } else { [double]$r.$c }
        $row[$c] = [Math]::Round($krw / $perUsd * $cur[$c].Unit, 2)
    }
    $posted[$p.Name] = $row
}
$postedDates = @($posted.Keys | Sort-Object)

# 달력의 모든 날짜로 펼치기 (주말·휴일은 직전 고시값)
$daily = New-Object System.Collections.Generic.List[object]
$last = $null; $lastDate = $null
# 시작일이 휴일이면 API가 직전 고시일(예: 12/31)부터 주므로 그 값으로 시작
$before = @($postedDates | Where-Object { $_ -lt $Start }) | Select-Object -Last 1
if ($before) { $last = $posted[$before]; $lastDate = $before }
for ($d = [datetime]::ParseExact($Start, 'yyyy-MM-dd', $null); $d -le $end; $d = $d.AddDays(1)) {
    $k = $d.ToString('yyyy-MM-dd')
    if ($posted.ContainsKey($k)) { $last = $posted[$k]; $lastDate = $k }
    if (-not $last) { continue }   # 첫 고시 전 날짜는 건너뜀
    $o = [ordered]@{
        '날짜' = $k; '월' = $d.ToString('yyyy-MM'); '요일' = $d.ToString('ddd', $ko)
        '주말여부' = $(if ($d.DayOfWeek -in 'Saturday', 'Sunday') { 'Y' } else { 'N' })
        '고시일' = $lastDate; '고시여부' = $(if ($lastDate -eq $k) { 'Y' } else { 'N' })
    }
    foreach ($c in $cur.Keys) { $o[$cur[$c].Col] = $last[$c] }
    $daily.Add([pscustomobject]$o)
}
$daily | Export-Csv (Join-Path $Out '환율_일별.csv') -NoTypeInformation -Encoding UTF8

# 국적별 길게 (Tableau 연결용)
$long = foreach ($r in $daily) {
    foreach ($c in $cur.Keys) {
        [pscustomobject][ordered]@{
            '날짜' = $r.'날짜'; '월' = $r.'월'; '요일' = $r.'요일'; '주말여부' = $r.'주말여부'
            '국적' = $cur[$c].Nat; '통화' = $c
            '단위' = "$($cur[$c].Unit)$($cur[$c].Name)당 원"   # 예: 1달러당 원, 100엔당 원
            '원화환율' = $r.($cur[$c].Col)
            '고시일' = $r.'고시일'
        }
    }
}
$long | Export-Csv (Join-Path $Out '환율_일별_국가별.csv') -NoTypeInformation -Encoding UTF8

# 월 평균 (실제 고시일만으로 평균) + 1월 대비 변화
$postedRows = @($daily | Where-Object { $_.'고시여부' -eq 'Y' })
$months = @($postedRows.'월' | Sort-Object -Unique)
$base = @{}
$monthly = foreach ($m in $months) {
    $g = @($postedRows | Where-Object { $_.'월' -eq $m })
    foreach ($c in $cur.Keys) {
        $avg = ($g | Measure-Object $cur[$c].Col -Average).Average
        if (-not $base.ContainsKey($c)) { $base[$c] = $avg }
        [pscustomobject][ordered]@{
            '월' = $m; '국적' = $cur[$c].Nat; '통화' = $c
            '월평균_원화환율' = [Math]::Round($avg, 2)
            '1월대비_변화율' = [Math]::Round(($avg / $base[$c] - 1) * 100, 2)
            '단위' = "$($cur[$c].Unit)$($cur[$c].Name)당 원"
            '고시일수' = $g.Count
        }
    }
}
$monthly | Export-Csv (Join-Path $Out '환율_월별.csv') -NoTypeInformation -Encoding UTF8

$readme = @(
    "환율 데이터 (만든 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm')))",
    "기간: $($daily[0].'날짜') ~ $($daily[-1].'날짜') (실제 고시일 $($postedDates.Count)일)",
    '출처: 유럽중앙은행(ECB) 기준환율, frankfurter.dev 공개 API. 원화 환율은 ECB의 원/달러와 각 통화/달러로 계산했습니다.',
    '한국은행 매매기준율(공식)과 0.5~1% 정도 차이가 날 수 있습니다. 공식 환율이 필요하면 한국은행 ECOS 인증키로 다시 받으세요.',
    '주말·휴일은 직전 고시값을 이어 붙였습니다 (고시여부 = N, 고시일 = 실제 값의 날짜).',
    '엔화와 루피아는 100단위당 원, 나머지는 1단위당 원입니다. 원화환율이 오르면 = 그 나라 돈의 가치가 오름 = 그 나라 관광객에게 한국 여행이 싸짐.',
    '국적 열(미국·일본·중국·태국·인도·프랑스·인도네시아·캐나다)은 국적별_분석 파일의 국적 이름과 같아서 Tableau에서 날짜+국적으로 연결할 수 있습니다.',
    '다시 받기: 프로젝트 폴더의 make_exchange_csv.ps1 실행'
)
[IO.File]::WriteAllLines((Join-Path $Out '읽어주세요.txt'), $readme, (New-Object Text.UTF8Encoding($true)))
"OK 고시일 $($postedDates.Count)일, 달력 $($daily.Count)일 -> $Out"
