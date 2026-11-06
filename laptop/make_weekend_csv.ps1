# 유동인구.csv 에서 주말(토·일) 데이터만 골라 유동인구_주말.csv 로 저장합니다.
# 주말 판단은 '인구기준시각'(실제 인구를 잰 시각) 기준입니다.
# 장소_좌표.csv 가 있으면 장소별 자치구·분류·위도·경도를 같이 붙여서, Tableau 지도에 바로 쓸 수 있게 합니다.
# 먼저 make_csv.ps1 (필요하면 make_coords_csv.ps1 도) 을 실행해 최신으로 만든 뒤 실행하세요.

$ErrorActionPreference = 'Stop'
$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$InFile    = Join-Path $Root '유동인구.csv'
$CoordFile = Join-Path $Root '장소_좌표.csv'
$OutFile   = Join-Path $Root '유동인구_주말.csv'

$coordOf = @{}
if (Test-Path $CoordFile) { Import-Csv $CoordFile -Encoding UTF8 | ForEach-Object { $coordOf[$_.'장소'] = $_ } }

$rows = Import-Csv -Path $InFile -Encoding UTF8
$weekend = foreach ($row in $rows) {
    $day = ([datetime]$row.'인구기준시각').DayOfWeek
    if ($day -ne 'Saturday' -and $day -ne 'Sunday') { continue }

    # 장소 바로 뒤에 자치구·분류·위도·경도 열을 끼워 넣습니다.
    $out = [ordered]@{}
    foreach ($prop in $row.PSObject.Properties) {
        $out[$prop.Name] = $prop.Value
        if ($prop.Name -eq '장소' -and $coordOf.Count) {
            $c = $coordOf[$row.'장소']
            $out['자치구'] = $c.'자치구'
            $out['분류']   = $c.'분류'
            $out['위도']   = $c.'위도'
            $out['경도']   = $c.'경도'
        }
    }
    [pscustomobject]$out
}

# Export-Csv -Encoding UTF8 은 BOM 을 붙여서 엑셀에서 한글이 깨지지 않습니다.
$weekend | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
"전체 $($rows.Count)줄 중 주말 $(@($weekend).Count)줄 저장: $OutFile"
if (-not $coordOf.Count) { '장소_좌표.csv 가 없어 좌표 없이 저장했습니다.' }
