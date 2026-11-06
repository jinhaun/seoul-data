# 발표용 추가 업소 데이터를 받아 외국인_공공데이터 폴더에 CSV로 저장합니다. (서울 열린데이터광장, config.txt 의 인증키 사용)
#   업소_병원_인허가.csv        : LOCALDATA_010101 병원 (전체)
#   업소_의원_인허가.csv        : LOCALDATA_010102 의원 (전체, 진료과목 포함)
#   업소_일반음식점_중국식.csv  : LOCALDATA_072404 일반음식점 중 업태가 '중국식'인 곳만 (원본 약 54만 건이라 오래 걸림)
# 폐업한 곳도 들어 있음. 영업 중인 곳만 쓰려면 TRDSTATENM 이 '영업/정상' 인 줄만

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
            if ($try -ge 5) { throw }
            Start-Sleep -Seconds (5 * $try)
        } finally { $wc.Dispose() }
    }
}
# 1000건씩 받으며 $keep 조건에 맞는 줄만 모음 (필요한 열만 남겨 파일을 작게)
function Get-Filtered($svc, [scriptblock]$keep, [string[]]$cols) {
    $rows = New-Object System.Collections.Generic.List[object]
    $first = Get-Page $svc 1 1000
    if (-not $first) { return $rows }
    $total = [int]$first.list_total_count
    for ($s = 1; $s -le $total; $s += 1000) {
        $p = if ($s -eq 1) { $first } else { Get-Page $svc $s ($s + 999) }
        foreach ($r in $p.row) {
            if (& $keep $r) {
                $o = [ordered]@{}; foreach ($c in $cols) { $o[$c] = "$($r.$c)".Trim() }
                $rows.Add([pscustomobject]$o)
            }
        }
        if ($s % 50000 -eq 1 -and $s -gt 1) { "  $svc $s / $total" }
    }
    $rows
}

$base = 'BPLCNM', 'TRDSTATENM', 'DTLSTATENM', 'APVPERMYMD', 'DCBYMD', 'SITEWHLADDR', 'RDNWHLADDR', 'UPTAENM'
$sets = @(
    @{ Svc = 'LOCALDATA_010101'; File = '업소_병원_인허가';       Keep = { $true }; Cols = $base },
    @{ Svc = 'LOCALDATA_010102'; File = '업소_의원_인허가';       Keep = { $true }; Cols = $base + 'MEDEXTRITEMSCNNM' },
    @{ Svc = 'LOCALDATA_072404'; File = '업소_일반음식점_중국식'; Keep = { param($r) "$($r.UPTAENM)".Trim() -eq '중국식' }; Cols = $base }
)
foreach ($s in $sets) {
    try {
        $rows = @(Get-Filtered $s.Svc $s.Keep $s.Cols | Where-Object { $_ -isnot [string] })
        $rows | Export-Csv -Path (Join-Path $Out "$($s.File).csv") -NoTypeInformation -Encoding UTF8
        $open = @($rows | Where-Object { $_.TRDSTATENM -like '영업*' }).Count
        "OK  $($s.File) : $($rows.Count)건 (영업 중 $open) - $($s.Svc)"
    } catch {
        "ERR $($s.Svc): $($_.Exception.Message)"
    }
}
