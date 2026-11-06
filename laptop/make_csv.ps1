# data 폴더의 수집 파일(*.json.gz)을 모두 읽어 장소별 유동인구 표(유동인구.csv)로 만듭니다.
# 한 줄 = 한 번의 수집에서 장소 하나. 엑셀/Tableau 에서 바로 열 수 있습니다.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root 'data'
$OutFile = Join-Path $Root '유동인구.csv'

function Read-Gz($path) {
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Decompress)
        $sr = New-Object System.IO.StreamReader($gz, [System.Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } finally { $fs.Dispose() }
}

# 매시간 수집 파일(HHmm.json.gz)만 읽습니다. 같은 폴더의 이벤트_*.json.gz 는 제외.
$files = Get-ChildItem $DataDir -Recurse -Filter '*.json.gz' |
    Where-Object { $_.Name -match '^\d{4}\.json\.gz$' } | Sort-Object FullName
$rows = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    $snap = Read-Gz $file.FullName | ConvertFrom-Json
    $collectedAt = ([datetime]$snap.collected_at).ToString('yyyy-MM-dd HH:mm')
    foreach ($place in $snap.places) {
        $d = $place.CITYDATA
        $p = $d.LIVE_PPLTN_STTS | Select-Object -First 1
        $w = $d.WEATHER_STTS | Select-Object -First 1
        $r = $d.ROAD_TRAFFIC_STTS.AVG_ROAD_DATA
        $rows.Add([pscustomobject][ordered]@{
            '수집시각'     = $collectedAt
            '인구기준시각' = $p.PPLTN_TIME
            '장소코드'     = $d.AREA_CD
            '장소'         = $d.AREA_NM
            '혼잡도'       = $p.AREA_CONGEST_LVL
            '인구_최소'    = $p.AREA_PPLTN_MIN
            '인구_최대'    = $p.AREA_PPLTN_MAX
            '남성비율'     = $p.MALE_PPLTN_RATE
            '여성비율'     = $p.FEMALE_PPLTN_RATE
            '0~9세'        = $p.PPLTN_RATE_0
            '10대'         = $p.PPLTN_RATE_10
            '20대'         = $p.PPLTN_RATE_20
            '30대'         = $p.PPLTN_RATE_30
            '40대'         = $p.PPLTN_RATE_40
            '50대'         = $p.PPLTN_RATE_50
            '60대'         = $p.PPLTN_RATE_60
            '70대이상'     = $p.PPLTN_RATE_70
            '상주인구비율' = $p.RESNT_PPLTN_RATE
            '비상주인구비율' = $p.NON_RESNT_PPLTN_RATE
            '기온'         = $w.TEMP
            '미세먼지'     = $w.PM10
            '초미세먼지'   = $w.PM25
            '도로소통'     = $r.ROAD_TRAFFIC_IDX
            '도로평균속도' = $r.ROAD_TRAFFIC_SPD
        })
    }
}

# Export-Csv -Encoding UTF8 은 BOM 을 붙여서 엑셀에서 한글이 깨지지 않습니다.
$rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
"파일 $($files.Count)개 -> $($rows.Count)줄 저장: $OutFile"
