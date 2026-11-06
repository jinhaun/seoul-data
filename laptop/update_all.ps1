# 매일 쌓이는 데이터를 최종_데이터\최종_데이터.xlsx 까지 한 번에 반영합니다. (작업 스케줄러 SeoulUpdateDaily, 매일 09:00)
#   1) 외국인_관광 합본 → 2) 행정동 단기 외국인(지난달·이번 달) 다시 받기 → 3) 환율·날씨 → 4) 국적별·동별·해커톤·발표용 표 → 5) 최종_데이터.xlsx
#   - 엑셀 파일이 열려 있으면 덮어쓸 수 없어 이번 회차는 건너뜁니다 (엑셀을 닫고 이 파일을 직접 실행하면 됨)
#   - 덮어쓰기 전 최종_데이터.xlsx 를 최종_데이터\이전\ 에 날짜별로 남깁니다 (최근 7개)
#   - 기록: logs\update_all_YYYY-MM-DD.log
# 태블로는 자동으로 바뀌지 않습니다. 태블로에서 데이터 원본 우클릭 → 추출 → 새로 고침 (Public은 다시 저장)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log  = Join-Path $Root ("logs\update_all_" + (Get-Date).ToString('yyyy-MM-dd') + '.log')
New-Item -ItemType Directory -Force -Path (Split-Path $Log) | Out-Null
function Write-Log($msg) { $line = (Get-Date).ToString('HH:mm:ss') + '  ' + $msg; Add-Content -Path $Log -Value $line -Encoding UTF8; $line }

# 덮어쓸 엑셀이 열려 있는지 먼저 확인
$outputs = @('최종_데이터\최종_데이터.xlsx', '최종_데이터\외국인관광_대시보드_전체국적.xlsx', '해커톤_데이터\해커톤_데이터.xlsx', '날씨\날씨_Tableau.xlsx')
foreach ($o in $outputs) {
    $p = Join-Path $Root $o
    if (-not (Test-Path $p)) { continue }
    try { (New-Object IO.FileStream($p, 'Open', 'ReadWrite', 'None')).Dispose() }
    catch { Write-Log "건너뜀: $o 이(가) 열려 있음 (닫고 update_all.ps1 을 다시 실행하세요)"; exit 1 }
}

# 순서대로 실행 (앞 단계 결과를 뒤 단계가 씀). 하나라도 실패하면 거기서 멈추고 최종 엑셀은 그대로 둠
$steps = @(
    @('make_tourism_csv.ps1'),
    @('download_foreigner_data.ps1', @{ Big = $true; Recent = $true }),
    @('make_exchange_csv.ps1'),
    @('make_weather_csv.ps1'),
    @('make_weather_xlsx.ps1'),
    @('make_nationality_csv.ps1'),
    @('make_dong_csv.ps1'),
    @('make_hackathon_data.ps1'),
    @('make_hackathon_xlsx.ps1'),
    @('make_presentation_data.ps1'),
    @('make_holiday_effect.ps1'),
    @('make_correlation.ps1'),
    @('make_dong_hourly.ps1'),
    @('make_dashboard_excel.ps1', @{ AllNat = $true })
)
Write-Log '===== 시작'
foreach ($s in $steps) {
    $name = $s[0]; $opt = if ($s.Count -gt 1) { $s[1] } else { @{} }   # 스위치는 @{ 이름 = $true } 로 넘겨야 제대로 켜짐
    $t0 = Get-Date
    try {
        & (Join-Path $Root $name) @opt 2>&1 | ForEach-Object { Add-Content -Path $Log -Value "    $_" -Encoding UTF8 }
        Write-Log ("OK   $name " + (($opt.Keys | ForEach-Object { "-$_" }) -join ' ') + "  ({0:N0}초)" -f ((Get-Date) - $t0).TotalSeconds)
    } catch {
        Write-Log "실패 $name : $($_.Exception.Message)"
        Write-Log '===== 멈춤 (최종_데이터.xlsx 는 바뀌지 않음)'
        exit 1
    }
}

# 지난 최종 엑셀 남기기
$final = Join-Path $Root '최종_데이터\최종_데이터.xlsx'
$prev  = Join-Path $Root '최종_데이터\이전'
if (Test-Path $final) {
    New-Item -ItemType Directory -Force -Path $prev | Out-Null
    Copy-Item $final (Join-Path $prev ('최종_데이터_' + (Get-Item $final).LastWriteTime.ToString('yyyy-MM-dd_HHmm') + '.xlsx')) -Force
    Get-ChildItem $prev -Filter '*.xlsx' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 7 | Remove-Item
}

try {
    & (Join-Path $Root 'make_final_xlsx.ps1') 2>&1 | ForEach-Object { Add-Content -Path $Log -Value "    $_" -Encoding UTF8 }
    Write-Log 'OK   make_final_xlsx.ps1'
    Write-Log '===== 끝 (최종_데이터.xlsx 업데이트됨)'
} catch {
    Write-Log "실패 make_final_xlsx.ps1 : $($_.Exception.Message)"
    exit 1
}
