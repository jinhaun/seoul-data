# 외국인·관광 관련 데이터를 매일 모아 외국인_관광 폴더에 저장합니다.
# 저장 방식: 월별 폴더 안의 날짜 폴더(외국인_관광\YYYY-MM\YYYY-MM-DD\)에 저장합니다.
#  1) 숙박 목록 3종 (서울시 지방행정 인허가, 매일 밤 갱신) -> 외국인_관광\YYYY-MM\오늘날짜\숙박_호텔.csv 등
#     - 가장 최근에 저장한 목록과 같으면 전체 목록 대신 숙박_호텔_변화없음.txt 만 남깁니다.
#     - 바뀌었으면 전체 목록을 다시 저장하고, 숙박_호텔_변경내역.csv 에 신규/삭제/변경을 정리합니다.
#     - 호텔: 관광숙박업 (관광호텔·호스텔·가족호텔 등)
#     - 외국인민박: 외국인관광 도시민박업
#     - 숙박업: 일반 숙박업 (모텔·생활숙박 등)
#     좌표는 원본 X,Y(중부원점 TM, EPSG:5174)와 변환한 위도·경도(WGS84)를 함께 넣습니다.
#  2) 외국인 생활인구 (서울시 250m 격자 기반 자치구별, 약 4일 지연) -> 외국인_관광\YYYY-MM\데이터날짜\외국인생활인구_단기.csv, _장기.csv
#     올해 1월 1일부터 어제까지 중 아직 저장 안 된 날짜만 받습니다. (API는 올해 자료만 제공)

param([switch]$SkipLodging, [switch]$SkipPopulation)

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutRoot = Join-Path $Root '외국인_관광'
$LogDir  = Join-Path $Root 'logs'
$Utf8    = New-Object System.Text.UTF8Encoding($false)
$today   = (Get-Date).Date
$LogFile = Join-Path $LogDir ((Get-Date).ToString('yyyy-MM') + '.log')
New-Item -ItemType Directory -Force -Path $OutRoot, $LogDir | Out-Null

function Write-Log($msg) {
    $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  [외국인관광] ' + $msg
    [System.IO.File]::AppendAllText($LogFile, $line + "`r`n", $Utf8)
}

# 서버가 가끔 JSON이 아닌 응답을 주므로 실패하면 최대 3번까지 다시 시도
function Get-Json($url) {
    for ($try = 1; ; $try++) {
        $wc = New-Object System.Net.WebClient
        try { return ($Utf8.GetString($wc.DownloadData($url)) | ConvertFrom-Json) }
        catch { if ($try -ge 3) { throw } ; Start-Sleep -Seconds (10 * $try) }
        finally { $wc.Dispose() }
    }
}

# 중부원점 TM(EPSG:5174, Bessel) -> WGS84 위경도
# +proj=tmerc +lat_0=38 +lon_0=127.0028902777778 +k=1 +x_0=200000 +y_0=500000 +ellps=bessel
# +towgs84=-115.80,474.99,674.11,1.16,-2.31,-1.63,6.43
function Convert-TmToWgs84([double]$x, [double]$y) {
    $a = 6377397.155; $f = 1 / 299.1528128
    $e2 = 2 * $f - $f * $f; $ep2 = $e2 / (1 - $e2)
    $lat0 = 38 * [Math]::PI / 180; $lon0 = 127.0028902777778 * [Math]::PI / 180
    $x0 = 200000.0; $y0 = 500000.0; $k0 = 1.0
    $e4 = $e2 * $e2; $e6 = $e4 * $e2
    $mFn = {
        param($p)
        $a * ((1 - $e2 / 4 - 3 * $e4 / 64 - 5 * $e6 / 256) * $p -
              (3 * $e2 / 8 + 3 * $e4 / 32 + 45 * $e6 / 1024) * [Math]::Sin(2 * $p) +
              (15 * $e4 / 256 + 45 * $e6 / 1024) * [Math]::Sin(4 * $p) -
              (35 * $e6 / 3072) * [Math]::Sin(6 * $p))
    }
    $m  = (& $mFn $lat0) + ($y - $y0) / $k0
    $mu = $m / ($a * (1 - $e2 / 4 - 3 * $e4 / 64 - 5 * $e6 / 256))
    $e1 = (1 - [Math]::Sqrt(1 - $e2)) / (1 + [Math]::Sqrt(1 - $e2))
    $p1 = $mu + (3 * $e1 / 2 - 27 * [Math]::Pow($e1, 3) / 32) * [Math]::Sin(2 * $mu) +
          (21 * $e1 * $e1 / 16 - 55 * [Math]::Pow($e1, 4) / 32) * [Math]::Sin(4 * $mu) +
          (151 * [Math]::Pow($e1, 3) / 96) * [Math]::Sin(6 * $mu) +
          (1097 * [Math]::Pow($e1, 4) / 512) * [Math]::Sin(8 * $mu)
    $sin1 = [Math]::Sin($p1); $cos1 = [Math]::Cos($p1); $tan1 = [Math]::Tan($p1)
    $c1 = $ep2 * $cos1 * $cos1; $t1 = $tan1 * $tan1
    $n1 = $a / [Math]::Sqrt(1 - $e2 * $sin1 * $sin1)
    $r1 = $a * (1 - $e2) / [Math]::Pow(1 - $e2 * $sin1 * $sin1, 1.5)
    $d  = ($x - $x0) / ($n1 * $k0)
    $lat = $p1 - ($n1 * $tan1 / $r1) * ($d * $d / 2 -
           (5 + 3 * $t1 + 10 * $c1 - 4 * $c1 * $c1 - 9 * $ep2) * [Math]::Pow($d, 4) / 24 +
           (61 + 90 * $t1 + 298 * $c1 + 45 * $t1 * $t1 - 252 * $ep2 - 3 * $c1 * $c1) * [Math]::Pow($d, 6) / 720)
    $lon = $lon0 + ($d - (1 + 2 * $t1 + $c1) * [Math]::Pow($d, 3) / 6 +
           (5 - 2 * $c1 + 28 * $t1 - 3 * $c1 * $c1 + 8 * $ep2 + 24 * $t1 * $t1) * [Math]::Pow($d, 5) / 120) / $cos1

    # Bessel 위경도 -> 지구중심 좌표 -> 7변수 변환 -> WGS84 위경도
    $n = $a / [Math]::Sqrt(1 - $e2 * [Math]::Sin($lat) * [Math]::Sin($lat))
    $X = $n * [Math]::Cos($lat) * [Math]::Cos($lon)
    $Y = $n * [Math]::Cos($lat) * [Math]::Sin($lon)
    $Z = $n * (1 - $e2) * [Math]::Sin($lat)
    $sec = [Math]::PI / (180 * 3600)
    $rx = 1.16 * $sec; $ry = -2.31 * $sec; $rz = -1.63 * $sec; $s = 1 + 6.43e-6
    $X2 = -115.80 + $s * ($X - $rz * $Y + $ry * $Z)
    $Y2 =  474.99 + $s * ($rz * $X + $Y - $rx * $Z)
    $Z2 =  674.11 + $s * (-$ry * $X + $rx * $Y + $Z)
    $aw = 6378137.0; $fw = 1 / 298.257223563; $e2w = 2 * $fw - $fw * $fw
    $lonW = [Math]::Atan2($Y2, $X2)
    $pw = [Math]::Sqrt($X2 * $X2 + $Y2 * $Y2)
    $latW = [Math]::Atan2($Z2, $pw * (1 - $e2w))
    for ($i = 0; $i -lt 5; $i++) {
        $nw = $aw / [Math]::Sqrt(1 - $e2w * [Math]::Sin($latW) * [Math]::Sin($latW))
        $latW = [Math]::Atan2($Z2 + $e2w * $nw * [Math]::Sin($latW), $pw)
    }
    return @([Math]::Round($latW * 180 / [Math]::PI, 6), [Math]::Round($lonW * 180 / [Math]::PI, 6))
}

# 저장 폴더: 외국인_관광\YYYY-MM\YYYY-MM-DD\  (월별 폴더 안에 날짜 폴더)
function Get-DayDir([datetime]$d) {
    # 날짜 폴더 이름에 요일 포함: 2026-10-17_토
    $name = $d.ToString('yyyy-MM-dd') + '_' + $d.ToString('ddd', [Globalization.CultureInfo]::GetCultureInfo('ko-KR'))
    return Join-Path (Join-Path $OutRoot $d.ToString('yyyy-MM')) $name
}

function Get-Gu($addr) {
    if ($addr -match '서울특별시\s+(\S+구)') { return $Matches[1] }
    return ''
}

$ApiKey = Get-Content (Join-Path $Root 'config.txt') -Encoding UTF8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.Contains('=') } |
    Select-Object -First 1
if (-not $ApiKey) { Write-Log 'ERROR config.txt 에 API 키가 없습니다.'; exit 1 }

$hadError = $false

# ---------------------------------------------------------------- 1) 숙박 목록
if (-not $SkipLodging) {
    $dayDir = Get-DayDir $today
    New-Item -ItemType Directory -Force -Path $dayDir | Out-Null
    $kinds = @(
        @{ Svc = 'LOCALDATA_031101'; Name = '호텔' },
        @{ Svc = 'LOCALDATA_031104'; Name = '외국인민박' },
        @{ Svc = 'LOCALDATA_031103'; Name = '숙박업' }
    )
    foreach ($k in $kinds) {
        try {
            $svc = $k.Svc
            $first = Get-Json "http://openapi.seoul.go.kr:8088/$ApiKey/json/$svc/1/1/"
            $total = [int]$first.$svc.list_total_count
            $rowsRaw = New-Object System.Collections.Generic.List[object]
            for ($s = 1; $s -le $total; $s += 1000) {
                $page = Get-Json "http://openapi.seoul.go.kr:8088/$ApiKey/json/$svc/$s/$($s + 999)/"
                if ($page.$svc.RESULT.CODE -ne 'INFO-000') { throw "API 오류: $($page.$svc.RESULT.CODE)" }
                foreach ($r in $page.$svc.row) { $rowsRaw.Add($r) }
            }
            if ($rowsRaw.Count -ne $total) { throw "건수 불일치: 받은 $($rowsRaw.Count) / 전체 $total" }

            $rows = foreach ($r in $rowsRaw) {
                $tx = "$($r.X)".Trim(); $ty = "$($r.Y)".Trim()
                $lat = ''; $lng = ''
                $dx = 0.0; $dy = 0.0
                if ([double]::TryParse($tx, [ref]$dx) -and [double]::TryParse($ty, [ref]$dy) -and $dx -gt 0) {
                    $ll = Convert-TmToWgs84 $dx $dy; $lat = $ll[0]; $lng = $ll[1]
                }
                $road = "$($r.RDNWHLADDR)".Trim()
                $jibun = if ($r.PSObject.Properties['SITEWHLADDR']) { "$($r.SITEWHLADDR)".Trim() } else { "$($r.LOTNO_ADDR)".Trim() }
                $gu = Get-Gu $road; if (-not $gu) { $gu = Get-Gu $jibun }
                $o = [ordered]@{
                    '자치단체코드' = $r.OPNSFTEAMCODE   # 관리번호는 구마다 따로 매겨져 겹치므로 이 코드와 함께 써야 고유함
                    '관리번호'   = $r.MGTNO
                    '업소명'     = "$($r.BPLCNM)".Trim()
                    '영업상태'   = $r.TRDSTATENM
                    '상세영업상태' = $r.DTLSTATENM
                    '인허가일자' = "$($r.APVPERMYMD)".Trim()
                    '폐업일자'   = if ($r.PSObject.Properties['DCBYMD']) { "$($r.DCBYMD)".Trim() } else { '' }
                    '자치구'     = $gu
                    '도로명주소' = $road
                    '지번주소'   = $jibun
                }
                switch ($k.Name) {
                    '호텔' {
                        $o['숙박업종'] = $r.TRSTLODGCLNM
                        $o['영문명']   = "$($r.ENGSTNTRNMNM)".Trim()
                        $o['객실수']   = "$($r.STROOMCNT)".Trim()
                        $o['시설면적'] = "$($r.FACILAR)".Trim()
                    }
                    '외국인민박' {
                        $o['객실수']   = "$($r.STROOMCNT)".Trim()
                        $o['시설면적'] = "$($r.FACILAR)".Trim()
                    }
                    '숙박업' {
                        $o['업태']     = $r.SNTUPTAENM
                        $o['한실수']   = "$($r.HANSHILCNT)".Trim()
                        $o['양실수']   = "$($r.YANGSILCNT)".Trim()
                        $o['시설면적'] = "$($r.SITEAREA)".Trim()
                    }
                }
                $o['최종수정일시'] = $r.LASTMODTS
                $o['데이터갱신일시'] = $r.UPDATEDT
                $o['위도'] = $lat
                $o['경도'] = $lng
                $o['TM_X'] = $tx
                $o['TM_Y'] = $ty
                [pscustomobject]$o
            }
            $rows = @($rows | Sort-Object '자치단체코드', '관리번호')
            $open = @($rowsRaw | Where-Object { $_.TRDSTATEGBN -eq '01' }).Count
            $baseName = '숙박_' + $k.Name

            # 가장 최근에 "전체 목록"을 저장한 날짜 폴더(오늘 이전) 찾기
            $prevFile = Get-ChildItem $OutRoot -Directory |
                Where-Object { $_.Name -match '^\d{4}-\d{2}$' } |
                ForEach-Object { Get-ChildItem $_.FullName -Directory } |
                Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}(_.)?$' -and $_.Name.Substring(0, 10) -lt $today.ToString('yyyy-MM-dd') } |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName ($baseName + '.csv') } |
                Where-Object { Test-Path $_ } | Select-Object -First 1

            # 파일 전체를 한 문자열로 비교 (칸 안에 줄바꿈이 있는 업소가 있어 줄 단위 비교는 어긋남)
            $newText = (@($rows | ConvertTo-Csv -NoTypeInformation) -join "`n") -replace "`r`n", "`n"
            $same = $false
            if ($prevFile) {
                $oldText = ([System.IO.File]::ReadAllText($prevFile, [System.Text.Encoding]::UTF8) -replace "`r`n", "`n").TrimEnd("`n")
                $same = ($newText.TrimEnd("`n") -ceq $oldText)
            }

            # 오늘 폴더에 남아 있을 수 있는 이전 실행 결과 정리
            foreach ($old in @("$baseName.csv", "$baseName`_변경내역.csv", "$baseName`_변화없음.txt")) {
                $p = Join-Path $dayDir $old; if (Test-Path $p) { Remove-Item $p -Force }
            }

            if ($same) {
                # 변화 없음: 전체 목록은 다시 저장하지 않고, 이름에 "변화없음"이 붙은 작은 안내 파일만 남김
                $prevDate = Split-Path (Split-Path $prevFile -Parent) -Leaf
                $marker = Join-Path $dayDir ($baseName + '_변화없음.txt')
                $msg = "$($today.ToString('yyyy-MM-dd')) 확인 결과 $prevDate 목록과 같습니다 (전체 $($total)곳, 영업중 $($open)곳).`r`n" +
                       "최신 전체 목록: 외국인_관광\$($prevDate.Substring(0, 7))\$prevDate\$($baseName).csv"
                [System.IO.File]::WriteAllText($marker, $msg, (New-Object System.Text.UTF8Encoding($true)))
                Write-Log ("OK 숙박-{0} 변화없음 ({1} 목록과 같음) -> {2}" -f $k.Name, $prevDate, $marker)
            } else {
                $file = Join-Path $dayDir ($baseName + '.csv')
                $rows | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
                $note = '첫 저장'
                if ($prevFile) {
                    # 무엇이 바뀌었는지 변경내역 파일로 정리 (신규 / 삭제 / 변경)
                    $oldRows = @{}
                    foreach ($o in (Import-Csv $prevFile -Encoding UTF8)) { $oldRows["$($o.'자치단체코드')|$($o.'관리번호')"] = $o }
                    $props = $rows[0].PSObject.Properties.Name
                    $changes = New-Object System.Collections.Generic.List[object]
                    $seen = @{}
                    foreach ($n in $rows) {
                        $id = "$($n.'자치단체코드')|$($n.'관리번호')"; $seen[$id] = $true
                        $o = $oldRows[$id]
                        if (-not $o) {
                            $changes.Add([pscustomobject][ordered]@{ '구분'='신규'; '자치단체코드'=$n.'자치단체코드'; '관리번호'=$n.'관리번호'; '업소명'=$n.'업소명'; '자치구'=$n.'자치구'; '영업상태'=$n.'영업상태'; '바뀐항목'='' })
                            continue
                        }
                        $diff = @($props | Where-Object { "$($n.$_)" -cne "$($o.$_)" })
                        if ($diff.Count -gt 0) {
                            $detail = ($diff | ForEach-Object { "$_`: $($o.$_) -> $($n.$_)" }) -join ' / '
                            $changes.Add([pscustomobject][ordered]@{ '구분'='변경'; '자치단체코드'=$n.'자치단체코드'; '관리번호'=$n.'관리번호'; '업소명'=$n.'업소명'; '자치구'=$n.'자치구'; '영업상태'=$n.'영업상태'; '바뀐항목'=$detail })
                        }
                    }
                    foreach ($id in $oldRows.Keys) {
                        if (-not $seen[$id]) {
                            $o = $oldRows[$id]
                            $changes.Add([pscustomobject][ordered]@{ '구분'='삭제'; '자치단체코드'=$o.'자치단체코드'; '관리번호'=$o.'관리번호'; '업소명'=$o.'업소명'; '자치구'=$o.'자치구'; '영업상태'=$o.'영업상태'; '바뀐항목'='' })
                        }
                    }
                    $changes | Export-Csv -Path (Join-Path $dayDir ($baseName + '_변경내역.csv')) -NoTypeInformation -Encoding UTF8
                    $cnt = $changes | Group-Object '구분' | ForEach-Object { "$($_.Name) $($_.Count)" }
                    $note = "$((Split-Path (Split-Path $prevFile -Parent) -Leaf)) 대비 " + ($cnt -join ', ')
                }
                Write-Log ("OK 숙박-{0} 전체 {1}곳(영업중 {2}곳), {3} -> {4}" -f $k.Name, $total, $open, $note, $file)
            }
        } catch {
            $hadError = $true
            Write-Log "ERROR 숙박-$($k.Name) 저장 실패: $($_.Exception.Message)"
        }
    }
}

# ---------------------------------------------------------------- 2) 외국인 생활인구
if (-not $SkipPopulation) {
    $guNames = @{
        '11110'='종로구'; '11140'='중구'; '11170'='용산구'; '11200'='성동구'; '11215'='광진구'
        '11230'='동대문구'; '11260'='중랑구'; '11290'='성북구'; '11305'='강북구'; '11320'='도봉구'
        '11350'='노원구'; '11380'='은평구'; '11410'='서대문구'; '11440'='마포구'; '11470'='양천구'
        '11500'='강서구'; '11530'='구로구'; '11545'='금천구'; '11560'='영등포구'; '11590'='동작구'
        '11620'='관악구'; '11650'='서초구'; '11680'='강남구'; '11710'='송파구'; '11740'='강동구'
    }
    $natNames = [ordered]@{
        'SPOP'='생활인구합계'; 'CHN'='중국'; 'JPN'='일본'; 'USA'='미국'; 'THA'='태국'; 'VNM'='베트남'
        'PHL'='필리핀'; 'IDN'='인도네시아'; 'MNG'='몽골'; 'RUS'='러시아'; 'KAZ'='카자흐스탄'; 'UZB'='우즈베키스탄'
        'CAN'='캐나다'; 'FRA'='프랑스'; 'IND'='인도'; 'NPL'='네팔'; 'LKA'='스리랑카'; 'KHM'='캄보디아'
        'PAK'='파키스탄'; 'MMR'='미얀마'; 'BGD'='방글라데시'; 'ETC'='기타'
    }
    $types = @(
        @{ Svc = 'Spop250mFornTempJachi'; Name = '단기' },
        @{ Svc = 'Spop250mFornLongJachi'; Name = '장기' }
    )
    foreach ($t in $types) {
        $saved = 0; $missing = New-Object System.Collections.Generic.List[string]
        try {
            $start = New-Object DateTime($today.Year, 1, 1)
            for ($d = $start; $d -lt $today; $d = $d.AddDays(1)) {
                # 데이터 날짜의 폴더에 저장: 외국인_관광\YYYY-MM\YYYY-MM-DD\외국인생활인구_단기.csv
                $file = Join-Path (Get-DayDir $d) ('외국인생활인구_' + $t.Name + '.csv')
                if (Test-Path $file) { continue }
                $svc = $t.Svc
                $res = Get-Json "http://openapi.seoul.go.kr:8088/$ApiKey/json/$svc/1/1000/$($d.ToString('yyyyMMdd'))"
                if (-not $res.$svc) {
                    if ($res.RESULT.CODE -eq 'INFO-200') { $missing.Add($d.ToString('MM-dd')); continue }
                    throw "API 오류: $($res.RESULT.CODE) $($res.RESULT.MESSAGE)"
                }
                $rows = foreach ($r in ($res.$svc.row | Sort-Object TT, H_DNG_CD)) {
                    $o = [ordered]@{
                        '날짜'       = [datetime]::ParseExact($r.YMD, 'yyyyMMdd', $null).ToString('yyyy-MM-dd')
                        '시간'       = [int]$r.TT
                        '자치구코드' = $r.H_DNG_CD
                        '자치구'     = $guNames["$($r.H_DNG_CD)"]
                    }
                    foreach ($code in $natNames.Keys) {
                        if ($r.PSObject.Properties[$code]) {
                            $v = "$($r.$code)"
                            $o[$natNames[$code]] = if ($v -eq '*') { '' } else { $v }   # * = 소수라 비공개
                        }
                    }
                    [pscustomobject]$o
                }
                New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent) | Out-Null
                $rows | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
                $saved++
            }
            $note = if ($missing.Count -gt 0) {
                $show = @($missing | Select-Object -Last 5) -join ','
                " (아직 제공 안 된 날짜 $($missing.Count)일, 최근: $show)"
            } else { '' }
            Write-Log ("OK 외국인생활인구-{0} 새로 저장 {1}일{2}" -f $t.Name, $saved, $note)
        } catch {
            $hadError = $true
            Write-Log ("ERROR 외국인생활인구-$($t.Name) 실패 (저장 $saved" + "일 후): " + $_.Exception.Message)
        }
    }
}

if ($hadError) { exit 1 }
