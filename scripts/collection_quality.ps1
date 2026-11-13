# 장소와 실제 기준 시각을 검사합니다. 통신·인증값 없이 시험 가능합니다.
function Get-RowSlot($Row) {
    $stamp = [datetime]::MinValue
    if ([datetime]::TryParseExact("$($Row.'인구기준시각')", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$stamp)) { return $stamp.ToString('yyyy-MM-dd HH') }
    return ''
}
function Test-PopulationRow($Row) {
    $lo = 0L; $hi = 0L
    return ((Get-RowSlot $Row) -ne '' -and "$($Row.'장소')" -ne '' -and
        "$($Row.'혼잡도')" -in @('여유','보통','약간 붐빔','붐빔') -and
        [long]::TryParse("$($Row.'인구_최소')", [ref]$lo) -and
        [long]::TryParse("$($Row.'인구_최대')", [ref]$hi) -and $lo -ge 0 -and $hi -ge $lo)
}
function Get-MissingPlaces([string]$Slot, $Names, $Rows) {
    $found = @{}
    foreach ($row in $Rows) {
        if ((Test-PopulationRow $row) -and (Get-RowSlot $row) -eq $Slot) { $found["$($row.'장소')"] = $true }
    }
    foreach ($name in $Names) { if (-not $found[$name]) { $name } }
}
function Invoke-PlaceCollection([string]$Slot, $Names, $Existing, [scriptblock]$Fetch, [scriptblock]$Pause, [int]$RetryRounds = 2, [int]$BudgetSeconds = 480) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Existing) { $all.Add($row) }
    $added = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($row in $all) { if (Test-PopulationRow $row) { $seen[(Get-RowSlot $row) + '|' + $row.'장소'] = $true } }
    for ($round = 0; $round -le $RetryRounds; $round++) {
        if ($timer.Elapsed.TotalSeconds -ge $BudgetSeconds) { break }
        $missing = @(Get-MissingPlaces $Slot $Names $all)
        if (-not $missing.Count) { break }
        if ($round -gt 0) { & $Pause }
        foreach ($name in $missing) {
            if ($timer.Elapsed.TotalSeconds -ge $BudgetSeconds) { break }
            try {
                $packet = & $Fetch $name
                $row = $packet.Row
                if (-not (Test-PopulationRow $row) -or $row.'장소' -ne $name) { continue }
                # 다른 시간 응답은 실제 시각대로 보존하고 목표 시간 완료로 세지 않습니다.
                $key = (Get-RowSlot $row) + '|' + $name
                if (-not $seen[$key]) { $all.Add($row); $added.Add($packet); $seen[$key] = $true }
            } catch { Write-Host "재수집 대상: $name (통신 또는 응답 오류)" }
        }
    }
    return [pscustomobject]@{ Added = $added.ToArray(); Missing = @(Get-MissingPlaces $Slot $Names $all) }
}
function Get-FinalPartialGaps($Checks, $AlertLog, [datetime]$Now) {
    $notified = @{}
    foreach ($entry in $AlertLog) { if ($entry.'종류' -eq '부분누락') { $notified[$entry.'시간대'] = $true } }
    foreach ($group in ($Checks | Group-Object '시간대')) {
        $last = $group.Group | Select-Object -Last 1
        $time = [datetime]::ParseExact($last.'시간대', 'yyyy-MM-dd HH', $null)
        if ($last.'상태' -ne '완료' -and $Now -ge $time.AddMinutes(110) -and -not $notified[$last.'시간대']) { $last }
    }
}
