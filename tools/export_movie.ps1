param(
    [Parameter(Mandatory=$true)][string]$GodotExe,
    [Parameter(Mandatory=$true)][string]$ProjectDir,
    [Parameter(Mandatory=$true)][string]$ReplayPath,
    [Parameter(Mandatory=$true)][string]$RawAvi,
    [Parameter(Mandatory=$true)][string]$Mp4Path,
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"

# Prefer godot_console.exe if sibling exists so Movie Maker runs cleanly without extra splash noise
$consoleCandidate = Join-Path (Split-Path $GodotExe -Parent) "godot_console.exe"
$runner = if (Test-Path $consoleCandidate) { $consoleCandidate } else { $GodotExe }

$godotArgs = @(
    "--path", $ProjectDir,
    "--minimized",
    "--log-file", "$Mp4Path.render.log",
    "--write-movie", $RawAvi,
    "--fixed-fps", "60",
    "-s", "tools/render_replay.gd",
    "--",
    "--replay=$ReplayPath"
)

& $runner @godotArgs | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $RawAvi)) {
    throw "Movie render failed: $RawAvi not created."
}

$tmpMp4 = "$Mp4Path.tmp.mp4"
$ffmpegArgs = @(
    "-y", "-v", "error",
    "-i", $RawAvi,
    "-c:v", "libx264",
    "-preset", "medium",
    "-crf", "18",
    "-pix_fmt", "yuv420p",
    "-c:a", "aac",
    "-b:a", "192k",
    "-movflags", "+faststart",
    $tmpMp4
)

$encoder = Get-Command ffmpeg -ErrorAction SilentlyContinue
$encoderPath = if ($encoder) { $encoder.Source } else { Join-Path $env:LOCALAPPDATA "Microsoft/WinGet/Links/ffmpeg.exe" }
if (-not (Test-Path -LiteralPath $encoderPath)) { throw "FFmpeg is required to export MP4." }
& $encoderPath @ffmpegArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpMp4)) {
    throw "ffmpeg transcode failed."
}

Move-Item -Force $tmpMp4 $Mp4Path
Remove-Item -Force $RawAvi -ErrorAction SilentlyContinue
if (-not $NoOpen) {
    explorer.exe (Split-Path $Mp4Path -Parent)
}
