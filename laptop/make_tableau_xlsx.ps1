# 유동인구_주말.csv 를 Tableau 에서 쓰기 좋은 엑셀 파일(유동인구_주말_Tableau.xlsx)로 정리합니다.
#   - 시트 '유동인구_주말' : 한 줄 = 한 시각·한 장소. 시각은 진짜 날짜·시간 값, 숫자는 숫자 값으로 저장
#                            날짜·요일·시간·평균인구·혼잡도_순서 열을 추가
#   - 시트 '장소별_요약'   : 한 줄 = 장소 하나(121곳). 지도에 바로 쓰는 주말 평균 값
#   - 시트 '설명'          : 각 열의 뜻
# 값은 수식이 아닌 숫자로 넣습니다. (Tableau 는 엑셀 수식을 계산하지 않고 저장된 값만 읽기 때문)
# 먼저 make_weekend_csv.ps1 을 실행해 유동인구_주말.csv 를 최신으로 만든 뒤 실행하세요. 엑셀이 설치돼 있어야 합니다.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$InFile  = Join-Path $Root '유동인구_주말.csv'
$OutFile = Join-Path $Root '유동인구_주말_Tableau.xlsx'
$Inv     = [Globalization.CultureInfo]::InvariantCulture
$Font    = '맑은 고딕'

function Num($s) { if ($s -eq $null -or $s -eq '') { $null } else { [double]::Parse($s, $Inv) } }
function Time($s) { [datetime]::ParseExact($s, 'yyyy-MM-dd HH:mm', $Inv) }

$CongestOrder = @{ '여유' = 1; '보통' = 2; '약간 붐빔' = 3; '붐빔' = 4 }
$DayName = @{ 'Saturday' = '토요일'; 'Sunday' = '일요일' }

# ---------- 1) 원본 줄 정리 ----------
$src = Import-Csv -Path $InFile -Encoding UTF8
$ratioCols = '남성비율','여성비율','0~9세','10대','20대','30대','40대','50대','60대','70대이상','상주인구비율','비상주인구비율'

# 열 이름, 엑셀 표시 형식
$cols = @(
    @('수집시각','yyyy-mm-dd hh:mm'), @('인구기준시각','yyyy-mm-dd hh:mm'),
    @('날짜','yyyy-mm-dd'), @('요일','@'), @('시간','0'),
    @('장소코드','@'), @('장소','@'), @('자치구','@'), @('분류','@'),
    @('위도','0.000000'), @('경도','0.000000'),
    @('혼잡도','@'), @('혼잡도_순서','0'),
    @('인구_최소','#,##0'), @('인구_최대','#,##0'), @('평균인구','#,##0')
) + ($ratioCols | ForEach-Object { ,@($_, '0.0') }) + @(
    @('기온','0.0'), @('미세먼지','0'), @('초미세먼지','0'),
    @('도로소통','@'), @('도로평균속도','0')
)

$rows = foreach ($r in $src) {
    $t = Time $r.'인구기준시각'
    $avg = ((Num $r.'인구_최소') + (Num $r.'인구_최대')) / 2
    $o = [ordered]@{
        '수집시각' = Time $r.'수집시각'; '인구기준시각' = $t
        '날짜' = $t.Date; '요일' = $DayName[[string]$t.DayOfWeek]; '시간' = $t.Hour
        '장소코드' = $r.'장소코드'; '장소' = $r.'장소'; '자치구' = $r.'자치구'; '분류' = $r.'분류'
        '위도' = Num $r.'위도'; '경도' = Num $r.'경도'
        '혼잡도' = $r.'혼잡도'; '혼잡도_순서' = $CongestOrder[$r.'혼잡도']
        '인구_최소' = Num $r.'인구_최소'; '인구_최대' = Num $r.'인구_최대'; '평균인구' = $avg
    }
    foreach ($c in $ratioCols) { $o[$c] = Num $r.$c }
    $o['기온'] = Num $r.'기온'; $o['미세먼지'] = Num $r.'미세먼지'; $o['초미세먼지'] = Num $r.'초미세먼지'
    $o['도로소통'] = $r.'도로소통'; $o['도로평균속도'] = Num $r.'도로평균속도'
    [pscustomobject]$o
}

# ---------- 2) 장소별 요약 ----------
$sumCols = @(
    @('장소코드','@'), @('장소','@'), @('자치구','@'), @('분류','@'),
    @('위도','0.000000'), @('경도','0.000000'),
    @('주말_평균인구','#,##0'), @('토요일_평균인구','#,##0'), @('일요일_평균인구','#,##0'),
    @('최고인구','#,##0'), @('가장_붐빈_시각','yyyy-mm-dd hh:mm'),
    @('붐빔_비율','0.0'), @('수집횟수','0')
)
$summary = foreach ($g in ($rows | Group-Object '장소코드' | Sort-Object { $_.Group[0].'장소' })) {
    $grp = $g.Group; $f = $grp[0]
    $peak = $grp | Sort-Object '평균인구' -Descending | Select-Object -First 1
    $sat = @($grp | Where-Object { $_.'요일' -eq '토요일' }); $sun = @($grp | Where-Object { $_.'요일' -eq '일요일' })
    $busy = @($grp | Where-Object { $_.'혼잡도_순서' -ge 3 }).Count
    [pscustomobject][ordered]@{
        '장소코드' = $f.'장소코드'; '장소' = $f.'장소'; '자치구' = $f.'자치구'; '분류' = $f.'분류'
        '위도' = $f.'위도'; '경도' = $f.'경도'
        '주말_평균인구' = [math]::Round(($grp | Measure-Object '평균인구' -Average).Average)
        '토요일_평균인구' = $(if ($sat.Count) { [math]::Round(($sat | Measure-Object '평균인구' -Average).Average) })
        '일요일_평균인구' = $(if ($sun.Count) { [math]::Round(($sun | Measure-Object '평균인구' -Average).Average) })
        '최고인구' = ($grp | Measure-Object '인구_최대' -Maximum).Maximum
        '가장_붐빈_시각' = $peak.'인구기준시각'
        '붐빔_비율' = [math]::Round(100 * $busy / $grp.Count, 1)
        '수집횟수' = $grp.Count
    }
}

# ---------- 3) 설명 ----------
$notes = @(
    @('시트','열','뜻'),
    @('유동인구_주말','수집시각','데이터를 받아 온 시각'),
    @('유동인구_주말','인구기준시각','서울시가 인구를 잰 시각(30분 간격). 시간 분석에는 이 열을 쓰세요'),
    @('유동인구_주말','날짜 / 요일 / 시간','인구기준시각에서 뽑은 날짜, 요일(토·일), 시(0~23)'),
    @('유동인구_주말','자치구 / 분류 / 위도 / 경도','서울 실시간 도시데이터 장소 목록 기준. 서울대공원은 과천이라 자치구가 비어 있음'),
    @('유동인구_주말','혼잡도_순서','여유=1, 보통=2, 약간 붐빔=3, 붐빔=4 (정렬·색상용)'),
    @('유동인구_주말','인구_최소 / 인구_최대','서울시가 범위로 알려 주는 인구(명)'),
    @('유동인구_주말','평균인구','(인구_최소 + 인구_최대) / 2'),
    @('유동인구_주말','남성비율 ~ 비상주인구비율','해당 장소 인구 중 비율(%)'),
    @('유동인구_주말','기온 / 미세먼지 / 초미세먼지','℃, ㎍/㎥. 일부 시각은 서울시가 값을 주지 않아 비어 있음'),
    @('유동인구_주말','도로소통 / 도로평균속도','주변 도로 상태, 평균 속도(km/h)'),
    @('장소별_요약','주말_평균인구','주말 전체 평균인구의 평균(명)'),
    @('장소별_요약','토요일_평균인구 / 일요일_평균인구','요일별 평균인구의 평균(명)'),
    @('장소별_요약','최고인구','주말 중 가장 큰 인구_최대(명)'),
    @('장소별_요약','가장_붐빈_시각','평균인구가 가장 많았던 인구기준시각'),
    @('장소별_요약','붐빔_비율','혼잡도가 약간 붐빔 또는 붐빔이었던 비율(%)'),
    @('장소별_요약','수집횟수','이 장소의 주말 데이터 줄 수'),
    @('','',''),
    @('출처','','서울 열린데이터광장 실시간 도시데이터(citydata) API, 원본 파일: 유동인구_주말.csv')
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

    Write-Sheet $wb.Worksheets.Item(1) '유동인구_주말' $cols $rows
    Write-Sheet $wb.Worksheets.Item(2) '장소별_요약' $sumCols $summary

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
} finally {
    $xl.Quit()
    [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
}
"주말 데이터 $(@($rows).Count)줄, 장소 $(@($summary).Count)곳 저장: $OutFile"
