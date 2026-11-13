# 지정 날짜의 누락 시간만 실제 노트북 관측으로 보충합니다. 기존 행·원본은 보존합니다.
param([Parameter(Mandatory=$true)][string]$Date, [string]$SourceRoot)
. "$PSScriptRoot/common.ps1"
. "$PSScriptRoot/collection_quality.ps1"
if (-not $SourceRoot) { $SourceRoot = Get-LaptopRoot }
if (-not $SourceRoot) { throw '노트북 원본 폴더를 찾지 못했습니다.' }
$day = [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null)
$meta = @(Read-Csv (Join-Path $RepoRoot 'data/meta/장소_121곳.csv'))
$expected = @($meta | ForEach-Object { $_.'장소' } | Sort-Object -Unique)
if (-not $expected.Count) { throw '기대 장소 목록이 없습니다.' }
$dst = Join-Path $RepoRoot ('data/realtime/' + (Get-DayPath $day) + '.csv')
$have = @(Read-Csv $dst)
$dateFolder = @(Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'data') -Directory | Where-Object { $_.Name -like "$Date*" })
if ($dateFolder.Count -ne 1) { throw '해당 날짜 원본 폴더를 하나로 확인할 수 없습니다.' }
$files = @(Get-ChildItem -LiteralPath $dateFolder[0].FullName -File | Where-Object { $_.Name -match '^\d{4}\.json\.gz$' } | Sort-Object Name)
$total = 0
foreach ($file in $files) {
    $fs=[IO.File]::OpenRead($file.FullName)
    $gz=New-Object IO.Compression.GZipStream($fs,[IO.Compression.CompressionMode]::Decompress)
    $reader=New-Object IO.StreamReader($gz,[Text.Encoding]::UTF8)
    try { $source=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose(); $gz.Dispose(); $fs.Dispose() }
    $collected=(To-Str $source.collected_at).Replace('T',' ')
    if ($collected.Length -ge 16) { $collected=$collected.Substring(0,16) }
    $rows=@(foreach($item in $source.places) { $city=if($item.CITYDATA){$item.CITYDATA}else{$item}; New-RealtimeRow $city $collected })
    $valid=@($rows | Where-Object { Test-PopulationRow $_ })
    foreach ($group in ($valid | Group-Object { Get-RowSlot $_ })) {
        $slot=$group.Name
        if (-not $slot.StartsWith($Date)) { continue }
        $missing=@(Get-MissingPlaces $slot $expected $have)
        if (-not $missing.Count) { continue }
        # 누락된 시간은 한 관측 묶음 전체를 보존합니다. 같은 시각·장소의 기존 행은 건드리지 않습니다.
        $seen=@{}; foreach($r in $have) { $seen[$r.'인구기준시각'+'|'+$r.'장소']=$true }
        $add=@(foreach($r in $group.Group) {
            $observationKey=$r.'인구기준시각'+'|'+$r.'장소'
            if($r.'장소' -in $expected -and -not $seen[$observationKey]) { $seen[$observationKey]=$true; $r }
        })
        if (-not $add.Count) { continue }
        $rawDir=Join-Path $RepoRoot 'tmp/raw'; New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
        $rawTarget=Join-Path $rawDir ($Date+'_'+$file.BaseName.Replace('.json','')+'_노트북_'+[guid]::NewGuid().ToString('N')+'.json.gz')
        Copy-Item -LiteralPath $file.FullName -Destination $rawTarget
        Add-CsvRows $dst $add; $have += $add; $total += $add.Count
        $after=@(Get-MissingPlaces $slot $expected $have)
        $repairedAt=(Get-KstNow).ToString('yyyy-MM-dd HH:mm')
        Add-CsvRows (Join-Path $RepoRoot 'data/status/수집완료검사.csv') @([pscustomobject][ordered]@{
            '검사시각'=$repairedAt;'시간대'=$slot;'대상수'=$expected.Count;'유효수'=($expected.Count-$after.Count);'상태'=$(if($after.Count){'미완료'}else{'완료'});'누락장소'=($after -join ' / ')
        })
        Add-CsvRows (Join-Path $RepoRoot 'data/status/수집기록.csv') @([pscustomobject][ordered]@{
            '수집시각'=$repairedAt;'인구기준시각'=($slot+':00');'성공'=($expected.Count-$after.Count);'실패'=$after.Count;'실행'='laptop';'실패장소'=($after -join ' / ')
        })
        Add-CsvRows (Join-Path $RepoRoot 'data/status/복구기록.csv') @([pscustomobject][ordered]@{
            '복구시각'=$repairedAt;'시간대'=$slot;'원본파일'=($dateFolder[0].Name+'/'+$file.Name);'원본SHA256'=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash;'추가행수'=$add.Count;'복구후장소수'=($expected.Count-$after.Count)
        })
        Write-Host ("노트북 원본 보충: {0}시, 추가 {1}행, 유효 장소 {2}/{3}" -f $slot,$add.Count,($expected.Count-$after.Count),$expected.Count)
    }
}
Write-Host "보충 완료: 추가 $total 행 (기존 자료 보존)"
