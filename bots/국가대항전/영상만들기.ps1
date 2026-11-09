# 서울 외국인 국가대항전 쇼츠 — 집계.py가 만든 지표.json을 읽어 음성·애니메이션·영상·썸네일 자동 생성
# 사용: powershell -ExecutionPolicy Bypass -File .\영상만들기.ps1 -Tag 261105
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Out   = '',
    [string]$Work  = (Join-Path $env:TEMP 'shorts_nation'),
    [string]$Voice = 'ko-KR-HyunsuMultilingualNeural',
    [string]$Rate = '+15%',
    [int]$Fps = 30
)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Out) { $Out = Join-Path $Here '리포트' }
$env:Path = $env:Path + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Add-Type -AssemblyName System.Drawing, System.Speech
Add-Type -TypeDefinition (Get-Content (Join-Path $Here 'renderer.cs') -Raw -Encoding UTF8) -ReferencedAssemblies System.Drawing

# ── 데이터: 집계.py 결과 ──
$J = Get-Content (Join-Path $Out "${Tag}_지표.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$S = $J.쇼츠
$top = @($J.TOP5)
[Shorts]::Name = [string[]]($top | ForEach-Object { $_.국적 })
[Shorts]::A = [double[]]($top | ForEach-Object { $_.지난주 })
[Shorts]::Bv = [double[]]($top | ForEach-Object { $_.이번주 })
[Shorts]::Badge = [string[]]$S.배지
[Shorts]::CardSub = [string[]]$S.카드설명
[Shorts]::LabelA = '지난주 하루 평균'; [Shorts]::LabelB = '이번 주 하루 평균'
[Shorts]::CoverTitle = [string[]]$S.표지; [Shorts]::CoverHi = $S.표지강조
[Shorts]::CoverPre = $S.표지윗줄; [Shorts]::CoverBig = $S.표지큰글씨
[Shorts]::CoverHint = ('{0} vs {1}, 누가 1위?' -f $top[0].국적, $top[1].국적)
[Shorts]::SummaryTitle = $S.요약제목
[Shorts]::OutroBig = '다음 주 1위는?'; [Shorts]::OutroSmall = '예상은 댓글로!'
[Shorts]::Source = $S.출처
[Shorts]::FlagDir = Join-Path $Here '국기'

# ── 대본 ──
$script = foreach ($k in 'cover', 'r5', 'r4', 'r3', 'r2', 'r1', 'summary') { @{ Kind = $k; Lines = [string[]]$S.대본.$k } }

# ── 음성 ──
Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
$frames = Join-Path $Work 'frames'; New-Item -ItemType Directory -Force $frames | Out-Null
# 자연스러운 신경망 음성 (edge-tts). 실패하면 Windows 기본 음성으로 대신 만든다.
$all = @(); foreach ($s in $script) { $all += $s.Lines }
$linesJson = Join-Path $Work 'lines.json'
ConvertTo-Json @($all) | Set-Content $linesJson -Encoding UTF8
$py = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
if (-not (Test-Path $py)) { $py = 'python' }   # GitHub 서버 등 다른 컴퓨터
& $py -X utf8 (Join-Path $Here 'tts.py') $linesJson $Work $Voice $Rate
$ext = 'mp3'
if ($LASTEXITCODE -ne 0) {
    Write-Host '신경망 음성 실패 → Windows 기본 음성으로 대신 만듭니다'
    $syn = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $syn.SelectVoice('Microsoft Heami Desktop'); $syn.Rate = 3
    for ($k = 0; $k -lt $all.Count; $k++) { $syn.SetOutputToWaveFile((Join-Path $Work ('v{0:D2}.wav' -f $k))); $syn.Speak($all[$k]); $syn.SetOutputToNull() }
    $syn.Dispose(); $ext = 'wav'
}
$clips = @()
for ($k = 0; $k -lt $all.Count; $k++) {
    $wav = Join-Path $Work ('v{0:D2}.{1}' -f $k, $ext)
    $dur = [double](& ffprobe -v error -show_entries format=duration -of csv=p=0 $wav)
    $clips += @{ Wav = $wav; Dur = $dur; Text = $all[$k] }
}

# ── 시간표 (두 번째 문장 시작 = 장면의 Mark) ──
$scenes = New-Object System.Collections.Generic.List[Scene]
$subs = New-Object System.Collections.Generic.List[Sub]
$t = 0.0; $ci = 0; $placed = @()
foreach ($s in $script) {
    $start = $t; $t += 0.25; $mark = 0.0
    for ($k = 0; $k -lt $s.Lines.Count; $k++) {
        $c = $clips[$ci]; $ci++
        if ($k -eq 1) { $mark = $t - $start }
        $subs.Add((New-Object Sub($t, ($t + $c.Dur), $c.Text)))
        $placed += @{ Wav = $c.Wav; At = $t }
        $t += $c.Dur + 0.1
    }
    if ($s.Lines.Count -eq 1) { $mark = $t - $start }
    if ($s.Kind -like 'r*' -and ($t - $start) -lt 3.2) { $t = $start + 3.2 }   # 막대 애니메이션이 끝날 시간 확보
    $t += $(if ($s.Kind -eq 'summary') { 1.5 } else { 0.25 })
    $scenes.Add((New-Object Scene($s.Kind, $start, $t, $mark)))
}
$totalDur = $t
Write-Host ('길이 {0:N1}초, 장면 {1}개' -f $totalDur, $scenes.Count)

# ── 프레임 ──
[void][Shorts]::Render($frames, $Fps, $scenes.ToArray(), $subs.ToArray(), $totalDur)

# ── 음성 합치기 + 영상 ──
$ffArgs = @('-y', '-v', 'error')
foreach ($p in $placed) { $ffArgs += @('-i', $p.Wav) }
$filter = ''; $j = 0
foreach ($p in $placed) { $ms = [int]($p.At * 1000); $filter += "[$j]aresample=48000,adelay=${ms}:all=1[a$j];"; $j++ }
$filter += (0..($placed.Count - 1) | ForEach-Object { "[a$_]" }) -join ''
$filter += "amix=inputs=$($placed.Count):normalize=0,apad,atrim=0:$totalDur[out]"
$audio = Join-Path $Work 'voice.wav'
& ffmpeg @ffArgs -filter_complex $filter -map '[out]' $audio

$mp4 = Join-Path $Out "${Tag}_쇼츠.mp4"
& ffmpeg -y -v error -framerate $Fps -i (Join-Path $frames 'f_%05d.png') -i $audio `
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k -shortest -movflags +faststart $mp4
Copy-Item (Join-Path $frames 'f_00000.png') (Join-Path $Out "${Tag}_썸네일.png") -Force
Write-Host "완성: $mp4"
