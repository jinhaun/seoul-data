# collect.ps1 을 작업 스케줄러에 30분마다(매시 01분·31분) 실행으로 등록합니다.
# 인구 데이터가 약 28~30분 늦게 들어오므로 01분 수집 = 전 시각 30분 데이터, 31분 수집 = 정각 데이터.
# 다시 실행하면 기존 등록을 덮어씁니다.
# 등록 해제: Unregister-ScheduledTask -TaskName SeoulRtdCollect -Confirm:$false

$TaskName = 'SeoulRtdCollect'
$Root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script = Join-Path $Root 'collect.ps1'

# 창이 뜨지 않도록 run_hidden.vbs 를 거쳐 PowerShell 스크립트를 실행합니다.
# (창을 닫으면 그 회차 수집이 중간에 멈추기 때문)
$Hidden = Join-Path $Root 'run_hidden.vbs'
function New-HiddenAction($ps1) {
    New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$Hidden`" `"$ps1`"" -WorkingDirectory $Root
}

$action = New-HiddenAction $Script

# 오늘 00:01 기준으로 30분마다 무기한 반복 (00:01, 00:31, 01:01, ...)
$start   = (Get-Date).Date.AddMinutes(1)
$trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes 30)

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -WakeToRun `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description '서울 실시간 도시데이터 30분마다 수집 (매시 01·31분)' -Force | Out-Null

# events.ps1 : 매일 아침 9시 오늘의 문화행사 정리
# 등록 해제: Unregister-ScheduledTask -TaskName SeoulEventsDaily -Confirm:$false
$EventsTask   = 'SeoulEventsDaily'
$EventsScript = Join-Path $Root 'events.ps1'
$eventsAction = New-HiddenAction $EventsScript
$eventsTrigger = New-ScheduledTaskTrigger -Daily -At '09:00'
Register-ScheduledTask -TaskName $EventsTask -Action $eventsAction -Trigger $eventsTrigger -Settings $settings `
    -Description '서울시 오늘의 문화행사 매일 9시 정리' -Force | Out-Null

# tourism.ps1 : 매일 아침 9시 숙박 목록 3종 + 외국인 생활인구 (외국인_관광 폴더)
# 등록 해제: Unregister-ScheduledTask -TaskName SeoulTourismDaily -Confirm:$false
$TourTask   = 'SeoulTourismDaily'
$TourScript = Join-Path $Root 'tourism.ps1'
$tourAction = New-HiddenAction $TourScript
$tourTrigger = New-ScheduledTaskTrigger -Daily -At '09:00'
Register-ScheduledTask -TaskName $TourTask -Action $tourAction -Trigger $tourTrigger -Settings $settings `
    -Description '숙박 목록 3종 + 외국인 생활인구 매일 9시 저장' -Force | Out-Null

# update_all.ps1 : 매일 9시 최종_데이터.xlsx 까지 다시 만들기. 오래 걸릴 수 있어 2시간까지 허용
# 등록 해제: Unregister-ScheduledTask -TaskName SeoulUpdateDaily -Confirm:$false
$UpdTask   = 'SeoulUpdateDaily'
$updAction = New-HiddenAction (Join-Path $Root 'update_all.ps1')
$updTrigger = New-ScheduledTaskTrigger -Daily -At '09:00'
$updSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -WakeToRun -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName $UpdTask -Action $updAction -Trigger $updTrigger -Settings $updSettings `
    -Description '매일 9시 최종_데이터.xlsx 자동 업데이트 (update_all.ps1)' -Force | Out-Null

Get-ScheduledTask -TaskName $TaskName, $EventsTask, $TourTask, $UpdTask | Get-ScheduledTaskInfo |
    Select-Object TaskName, NextRunTime, LastRunTime, LastTaskResult
