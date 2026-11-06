# 외국인 가이드(Seoul_Guide.html)가 읽는 데이터 파일을 만듭니다.
#   - 장소별 최신 혼잡도·인구·12시간 예측, 오늘 수집분 추이, 가까운 지하철역, 진행 중인 행사
#   - 장소 분류와 좌표는 서울 실시간 도시데이터 사이트의 장소 목록에서 받습니다.
# 결과: 외국인가이드_data.js (window.GUIDE = {...})

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root 'data'
$Utf8    = New-Object System.Text.UTF8Encoding($false)

function Read-Gz($path) {
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Decompress)
        $sr = New-Object System.IO.StreamReader($gz, [System.Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } finally { $fs.Dispose() }
}

# 장소 분류·좌표
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('Referer', 'https://data.seoul.go.kr/SeoulRtd/list')
$listJson = $Utf8.GetString($wc.DownloadData('https://data.seoul.go.kr/SeoulRtd/api/hotspot-category?page=1&category=%EC%A0%84%EC%B2%B4%EB%B3%B4%EA%B8%B0&count=300'))
$wc.Dispose()
$meta = @{}
foreach ($r in ($listJson | ConvertFrom-Json).row) { $meta[$r.area_nm] = $r }

# 장소별 자치구 (집값_연결분석.ps1 결과)
$guOf = @{}
$placeCsv = Join-Path $Root '장소별_실시간지표.csv'
if (Test-Path $placeCsv) { Import-Csv $placeCsv -Encoding UTF8 | ForEach-Object { $guOf[$_.'장소'] = $_.'자치구' } }

$files = @(Get-ChildItem $DataDir -Recurse -Filter '*.json.gz' |
    Where-Object { $_.Name -match '^\d{4}(_\d{4})?\.json\.gz$' } | Sort-Object FullName)
$hist = @{}; $latest = @{}
foreach ($file in $files) {
    $snap = Read-Gz $file.FullName | ConvertFrom-Json
    foreach ($place in $snap.places) {
        $d = $place.CITYDATA; $p = $d.LIVE_PPLTN_STTS | Select-Object -First 1
        if (-not $p) { continue }
        if (-not $hist.ContainsKey($d.AREA_NM)) { $hist[$d.AREA_NM] = New-Object System.Collections.Generic.List[object] }
        $hist[$d.AREA_NM].Add([ordered]@{ t = $p.PPLTN_TIME; l = $p.AREA_CONGEST_LVL; lo = [int]$p.AREA_PPLTN_MIN; hi = [int]$p.AREA_PPLTN_MAX })
        $latest[$d.AREA_NM] = $d
    }
}

$weather = $null
$places = foreach ($name in ($latest.Keys | Sort-Object)) {
    $d = $latest[$name]; $p = $d.LIVE_PPLTN_STTS | Select-Object -First 1
    if (-not $weather -and $d.WEATHER_STTS) {
        $w = $d.WEATHER_STTS | Select-Object -First 1
        $weather = [ordered]@{ temp = $w.TEMP; pm10 = $w.PM10_INDEX; pm25 = $w.PM25_INDEX; time = $w.WEATHER_TIME }
    }
    $subs = @($d.SUB_STTS | Where-Object { $_.SUB_STN_NM } | ForEach-Object { [ordered]@{ n = $_.SUB_STN_NM; line = $_.SUB_STN_LINE } } |
        Group-Object { $_.n + '|' + $_.line } | ForEach-Object { $_.Group[0] })
    $events = @($d.EVENT_STTS | Where-Object { $_.EVENT_NM } | Select-Object -First 3 |
        ForEach-Object { [ordered]@{ n = $_.EVENT_NM; period = $_.EVENT_PERIOD; place = $_.EVENT_PLACE; url = $_.URL } })
    $m = $meta[$name]
    [object[]]$fc = @($p.FCST_PPLTN | ForEach-Object { [pscustomobject]@{ t = $_.FCST_TIME; l = $_.FCST_CONGEST_LVL; lo = [int]$_.FCST_PPLTN_MIN; hi = [int]$_.FCST_PPLTN_MAX } })
    [object[]]$hs = @($hist[$name] | ForEach-Object { [pscustomobject]$_ })
    [pscustomobject][ordered]@{
        ko     = $name
        cat    = $(if ($m) { $m.category } else { '' })
        lat    = $(if ($m) { [double]$m.x } else { $null })
        lng    = $(if ($m) { [double]$m.y } else { $null })
        gu     = $guOf[$name]
        lvl    = $p.AREA_CONGEST_LVL
        lo     = [int]$p.AREA_PPLTN_MIN
        hi     = [int]$p.AREA_PPLTN_MAX
        time   = $p.PPLTN_TIME
        nonres = [double]$p.NON_RESNT_PPLTN_RATE
        fcst   = $fc
        hist   = $hs
        subway = [object[]]$subs
        events = [object[]]$events
    }
}

$out = [ordered]@{ generated = (Get-Date).ToString('yyyy-MM-dd HH:mm'); snapshots = $files.Count; weather = $weather; places = @($places) }
[System.IO.File]::WriteAllText((Join-Path $Root '외국인가이드_data.js'), 'window.GUIDE = ' + ($out | ConvertTo-Json -Depth 6 -Compress) + ';', $Utf8)
"수집 파일 $($files.Count)개, 장소 $(@($places).Count)곳 -> 외국인가이드_data.js"
