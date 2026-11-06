# 서울 열린데이터광장의 외국인 관련 데이터를 한 번에 받아 외국인_공공데이터 폴더에 CSV로 저장합니다.
# 사용: powershell -File download_foreigner_data.ps1            (작은 데이터 전부)
#       powershell -File download_foreigner_data.ps1 -Big       (행정동 단위 외국인 생활인구, 월별 파일로 저장 - 오래 걸림)

#       powershell -File download_foreigner_data.ps1 -Big -Recent  (단기만, 지난달·이번 달만 다시 받기 - 매일 자동 업데이트용)

param([switch]$Big, [switch]$Recent)

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out     = Join-Path $Root '외국인_공공데이터'
$Utf8    = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$ApiKey = Get-Content (Join-Path $Root 'config.txt') -Encoding UTF8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.Contains('=') } |
    Select-Object -First 1

function Get-Page($svc, [int]$s, [int]$e, $extra) {
    $url = "http://openapi.seoul.go.kr:8088/$ApiKey/json/$svc/$s/$e/" + $(if ($extra) { $extra } else { '' })
    for ($try = 1; ; $try++) {
        $wc = New-Object System.Net.WebClient
        try {
            $j = $Utf8.GetString($wc.DownloadData($url)) | ConvertFrom-Json
            if ($j.$svc) { return $j.$svc }
            if ($j.RESULT.CODE -eq 'INFO-200') { return $null }   # 해당 데이터 없음
            throw "API 오류: $($j.RESULT.CODE)"
        } catch {
            if ($try -ge 3) { throw }
            Start-Sleep -Seconds (5 * $try)
        } finally { $wc.Dispose() }
    }
}

function Get-All($svc, $extra) {
    $first = Get-Page $svc 1 1000 $extra
    if (-not $first) { return @() }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($r in $first.row) { $rows.Add($r) }
    $total = [int]$first.list_total_count
    for ($s = 1001; $s -le $total; $s += 1000) {
        $p = Get-Page $svc $s ($s + 999) $extra
        foreach ($r in $p.row) { $rows.Add($r) }
    }
    return $rows
}

# 값 앞뒤 공백 정리
function Clean($rows) {
    foreach ($r in $rows) {
        foreach ($p in $r.PSObject.Properties) { if ($p.Value -is [string]) { $p.Value = $p.Value.Trim() } }
        $r
    }
}

$log = New-Object System.Collections.Generic.List[string]

if (-not $Big) {
    $sets = @(
        # 외국인 대상 관광 정보 (visitseoul, 5개 언어: ko/en/ja/zh-CN/zh-TW)
        @{ Svc = 'TbVwAttractions';  File = '관광_명소_5개언어';            Src = '서울시 관광 명소 (visitseoul)' },
        @{ Svc = 'TbVwRestaurants';  File = '관광_음식점_5개언어';          Src = '서울시 관광 음식 (visitseoul)' },
        @{ Svc = 'TbVwShopping';     File = '관광_쇼핑_5개언어';            Src = '서울시 관광 쇼핑 (visitseoul)' },
        @{ Svc = 'TbVwNature';       File = '관광_자연_5개언어';            Src = '서울시 관광 자연 (visitseoul)' },
        @{ Svc = 'SebcTourZoneEng';  File = '관광특구_영어';                Src = 'OA-13067 서울시 관광특구 데이터 정보 (영어)' },
        # 외국인 교통
        @{ Svc = 'tbTrfcDailyTourlistPassStats';       File = '교통_외국인관광객기간권_통행';  Src = 'OA-22515 서울교통공사 외국인 관광객 기간권 일별통행통계' },
        @{ Svc = 'tbTrfcDailyTourlistPassInflowStats'; File = '교통_외국인관광객기간권_유입';  Src = 'OA-22516 서울교통공사 외국인 관광객 기간권 일별 유입통계' },
        @{ Svc = 'tbTrfcForeignerPssOutflow';          File = '교통_외국인관광객기간권_유출';  Src = 'OA-22514 서울교통공사 외국인 관광객 기간권 일별 유출통계' },
        @{ Svc = 'cycleForeignerRentMonthInfo';        File = '교통_따릉이_외국인대여_월별';   Src = 'OA-15242 서울시 공공자전거 따릉이 외국인 대여정보(월별)' },
        # 외국인 대상 업소·시설
        @{ Svc = 'frgnrTourGiftShopInfo'; File = '업소_외국인전용_관광기념품판매점'; Src = 'OA-15164 서울시 외국인전용 관광기념품 판매점 정보' },
        @{ Svc = 'SebcPharmacyInfoKor';   File = '업소_외국어가능_약국';            Src = 'OA-12967 서울시 외국어 가능 약국 정보' },
        @{ Svc = 'brkPgGlobal';           File = '업소_글로벌공인중개사무소';        Src = 'OA-22813 서울시 글로벌공인중개사무소 현황' },
        @{ Svc = 'LOCALDATA_031203';      File = '업소_종합여행업_인허가';           Src = 'OA-16051 서울시 종합여행업 인허가 정보' },
        @{ Svc = 'neisSchoolInfoFs';      File = '시설_외국인학교';                 Src = 'OA-20562 서울시 외국인학교 기본정보' },
        # 생활인구 일별 집계 (자치구별 내국인·장기·단기 외국인)
        @{ Svc = 'aiSe250MSpopLocalResd'; File = '생활인구_자치구별_일별집계_내외국인'; Src = 'OA-23060 자치구별 서울 생활인구(250m) 일별집계표' }
    )
    foreach ($s in $sets) {
        try {
            $rows = @(Clean (Get-All $s.Svc $null))
            $file = Join-Path $Out ($s.File + '.csv')
            $rows | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
            $log.Add(("{0}.csv | {1}건 | {2} | API {3}" -f $s.File, $rows.Count, $s.Src, $s.Svc))
            "OK  $($s.File): $($rows.Count)건"
        } catch {
            $log.Add(("{0}.csv | 실패: {1} | {2}" -f $s.File, $_.Exception.Message, $s.Src))
            "ERR $($s.File): $($_.Exception.Message)"
        }
    }
    $log.Add('받지 못함 (서울시 서버 오류 ERROR-500 반복): OA-22517 서울교통공사 1회권 외국인 일별통행통계, OA-16093 외국인전용유흥음식점업 인허가 정보')
    $readme = @(
        "외국인 관련 공공데이터 (서울 열린데이터광장) - 받은 날짜: $((Get-Date).ToString('yyyy-MM-dd HH:mm'))",
        '한 번 받아 둔 자료입니다. 자동으로 갱신되지 않습니다. 다시 받으려면 download_foreigner_data.ps1 을 실행하세요.',
        '이미 매일 모으는 외국인 생활인구(자치구별)·외국인 민박·호텔 목록은 외국인_관광 폴더에 있습니다.',
        '출처: 서울 열린데이터광장 (공공누리 1유형 등, 각 데이터셋 이용조건 확인)',
        ''
    ) + $log
    [IO.File]::WriteAllLines((Join-Path $Out '읽어주세요.txt'), $readme, $Utf8Bom)
} else {
    # 행정동 단위 단기·장기 외국인 생활인구 (API는 올해 자료만 제공) -> 월별 파일
    $types = @(@{ Svc = 'Spop250mFornTempDong'; Name = '단기' }, @{ Svc = 'Spop250mFornLongDong'; Name = '장기' })
    if ($Recent) { $types = @($types[0]) }   # 대시보드에 쓰는 단기만
    foreach ($t in $types) {
        $dir = Join-Path $Out "생활인구_행정동별_$($t.Name)외국인"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $today = (Get-Date).Date
        $from = New-Object DateTime($today.Year, 1, 1)
        if ($Recent) { $from = (New-Object DateTime($today.Year, $today.Month, 1)).AddMonths(-1) }   # 늦게 올라오는 날까지 채우려고 지난달부터
        for ($m = $from; $m -le $today; $m = $m.AddMonths(1)) {
            $file = Join-Path $dir ("행정동별_$($t.Name)외국인_" + $m.ToString('yyyy-MM') + '.csv')
            $monthRows = New-Object System.Collections.Generic.List[object]
            $days = 0
            for ($d = $m; $d -lt $m.AddMonths(1) -and $d -lt $today; $d = $d.AddDays(1)) {
                $rows = Get-All $t.Svc $d.ToString('yyyyMMdd')
                if (@($rows).Count -gt 0) { $days++; foreach ($r in (Clean $rows)) { $monthRows.Add($r) } }
            }
            if ($monthRows.Count -gt 0) {
                $monthRows | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
                "OK  $($t.Name) $($m.ToString('yyyy-MM')): $days 일, $($monthRows.Count)행"
            }
        }
    }
}
