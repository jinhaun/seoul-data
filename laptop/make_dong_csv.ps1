# 행정동(서울 약 425개) 단위로 "외국인이 얼마나 있나"와 "그 동에 무엇이 있나"를 한 표로 만듭니다.
# 원본:
#   외국인_공공데이터\생활인구_행정동별_단기외국인\*.csv   (행정동 x 시간, 국적별 단기체류 외국인, 2026-05~)
#   외국인_공공데이터\행정동_경계_서울.geojson             (행정동 경계 -> 위도·경도로 어느 동인지 판정)
#   외국인_관광\합본\숙박_호텔_최신.csv, 숙박_외국인민박_최신.csv, 숙박_숙박업_최신.csv  (영업 중인 곳만)
#   태블로_외국인분석\관광지_목록.csv                       (관광 명소, 위도·경도)
# 결과: 동별_분석\
#   동별_시설.csv          : 동 하나 = 한 줄. 숙박·관광지 개수, 동 중심 위도·경도
#   동별_국적별_외국인.csv : 동 x 국적 = 한 줄. 하루 평균 인원, 비중, 특화지수 + 그 동의 시설 개수 (Tableau에서 이 파일 하나로 대시보드 가능)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out  = Join-Path $Root '동별_분석'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Inv  = [Globalization.CultureInfo]::InvariantCulture

# ---------- 점이 어느 행정동 안에 있는지 판정 (빠르게 하려고 C#으로) ----------
Add-Type -TypeDefinition @'
using System.Collections.Generic;
public class DongIndex {
    class Poly { public double[][] Xs; public double[][] Ys; public double MinX, MinY, MaxX, MaxY; public string Code; }
    List<Poly> polys = new List<Poly>();
    public void Add(string code, double[][] xs, double[][] ys) {
        var p = new Poly { Code = code, Xs = xs, Ys = ys, MinX = 999, MinY = 999, MaxX = -999, MaxY = -999 };
        for (int i = 0; i < xs[0].Length; i++) {
            if (xs[0][i] < p.MinX) p.MinX = xs[0][i]; if (xs[0][i] > p.MaxX) p.MaxX = xs[0][i];
            if (ys[0][i] < p.MinY) p.MinY = ys[0][i]; if (ys[0][i] > p.MaxY) p.MaxY = ys[0][i];
        }
        polys.Add(p);
    }
    static bool InRing(double[] xs, double[] ys, double x, double y) {
        bool c = false;
        for (int i = 0, j = xs.Length - 1; i < xs.Length; j = i++)
            if (((ys[i] > y) != (ys[j] > y)) && (x < (xs[j] - xs[i]) * (y - ys[i]) / (ys[j] - ys[i]) + xs[i])) c = !c;
        return c;
    }
    public string Find(double x, double y) {
        foreach (var p in polys) {
            if (x < p.MinX || x > p.MaxX || y < p.MinY || y > p.MaxY) continue;
            if (!InRing(p.Xs[0], p.Ys[0], x, y)) continue;
            bool hole = false;
            for (int r = 1; r < p.Xs.Length; r++) if (InRing(p.Xs[r], p.Ys[r], x, y)) { hole = true; break; }
            if (!hole) return p.Code;
        }
        return null;
    }
}
'@

$geo = Get-Content (Join-Path $Root '외국인_공공데이터\행정동_경계_서울.geojson') -Raw -Encoding UTF8 | ConvertFrom-Json
$idx = New-Object DongIndex
$dong = [ordered]@{}   # 행정동코드(8자리) -> 정보
foreach ($f in $geo.features) {
    $code = $f.properties.adm_cd2.Substring(0, 8)
    $parts = $f.properties.adm_nm.Split(' ')
    $sx = 0.0; $sy = 0.0; $sn = 0
    $polys = $f.geometry.coordinates                                   # if 식으로 받으면 PowerShell이 배열을 한 겹 풀어 버림
    if ($f.geometry.type -eq 'Polygon') { $polys = ,$polys }
    foreach ($poly in $polys) {
        $xs = New-Object 'double[][]' $poly.Count; $ys = New-Object 'double[][]' $poly.Count
        for ($r = 0; $r -lt $poly.Count; $r++) {
            $ring = $poly[$r]
            $xs[$r] = [double[]]@($ring | ForEach-Object { [double]$_[0] })
            $ys[$r] = [double[]]@($ring | ForEach-Object { [double]$_[1] })
        }
        $idx.Add($code, $xs, $ys)
        foreach ($v in $xs[0]) { $sx += $v }; foreach ($v in $ys[0]) { $sy += $v }; $sn += $xs[0].Count
    }
    $dong[$code] = [ordered]@{
        '행정동코드' = $code; '자치구' = $parts[1]; '행정동' = $parts[2]
        '위도' = [Math]::Round($sy / $sn, 6); '경도' = [Math]::Round($sx / $sn, 6)
        '호텔_수' = 0; '호텔_객실수' = 0; '외국인민박_수' = 0; '외국인민박_객실수' = 0; '일반숙박_수' = 0
        '명소_수' = 0
    }
}

function Num($s) { $d = 0.0; if ([double]::TryParse("$s", [Globalization.NumberStyles]::Float, $Inv, [ref]$d)) { $d } else { $null } }
$miss = @{}
function Put($lat, $lon, $what, $rooms, $roomCol) {
    $y = Num $lat; $x = Num $lon
    if ($null -eq $x -or $null -eq $y) { $miss[$what] = [int]$miss[$what] + 1; return }
    $c = $idx.Find($x, $y)
    if (-not $c) { $miss[$what] = [int]$miss[$what] + 1; return }
    $dong[$c][$what] += 1
    if ($roomCol) { $r = Num $rooms; if ($r) { $dong[$c][$roomCol] += $r } }
}

# ---------- 숙박 (영업 중인 곳만) ----------
$lodge = @(
    @('숙박_호텔_최신.csv', '호텔_수', '호텔_객실수'),
    @('숙박_외국인민박_최신.csv', '외국인민박_수', '외국인민박_객실수'),
    @('숙박_숙박업_최신.csv', '일반숙박_수', $null)
)
foreach ($l in $lodge) {
    foreach ($r in (Import-Csv (Join-Path $Root "외국인_관광\합본\$($l[0])") -Encoding UTF8)) {
        if ($r.'영업상태' -notlike '영업*') { continue }
        Put $r.'위도' $r.'경도' $l[1] $r.'객실수' $l[2]
    }
}

# ---------- 관광 명소 (쇼핑·음식점은 위도·경도가 없어 동 단위는 생략, 구 단위는 자치구_정보.csv 참고) ----------
foreach ($r in (Import-Csv (Join-Path $Root '태블로_외국인분석\관광지_목록.csv') -Encoding UTF8)) {
    if ($r.'종류' -ne '명소') { continue }
    Put $r.'위도' $r.'경도' '명소_수' $null $null
}

$facility = foreach ($d in $dong.Values) { [pscustomobject]$d }
$facility | Export-Csv (Join-Path $Out '동별_시설.csv') -NoTypeInformation -Encoding UTF8

# ---------- 행정동 x 국적 외국인 (하루 평균) ----------
$natCols = [ordered]@{ 'SPOP' = '전체'; 'CHN' = '중국'; 'USA' = '미국'; 'JPN' = '일본'; 'THA' = '태국'; 'IDN' = '인도네시아'; 'FRA' = '프랑스'; 'CAN' = '캐나다' }
$sum = @{}; $days = @{}
foreach ($file in Get-ChildItem (Join-Path $Root '외국인_공공데이터\생활인구_행정동별_단기외국인') -Filter '*.csv' | Sort-Object Name) {
    $hdr = $null; $pos = @{}
    foreach ($line in [IO.File]::ReadLines($file.FullName, [Text.Encoding]::UTF8)) {
        $f = $line.Replace('"', '').Split(',')
        if (-not $hdr) { $hdr = $f; for ($i = 0; $i -lt $f.Count; $i++) { $pos[$f[$i].Trim([char]0xFEFF)] = $i }; continue }
        $days[$f[$pos['YMD']]] = 1
        $c = $f[$pos['H_DNG_CD']]
        foreach ($k in $natCols.Keys) {
            $v = $f[$pos[$k]]
            if ($v -and $v -ne '*') { $key = "$c|$k"; $sum[$key] = [double]$sum[$key] + [double]::Parse($v, $Inv) }   # * (인원 적어 비공개) = 0
        }
    }
}
$nDays = $days.Count
$period = "$(($days.Keys | Sort-Object)[0]) ~ $(($days.Keys | Sort-Object)[-1])"

$codes = @($dong.Keys)
$allTot = 0.0; foreach ($c in $codes) { $allTot += [double]$sum["$c|SPOP"] }
$rows = foreach ($k in $natCols.Keys) {
    $natTot = 0.0; foreach ($c in $codes) { $natTot += [double]$sum["$c|$k"] }
    foreach ($c in $codes) {
        $avg = [double]$sum["$c|$k"] / 24 / $nDays
        $share = if ($natTot) { [double]$sum["$c|$k"] / $natTot * 100 } else { 0 }
        $base  = if ($allTot) { [double]$sum["$c|SPOP"] / $allTot * 100 } else { 0 }
        $o = [ordered]@{ '국적' = $natCols[$k] }
        foreach ($p in $dong[$c].GetEnumerator()) { if ($p.Key -in '행정동코드', '자치구', '행정동') { $o[$p.Key] = $p.Value } }
        $o['하루평균인원'] = [Math]::Round($avg, 1)
        $o['국적내비중'] = [Math]::Round($share, 3)
        $o['특화지수'] = $(if ($base -and $k -ne 'SPOP') { [Math]::Round($share / $base, 2) } elseif ($k -eq 'SPOP') { 1 } else { '' })
        $o['동내_국적비율'] = $(if ($sum["$c|SPOP"]) { [Math]::Round([double]$sum["$c|$k"] / [double]$sum["$c|SPOP"] * 100, 1) } else { '' })
        foreach ($p in $dong[$c].GetEnumerator()) { if ($p.Key -notin '행정동코드', '자치구', '행정동') { $o[$p.Key] = $p.Value } }
        [pscustomobject]$o
    }
}
$rows | Export-Csv (Join-Path $Out '동별_국적별_외국인.csv') -NoTypeInformation -Encoding UTF8

$noData = @($codes | Where-Object { -not $sum.ContainsKey("$_|SPOP") }).Count
$readme = @(
    "동별 분석 데이터 (만든 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm')))",
    "외국인 기간: $period ($nDays 일), 행정동 $($codes.Count)개 (외국인 데이터 없는 동 $noData 개)",
    '',
    '동별_국적별_외국인.csv : 한 줄 = 행정동 하나 x 국적 하나 (전체·중국·미국·일본·태국·인도네시아·프랑스·캐나다).',
    '  하루평균인원  = 그 기간 하루 평균, 그 동에 머문 단기체류 외국인 수 (같은 사람이 여러 날 머물면 매일 잡힘)',
    '  국적내비중    = 그 나라 사람 중 몇 %가 이 동에 있었나',
    '  특화지수      = 국적내비중 / (전체 외국인 중 이 동 비율). 1보다 크면 그 나라 사람이 이 동에 더 몰림',
    '  동내_국적비율 = 이 동에 있는 단기 외국인 중 그 나라 사람이 몇 %인가 (예: 대림2동 중국 87%)',
    '  나머지 열(호텔_수 등)은 동별_시설.csv 와 같은 값을 붙여 둔 것입니다. 국적 필터를 걸고 쓰세요.',
    '동별_시설.csv : 한 줄 = 행정동 하나. 위도·경도는 동 경계의 대략적인 중심입니다.',
    '  호텔·외국인민박·일반숙박(모텔·여관 등)은 영업 중인 곳만 셌습니다. 명소는 서울 관광 누리집(visitseoul) 목록 기준. 쇼핑·음식점은 위치 좌표가 없어 동 단위에는 없습니다(구 단위는 해커톤_데이터 참고).',
    "  위치로 동을 찾지 못한 곳: $(($miss.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', ')",
    '하루평균인원을 여러 동·국적에서 합칠 때: 동끼리는 더해도 되고(SUM), 같은 동의 여러 기간을 합칠 때는 평균(AVG).',
    '다시 만들기: 프로젝트 폴더의 make_dong_csv.ps1 실행'
)
[IO.File]::WriteAllLines((Join-Path $Out '읽어주세요.txt'), $readme, (New-Object Text.UTF8Encoding($true)))
"OK 행정동 $($codes.Count)개, 외국인 $nDays 일 ($period), 매칭 실패: $(($miss.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', ') -> $Out"
