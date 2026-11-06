# 폴더 안의 CSV를 엑셀(.xlsx)로 바꿉니다. 엑셀이 설치돼 있어야 합니다.
#   날짜 열(날짜·시작일·종료일) = 진짜 날짜, 모든 값이 숫자인 열 = 숫자, 나머지 = 글자 (코드·월은 글자로 둬서 연결이 깨지지 않게)
#   -Combine 을 주면 CSV마다 시트 하나씩, 엑셀 파일 하나로 합칩니다 (Tableau에서 파일 하나만 열면 시트가 다 보임).
# 사용 예:
#   .\csv_to_xlsx.ps1 해커톤_데이터\csv 해커톤_데이터                       -> CSV마다 엑셀 파일 하나
#   .\csv_to_xlsx.ps1 해커톤_데이터\csv,동별_분석 해커톤_데이터 -Combine 해커톤_데이터.xlsx -Notes 해커톤_데이터\읽어주세요.txt
#   -Sheets '..\외국인 프로젝트\외국인관광_대시보드.xlsx|1_관광명소' 처럼 주면 다른 엑셀의 시트를 그대로 복사해 맨 앞에 넣음

param(
    [Parameter(Mandatory = $true)][string[]]$Src,   # CSV가 있는 폴더 (여러 개면 쉼표로, 프로젝트 폴더 기준 상대 경로 가능)
    [string]$Dst,                                   # 엑셀을 둘 폴더 (없으면 첫 Src와 같은 곳)
    [string]$Combine,                               # 합칠 엑셀 파일 이름
    [string[]]$Order,                               # 합칠 때 시트 순서 (CSV 이름, 빠진 것은 뒤에 이름순)
    [string]$Notes,                                 # 합칠 때 맨 뒤 '설명' 시트에 넣을 텍스트 파일
    [string[]]$Sheets                               # 합칠 때 맨 앞에 그대로 복사해 올 엑셀 시트들 ("파일경로|시트이름")
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
function Abs($p) { if ([IO.Path]::IsPathRooted($p)) { $p } else { [IO.Path]::GetFullPath((Join-Path $Root $p)) } }
$Src = @($Src | ForEach-Object { Abs $_ })
$Dst = if ($Dst) { Abs $Dst } else { $Src[0] }
New-Item -ItemType Directory -Force -Path $Dst | Out-Null
$Inv  = [Globalization.CultureInfo]::InvariantCulture
$Font = '맑은 고딕'

$dateCols = '날짜', '시작일', '종료일'
$textCols = '월', '자치구코드', '행정동코드', '고시일'   # 숫자처럼 보여도 글자로 둘 열

function IsNum($s) { $d = 0.0; [double]::TryParse($s, [Globalization.NumberStyles]::Float, $Inv, [ref]$d) }

# CSV 하나를 시트 하나에 씀
function Write-CsvSheet($ws, $csv) {
    $data = @(Import-Csv $csv.FullName -Encoding UTF8)
    $names = @($data[0].PSObject.Properties.Name)
    $kind = @{}
    foreach ($n in $names) {
        if ($n -in $dateCols) { $kind[$n] = 'date' }
        elseif ($n -in $textCols) { $kind[$n] = 'text' }
        else {
            $vals = @($data | ForEach-Object { $_.$n } | Where-Object { $_ -ne '' })
            $k = if ($vals.Count -and -not @($vals | Where-Object { -not (IsNum $_) }).Count) { 'num' } else { 'text' }
            $kind[$n] = $k   # $hash[..] = if (...) 꼴은 PowerShell 5.1에서 오류가 나서 한 번 받아서 넣음
        }
    }
    $nR = $data.Count + 1; $nC = $names.Count
    $arr = New-Object 'object[,]' $nR, $nC
    for ($c = 0; $c -lt $nC; $c++) { $arr[0, $c] = $names[$c] }
    for ($i = 0; $i -lt $data.Count; $i++) {
        for ($c = 0; $c -lt $nC; $c++) {
            $v = $data[$i].($names[$c])
            $x = $null
            if ($v -eq '') { }
            elseif ($kind[$names[$c]] -eq 'date') { $x = [datetime]::ParseExact($v, 'yyyy-MM-dd', $Inv).ToOADate() }
            elseif ($kind[$names[$c]] -eq 'num') { $x = [double]::Parse($v, $Inv) }
            else { $x = [string]$v }
            $arr[($i + 1), $c] = $x
        }
    }
    $ws.Name = $csv.BaseName.Substring(0, [Math]::Min(31, $csv.BaseName.Length))
    for ($c = 0; $c -lt $nC; $c++) {   # 형식을 먼저 정해야 글자 열이 숫자로 바뀌지 않음
        $col = $ws.Range($ws.Cells(2, $c + 1), $ws.Cells([Math]::Max($nR, 2), $c + 1))
        switch ($kind[$names[$c]]) { 'date' { $col.NumberFormat = 'yyyy-mm-dd' } 'text' { $col.NumberFormat = '@' } }
    }
    $range = $ws.Range($ws.Cells(1, 1), $ws.Cells($nR, $nC))
    $range.Value2 = $arr
    $range.Font.Name = $Font; $range.Font.Size = 10
    $hdr = $ws.Range($ws.Cells(1, 1), $ws.Cells(1, $nC))
    $hdr.Font.Bold = $true; $hdr.Interior.Color = 0xEBE3DA   # 연한 파랑 (BGR)
    $range.AutoFilter() | Out-Null
    $ws.Columns.AutoFit() | Out-Null
    $ws.Activate()
    $xl.ActiveWindow.SplitRow = 1; $xl.ActiveWindow.SplitColumn = 0; $xl.ActiveWindow.FreezePanes = $true
    "  $($ws.Name) ($($data.Count)줄)"
}

$csvs = @(foreach ($s in $Src) { Get-ChildItem $s -Filter '*.csv' })
if ($Order) {
    $rank = @{}; for ($i = 0; $i -lt $Order.Count; $i++) { $rank[$Order[$i]] = $i }
    $csvs = @($csvs | Sort-Object { if ($rank.ContainsKey($_.BaseName)) { $rank[$_.BaseName] } else { 1000 } }, BaseName)
}

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.ScreenUpdating = $false
try {
    if ($Combine) {
        $wb = $xl.Workbooks.Add()
        while ($wb.Worksheets.Count -gt 1) { $wb.Worksheets.Item($wb.Worksheets.Count).Delete() }
        $blank = $wb.Worksheets.Item(1)   # 새 문서의 빈 시트 (마지막에 지움)
        foreach ($spec in $Sheets) {      # 다른 엑셀의 시트를 내용·서식 그대로 복사
            $path, $name = $spec.Split('|')
            $book = $xl.Workbooks.Open((Abs $path), 0, $true)   # $src 로 쓰면 매개변수 $Src(글자 목록)와 겹침
            $book.Worksheets.Item($name).Copy([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
            $book.Close($false)
            $ws = $wb.Worksheets.Item($wb.Worksheets.Count)
            "  $($ws.Name) ($($ws.UsedRange.Rows.Count - 1)줄, $([IO.Path]::GetFileName($path))에서 복사)"
        }
        for ($i = 0; $i -lt $csvs.Count; $i++) {
            $ws = if ($i -eq 0 -and -not $Sheets) { $blank } else { $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count)) }
            Write-CsvSheet $ws $csvs[$i]
        }
        if ($Sheets) { $blank.Delete() }
        if ($Notes) {
            $lines = @([IO.File]::ReadAllLines((Abs $Notes), [Text.Encoding]::UTF8))
            $ws = $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count)); $ws.Name = '설명'
            $arr = New-Object 'object[,]' $lines.Count, 1
            for ($i = 0; $i -lt $lines.Count; $i++) { $arr[$i, 0] = $lines[$i] }
            $r = $ws.Range($ws.Cells(1, 1), $ws.Cells($lines.Count, 1)); $r.NumberFormat = '@'; $r.Value2 = $arr
            $r.Font.Name = $Font; $r.Font.Size = 10; $ws.Cells(1, 1).Font.Bold = $true
        }
        $wb.Worksheets.Item(1).Activate()
        $xf = Join-Path $Dst $Combine
        if (Test-Path $xf) { Remove-Item $xf }
        $wb.SaveAs($xf, 51)   # 51 = .xlsx
        $wb.Close($false)
        "저장: $xf"
    } else {
        foreach ($csv in $csvs) {
            $wb = $xl.Workbooks.Add()
            while ($wb.Worksheets.Count -gt 1) { $wb.Worksheets.Item($wb.Worksheets.Count).Delete() }
            Write-CsvSheet $wb.Worksheets.Item(1) $csv
            $xf = Join-Path $Dst ($csv.BaseName + '.xlsx')
            if (Test-Path $xf) { Remove-Item $xf }
            $wb.SaveAs($xf, 51)
            $wb.Close($false)
        }
    }
} finally {
    $xl.Quit()
    [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
}
