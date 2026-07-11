<#
.SYNOPSIS
  Generate a video via mid-relay OpenAI/xAI-compatible /videos/generations (async poll).

.EXAMPLE
  .\gen-video.ps1 -Prompt "cat at sunset, soft fur motion" -Duration 6 -OutDir videos -Name sunset-cat -Open -Json

.EXAMPLE
  .\gen-video.ps1 -Prompt "gentle breeze on fur" -ImagePath .\images\sunset-cat.jpg -Duration 6 -Json
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Prompt,

  [string]$OutDir = "",
  [string]$Name = "",
  [string]$Model = "",
  [string]$BaseUrl = "",
  [string]$ApiKey = "",
  [int]$Duration = 6,
  [string]$AspectRatio = "16:9",
  [string]$Resolution = "480p",
  [string]$ImagePath = "",
  [string]$ImageUrl = "",
  [int]$PollSeconds = 5,
  [int]$MaxPolls = 60,
  [int]$TimeoutSec = 120,
  [switch]$Json,
  [switch]$Open
)

$ErrorActionPreference = "Stop"

function Get-EnvFirst([string[]]$Names) {
  foreach ($n in $Names) {
    $v = [Environment]::GetEnvironmentVariable($n)
    if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
  }
  return $null
}

function Get-Slug([string]$Text) {
  $s = $Text.ToLowerInvariant()
  $s = [regex]::Replace($s, "[^a-z0-9]+", "-")
  $s = $s.Trim("-")
  if ([string]::IsNullOrWhiteSpace($s)) { $s = "video" }
  if ($s.Length -gt 48) { $s = $s.Substring(0, 48).TrimEnd("-") }
  return $s
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = Get-EnvFirst @(
    "GROK_VIDEO_BASE_URL", "GROK_IMAGEN_BASE_URL",
    "PROXY_IMAGEN_BASE_URL", "ANTHROPIC_BASE_URL"
  )
  if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = "https://codexone.aieania.tech"
  }
}
$BaseUrl = $BaseUrl.TrimEnd("/")
$apiRoot = if ($BaseUrl.EndsWith("/v1")) { $BaseUrl } else { "$BaseUrl/v1" }
$createUrl = "$apiRoot/videos/generations"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $ApiKey = Get-EnvFirst @(
    "GROK_VIDEO_API_KEY", "GROK_IMAGEN_API_KEY", "PROXY_IMAGEN_API_KEY",
    "GROK_API_KEY", "THIRD_PARTY_API_KEY", "XAI_API_KEY"
  )
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw "No API key. Set GROK_API_KEY (or GROK_VIDEO_API_KEY)."
}

if ([string]::IsNullOrWhiteSpace($Model)) {
  $Model = Get-EnvFirst @("GROK_VIDEO_MODEL", "PROXY_VIDEO_MODEL")
  if ([string]::IsNullOrWhiteSpace($Model)) { $Model = "grok-imagine-video" }
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Get-EnvFirst @("GROK_VIDEO_OUT_DIR", "PROXY_VIDEO_OUT_DIR")
  if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = (Join-Path (Get-Location) "videos") }
}
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ([string]::IsNullOrWhiteSpace($Name)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $Name = "$(Get-Slug $Prompt)-$stamp"
} else {
  $Name = Get-Slug $Name
}

# Optional still image for image-to-video
if (-not [string]::IsNullOrWhiteSpace($ImagePath) -and [string]::IsNullOrWhiteSpace($ImageUrl)) {
  $ImagePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ImagePath)
  if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "ImagePath not found: $ImagePath"
  }
  $bytes = [IO.File]::ReadAllBytes($ImagePath)
  $b64 = [Convert]::ToBase64String($bytes)
  $ext = [IO.Path]::GetExtension($ImagePath).ToLowerInvariant()
  $mime = switch ($ext) {
    ".png" { "image/png" }
    ".webp" { "image/webp" }
    ".gif" { "image/gif" }
    default { "image/jpeg" }
  }
  $ImageUrl = "data:$mime;base64,$b64"
}

$bodyObj = [ordered]@{
  model    = $Model
  prompt   = $Prompt
  duration = $Duration
}
if (-not [string]::IsNullOrWhiteSpace($AspectRatio)) { $bodyObj.aspect_ratio = $AspectRatio }
if (-not [string]::IsNullOrWhiteSpace($Resolution)) { $bodyObj.resolution = $Resolution }
if (-not [string]::IsNullOrWhiteSpace($ImageUrl)) {
  $bodyObj.image = @{ url = $ImageUrl }
}

$bodyJson = $bodyObj | ConvertTo-Json -Depth 6 -Compress
$headers = @{
  Authorization  = "Bearer $ApiKey"
  "Content-Type" = "application/json; charset=utf-8"
}

try {
  $create = Invoke-RestMethod -Uri $createUrl -Method Post -Headers $headers `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec $TimeoutSec
} catch {
  $msg = $_.Exception.Message
  if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = "$msg | $($_.ErrorDetails.Message)" }
  throw "Video create failed: $msg"
}

$rid = $create.request_id
if ([string]::IsNullOrWhiteSpace($rid)) {
  throw "No request_id in create response: $($create | ConvertTo-Json -Depth 6 -Compress)"
}

$pollUrl = "$apiRoot/videos/$rid"
$status = $null
$videoUrl = $null
$finalDuration = $null

for ($i = 1; $i -le $MaxPolls; $i++) {
  Start-Sleep -Seconds $PollSeconds
  try {
    $st = Invoke-RestMethod -Uri $pollUrl -Headers @{ Authorization = "Bearer $ApiKey" } -TimeoutSec $TimeoutSec
  } catch {
    continue
  }
  $status = $st.status
  if ($st.video -and $st.video.url) {
    $videoUrl = $st.video.url
    $finalDuration = $st.video.duration
  } elseif ($st.url) {
    $videoUrl = $st.url
  } elseif ($st.data -and $st.data[0].url) {
    $videoUrl = $st.data[0].url
  }

  if ($status -eq "failed" -or $st.error) {
    $err = if ($st.error) { ($st.error | ConvertTo-Json -Compress) } else { "status=failed" }
    throw "Video generation failed (request_id=$rid): $err"
  }

  if ($status -in @("done", "completed", "succeeded") -or $videoUrl) {
    break
  }
}

if (-not $videoUrl) {
  throw "Timed out waiting for video (request_id=$rid, last_status=$status, polls=$MaxPolls)"
}

$outPath = Join-Path $OutDir "$Name.mp4"
Invoke-WebRequest -Uri $videoUrl -OutFile $outPath -TimeoutSec $TimeoutSec | Out-Null

$cwd = (Get-Location).Path
$full = (Resolve-Path $outPath).Path
$rel = $full
if ($full.StartsWith($cwd, [System.StringComparison]::OrdinalIgnoreCase)) {
  $rel = $full.Substring($cwd.Length).TrimStart('\', '/')
}
$rel = ($rel -replace '\\', '/')
$fileUri = "file:///" + ($full -replace '\\', '/')

if ($Open) {
  try { Start-Process -FilePath $full } catch { Write-Warning "Open failed: $_" }
}

$result = [ordered]@{
  ok            = $true
  path          = $full
  relative_path = $rel
  file_uri      = $fileUri
  url           = $videoUrl
  request_id    = $rid
  model         = $Model
  duration      = $(if ($null -ne $finalDuration) { $finalDuration } else { $Duration })
  endpoint      = $createUrl
  bytes         = (Get-Item $outPath).Length
  opened        = [bool]$Open
}

if ($Json) {
  $result | ConvertTo-Json -Compress
} else {
  Write-Output "URL: $videoUrl"
  Write-Output "FILE: $fileUri"
  Write-Output "PATH: $rel"
  Write-Output "REQUEST_ID: $rid"
}
