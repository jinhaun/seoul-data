$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$sandbox = Join-Path $source ('시험결과/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $sandbox 'scripts') | Out-Null
Copy-Item (Join-Path $source 'scripts/collect_hourly.ps1') (Join-Path $sandbox 'scripts')
Copy-Item (Join-Path $source 'scripts/collection_quality.ps1') (Join-Path $sandbox 'scripts')
Copy-Item (Join-Path $source 'scripts/watch_alert.ps1') (Join-Path $sandbox 'scripts')
Copy-Item (Join-Path $PSScriptRoot 'fixture_common.ps1') (Join-Path $sandbox 'scripts/common.ps1')
$utf = New-Object Text.UTF8Encoding($true)
$scenarioPath = Join-Path $sandbox 'scenario.txt'
$engine = (Get-Process -Id $PID).Path
function Run-Collector([string]$scenario) {
    [IO.File]::WriteAllText($scenarioPath, $scenario, $utf)
    & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sandbox 'scripts/collect_hourly.ps1')
    if ($LASTEXITCODE -ne 0) { throw '수집기 실행 실패' }
}
Run-Collector 'permanent'
$day = Join-Path $sandbox 'data/realtime/2026-11/2026-11-13.csv'
$check = Join-Path $sandbox 'data/status/수집완료검사.csv'
if (@(Import-Csv $day -Encoding UTF8).Count -ne 119) { throw '119곳 부분 저장 실패' }
if ((Import-Csv $check -Encoding UTF8 | Select-Object -Last 1).'상태' -ne '미완료') { throw '미완료 기록 실패' }
$message = & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sandbox 'scripts/watch_alert.ps1') -DryRun -At '2026-11-13 13:00' -From '2026-11-13 11:00'
if ($LASTEXITCODE -ne 0 -or "$message" -notmatch '장소120 / 장소121') { throw '부분 누락 알림 내용 실패' }
if (Test-Path (Join-Path $sandbox 'data/status/알림기록.csv')) { throw '시험 실행이 알림 기록을 남겼습니다.' }
Write-Host '통과: 실제 알림기에서 두 누락 장소 확인, 전송 없는 시험은 기록을 남기지 않음'
Run-Collector 'normal'
$rows = @(Import-Csv $day -Encoding UTF8)
if ($rows.Count -ne 121 -or @($rows | Group-Object '장소').Count -ne 121) { throw '두 곳 보충 또는 중복 방지 실패' }
if ((Import-Csv $check -Encoding UTF8 | Select-Object -Last 1).'상태' -ne '완료') { throw '완료 기록 실패' }
Run-Collector 'normal'
if (@(Import-Csv $day -Encoding UTF8).Count -ne 121) { throw '완료 후 중복 저장' }
$raws = @(Get-ChildItem (Join-Path $sandbox 'tmp/raw') -Filter '*.json.gz')
if ($raws.Count -ne 2) { throw '추가 원본 보존 실패' }
foreach ($file in $raws) {
    $fs = [IO.File]::OpenRead($file.FullName)
    $gz = New-Object IO.Compression.GZipStream($fs,[IO.Compression.CompressionMode]::Decompress)
    $reader = New-Object IO.StreamReader($gz)
    try { $json = $reader.ReadToEnd() | ConvertFrom-Json; if ($json.count -ne @($json.places).Count) { throw '원본 수 불일치' } } finally { $reader.Dispose(); $gz.Dispose(); $fs.Dispose() }
}
Write-Host '통과: 실제 수집기 119곳 저장 → 두 곳 보충 → 완료 → 재실행 중복 없음 → 압축 원본 두 개 보존'
Write-Host '전체 통합 검사 통과 (시험 폴더만 사용)'
