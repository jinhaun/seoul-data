# 해커톤 CSV(해커톤_데이터\csv + 동별_분석)를 시트 여러 개짜리 엑셀 하나(해커톤_데이터\해커톤_데이터.xlsx)로 합칩니다.
# 먼저 make_hackathon_data.ps1, make_dong_csv.ps1 을 실행하세요.

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $Root 'csv_to_xlsx.ps1') -Src '해커톤_데이터\csv', '동별_분석' -Dst '해커톤_데이터' -Combine '해커톤_데이터.xlsx' `
    -Order '자치구_국적별', '자치구_시설', '동별_국적별_외국인', '동별_시설', '연휴_효과', '연휴_자치구', '연휴_목록', '일별_국적_연휴', '월별_방문_환율_기온' `
    -Notes '해커톤_데이터\읽어주세요.txt'
