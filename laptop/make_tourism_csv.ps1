# 외국인_관광 폴더의 날짜별 파일을 Tableau에서 바로 쓸 수 있게 합칩니다.
# 결과: 외국인_관광\합본\
#   외국인생활인구_단기_전체.csv / 외국인생활인구_장기_전체.csv : 1월~현재 모든 날짜 (요일·주말여부 열 추가)
#   숙박_호텔_최신.csv / 숙박_외국인민박_최신.csv / 숙박_숙박업_최신.csv : 가장 최근에 저장된 전체 목록
#   숙박_변경내역_전체.csv : 날짜별 신규·삭제·변경 내역을 모두 합친 것
# 데이터가 더 쌓이면 이 스크립트를 다시 실행하면 됩니다.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src     = Join-Path $Root '외국인_관광'
$Out     = Join-Path $Src '합본'
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$ko      = [Globalization.CultureInfo]::GetCultureInfo('ko-KR')
New-Item -ItemType Directory -Force -Path $Out | Out-Null

# 날짜 폴더 목록 (외국인_관광\YYYY-MM\YYYY-MM-DD_요일), 날짜순
$dayDirs = Get-ChildItem $Src -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}$' } |
    ForEach-Object { Get-ChildItem $_.FullName -Directory } |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}' } | Sort-Object Name

function Get-DayInfo($dirName) {
    $d = [datetime]::ParseExact($dirName.Substring(0, 10), 'yyyy-MM-dd', $null)
    $wd = $d.ToString('ddd', $ko)
    $weekend = if ($d.DayOfWeek -in 'Saturday', 'Sunday') { 'Y' } else { 'N' }
    return @($wd, $weekend)
}

$summary = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------- 외국인 생활인구 합치기
foreach ($kind in '단기', '장기') {
    $files = @($dayDirs | ForEach-Object { Join-Path $_.FullName "외국인생활인구_$kind.csv" } | Where-Object { Test-Path $_ })
    if ($files.Count -eq 0) { continue }
    $headers = @($files | ForEach-Object { (Get-Content $_ -Encoding UTF8 -TotalCount 1) } | Select-Object -Unique)
    $outFile = Join-Path $Out "외국인생활인구_$($kind)_전체.csv"
    $sb = New-Object System.Text.StringBuilder
    if ($headers.Count -eq 1) {
        # 모든 날짜의 열 구성이 같으면 빠르게 줄 단위로 합침 (날짜 뒤에 요일·주말여부 열 추가)
        [void]$sb.AppendLine(($headers[0] -replace '^("날짜"),', '$1,"요일","주말여부",'))
        $rows = 0
        foreach ($f in $files) {
            $info = Get-DayInfo (Split-Path (Split-Path $f -Parent) -Leaf)
            $insert = '$1,"' + $info[0] + '","' + $info[1] + '",'
            foreach ($line in (Get-Content $f -Encoding UTF8 | Select-Object -Skip 1)) {
                if ($line) { [void]$sb.AppendLine(($line -replace '^("[^"]*"),', $insert)); $rows++ }
            }
        }
        [IO.File]::WriteAllText($outFile, $sb.ToString(), $Utf8Bom)
    } else {
        # 날짜마다 열 구성이 다르면(국적 열 추가 등) 열 이름을 맞춰서 합침
        $all = foreach ($f in $files) {
            $info = Get-DayInfo (Split-Path (Split-Path $f -Parent) -Leaf)
            Import-Csv $f -Encoding UTF8 | ForEach-Object {
                $_ | Add-Member -NotePropertyName '요일' -NotePropertyValue $info[0] -PassThru |
                     Add-Member -NotePropertyName '주말여부' -NotePropertyValue $info[1] -PassThru
            }
        }
        $cols = @('날짜', '요일', '주말여부') + @($all | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique | Where-Object { $_ -notin '날짜', '요일', '주말여부' })
        $all | Select-Object $cols | Export-Csv $outFile -NoTypeInformation -Encoding UTF8
        $rows = @($all).Count
    }
    $first = (Split-Path (Split-Path $files[0] -Parent) -Leaf); $last = (Split-Path (Split-Path $files[-1] -Parent) -Leaf)
    $summary.Add("외국인생활인구_$($kind)_전체.csv : $($files.Count)일치 ($first ~ $last), $rows 행")
}

# ---------------------------------------------------------------- 숙박 목록 (가장 최근 전체 목록)
foreach ($kind in '호텔', '외국인민박', '숙박업') {
    $latest = $dayDirs | Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "숙박_$kind.csv" } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $latest) { continue }
    $dst = Join-Path $Out "숙박_$($kind)_최신.csv"
    Copy-Item $latest $dst -Force
    $n = @(Import-Csv $dst -Encoding UTF8).Count
    $summary.Add("숙박_$($kind)_최신.csv : $(Split-Path (Split-Path $latest -Parent) -Leaf) 기준 목록, $n 곳 (폐업 포함, '영업상태'로 거르기)")
}

# ---------------------------------------------------------------- 숙박 변경내역 합치기
$changes = foreach ($dd in $dayDirs) {
    $info = Get-DayInfo $dd.Name
    foreach ($kind in '호텔', '외국인민박', '숙박업') {
        $f = Join-Path $dd.FullName "숙박_$($kind)_변경내역.csv"
        if (Test-Path $f) {
            Import-Csv $f -Encoding UTF8 | ForEach-Object {
                $o = [ordered]@{ '확인날짜' = $dd.Name.Substring(0, 10); '요일' = $info[0]; '숙박종류' = $kind }
                foreach ($p in $_.PSObject.Properties) { $o[$p.Name] = $p.Value }
                [pscustomobject]$o
            }
        }
    }
}
$chFile = Join-Path $Out '숙박_변경내역_전체.csv'
if ($changes) {
    $changes | Export-Csv $chFile -NoTypeInformation -Encoding UTF8
    $summary.Add("숙박_변경내역_전체.csv : $(@($changes).Count) 건 (신규 $(@($changes | Where-Object 구분 -eq '신규').Count), 삭제 $(@($changes | Where-Object 구분 -eq '삭제').Count), 변경 $(@($changes | Where-Object 구분 -eq '변경').Count))")
}

# ---------------------------------------------------------------- 안내 파일
$readme = @(
    "외국인_관광 합본 파일 (만든 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm')))",
    '날짜별 폴더의 파일을 Tableau에서 쓰기 쉽게 합친 것입니다. 원본은 날짜 폴더에 그대로 있습니다.',
    '새 데이터가 쌓이면 프로젝트 폴더의 make_tourism_csv.ps1 을 다시 실행하세요.',
    ''
) + $summary
[IO.File]::WriteAllLines((Join-Path $Out '읽어주세요.txt'), $readme, $Utf8Bom)
$summary
