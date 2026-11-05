# 노트북 바탕화면\프로젝트 에 모아 둔 데이터를 이 저장소 형식으로 옮깁니다. (GitHub이 이미 받은 시각은 그대로 둠)
#   -Part realtime|foreigner|events|lodging 로 일부만 실행 가능
#   -Since 2026-11-03 처럼 주면 그 날짜 폴더부터만 옮김 (그 전 노트북 기록은 그대로 둠)

param([string]$Part, [string]$Since)

. "$PSScriptRoot/common.ps1"
$Src = 'C:\Users\Administrator\Desktop\프로젝트'
if (-not (Test-Path $Src)) { throw "노트북 프로젝트 폴더가 없습니다: $Src" }

function Read-GzText([string]$path) {
    $fs = [IO.File]::OpenRead($path)
    try { $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress); $sr = New-Object IO.StreamReader($gz, $Utf8); return $sr.ReadToEnd() }
    finally { $fs.Dispose() }
}

# ---------------- 실시간 121곳 (30분 간격이던 기간 포함, 원본 전부를 요약 표로)
if (-not $Part -or $Part -eq 'realtime') {
    $byDay = @{}; $status = New-Object System.Collections.Generic.List[object]
    $files = @(Get-ChildItem (Join-Path $Src 'data') -Recurse -File | Where-Object { $_.Name -match '^\d{4}\.json\.gz$' -and (-not $Since -or $_.Directory.Name.Substring(0, 10) -ge $Since) } | Sort-Object FullName)
    $i = 0
    foreach ($f in $files) {
        $i++; if ($i % 50 -eq 0) { Write-Host "실시간 변환 $i / $($files.Count)" }
        try { $j = Read-GzText $f.FullName | ConvertFrom-Json } catch { Write-Host "건너뜀(읽기 실패): $($f.FullName)"; continue }
        $collected = To-Str $j.collected_at 'yyyy-MM-dd HH:mm'
        if ($collected.Length -ge 16) { $collected = $collected.Substring(0, 16).Replace('T', ' ') }
        $rows = @($j.places | ForEach-Object { New-RealtimeRow $_.CITYDATA $collected })
        if (-not $rows.Count) { continue }
        $stampText = @($rows | Group-Object '인구기준시각' | Sort-Object Count -Descending | Select-Object -First 1).Name
        $day = $stampText.Substring(0, 10)
        if (-not $byDay.ContainsKey($day)) { $byDay[$day] = New-Object System.Collections.Generic.List[object] }
        if (@($byDay[$day] | Where-Object { $_.'인구기준시각' -eq $stampText } | Select-Object -First 1).Count -eq 0) { foreach ($r in $rows) { $byDay[$day].Add($r) } }
        $status.Add([pscustomobject][ordered]@{ '수집시각' = $collected; '인구기준시각' = $stampText; '성공' = $rows.Count; '실패' = @($j.failed).Count; '실행' = 'laptop'; '실패장소' = '' })
    }
    foreach ($day in ($byDay.Keys | Sort-Object)) {
        $d = [datetime]::ParseExact($day, 'yyyy-MM-dd', $null)
        $dst = Join-Path $RepoRoot ("data/realtime/" + (Get-DayPath $d) + '.csv')
        # GitHub이 이미 받은 시각은 그대로 두고, 노트북에만 있는 시각을 더함 (반납 전에 다시 실행해도 안전)
        $have = @(Read-Csv $dst); $haveStamps = @{}; foreach ($r in $have) { $haveStamps[$r.'인구기준시각'] = $true }
        $add = @($byDay[$day] | Where-Object { -not $haveStamps[$_.'인구기준시각'] })
        Write-CsvBom $dst (@($have) + $add | Sort-Object '인구기준시각', '장소코드')
    }
    $st = Join-Path $RepoRoot 'data/status/수집기록.csv'
    $keep = @(Read-Csv $st | Where-Object { $_.'실행' -ne 'laptop' -or ($Since -and $_.'수집시각' -lt $Since) })
    Write-CsvBom $st ($status.ToArray() + $keep | Sort-Object '수집시각')
    Write-Host "실시간: 원본 $($files.Count)개 -> $($byDay.Count)일"
}

# ---------------- 외국인 생활인구 (자치구, 단기·장기)
if (-not $Part -or $Part -eq 'foreigner') {
    $n = 0
    foreach ($f in (Get-ChildItem (Join-Path $Src '외국인_관광') -Recurse -File -Filter '외국인생활인구_*.csv')) {
        if ($f.Name -notmatch '외국인생활인구_(단기|장기)\.csv$') { continue }
        $kind = $Matches[1]; $date = $f.Directory.Name.Substring(0, 10)
        $d = [datetime]::ParseExact($date, 'yyyy-MM-dd', $null)
        $dst = Join-Path $RepoRoot ("data/foreigner/$kind/" + (Get-DayPath $d) + '.csv')
        New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
        Copy-Item $f.FullName $dst -Force; $n++
    }
    Write-Host "외국인 생활인구: $n 개 파일"
}

# ---------------- 행사 (공식·웹검색)
if (-not $Part -or $Part -eq 'events') {
    $n = 0
    foreach ($dir in (Get-ChildItem (Join-Path $Src 'data') -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}' })) {
        $d = [datetime]::ParseExact($dir.Name.Substring(0, 10), 'yyyy-MM-dd', $null)
        foreach ($pair in @(@('이벤트_공식.csv', '_공식'), @('이벤트_웹검색.csv', '_웹검색'))) {
            $s = Join-Path $dir.FullName $pair[0]
            if (Test-Path $s) {
                $dst = Join-Path $RepoRoot ("data/events/" + (Get-DayPath $d) + $pair[1] + '.csv')
                New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
                Copy-Item $s $dst -Force; $n++
            }
        }
    }
    Write-Host "행사: $n 개 파일"
}

# ---------------- 숙박 변경내역 + 기록
if (-not $Part -or $Part -eq 'lodging') {
    $logRows = New-Object System.Collections.Generic.List[object]; $n = 0; $lastCount = @{}
    foreach ($dir in (Get-ChildItem (Join-Path $Src '외국인_관광') -Recurse -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_' } | Sort-Object Name)) {
        $d = [datetime]::ParseExact($dir.Name.Substring(0, 10), 'yyyy-MM-dd', $null)
        foreach ($kind in '호텔', '외국인민박', '숙박업') {
            $full = Join-Path $dir.FullName "숙박_$kind.csv"; $chg = Join-Path $dir.FullName "숙박_$($kind)_변경내역.csv"; $same = Join-Path $dir.FullName "숙박_$($kind)_변화없음.txt"
            if (-not ((Test-Path $full) -or (Test-Path $same))) { continue }
            $cnt = @{ '신규' = 0; '변경' = 0; '삭제' = 0 }
            if (Test-Path $chg) {
                $dst = Join-Path $RepoRoot ("data/lodging/changes/" + (Get-DayPath $d) + "_$kind.csv")
                New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
                Copy-Item $chg $dst -Force; $n++
                foreach ($c in (Read-Csv $chg)) { $cnt[$c.'구분']++ }
            }
            # 변화없음인 날은 전체 파일이 없으니 앞 날짜 숫자를 그대로 씀
            if (Test-Path $full) { $all = @(Read-Csv $full); $lastCount[$kind] = @($all.Count, @($all | Where-Object { $_.'영업상태' -eq '영업/정상' }).Count) }
            $total = ''; $open = ''; if ($lastCount[$kind]) { $total = $lastCount[$kind][0]; $open = $lastCount[$kind][1] }
            $logRows.Add([pscustomobject][ordered]@{ '날짜' = $d.ToString('yyyy-MM-dd'); '종류' = $kind; '전체' = $total; '영업중' = $open; '신규' = $cnt['신규']; '변경' = $cnt['변경']; '삭제' = $cnt['삭제'] })
        }
    }
    Write-CsvBom (Join-Path $RepoRoot 'data/status/숙박기록.csv') $logRows
    Write-Host "숙박: 변경내역 $n 개, 기록 $($logRows.Count)줄"
}
