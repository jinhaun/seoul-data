param([string]$Only = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$H = $env:USERPROFILE
$Desk = Join-Path $H 'Desktop'
$Out = Join-Path $Desk '가져갈것'
New-Item -ItemType Directory -Force $Out | Out-Null
$Log = Join-Path $Out '_작업기록.txt'

$SkipDirs = @('node_modules', '.pnpm-store', '.next', '.venv', 'venv', '__pycache__')
$Stored = @('.zip', '.gz', '.png', '.jpg', '.jpeg', '.webp', '.gif', '.mp4', '.mp3', '.pdf', '.twbx', '.xlsx', '.pptx', '.docx', '.7z', '.woff', '.woff2')

function Say($m) { $line = "{0:HH:mm:ss} {1}" -f (Get-Date), $m; Add-Content -Path $Log -Value $line -Encoding UTF8; Write-Host $line }

function Walk($dir, $skipNames) {
  try { $items = [IO.Directory]::GetFileSystemEntries($dir) } catch { Say "  읽기 실패(폴더): $dir"; return }
  foreach ($p in $items) {
    $name = [IO.Path]::GetFileName($p)
    try { $attr = [IO.File]::GetAttributes($p) } catch { Say "  읽기 실패: $p"; continue }
    if ($attr -band [IO.FileAttributes]::Directory) {
      if ($SkipDirs -contains $name -or $skipNames -contains $name) { continue }
      if ($attr -band [IO.FileAttributes]::ReparsePoint) { Say "  바로가기 폴더 건너뜀: $p"; continue }
      Walk $p $skipNames
    } else {
      $p
    }
  }
}

# $sources: list of @{ Path=...; Prefix=...; Skip=@(...); SkipExt=@(...) }
function Pack($zipName, $sources) {
  if ($Only -and $zipName -notlike "*$Only*") { return }
  $zipPath = Join-Path $Out $zipName
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Say "시작: $zipName"
  $fs = [IO.File]::Open($zipPath, 'CreateNew')
  $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create, $false, [Text.Encoding]::UTF8)
  $n = 0; $bytes = 0; $fail = 0
  try {
    foreach ($s in $sources) {
      $root = $s.Path
      if (-not (Test-Path -LiteralPath $root)) { Say "  없음: $root"; continue }
      $skip = @(); if ($s.Skip) { $skip = $s.Skip }
      $skipExt = @(); if ($s.SkipExt) { $skipExt = $s.SkipExt }
      $isDir = (Get-Item -LiteralPath $root -Force).PSIsContainer
      $root = '\\?\' + $root
      if ($isDir) {
        $files = Walk $root $skip
        $base = $root.TrimEnd('\') + '\'
      } else {
        $files = @($root)
        $base = (Split-Path $root -Parent).TrimEnd('\') + '\'
      }
      foreach ($f in $files) {
        $ext = [IO.Path]::GetExtension($f).ToLower()
        if ($skipExt -contains $ext) { continue }
        if ($s.SkipFiles -and ($s.SkipFiles -contains [IO.Path]::GetFileName($f))) { continue }
        $rel = $f.Substring($base.Length).Replace('\', '/')
        $entryName = if ($s.Prefix) { $s.Prefix.TrimEnd('/') + '/' + $rel } else { $rel }
        $level = if ($Stored -contains $ext) { [IO.Compression.CompressionLevel]::NoCompression } else { [IO.Compression.CompressionLevel]::Optimal }
        try {
          $src = New-Object IO.FileStream($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
          try {
            $e = $zip.CreateEntry($entryName, $level)
            $t = [IO.File]::GetLastWriteTime($f)
            if ($t.Year -ge 1980 -and $t.Year -le 2107) { $e.LastWriteTime = $t }
            $dst = $e.Open(); try { $src.CopyTo($dst) } finally { $dst.Dispose() }
            $n++; $bytes += $src.Length
          } finally { $src.Dispose() }
        } catch { $fail++; Say "  복사 실패: $f ($($_.Exception.Message))" }
      }
    }
  } finally { $zip.Dispose(); $fs.Dispose() }
  $zsize = (Get-Item $zipPath).Length
  Say ("끝: {0} — 파일 {1}개, 원래 {2:N0}MB → 압축 {3:N0}MB, 실패 {4}개" -f $zipName, $n, ($bytes / 1MB), ($zsize / 1MB), $fail)
}

Say "===== 모으기 시작 ====="

# 1. 바탕화면 폴더 (하나씩)
# 깃허브에 다 있는 사이트(멀리건 랩, 파이트 다이어리, 나다운하루)는 폴더째 빼고, 깃허브에 없는 비밀키·백업만 따로 담음
$OnGitHub = @('가져갈것', 'mulligan-lab', 'vanguard-play-log')
foreach ($d in Get-ChildItem $Desk -Directory -Force | Where-Object { $OnGitHub -notcontains $_.Name }) {
  $skip = @(); if ($d.Name -eq 'agentic-ai-fundamentals') { $skip = @('unharu') }
  Pack ("바탕화면_" + $d.Name + ".zip") @(@{ Path = $d.FullName; Prefix = $d.Name; Skip = $skip })
}
Pack '사이트_비밀키와_백업.zip' @(
  @{ Path = (Join-Path $Desk 'mulligan-lab\.env.local'); Prefix = 'mulligan-lab' },
  @{ Path = (Join-Path $Desk 'mulligan-lab\data'); Prefix = 'mulligan-lab/data' },
  @{ Path = (Join-Path $Desk 'vanguard-play-log\.env.local'); Prefix = 'vanguard-play-log' },
  @{ Path = (Join-Path $Desk 'vanguard-play-log\data'); Prefix = 'vanguard-play-log/data' }
)

# 2. 바탕화면 낱개 파일
$loose = Get-ChildItem $Desk -File -Force | Where-Object { @('.lnk', '.exe', '.msi') -notcontains $_.Extension.ToLower() -and $_.Name -ne 'desktop.ini' }
Pack '바탕화면_낱개파일.zip' @($loose | ForEach-Object { @{ Path = $_.FullName } })

# 3. 문서
$Doc = Join-Path $H 'Documents'
Pack '문서_태블로.zip' @(
  @{ Path = (Join-Path $Doc '내 Tableau 리포지토리'); Prefix = '내 Tableau 리포지토리'; Skip = @('로그') },
  @{ Path = (Join-Path $Doc '내 Tableau Prep 리포지토리'); Prefix = '내 Tableau Prep 리포지토리'; Skip = @('로그') }
)
Pack '문서_ChatGPT.zip' @(@{ Path = (Join-Path $Doc 'ChatGPT'); Prefix = 'ChatGPT'; Skip = @('New project') })
Pack '문서_Codex.zip' @(@{ Path = (Join-Path $Doc 'Codex'); Prefix = 'Codex' })

# 4. 다운로드 (설치 파일 제외)
Pack '다운로드.zip' @(@{ Path = (Join-Path $H 'Downloads'); Prefix = 'Downloads'; SkipExt = @('.exe', '.msix', '.winmd'); SkipFiles = @('desktop.ini') })

# 5. 사진
Pack '사진_스크린샷.zip' @(@{ Path = (Join-Path $H 'Pictures'); Prefix = 'Pictures'; SkipFiles = @('desktop.ini') })

# 6. 하네스 (클로드)
Pack '하네스_클로드.zip' @(
  @{ Path = (Join-Path $H '.claude'); Prefix = '.claude'; Skip = @('cache', 'telemetry', 'session-env', 'shell-snapshots', 'downloads', 'ide', 'sessions'); SkipFiles = @('.credentials.json') },
  @{ Path = (Join-Path $H '.claude.json') },
  @{ Path = (Join-Path $H '.agents'); Prefix = '.agents' }
)

# 7. 하네스 (코덱스)
$Cx = Join-Path $H '.codex'
Pack '하네스_코덱스_설정.zip' @(
  @{ Path = (Join-Path $Cx 'AGENTS.md') },
  @{ Path = (Join-Path $Cx 'config.toml') },
  @{ Path = (Join-Path $Cx 'memories_1.sqlite') },
  @{ Path = (Join-Path $Cx 'skills'); Prefix = 'skills' },
  @{ Path = (Join-Path $Cx 'rules'); Prefix = 'rules' },
  @{ Path = (Join-Path $Cx 'automations'); Prefix = 'automations' },
  @{ Path = (Join-Path $Cx 'generated_images'); Prefix = 'generated_images' },
  @{ Path = (Join-Path $Cx 'visualizations'); Prefix = 'visualizations' }
)
Pack '하네스_코덱스_대화기록.zip' @(
  @{ Path = (Join-Path $Cx 'sessions'); Prefix = 'sessions' },
  @{ Path = (Join-Path $Cx 'archived_sessions'); Prefix = 'archived_sessions' },
  @{ Path = (Join-Path $Cx 'session_index.jsonl') }
)

$total = (Get-ChildItem $Out -Filter *.zip | Measure-Object Length -Sum).Sum
Say ("===== 모두 끝: 압축 파일 합계 {0:N2}GB =====" -f ($total / 1GB))
