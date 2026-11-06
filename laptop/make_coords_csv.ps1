# 장소별 위도·경도를 서울 실시간 도시데이터 사이트의 장소 목록에서 받아 장소_좌표.csv 로 저장합니다.
# 한 줄 = 장소 하나 (121곳). Tableau 에서 유동인구 CSV 와 '장소' 로 연결해 지도에 씁니다.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutFile = Join-Path $Root '장소_좌표.csv'
$Utf8    = New-Object System.Text.UTF8Encoding($false)

$wc = New-Object System.Net.WebClient
$wc.Headers.Add('Referer', 'https://data.seoul.go.kr/SeoulRtd/list')
$listJson = $Utf8.GetString($wc.DownloadData('https://data.seoul.go.kr/SeoulRtd/api/hotspot-category?page=1&category=%EC%A0%84%EC%B2%B4%EB%B3%B4%EA%B8%B0&count=300'))
$wc.Dispose()

# 장소별 자치구 (집값_연결분석.ps1 결과가 있으면 같이 넣음)
$guOf = @{}
$placeCsv = Join-Path $Root '장소별_실시간지표.csv'
if (Test-Path $placeCsv) { Import-Csv $placeCsv -Encoding UTF8 | ForEach-Object { $guOf[$_.'장소'] = $_.'자치구' } }

# 사이트 목록의 x 가 위도, y 가 경도입니다.
$rows = foreach ($r in ($listJson | ConvertFrom-Json).row) {
    [pscustomobject][ordered]@{
        '장소'   = $r.area_nm
        '분류'   = $r.category
        '자치구' = $guOf[$r.area_nm]
        '위도'   = $r.x
        '경도'   = $r.y
    }
}

# Export-Csv -Encoding UTF8 은 BOM 을 붙여서 엑셀에서 한글이 깨지지 않습니다.
$rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
"장소 $(@($rows).Count)곳 좌표 저장: $OutFile"
