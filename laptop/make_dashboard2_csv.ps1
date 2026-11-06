# 두 번째 대시보드(언제·어디에 많이 오나)용으로 방문자·환율·기온을 한 파일로 합칩니다.
# 먼저 최신화: make_nationality_csv.ps1, make_exchange_csv.ps1, make_weather_csv.ps1
# 결과: 대시보드2_데이터\
#   월별_국적_통합.csv   : 월 x 국적(6개 나라) - 하루 평균 인원, 원화 환율, 현지·서울 기온
#   월별_국적_자치구.csv : 월 x 국적(전체 + 6개 나라) x 자치구 - 하루 평균 인원, 비중, 특화지수 + 그 달 환율·기온 변화

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out  = Join-Path $Root '대시보드2_데이터'
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$nats = @('미국', '중국', '일본', '태국', '인도네시아', '프랑스')

$visit   = Import-Csv (Join-Path $Root '국적별_분석\국적별_월별.csv') -Encoding UTF8
$visitGu = Import-Csv (Join-Path $Root '국적별_분석\국적별_자치구_월별.csv') -Encoding UTF8
$fx      = Import-Csv (Join-Path $Root '환율\환율_월별.csv') -Encoding UTF8
$wx      = Import-Csv (Join-Path $Root '날씨\csv\날씨_월별_국가별.csv') -Encoding UTF8

$fxBy = @{}; foreach ($r in $fx) { $fxBy["$($r.'월')|$($r.'국적')"] = $r }
$wxBy = @{}; foreach ($r in $wx) { $wxBy["$($r.'월')|$($r.'국적')"] = $r }

# 1월 인원 (변화율 기준)
$jan = @{}
foreach ($r in $visit) { if ($r.'월' -eq '2026-01') { $jan[$r.'국적'] = [double]$r.'하루평균인원' } }

# 1) 월 x 국적
$merged = foreach ($r in ($visit | Where-Object { $_.'국적' -in $nats })) {
    $k = "$($r.'월')|$($r.'국적')"; $f = $fxBy[$k]; $w = $wxBy[$k]
    [pscustomobject][ordered]@{
        '월' = $r.'월'; '국적' = $r.'국적'
        '하루평균인원' = $r.'하루평균인원'; '평일_하루평균' = $r.'평일_하루평균'; '주말_하루평균' = $r.'주말_하루평균'
        '인원_1월대비_변화율' = [Math]::Round(([double]$r.'하루평균인원' / $jan[$r.'국적'] - 1) * 100, 1)
        '통화' = $f.'통화'; '월평균_원화환율' = $f.'월평균_원화환율'; '환율_1월대비_변화율' = $f.'1월대비_변화율'
        '도시' = $w.'도시'; '현지_월평균기온' = $w.'월평균기온'; '서울_월평균기온' = $w.'서울_월평균기온'
        '서울보다_따뜻함' = $w.'서울보다_따뜻함'; '현지_월강수량_mm' = $w.'월강수량_mm'
        '집계일수' = $r.'집계일수'
    }
}
$merged = $merged | Sort-Object '국적', '월'
$merged | Export-Csv (Join-Path $Out '월별_국적_통합.csv') -NoTypeInformation -Encoding UTF8

# 2) 월 x 국적 x 자치구 (+ 그 달 환율·기온)
$guRows = foreach ($r in ($visitGu | Where-Object { $_.'국적' -in (@('전체') + $nats) })) {
    $k = "$($r.'월')|$($r.'국적')"; $f = $fxBy[$k]; $w = $wxBy[$k]
    [pscustomobject][ordered]@{
        '월' = $r.'월'; '국적' = $r.'국적'; '자치구' = $r.'자치구'
        '하루평균인원' = $r.'하루평균인원'; '국적내비중' = $r.'국적내비중'; '특화지수' = $r.'특화지수'
        '환율_1월대비_변화율' = $(if ($f) { $f.'1월대비_변화율' } else { '' })
        '서울보다_따뜻함' = $(if ($w) { $w.'서울보다_따뜻함' } else { '' })
        '집계일수' = $r.'집계일수'
    }
}
$guRows | Export-Csv (Join-Path $Out '월별_국적_자치구.csv') -NoTypeInformation -Encoding UTF8

$readme = @(
    "대시보드2 데이터 (만든 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm')))",
    "국적: $($nats -join ', ') (환율과 날씨가 모두 있는 6개 나라). 월별_국적_자치구.csv에는 '전체'도 들어 있습니다.",
    '',
    '월별_국적_통합.csv : 한 줄 = 한 달 x 한 나라. 이 파일 하나로 "환율·기온과 방문자" 차트를 만들 수 있습니다.',
    '  하루평균인원        = 그 달 하루 평균, 서울에 머문 단기체류 외국인 수 (같은 사람이 여러 날 머물면 매일 잡힘)',
    '  인원_1월대비_변화율 = 1월보다 몇 % 늘었나',
    '  월평균_원화환율     = 그 나라 돈 1단위(엔·루피아는 100단위)가 몇 원인지. 오르면 그 나라 사람에게 한국 여행이 싸짐',
    '  환율_1월대비_변화율 = 1월보다 몇 % 올랐나 (마이너스 = 한국 여행이 비싸짐)',
    '  서울보다_따뜻함     = 현지 월평균기온 - 서울 월평균기온 (도시: 각 나라 수도)',
    '월별_국적_자치구.csv : 한 줄 = 한 달 x 한 나라 x 한 자치구. 지도에 "월" 필터를 걸어 달마다 어느 구에 많은지 볼 수 있습니다.',
    '  특화지수 = (그 나라 사람 중 이 구에 있는 비율) / (전체 외국인 중 이 구에 있는 비율). 1보다 크면 그 나라 사람이 이 구에 더 몰림',
    '  하루평균인원은 여러 달을 합칠 때 더하지 말고 평균(AVG)을 쓰세요.',
    '마지막 달(10월)은 데이터가 있는 날까지만 들어 있습니다 (집계일수 참고).',
    '다시 만들기: 프로젝트 폴더의 make_dashboard2_csv.ps1 실행'
)
[IO.File]::WriteAllLines((Join-Path $Out '읽어주세요.txt'), $readme, (New-Object Text.UTF8Encoding($true)))
"OK 통합 $(@($merged).Count)줄, 자치구 $(@($guRows).Count)줄 -> $Out"
