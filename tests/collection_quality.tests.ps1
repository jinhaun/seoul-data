$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/collection_quality.ps1"
function Assert($Condition, [string]$Label) { if (-not $Condition) { throw "검사 실패: $Label" }; Write-Host "통과: $Label" }
function New-Row([string]$Name, [string]$Time = '2026-11-13 11:05') {
    [pscustomobject]@{ '장소'=$Name; '인구기준시각'=$Time; '혼잡도'='여유'; '인구_최소'='0'; '인구_최대'='100' }
}
$names = @(1..121 | ForEach-Object { '장소' + $_ })
$slot = '2026-11-13 11'
$script:calls = @{}
$normal = { param($n) $script:calls[$n]++; [pscustomobject]@{ Row=(New-Row $n); Raw='{}' } }
$r = Invoke-PlaceCollection $slot $names @() $normal {}
Assert ($r.Added.Count -eq 121 -and $r.Missing.Count -eq 0) '정상 응답 121곳 완료'
$existing = @($r.Added | ForEach-Object { $_.Row })
$r = Invoke-PlaceCollection $slot $names $existing { throw '이미 받은 장소를 호출했습니다.' } {}
Assert ($r.Added.Count -eq 0 -and $r.Missing.Count -eq 0) '완료 시간은 중복 호출·중복 저장 없음'
$script:calls = @{}
$retry = { param($n)
    $script:calls[$n]++
    if ($n -in @('장소120','장소121') -and $script:calls[$n] -eq 1) { throw '시험용 접속 실패' }
    [pscustomobject]@{ Row=(New-Row $n); Raw='{}' }
}
$r = Invoke-PlaceCollection $slot $names @() $retry {}
Assert ($r.Added.Count -eq 121 -and $r.Missing.Count -eq 0 -and $script:calls['장소1'] -eq 1 -and $script:calls['장소121'] -eq 2) '두 장소 실패 후 빠진 곳만 재시도 성공'
$permanent = { param($n) if ($n -in @('장소120','장소121')) { throw '시험용 지속 실패' }; [pscustomobject]@{ Row=(New-Row $n); Raw='{}' } }
$r = Invoke-PlaceCollection $slot $names @() $permanent {}
Assert ($r.Added.Count -eq 119 -and $r.Missing.Count -eq 2) '지속 실패는 119곳 보존·두 곳 미완료'
$r2 = Invoke-PlaceCollection $slot $names @($r.Added | ForEach-Object { $_.Row }) $normal {}
Assert ($r2.Added.Count -eq 2 -and $r2.Missing.Count -eq 0) '다음 실행에서도 미완료 장소만 보충'
$nextHour = { param($n) [pscustomobject]@{ Row=(New-Row $n '2026-11-13 12:00'); Raw='{}' } }
$r = Invoke-PlaceCollection $slot @('장소1') @() $nextHour {}
Assert ($r.Added.Count -eq 1 -and $r.Missing.Count -eq 1 -and (Get-RowSlot $r.Added[0].Row) -eq '2026-11-13 12') '다음 시간 응답을 이전 시간 복구로 오인하지 않음'
$bad = New-Row '장소1'; $bad.'인구_최소' = ''; Assert (-not (Test-PopulationRow $bad)) '빈 인구는 완료에서 제외'
$bad = New-Row '장소1'; $bad.'인구_최대' = '-1'; Assert (-not (Test-PopulationRow $bad)) '잘못된 범위는 완료에서 제외'
Assert (Test-PopulationRow (New-Row '장소1')) '실제 0명은 유효값'
$checks = @([pscustomobject]@{ '시간대'=$slot; '상태'='미완료'; '누락장소'='장소120 / 장소121' })
Assert (@(Get-FinalPartialGaps $checks @() ([datetime]'2026-11-13 12:49')).Count -eq 0) '재시도 중에는 알림 없음'
Assert (@(Get-FinalPartialGaps $checks @() ([datetime]'2026-11-13 12:50')).Count -eq 1) '재시도 기한 후 부분 누락 감지'
$alert = @([pscustomobject]@{ '종류'='부분누락'; '시간대'=$slot })
Assert (@(Get-FinalPartialGaps $checks $alert ([datetime]'2026-11-13 13:00')).Count -eq 0) '동일 누락 중복 알림 방지'
$checks += [pscustomobject]@{ '시간대'=$slot; '상태'='완료'; '누락장소'='' }
Assert (@(Get-FinalPartialGaps $checks @() ([datetime]'2026-11-13 13:00')).Count -eq 0) '재시도로 채워지면 알림 없음'
Write-Host '전체 검사 통과 (외부 통신·인증값·슬랙 전송 없음)'
# 요청 함수가 부모 범위의 설정을 참조하는 실제 구조로 변수 충돌 재발을 검사합니다.
$key = '시험용-설정'; $script:authFailures = 0
$fetchPacket = { param($place)
    if ($key -ne '시험용-설정') { $script:authFailures++; throw '시험용 인증 설정 충돌' }
    [pscustomobject]@{ Row=(New-Row $place); Raw='{}' }
}
$provider = { param($place) & $fetchPacket $place }
$r = Invoke-PlaceCollection $slot $names @() $provider {}
Assert ($r.Missing.Count -eq 0 -and $script:authFailures -eq 0) '121곳 연속 요청에서 부모 인증 설정 보존'
$msg = Get-PartialAlertText @([pscustomobject]@{ '시간대'=$slot; '대상수'=121; '누락장소'='노량진 / 대림역' })
Assert ($msg -match '노량진, 대림역' -and $msg -notmatch '121|119|완료') '경고에는 미수집 장소만 표시'
$many = @([pscustomobject]@{ '시간대'=$slot; '대상수'=121; '누락장소'=($names[0..99] -join ' / ') })
$msg = Get-PartialAlertText $many
Assert ($msg.Length -lt 500 -and $msg -match '외 90곳' -and $msg -match 'https://github.com') '대량 누락은 짧게 표시하고 전체 목록 연결'
