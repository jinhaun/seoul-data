# 나라별 2026년 연휴 데이터를 엑셀 하나(연휴_데이터\연휴_데이터.xlsx)로 만듭니다.
#   연휴_목록 : 연휴 하나 = 한 줄 (공휴일 / 명절 연휴 / 방학)
#   연휴_달력 : 2026년 하루 x 나라 = 한 줄. 그날이 그 나라 연휴인지 (다른 데이터와 날짜+국적으로 연결하기 좋음)
# 나라: 중국·미국·일본·태국·한국 (국적 이름은 외국인 데이터와 같음)
# 출처: 공휴일 = Nager.Date 공개 API (나라 전체가 쉬는 날만), 태국 공휴일·명절 연휴 기간·방학 = 각국 발표를 보고 직접 입력

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dir  = Join-Path $Root '연휴_데이터'
$Out  = Join-Path $Dir 'csv'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Inv  = [Globalization.CultureInfo]::InvariantCulture
$ko   = [Globalization.CultureInfo]::GetCultureInfo('ko-KR')
$Year = 2026

$api = [ordered]@{ 'CN' = '중국'; 'US' = '미국'; 'JP' = '일본'; 'KR' = '한국' }   # 태국은 API에 없어 아래에 직접 입력
$countries = @('중국', '미국', '일본', '태국', '한국')

# 영어 이름 -> 한국어 (한국은 API의 한국어 이름을 그대로 씀)
$koName = @{
    "New Year's Day" = '신정'; 'Martin Luther King, Jr. Day' = '마틴 루서 킹 데이'; 'Presidents Day' = '대통령의 날'
    'Memorial Day' = '메모리얼 데이(전몰장병 추모일)'; 'Juneteenth National Independence Day' = '준틴스(노예해방 기념일)'
    'Independence Day' = '독립기념일'; 'Labour Day' = '노동절'; 'Columbus Day' = '콜럼버스 데이'; 'Veterans Day' = '재향군인의 날'
    'Thanksgiving Day' = '추수감사절'; 'Thanksgiving' = '추수감사절'; 'Christmas Day' = '크리스마스'
    'Easter Monday' = '부활절 월요일'; 'Easter Sunday' = '부활절'; 'Good Friday' = '성금요일'
    'Victory in Europe Day' = '유럽 전승 기념일'; 'Ascension Day' = '예수 승천일'; 'Whit Monday' = '성령강림 월요일'
    'Bastille Day' = '혁명 기념일(바스티유의 날)'; 'Assumption Day' = '성모 승천일'; "All Saints' Day" = '만성절'; 'Armistice Day' = '휴전 기념일'
    'Victoria Day' = '빅토리아 데이'; 'Canada Day' = '캐나다 데이'; 'National Day for Truth and Reconciliation' = '진실과 화해의 날'
    'Pancasila Day' = '판차실라의 날'
    'Chinese New Year (Spring Festival)' = '춘절'; 'Dragon Boat Festival' = '단오절'; 'Mid-Autumn Festival' = '중추절'; 'National Day' = '국경절'
    'Coming of Age Day' = '성인의 날'; 'Foundation Day' = '건국기념일'; "The Emperor's Birthday" = '천황 탄생일'; 'Vernal Equinox Day' = '춘분'
    'Shōwa Day' = '쇼와의 날'; 'Constitution Memorial Day' = '헌법기념일'; 'Greenery Day' = '녹색의 날'; "Children's Day" = '어린이날'
    'Marine Day' = '바다의 날'; 'Mountain Day' = '산의 날'; 'Respect for the Aged Day' = '경로의 날'; 'Autumnal Equinox Day' = '추분'
    'Sports Day' = '스포츠의 날'; 'Culture Day' = '문화의 날'; 'Labour Thanksgiving Day' = '근로감사의 날'
}

$hol = New-Object System.Collections.Generic.List[object]
foreach ($cc in $api.Keys) {
    foreach ($h in (Invoke-RestMethod "https://date.nager.at/api/v3/PublicHolidays/$Year/$cc" -TimeoutSec 60)) {
        if ($h.global -eq $false) { continue }   # 일부 주·지역만 쉬는 날은 뺌
        $name = if ($cc -eq 'KR') { $h.localName } elseif ($koName.ContainsKey($h.name)) { $koName[$h.name] } else { $h.name }
        $hol.Add([pscustomobject][ordered]@{
            '국적' = $api[$cc]; '연휴명' = $name; '원어명' = $h.localName; '영문명' = $h.name; '종류' = '공휴일'
            '시작일' = $h.date; '종료일' = $h.date; '출처' = 'Nager.Date API'
        })
    }
}
# 명절 연휴 기간(주말 포함), API에 없는 공휴일, 방학(지역·학교마다 달라 대략)
$manual = @(
    @('중국','원단 연휴','元旦','New Year holiday','명절 연휴','2026-01-01','2026-01-03'),
    @('중국','춘절 연휴','春节','Spring Festival holiday','명절 연휴','2026-02-15','2026-02-23'),
    @('중국','청명절 연휴','清明节','Qingming holiday','명절 연휴','2026-04-04','2026-04-06'),
    @('중국','노동절 연휴','劳动节','Labour Day holiday','명절 연휴','2026-05-01','2026-05-05'),
    @('중국','단오절 연휴','端午节','Dragon Boat holiday','명절 연휴','2026-06-19','2026-06-21'),
    @('중국','중추절 연휴','中秋节','Mid-Autumn holiday','명절 연휴','2026-09-25','2026-09-27'),
    @('중국','국경절 연휴','国庆节','National Day holiday','명절 연휴','2026-10-01','2026-10-07'),
    @('중국','여름방학','暑假','Summer vacation','방학(대략)','2026-07-11','2026-08-31'),
    @('일본','연말연시','年末年始','New Year holidays','명절 연휴','2026-01-01','2026-01-04'),
    @('일본','골든위크','ゴールデンウィーク','Golden Week','명절 연휴','2026-04-29','2026-05-06'),
    @('일본','오봉','お盆','Obon','명절 연휴','2026-08-13','2026-08-16'),
    @('일본','실버위크','シルバーウィーク','Silver Week','명절 연휴','2026-09-19','2026-09-23'),
    @('일본','여름방학','夏休み','Summer vacation','방학(대략)','2026-07-20','2026-08-31'),
    @('태국','신정','วันขึ้นปีใหม่','New Year''s Day','공휴일','2026-01-01','2026-01-01'),
    @('태국','마카부차','วันมาฆบูชา','Makha Bucha Day','공휴일','2026-03-03','2026-03-03'),
    @('태국','짜끄리 왕조 기념일','วันจักรี','Chakri Memorial Day','공휴일','2026-04-06','2026-04-06'),
    @('태국','송끄란','วันสงกรานต์','Songkran Festival','명절 연휴','2026-04-13','2026-04-15'),
    @('태국','노동절','วันแรงงาน','Labour Day','공휴일','2026-05-01','2026-05-01'),
    @('태국','대관식 기념일','วันฉัตรมงคล','Coronation Day','공휴일','2026-05-04','2026-05-04'),
    @('태국','위사카부차','วันวิสาขบูชา','Visakha Bucha Day','공휴일','2026-05-31','2026-06-01'),
    @('태국','왕비 탄신일','วันเฉลิมพระชนมพรรษาสมเด็จพระราชินี','Queen Suthida''s Birthday','공휴일','2026-06-03','2026-06-03'),
    @('태국','국왕 탄신일','วันเฉลิมพระชนมพรรษา ร.10','King Vajiralongkorn''s Birthday','공휴일','2026-07-28','2026-07-28'),
    @('태국','아산하부차·카오판사','วันอาสาฬหบูชา / วันเข้าพรรษา','Asahna Bucha / Buddhist Lent Day','공휴일','2026-07-29','2026-07-30'),
    @('태국','어머니날(왕대비 탄신일)','วันแม่แห่งชาติ','Mother''s Day','공휴일','2026-08-12','2026-08-12'),
    @('태국','라마 9세 추모일','วันนวมินทรมหาราช','King Bhumibol Memorial Day','공휴일','2026-10-13','2026-10-13'),
    @('태국','쭐라롱꼰 대왕 기념일','วันปิยมหาราช','Chulalongkorn Day','공휴일','2026-10-23','2026-10-23'),
    @('태국','아버지날','วันพ่อแห่งชาติ','Father''s Day','공휴일','2026-12-05','2026-12-05'),
    @('태국','제헌절','วันรัฐธรรมนูญ','Constitution Day','공휴일','2026-12-10','2026-12-10'),
    @('태국','연말','วันสิ้นปี','New Year''s Eve','공휴일','2026-12-31','2026-12-31'),
    @('태국','여름방학','ปิดภาคเรียนฤดูร้อน','School summer break','방학(대략)','2026-03-15','2026-05-15'),
    @('태국','10월 방학','ปิดภาคเรียนเดือนตุลาคม','School October break','방학(대략)','2026-10-01','2026-10-31'),
    @('미국','봄방학','Spring break','Spring break','방학(대략)','2026-03-07','2026-03-29'),
    @('미국','여름방학','Summer vacation','Summer vacation','방학(대략)','2026-06-06','2026-08-23'),
    @('미국','추수감사절 연휴','Thanksgiving weekend','Thanksgiving weekend','명절 연휴','2026-11-26','2026-11-29'),
    @('미국','연말 연휴','Holiday season','Holiday season','명절 연휴','2026-12-24','2026-12-31'),
    @('한국','설날 연휴','설날','Seollal holiday','명절 연휴','2026-02-14','2026-02-18'),
    @('한국','추석 연휴','추석','Chuseok holiday','명절 연휴','2026-09-24','2026-09-27')
)
foreach ($m in $manual) {
    $hol.Add([pscustomobject][ordered]@{
        '국적' = $m[0]; '연휴명' = $m[1]; '원어명' = $m[2]; '영문명' = $m[3]; '종류' = $m[4]
        '시작일' = $m[5]; '종료일' = $m[6]; '출처' = '직접 입력 (각국 발표 기준, 확인 필요)'
    })
}
$list = foreach ($h in ($hol | Sort-Object '국적', '시작일', '종류')) {
    $s = [datetime]::ParseExact($h.'시작일', 'yyyy-MM-dd', $Inv); $e = [datetime]::ParseExact($h.'종료일', 'yyyy-MM-dd', $Inv)
    $o = [ordered]@{}; foreach ($p in $h.PSObject.Properties) { $o[$p.Name] = $p.Value }
    $o['일수'] = ($e - $s).Days + 1
    [pscustomobject]$o
}
$list | Export-Csv (Join-Path $Out '연휴_목록.csv') -NoTypeInformation -Encoding UTF8

# 하루 x 나라 달력
$cal = foreach ($n in $countries) {
    $mine = @($list | Where-Object { $_.'국적' -eq $n })
    for ($d = [datetime]::new($Year, 1, 1); $d.Year -eq $Year; $d = $d.AddDays(1)) {
        $ds = $d.ToString('yyyy-MM-dd')
        $on = @($mine | Where-Object { $_.'시작일' -le $ds -and $_.'종료일' -ge $ds })
        $weekend = $d.DayOfWeek -in 'Saturday', 'Sunday'
        $off = @($on | Where-Object { $_.'종류' -ne '방학(대략)' }).Count -gt 0
        [pscustomobject][ordered]@{
            '날짜' = $ds; '월' = $d.ToString('yyyy-MM'); '요일' = $d.ToString('ddd', $ko)
            '주말여부' = $(if ($weekend) { 'Y' } else { 'N' }); '국적' = $n
            '연휴여부' = $(if ($on.Count) { 'Y' } else { 'N' })
            '쉬는날' = $(if ($weekend -or $off) { 'Y' } else { 'N' })   # 주말 또는 공휴일·명절 (방학은 제외)
            '연휴명' = ($on | ForEach-Object { $_.'연휴명' } | Select-Object -Unique) -join ' / '
            '종류' = ($on | ForEach-Object { $_.'종류' } | Select-Object -Unique) -join ' / '
        }
    }
}
$cal | Export-Csv (Join-Path $Out '연휴_달력.csv') -NoTypeInformation -Encoding UTF8

$readme = @(
    "나라별 연휴 데이터 (만든 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm')))",
    "나라: $($countries -join ', ')  /  기간: $Year 년",
    '',
    '연휴_목록 : 연휴 하나 = 한 줄',
    '  종류 = 공휴일(하루) / 명절 연휴(주말 포함 연속 기간) / 방학(대략: 지역·학교마다 달라 대표 기간)',
    '  공휴일 = Nager.Date 공개 API (나라 전체가 쉬는 날만). 태국 공휴일(API에 없음)·명절 연휴·방학 = 각국 발표를 보고 직접 입력 → 발표 전 확인 권장 (태국 불교 명절은 음력이라 해마다 날짜가 바뀜)',
    '  한국 공휴일은 대체공휴일 날짜로 들어가 있음 (예: 3·1절 → 3월 2일, 광복절 → 8월 17일, 개천절 → 10월 5일)',
    '연휴_달력 : 하루 x 나라 = 한 줄 (365일 x 5개 나라)',
    '  연휴여부 = 그날이 그 나라 공휴일·명절·방학 중 하나면 Y',
    '  쉬는날   = 주말이거나 공휴일·명절이면 Y (방학은 제외)',
    '  연휴명·종류 = 그날 겹친 연휴가 여러 개면 " / " 로 이어 붙임',
    '  다른 데이터와 연결: 날짜 + 국적 두 칸으로 (국적 이름이 외국인 데이터와 같음)',
    '다시 만들기: 프로젝트 폴더의 make_holiday_data.ps1 실행'
)
[IO.File]::WriteAllLines((Join-Path $Dir '읽어주세요.txt'), $readme, (New-Object Text.UTF8Encoding($true)))
"OK 연휴 $(@($list).Count)개, 달력 $(@($cal).Count)줄 -> $Out"
& (Join-Path $Root 'csv_to_xlsx.ps1') -Src $Out -Dst $Dir -Combine '연휴_데이터.xlsx' -Order '연휴_목록', '연휴_달력' -Notes (Join-Path $Dir '읽어주세요.txt')
