# 시간당 자료를 장소별로 검사하고 빠진 장소만 재시도합니다. 자료는 추가만 합니다.
. "$PSScriptRoot/common.ps1"
. "$PSScriptRoot/collection_quality.ps1"
trap { Write-Host '::error::수집 중단: 통신 또는 저장 오류 (인증값 보호를 위해 원문 생략)'; exit 1 }
$seoulApiCredential = Get-ApiKey
$now = Get-KstNow
$spots = @(Get-Hotspots)
$names = @($spots | ForEach-Object { "$($_.'장소')" } | Sort-Object -Unique)
if (-not $names.Count) { throw '장소 목록이 비었습니다.' }
$qualityPath = Join-Path $RepoRoot 'data/status/수집완료검사.csv'
$history = @(Read-Csv $qualityPath)
$existing = @(foreach ($day in @($now.Date.AddDays(-1), $now.Date)) {
    Read-Csv (Join-Path $RepoRoot ('data/realtime/' + (Get-DayPath $day) + '.csv'))
})
$fetchPacket = {
    param($name)
    $text = Get-Text ("http://openapi.seoul.go.kr:8088/$seoulApiCredential/json/citydata/1/5/" + [Uri]::EscapeDataString($name)) $null
    if ($text -notmatch '"INFO-000"') { throw '응답 오류' }
    return [pscustomobject]@{ Row = (New-RealtimeRow ($text | ConvertFrom-Json).CITYDATA (Get-KstNow).ToString('yyyy-MM-dd HH:mm')); Raw = $text }
}
# 한 곳이 실패해도 다른 두 곳까지 확인합니다.
$probe = $null
foreach ($name in ($names | Select-Object -First 3)) {
    try { $candidate = & $fetchPacket $name; if (Test-PopulationRow $candidate.Row) { $probe = $candidate; break } } catch {}
}
if (-not $probe) { throw '현재 기준 시각을 확인할 수 없습니다.' }
$current = Get-RowSlot $probe.Row
$slots = @($current)
foreach ($group in ($history | Group-Object '시간대')) {
    $last = $group.Group | Select-Object -Last 1
    $time = [datetime]::ParseExact($last.'시간대', 'yyyy-MM-dd HH', $null)
    if ($last.'상태' -ne '완료' -and $time -ge $now.AddMinutes(-110)) { $slots += $last.'시간대' }
}
$slots = @($slots | Sort-Object -Unique)
$saved = $false
$totalAdded = 0
foreach ($slot in $slots) {
    $beforeMissing = @(Get-MissingPlaces $slot $names $existing)
    $script:probeUsed = $false
    $provider = { param($name)
        if (-not $script:probeUsed -and $name -eq $probe.Row.'장소') { $script:probeUsed = $true; return $probe }
        return (& $fetchPacket $name)
    }
    $result = Invoke-PlaceCollection $slot $names $existing $provider { Start-Sleep -Seconds 60 }
    if ($result.Added.Count) {
        $rawDir = Join-Path $RepoRoot 'tmp/raw'
        New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
        # 보충 원본도 고유 이름: 기존 보관 원본을 덮어쓰지 않습니다.
        $rawFile = Join-Path $rawDir ($slot.Replace(' ', '_') + '_추가_' + [guid]::NewGuid().ToString('N') + '.json.gz')
        $body = '{"collected_at":"' + (Get-KstNow).ToString('yyyy-MM-dd HH:mm') + '","count":' + $result.Added.Count + ',"places":[' + (($result.Added | ForEach-Object { $_.Raw }) -join ',') + ']}'
        $fs = [IO.File]::Create($rawFile)
        try { $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Compress); try { $b = $Utf8.GetBytes($body); $gz.Write($b,0,$b.Length) } finally { $gz.Dispose() } } finally { $fs.Dispose() }
    }
    foreach ($packet in $result.Added) {
        $stamp = [datetime]::ParseExact($packet.Row.'인구기준시각', 'yyyy-MM-dd HH:mm', $null)
        Add-CsvRows (Join-Path $RepoRoot ('data/realtime/' + (Get-DayPath $stamp) + '.csv')) @($packet.Row)
        $existing += $packet.Row
        $saved = $true; $totalAdded++
    }
    $missing = @(Get-MissingPlaces $slot $names $existing)
    $state = if ($missing.Count) { '미완료' } else { '완료' }
    $previous = $history | Where-Object { $_.'시간대' -eq $slot } | Select-Object -Last 1
    if ($beforeMissing.Count -or -not $previous -or $previous.'상태' -ne $state) {
        $check = [pscustomobject][ordered]@{ '검사시각'=(Get-KstNow).ToString('yyyy-MM-dd HH:mm'); '시간대'=$slot; '대상수'=$names.Count; '유효수'=($names.Count-$missing.Count); '상태'=$state; '누락장소'=($missing -join ' / ') }
        Add-CsvRows $qualityPath @($check)
        Add-CsvRows (Join-Path $RepoRoot 'data/status/수집기록.csv') @([pscustomobject][ordered]@{
            '수집시각'=$check.'검사시각'; '인구기준시각'=($slot + ':00'); '성공'=$check.'유효수'; '실패'=$missing.Count; '실행'='github'; '실패장소'=$check.'누락장소'
        })
    }
    Write-Host ("장소별 검사: {0}시 {1}/{2}곳, {3}" -f $slot,($names.Count-$missing.Count),$names.Count,$state)
}
if ($env:GITHUB_OUTPUT) { "saved=$($saved.ToString().ToLowerInvariant())" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8 }
if ($totalAdded -eq 0 -and @(Get-MissingPlaces $current $names $existing).Count -eq $names.Count) { exit 1 }
exit 0
