# 통합 시험 전용. 실제 인증값이나 네트워크에 접근하지 않습니다.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Utf8 = New-Object Text.UTF8Encoding($false)
$Utf8Bom = New-Object Text.UTF8Encoding($true)
function Get-KstNow { return [datetime]'2026-11-13 11:40' }
function Get-ApiKey { return '시험전용' }
function Get-Hotspots { 1..121 | ForEach-Object { [pscustomobject]@{ '장소'=('장소' + $_) } } }
function Get-DayPath([datetime]$d) { $d.ToString('yyyy-MM') + '/' + $d.ToString('yyyy-MM-dd') }
function Read-Csv([string]$p) { if (Test-Path $p) { Import-Csv $p -Encoding UTF8 } }
function Add-CsvRows([string]$p, $rows) {
    New-Item -ItemType Directory -Force -Path (Split-Path $p -Parent) | Out-Null
    if (Test-Path $p) { $rows | Export-Csv $p -NoTypeInformation -Encoding UTF8 -Append }
    else { $rows | Export-Csv $p -NoTypeInformation -Encoding UTF8 }
}
$script:attempt = @{}
function Get-Text([string]$url, $referer) {
    # 단순 응답 모형도 실제 요청의 인증 설정값을 검사해야 변수 충돌을 잡습니다.
    if ($url -notlike 'http://openapi.seoul.go.kr:8088/시험전용/json/citydata/1/5/*') { throw '시험용 요청 인증 설정이 변경됐습니다.' }
    $n = [Uri]::UnescapeDataString(($url -split '/')[-1])
    $script:attempt[$n]++
    $scenarioPath = Join-Path $RepoRoot 'scenario.txt'
    $scenario = if (Test-Path $scenarioPath) { (Get-Content $scenarioPath -Raw).Trim() } else { 'normal' }
    if ($n -in @('장소120','장소121')) {
        if ($scenario -eq 'permanent' -or ($scenario -eq 'retry' -and $script:attempt[$n] -eq 1)) { throw '시험 접속 실패' }
    }
    return (@{ RESULT='INFO-000'; CITYDATA=@{ name=$n } } | ConvertTo-Json -Compress)
}
function New-RealtimeRow($d,[string]$c) {
    [pscustomobject][ordered]@{ '수집시각'=$c; '인구기준시각'='2026-11-13 11:05'; '장소코드'=$d.name; '장소'=$d.name; '혼잡도'='여유'; '인구_최소'='0'; '인구_최대'='100' }
}
function Start-Sleep { param($Seconds) }
