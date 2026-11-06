# 날씨 폴더의 CSV를 Tableau 에서 쓰기 좋은 엑셀 파일(날씨\날씨_Tableau.xlsx)로 정리합니다.
#   - 시트 '일별_국가별' : 한 줄 = 하루 x 도시. 7개 나라 수도 + 서울(국적 = 한국)
#   - 시트 '월별_국가별' : 한 줄 = 한 달 x 도시. 7개 나라 수도 + 서울 (서울 = 25개 구 평균의 월평균)
#   - 시트 '설명'        : 각 열의 뜻
# 그리고 날씨\csv 의 CSV 하나하나를 같은 이름의 엑셀(날씨\이름.xlsx, 시트 하나)로도 바꿉니다.
# 값은 수식이 아닌 숫자로 넣습니다. 먼저 make_weather_csv.ps1 을 실행해 CSV를 최신으로 만든 뒤 실행하세요. 엑셀이 설치돼 있어야 합니다.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutDir  = Join-Path $Root '날씨'
$InDir   = Join-Path $OutDir 'csv'
$OutFile = Join-Path $OutDir '날씨_Tableau.xlsx'
$Inv     = [Globalization.CultureInfo]::InvariantCulture
$Font    = '맑은 고딕'

function Num($s) { if ($s -eq $null -or $s -eq '') { $null } else { [double]::Parse($s, $Inv) } }
function Day($s) { [datetime]::ParseExact($s, 'yyyy-MM-dd', $Inv) }

$natDaily  = Import-Csv (Join-Path $InDir '날씨_일별_국가별.csv') -Encoding UTF8
$natMonth  = Import-Csv (Join-Path $InDir '날씨_월별_국가별.csv') -Encoding UTF8
$seoulDay  = Import-Csv (Join-Path $InDir '날씨_일별_서울.csv') -Encoding UTF8
$seoulMon  = Import-Csv (Join-Path $InDir '날씨_월별_서울.csv') -Encoding UTF8

# ---------- 1) 일별: 7개 나라 + 서울 ----------
$dailyCols = @(
    @('날짜','yyyy-mm-dd'), @('월','@'), @('요일','@'), @('국적','@'), @('도시','@'),
    @('평균기온','0.0'), @('최고기온','0.0'), @('최저기온','0.0'), @('강수량_mm','0.0'),
    @('서울_평균기온','0.0'), @('서울보다_따뜻함','0.0')
)
$daily = @(foreach ($r in $natDaily) {
    [pscustomobject][ordered]@{
        '날짜' = Day $r.'날짜'; '월' = $r.'월'; '요일' = $r.'요일'; '국적' = $r.'국적'; '도시' = $r.'도시'
        '평균기온' = Num $r.'평균기온'; '최고기온' = Num $r.'최고기온'; '최저기온' = Num $r.'최저기온'
        '강수량_mm' = Num $r.'강수량_mm'; '서울_평균기온' = Num $r.'서울_평균기온'; '서울보다_따뜻함' = Num $r.'서울보다_따뜻함'
    }
}) + @(foreach ($r in $seoulDay) {
    [pscustomobject][ordered]@{
        '날짜' = Day $r.'날짜'; '월' = $r.'월'; '요일' = $r.'요일'; '국적' = '한국'; '도시' = '서울(한국)'
        '평균기온' = Num $r.'평균기온'; '최고기온' = Num $r.'최고기온'; '최저기온' = Num $r.'최저기온'
        '강수량_mm' = Num $r.'강수량_mm'; '서울_평균기온' = Num $r.'평균기온'; '서울보다_따뜻함' = 0
    }
})

# ---------- 2) 월별: 7개 나라 + 서울 ----------
$monthCols = @(
    @('월','@'), @('국적','@'), @('도시','@'),
    @('월평균기온','0.0'), @('월강수량_mm','0.0'), @('서울_월평균기온','0.0'), @('서울보다_따뜻함','0.0')
)
$monthly = @(foreach ($r in $natMonth) {
    [pscustomobject][ordered]@{
        '월' = $r.'월'; '국적' = $r.'국적'; '도시' = $r.'도시'
        '월평균기온' = Num $r.'월평균기온'; '월강수량_mm' = Num $r.'월강수량_mm'
        '서울_월평균기온' = Num $r.'서울_월평균기온'; '서울보다_따뜻함' = Num $r.'서울보다_따뜻함'
    }
}) + @(foreach ($r in $seoulMon) {
    [pscustomobject][ordered]@{
        '월' = $r.'월'; '국적' = '한국'; '도시' = '서울(한국)'
        '월평균기온' = Num $r.'월평균기온'; '월강수량_mm' = Num $r.'월강수량_mm'
        '서울_월평균기온' = Num $r.'월평균기온'; '서울보다_따뜻함' = 0
    }
})

# ---------- 설명 ----------
$notes = @(
    @('시트','열','뜻'),
    @('일별_국가별','국적·도시','미국=워싱턴DC, 중국=베이징, 일본=도쿄, 태국=방콕, 인도네시아=자카르타, 프랑스=파리, 캐나다=오타와, 한국=서울(25개 구 평균)'),
    @('일별_국가별','날짜','그 도시의 현지 날짜'),
    @('일별_국가별','평균·최고·최저기온','그날의 기온(℃)'),
    @('일별_국가별','서울_평균기온','같은 날 서울(25개 구 평균) 평균기온'),
    @('일별_국가별','서울보다_따뜻함','그 도시 평균기온 - 서울 평균기온. 마이너스면 서울이 더 따뜻함. 서울 줄은 0'),
    @('월별_국가별','월평균기온','그 달 하루 평균기온의 평균'),
    @('월별_국가별','월강수량_mm','그 달 강수량 합계'),
    @('월별_국가별','서울(한국)','25개 구 날씨를 평균 낸 서울 값의 월평균. 구별 일별 날씨는 날씨_일별_자치구.csv 에 있음'),
    @('','',''),
    @('주의','','여러 날을 합칠 때 기온은 평균(AVG), 강수량은 합계(SUM)를 쓰세요. 국적 이름이 외국인 데이터와 같아서 월+국적으로 연결할 수 있습니다(한국 줄은 짝이 없음).'),
    @('출처','','Open-Meteo 과거 날씨 API (기상 모델 값, 관측소 값과 0.5~1도 차이 가능). 원본: 날씨 폴더 CSV')
)

# ---------- 4) 엑셀로 쓰기 ----------
function Cell($v) {   # 엑셀이 받는 형태(빈칸·글자·숫자)로만 바꿔서 넘김
    if ($v -eq $null) { return $null }
    if ($v -is [datetime]) { return [double]$v.ToOADate() }
    if ($v -is [string]) { if ($v -eq '') { return $null } else { return [string]$v } }
    return [double]$v
}
function Write-Sheet($ws, $name, $colSpec, $data) {
    $ws.Name = $name
    $nR = @($data).Count + 1; $nC = $colSpec.Count
    $arr = New-Object 'object[,]' $nR, $nC
    for ($c = 0; $c -lt $nC; $c++) { $arr[0, $c] = [string]$colSpec[$c][0] }
    $i = 1
    foreach ($row in $data) {
        for ($c = 0; $c -lt $nC; $c++) { $arr[$i, $c] = Cell $row.($colSpec[$c][0]) }
        $i++
    }
    for ($c = 0; $c -lt $nC; $c++) {   # 형식을 먼저 정해야 글자 열이 숫자로 바뀌지 않음
        if (-not $colSpec[$c][1]) { continue }   # 형식 없음 = 엑셀 기본(일반)
        $ws.Range($ws.Cells(2, $c + 1), $ws.Cells([math]::Max($nR, 2), $c + 1)).NumberFormat = $colSpec[$c][1]
    }
    $range = $ws.Range($ws.Cells(1, 1), $ws.Cells($nR, $nC))
    $range.Value2 = $arr
    $range.Font.Name = $Font; $range.Font.Size = 10
    $hdr = $ws.Range($ws.Cells(1, 1), $ws.Cells(1, $nC))
    $hdr.Font.Bold = $true; $hdr.Interior.Color = 0xEBE3DA   # 연한 파랑 (BGR)
    $range.AutoFilter() | Out-Null
    $ws.Columns.AutoFit() | Out-Null
}

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.ScreenUpdating = $false
try {
    $wb = $xl.Workbooks.Add()
    while ($wb.Worksheets.Count -lt 3) { $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count)) | Out-Null }
    while ($wb.Worksheets.Count -gt 3) { $wb.Worksheets.Item($wb.Worksheets.Count).Delete() }

    Write-Sheet $wb.Worksheets.Item(1) '일별_국가별' $dailyCols $daily
    Write-Sheet $wb.Worksheets.Item(2) '월별_국가별' $monthCols $monthly

    $ws = $wb.Worksheets.Item(3); $ws.Name = '설명'
    $arr = New-Object 'object[,]' $notes.Count, 3
    for ($i = 0; $i -lt $notes.Count; $i++) { for ($c = 0; $c -lt 3; $c++) { $arr[$i, $c] = $notes[$i][$c] } }
    $range = $ws.Range($ws.Cells(1, 1), $ws.Cells($notes.Count, 3))
    $range.Value2 = $arr; $range.Font.Name = $Font; $range.Font.Size = 10
    $ws.Range('A1:C1').Font.Bold = $true; $ws.Range('A1:C1').Interior.Color = 0xEBE3DA
    $ws.Columns.AutoFit() | Out-Null

    # 첫 줄(제목) 고정
    foreach ($n in 1, 2) {
        $wb.Worksheets.Item($n).Activate()
        $xl.ActiveWindow.SplitRow = 1; $xl.ActiveWindow.SplitColumn = 0; $xl.ActiveWindow.FreezePanes = $true
    }
    $wb.Worksheets.Item(1).Activate()

    if (Test-Path $OutFile) { Remove-Item $OutFile }
    $wb.SaveAs($OutFile, 51)   # 51 = .xlsx
    $wb.Close($false)

    # CSV 하나 -> 같은 이름의 엑셀 하나 (날짜는 날짜, 숫자는 숫자, 나머지는 글자)
    $textCols = '월','요일','주말여부','국적','도시','자치구','자치구코드'
    foreach ($csv in Get-ChildItem $InDir -Filter '*.csv') {
        $src = @(Import-Csv $csv.FullName -Encoding UTF8)
        $names = @($src[0].PSObject.Properties.Name)
        $spec = foreach ($n in $names) {
            if ($n -eq '날짜') { ,@($n, 'yyyy-mm-dd') } elseif ($n -in $textCols) { ,@($n, '@') } else { ,@($n, '') }
        }
        $data = foreach ($r in $src) {
            $o = [ordered]@{}
            foreach ($s in $spec) {
                $v = $r.($s[0])
                $o[$s[0]] = if ($s[1] -eq 'yyyy-mm-dd') { Day $v } elseif ($s[1] -eq '@') { $v } else { Num $v }   # 형식 없는 열 = 숫자
            }
            [pscustomobject]$o
        }
        $wb = $xl.Workbooks.Add()
        while ($wb.Worksheets.Count -gt 1) { $wb.Worksheets.Item($wb.Worksheets.Count).Delete() }
        Write-Sheet $wb.Worksheets.Item(1) $csv.BaseName.Replace('날씨_', '') $spec $data
        $xl.ActiveWindow.SplitRow = 1; $xl.ActiveWindow.SplitColumn = 0; $xl.ActiveWindow.FreezePanes = $true
        $xf = Join-Path $OutDir ($csv.BaseName + '.xlsx')
        if (Test-Path $xf) { Remove-Item $xf }
        $wb.SaveAs($xf, 51)
        $wb.Close($false)
        "  $($csv.BaseName).xlsx ($($src.Count)줄)"
    }
} finally {
    $xl.Quit()
    [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
}
"일별 $(@($daily).Count)줄, 월별 $(@($monthly).Count)줄 저장: $OutFile"
