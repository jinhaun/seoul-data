# 서울 실시간 도시데이터 수집 스크립트
# 실행할 때마다 모든 장소(약 121곳)의 citydata 응답을 받아
# data\YYYY-MM-DD\HHmm.json.gz 파일 하나로 압축 저장합니다. (파일 이름 = 실제 인구 기준 시각)

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root 'data'
$LogDir  = Join-Path $Root 'logs'
$PlacesFile = Join-Path $Root 'places.json'
New-Item -ItemType Directory -Force -Path $DataDir, $LogDir | Out-Null

$Utf8 = New-Object System.Text.UTF8Encoding($false)
$now  = Get-Date
$LogFile = Join-Path $LogDir ($now.ToString('yyyy-MM') + '.log')

function Write-Log($msg) {
    $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $msg
    [System.IO.File]::AppendAllText($LogFile, $line + "`r`n", $Utf8)
}

function Get-Text($url, $referer) {
    $wc = New-Object System.Net.WebClient
    if ($referer) { $wc.Headers.Add('Referer', $referer) }
    try { return $Utf8.GetString($wc.DownloadData($url)) }
    finally { $wc.Dispose() }
}

# 1) API 키 읽기 (config.txt 에서 # 으로 시작하지 않는 첫 줄)
$configFile = Join-Path $Root 'config.txt'
$ApiKey = $null
if (Test-Path $configFile) {
    $ApiKey = Get-Content $configFile -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.Contains('=') } |
        Select-Object -First 1
}
if (-not $ApiKey -or $ApiKey -eq '여기에_API_키를_붙여넣으세요') {
    Write-Log 'ERROR config.txt 에 API 키가 없습니다.'
    exit 1
}

# 2) 장소 목록: 사이트에서 최신 목록을 받고, 실패하면 저장해 둔 목록 사용
$places = $null
try {
    $listUrl = 'https://data.seoul.go.kr/SeoulRtd/api/hotspot-category?page=1&category=%EC%A0%84%EC%B2%B4%EB%B3%B4%EA%B8%B0&count=300'
    $listJson = Get-Text $listUrl 'https://data.seoul.go.kr/SeoulRtd/list'
    $places = @(($listJson | ConvertFrom-Json).row | ForEach-Object { $_.area_nm })
    if ($places.Count -lt 50) { throw "장소 수가 너무 적음: $($places.Count)" }
    [System.IO.File]::WriteAllText($PlacesFile, (ConvertTo-Json @($places)), $Utf8)
} catch {
    Write-Log "WARN 장소 목록 갱신 실패, 저장된 목록 사용: $($_.Exception.Message)"
    if (Test-Path $PlacesFile) {
        # ConvertFrom-Json 은 배열을 한 덩어리로 넘기므로 ForEach-Object 로 하나씩 풀어 줌
        $places = @([System.IO.File]::ReadAllText($PlacesFile, $Utf8) | ConvertFrom-Json | ForEach-Object { $_ })
    } else {
        Write-Log 'ERROR 저장된 장소 목록도 없습니다.'
        exit 1
    }
}

# 3) 장소별 수집 (실패 시 최대 3번 시도)
$results = New-Object System.Collections.Generic.List[string]
$failed  = New-Object System.Collections.Generic.List[string]
foreach ($place in $places) {
    $url = "http://openapi.seoul.go.kr:8088/$ApiKey/json/citydata/1/5/" + [Uri]::EscapeDataString($place)
    $ok = $false
    for ($try = 1; $try -le 3 -and -not $ok; $try++) {
        try {
            $text = Get-Text $url $null
            if ($text -notmatch '"INFO-000"') {
                throw ('API 오류 응답: ' + $text.Substring(0, [Math]::Min(200, $text.Length)))
            }
            $results.Add($text)
            $ok = $true
        } catch {
            if ($try -eq 3) {
                $failed.Add($place)
                Write-Log "WARN $place 수집 실패: $($_.Exception.Message)"
            } else {
                Start-Sleep -Seconds (5 * $try)
            }
        }
    }
}

if ($results.Count -eq 0) {
    Write-Log "ERROR 수집 성공 0건 (실패 $($failed.Count)건)"
    exit 1
}

# 4) 한 파일로 묶어서 gzip 저장
#    파일 이름 = 응답에 들어 있는 실제 인구 기준 시각(PPLTN_TIME, 24시간제)
#    인구 데이터는 약 28~30분 늦게 5분 단위로 갱신되므로 매시 01분·31분에 수집하면
#    예) 13:31 수집 -> data\날짜\1300.json.gz , 00:01 수집 -> 전날 폴더의 2330.json.gz
#    기준 시각을 못 읽으면 예전처럼 수집 시각 - 30분을 씁니다.
$stamp = $null
$ppltnTimes = $results | ForEach-Object {
    $m = [regex]::Match($_, '"PPLTN_TIME":"(\d{4}-\d{2}-\d{2} \d{2}:\d{2})"')
    if ($m.Success) { $m.Groups[1].Value }
}
$mostCommon = $ppltnTimes | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
if ($mostCommon) { $stamp = [datetime]::ParseExact($mostCommon.Name, 'yyyy-MM-dd HH:mm', $null) }
if (-not $stamp) { $stamp = $now.AddMinutes(-30) }
# 날짜 폴더 이름에 요일 포함: 2026-10-17_토
$dayDir = Join-Path $DataDir ($stamp.ToString('yyyy-MM-dd') + '_' + $stamp.ToString('ddd', [Globalization.CultureInfo]::GetCultureInfo('ko-KR')))
New-Item -ItemType Directory -Force -Path $dayDir | Out-Null
$outFile = Join-Path $dayDir ($stamp.ToString('HHmm') + '.json.gz')
if (Test-Path $outFile) {   # 같은 기준 시각을 두 번 받은 경우 덮어쓰지 않음
    $outFile = Join-Path $dayDir ($stamp.ToString('HHmm') + '_' + $now.ToString('HHmm') + '.json.gz')
}

$header = '{"collected_at":"' + $now.ToString('yyyy-MM-ddTHH:mm:ssK') + '","count":' + $results.Count +
          ',"failed":' + (ConvertTo-Json @($failed) -Compress) + ',"places":['
$body   = $header + [string]::Join(',', $results) + ']}'

$fs = [System.IO.File]::Create($outFile)
try {
    $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Compress)
    $bytes = $Utf8.GetBytes($body)
    $gz.Write($bytes, 0, $bytes.Length)
    $gz.Dispose()
} finally { $fs.Dispose() }

Write-Log ("OK 성공 {0}건, 실패 {1}건 -> {2}" -f $results.Count, $failed.Count, $outFile)
