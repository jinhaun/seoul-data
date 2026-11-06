# 서울시 유흥 업소 인허가 정보를 받아 외국인_공공데이터 폴더에 CSV로 저장합니다. (서울 열린데이터광장, config.txt 의 인증키 사용)
#   업소_유흥주점_인허가.csv  : LOCALDATA_072302 유흥주점영업 (룸살롱·클럽·노래클럽 등)
#   업소_단란주점_인허가.csv  : LOCALDATA_072301 단란주점영업
#   외국인전용 유흥음식점업(OA-16093)은 LOCALDATA_072402/072403 으로 보이지만 서울시 서버가 ERROR-500 을 내서 받히는 대로 저장
#   (폐업한 곳도 들어 있음. 영업 중인 곳만 쓰려면 TRDSTATENM 이 '영업/정상' 인 줄만)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out  = Join-Path $Root '외국인_공공데이터'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$ApiKey = Get-Content (Join-Path $Root 'config.txt') -Encoding UTF8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.Contains('=') } |
    Select-Object -First 1

function Get-Page($svc, [int]$s, [int]$e) {
    $url = "http://openapi.seoul.go.kr:8088/$ApiKey/json/$svc/$s/$e/"
    for ($try = 1; ; $try++) {
        $wc = New-Object System.Net.WebClient
        try {
            $j = $Utf8.GetString($wc.DownloadData($url)) | ConvertFrom-Json
            if ($j.$svc) { return $j.$svc }
            if ($j.RESULT.CODE -eq 'INFO-200') { return $null }   # 해당 데이터 없음
            throw "API 오류: $($j.RESULT.CODE)"
        } catch {
            if ($try -ge 3) { throw }
            Start-Sleep -Seconds (5 * $try)
        } finally { $wc.Dispose() }
    }
}
function Get-All($svc) {
    $first = Get-Page $svc 1 1000
    if (-not $first) { return @() }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($r in $first.row) { $rows.Add($r) }
    $total = [int]$first.list_total_count
    for ($s = 1001; $s -le $total; $s += 1000) {
        $p = Get-Page $svc $s ($s + 999)
        foreach ($r in $p.row) { $rows.Add($r) }
    }
    return $rows
}
function Clean($rows) {
    foreach ($r in $rows) {
        foreach ($p in $r.PSObject.Properties) { if ($p.Value -is [string]) { $p.Value = $p.Value.Trim() } }
        $r
    }
}

$sets = @(
    @{ Svc = 'LOCALDATA_072302'; File = '업소_유흥주점_인허가' },
    @{ Svc = 'LOCALDATA_072301'; File = '업소_단란주점_인허가' },
    @{ Svc = 'LOCALDATA_072403'; File = $null },   # 외국인전용(또는 관광) 유흥음식점업 후보: 받히면 분류 이름으로 저장
    @{ Svc = 'LOCALDATA_072402'; File = $null }
)
foreach ($s in $sets) {
    try {
        $rows = @(Clean (Get-All $s.Svc))
        $name = $s.File
        if (-not $name) {
            $kind = @($rows | ForEach-Object { $_.CULPHYEDCOBNM } | Where-Object { $_ } | Select-Object -First 1)
            $name = "업소_$($kind[0] -replace '\s', '')_인허가"
        }
        $rows | Export-Csv -Path (Join-Path $Out "$name.csv") -NoTypeInformation -Encoding UTF8
        $open = @($rows | Where-Object { $_.TRDSTATENM -like '영업*' }).Count
        "OK  $name : $($rows.Count)건 (영업 중 $open) - $($s.Svc)"
    } catch {
        "ERR $($s.Svc): $($_.Exception.Message)"
    }
}
