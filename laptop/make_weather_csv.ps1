# 2026년 1월 1일 ~ 어제까지 서울 25개 자치구의 하루 날씨(평균·최고·최저 기온, 강수량)를 받아 날씨 폴더에 저장합니다.
# 출처: Open-Meteo 과거 날씨 API (historical-forecast-api.open-meteo.com, 인증키 불필요)
#   - 각 구청 위치의 좌표로 받습니다. 기상 모델 격자 값이라 실제 관측소 값과 0.5~1도 정도 차이가 날 수 있습니다.
# 결과:
#   날씨_일별_자치구.csv : 날짜 x 자치구 (자치구 이름·코드가 외국인 데이터와 같아서 Tableau에서 날짜+자치구로 연결 가능)
#   날씨_일별_서울.csv   : 날짜별 한 줄 (25개 구 평균)
#   날씨_월별_서울.csv   : 월 평균 기온 + 월 강수량 합계
#   날씨_일별_국가별.csv : 날짜 x 7개 나라 수도 (국적 이름이 국적별_분석 파일과 같아서 날짜+국적으로 연결 가능)
#   날씨_월별_국가별.csv : 나라별 월 평균 기온 + 서울과의 기온 차이

param([string]$Start = '2026-01-01')

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out  = Join-Path $Root '날씨\csv'   # 엑셀은 make_weather_xlsx.ps1 이 이 CSV로 날씨 폴더에 만듦
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$ko = [Globalization.CultureInfo]::GetCultureInfo('ko-KR')

# 자치구 -> (코드, 구청 위도, 경도)
$gu = @(
    @('11110','종로구',37.5735,126.9790), @('11140','중구',37.5638,126.9976),
    @('11170','용산구',37.5326,126.9905), @('11200','성동구',37.5634,127.0369),
    @('11215','광진구',37.5385,127.0823), @('11230','동대문구',37.5744,127.0396),
    @('11260','중랑구',37.6066,127.0927), @('11290','성북구',37.5894,127.0167),
    @('11305','강북구',37.6396,127.0257), @('11320','도봉구',37.6688,127.0471),
    @('11350','노원구',37.6543,127.0568), @('11380','은평구',37.6027,126.9291),
    @('11410','서대문구',37.5791,126.9368), @('11440','마포구',37.5663,126.9019),
    @('11470','양천구',37.5170,126.8664), @('11500','강서구',37.5510,126.8495),
    @('11530','구로구',37.4955,126.8875), @('11545','금천구',37.4569,126.8955),
    @('11560','영등포구',37.5264,126.8962), @('11590','동작구',37.5124,126.9393),
    @('11620','관악구',37.4784,126.9516), @('11650','서초구',37.4837,127.0324),
    @('11680','강남구',37.5172,127.0473), @('11710','송파구',37.5145,127.1059),
    @('11740','강동구',37.5301,127.1238)
)

$end  = (Get-Date).Date.AddDays(-1).ToString('yyyy-MM-dd')   # 오늘은 아직 하루가 안 끝났으므로 어제까지
$lats = ($gu | ForEach-Object { $_[2] }) -join ','
$lons = ($gu | ForEach-Object { $_[3] }) -join ','
$url  = "https://historical-forecast-api.open-meteo.com/v1/forecast?latitude=$lats&longitude=$lons&start_date=$Start&end_date=$end" +
        "&daily=temperature_2m_mean,temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=Asia%2FSeoul"
$res = Invoke-RestMethod -Uri $url -TimeoutSec 120

# 날짜 x 자치구
$rows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $gu.Count; $i++) {
    $d = $res[$i].daily
    for ($j = 0; $j -lt $d.time.Count; $j++) {
        $dt = [datetime]::ParseExact($d.time[$j], 'yyyy-MM-dd', $null)
        $rows.Add([pscustomobject][ordered]@{
            '날짜'       = $d.time[$j]
            '월'         = $dt.ToString('yyyy-MM')
            '요일'       = $dt.ToString('ddd', $ko)
            '주말여부'   = $(if ($dt.DayOfWeek -in 'Saturday','Sunday') { 'Y' } else { 'N' })
            '자치구코드' = $gu[$i][0]
            '자치구'     = $gu[$i][1]
            '평균기온'   = $d.temperature_2m_mean[$j]
            '최고기온'   = $d.temperature_2m_max[$j]
            '최저기온'   = $d.temperature_2m_min[$j]
            '강수량_mm'  = $d.precipitation_sum[$j]
        })
    }
}
$rows | Export-Csv (Join-Path $Out '날씨_일별_자치구.csv') -NoTypeInformation -Encoding UTF8

# 서울 평균 (날짜별)
$seoul = $rows | Group-Object '날짜' | Sort-Object Name | ForEach-Object {
    $g = $_.Group
    [pscustomobject][ordered]@{
        '날짜'      = $_.Name
        '월'        = $g[0].'월'
        '요일'      = $g[0].'요일'
        '주말여부'  = $g[0].'주말여부'
        '평균기온'  = [math]::Round(($g | Measure-Object '평균기온' -Average).Average, 1)
        '최고기온'  = [math]::Round(($g | Measure-Object '최고기온' -Average).Average, 1)
        '최저기온'  = [math]::Round(($g | Measure-Object '최저기온' -Average).Average, 1)
        '강수량_mm' = [math]::Round(($g | Measure-Object '강수량_mm' -Average).Average, 1)
    }
}
$seoul | Export-Csv (Join-Path $Out '날씨_일별_서울.csv') -NoTypeInformation -Encoding UTF8

# 서울 월별
$monthly = $seoul | Group-Object '월' | Sort-Object Name | ForEach-Object {
    $g = $_.Group
    [pscustomobject][ordered]@{
        '월'            = $_.Name
        '월평균기온'    = [math]::Round(($g | Measure-Object '평균기온' -Average).Average, 1)
        '월평균_최고'   = [math]::Round(($g | Measure-Object '최고기온' -Average).Average, 1)
        '월평균_최저'   = [math]::Round(($g | Measure-Object '최저기온' -Average).Average, 1)
        '월강수량_mm'   = [math]::Round(($g | Measure-Object '강수량_mm' -Sum).Sum, 1)
        '비온날수'      = @($g | Where-Object { $_.'강수량_mm' -ge 1 }).Count
        '일수'          = $g.Count
    }
}
$monthly | Export-Csv (Join-Path $Out '날씨_월별_서울.csv') -NoTypeInformation -Encoding UTF8

# 외국인 출발 나라 (수도 기준) -> (국적, 도시, 위도, 경도)
$nat = @(
    @('미국','워싱턴DC(미국)',38.9072,-77.0369), @('중국','베이징(중국)',39.9042,116.4074),
    @('일본','도쿄(일본)',35.6762,139.6503),     @('태국','방콕(태국)',13.7563,100.5018),
    @('인도네시아','자카르타(인도네시아)',-6.2088,106.8456), @('프랑스','파리(프랑스)',48.8566,2.3522),
    @('캐나다','오타와(캐나다)',45.4215,-75.6972)
)
$lats = ($nat | ForEach-Object { $_[2] }) -join ','
$lons = ($nat | ForEach-Object { $_[3] }) -join ','
$url  = "https://historical-forecast-api.open-meteo.com/v1/forecast?latitude=$lats&longitude=$lons&start_date=$Start&end_date=$end" +
        "&daily=temperature_2m_mean,temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=auto"
$res = Invoke-RestMethod -Uri $url -TimeoutSec 120

$seoulTemp = @{}; foreach ($s in $seoul) { $seoulTemp[$s.'날짜'] = $s.'평균기온' }
$natRows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $nat.Count; $i++) {
    $d = $res[$i].daily
    for ($j = 0; $j -lt $d.time.Count; $j++) {
        $dt = [datetime]::ParseExact($d.time[$j], 'yyyy-MM-dd', $null)
        $t  = $d.temperature_2m_mean[$j]
        $natRows.Add([pscustomobject][ordered]@{
            '날짜'           = $d.time[$j]
            '월'             = $dt.ToString('yyyy-MM')
            '요일'           = $dt.ToString('ddd', $ko)
            '국적'           = $nat[$i][0]
            '도시'           = $nat[$i][1]
            '평균기온'       = $t
            '최고기온'       = $d.temperature_2m_max[$j]
            '최저기온'       = $d.temperature_2m_min[$j]
            '강수량_mm'      = $d.precipitation_sum[$j]
            '서울_평균기온'  = $seoulTemp[$d.time[$j]]
            '서울보다_따뜻함' = $(if ($null -ne $t -and $null -ne $seoulTemp[$d.time[$j]]) { [math]::Round($t - $seoulTemp[$d.time[$j]], 1) })
        })
    }
}
$natRows | Export-Csv (Join-Path $Out '날씨_일별_국가별.csv') -NoTypeInformation -Encoding UTF8

$seoulMonth = @{}; foreach ($m in $monthly) { $seoulMonth[$m.'월'] = $m.'월평균기온' }
$natMonthly = $natRows | Group-Object '국적','월' | ForEach-Object {
    $g = $_.Group
    $avg = [math]::Round(($g | Measure-Object '평균기온' -Average).Average, 1)
    [pscustomobject][ordered]@{
        '월'              = $g[0].'월'
        '국적'            = $g[0].'국적'
        '도시'            = $g[0].'도시'
        '월평균기온'      = $avg
        '월강수량_mm'     = [math]::Round(($g | Measure-Object '강수량_mm' -Sum).Sum, 1)
        '서울_월평균기온' = $seoulMonth[$g[0].'월']
        '서울보다_따뜻함' = [math]::Round($avg - $seoulMonth[$g[0].'월'], 1)
    }
} | Sort-Object '국적','월'
$natMonthly | Export-Csv (Join-Path $Out '날씨_월별_국가별.csv') -NoTypeInformation -Encoding UTF8

$readme = @"
날씨 데이터 (만든 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm')))
기간: $Start ~ $end
출처: Open-Meteo 과거 날씨 API (인증키 불필요). 각 구청 위치 좌표의 기상 모델 값입니다.
  기상청 관측소 값과 0.5~1도 정도 차이가 날 수 있고, 서울 안에서는 구끼리 차이가 1도 안팎으로 작습니다.
파일 (모두 엑셀, Tableau에서 "Microsoft Excel"로 연결):
  날씨_Tableau.xlsx    : 아래 국가별 일별·월별(서울 포함)을 시트 두 개로 묶은 파일. 보통은 이것 하나면 됩니다.
  날씨_일별_자치구.xlsx: 날짜 x 25개 자치구. 자치구·자치구코드·날짜가 외국인 데이터와 같아서 Tableau에서 바로 연결할 수 있습니다.
  날씨_일별_서울.xlsx  : 25개 구 평균, 날짜별 한 줄.
  날씨_월별_서울.xlsx  : 월 평균 기온, 월 강수량 합계, 비 온 날 수(1mm 이상).
  날씨_일별_국가별.xlsx: 날짜 x 7개 나라 수도(미국=워싱턴DC, 중국=베이징, 일본=도쿄, 태국=방콕, 인도네시아=자카르타, 프랑스=파리, 캐나다=오타와).
                         국적 이름이 국적별_분석 파일과 같아서 Tableau에서 날짜+국적으로 연결할 수 있습니다.
                         날짜는 그 나라 현지 날짜입니다. 서울보다_따뜻함 = 그 도시 평균기온 - 서울 평균기온 (마이너스면 서울이 더 따뜻함).
  날씨_월별_국가별.xlsx: 나라별 월 평균 기온, 월 강수량, 서울과의 기온 차이.
  주의: 미국·중국처럼 큰 나라는 수도 한 곳의 날씨가 나라 전체를 대표하지 못합니다. 도시를 바꾸려면 스크립트의 `$nat 목록을 고치세요.
여러 날을 합칠 때 기온은 평균(AVG), 강수량은 합계(SUM)를 쓰세요.
주말여부: 토·일 = Y. 공휴일은 평일(N)로 들어가 있습니다.
csv 폴더: 엑셀을 만들 때 쓰는 원본(같은 내용의 CSV)입니다. 지우지 마세요.
다시 받기: 프로젝트 폴더의 make_weather_csv.ps1 실행 -> make_weather_xlsx.ps1 실행
"@
[IO.File]::WriteAllLines((Join-Path $Root '날씨\읽어주세요.txt'), $readme, (New-Object Text.UTF8Encoding($true)))

Write-Host "완료: $Out ($($rows.Count) 줄, $Start ~ $end)"
