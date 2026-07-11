<#
.SYNOPSIS
  Generate an image via an OpenAI-compatible /images/generations proxy (not xAI official image_gen).

.EXAMPLE
  .\gen-image.ps1 -Prompt "Suzhou Bay sunset" -OutDir ".\images" -Name "suzhou-bay-sunset"
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
  [int]$TimeoutSec = 180,
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
  if ([string]::IsNullOrWhiteSpace($s)) { $s = "image" }
  if ($s.Length -gt 48) { $s = $s.Substring(0, 48).TrimEnd("-") }
  return $s
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = Get-EnvFirst @("GROK_IMAGEN_BASE_URL", "PROXY_IMAGEN_BASE_URL", "ANTHROPIC_BASE_URL")
  if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = "https://codexone.aieania.tech"
  }
}
$BaseUrl = $BaseUrl.TrimEnd("/")
if ($BaseUrl.EndsWith("/v1")) {
  $endpoint = "$BaseUrl/images/generations"
} else {
  $endpoint = "$BaseUrl/v1/images/generations"
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $ApiKey = Get-EnvFirst @("GROK_IMAGEN_API_KEY", "PROXY_IMAGEN_API_KEY", "GROK_API_KEY", "THIRD_PARTY_API_KEY", "XAI_API_KEY")
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw "No API key. Set GROK_API_KEY (or GROK_IMAGEN_API_KEY)."
}

if ([string]::IsNullOrWhiteSpace($Model)) {
  $Model = Get-EnvFirst @("GROK_IMAGEN_MODEL", "PROXY_IMAGEN_MODEL")
  if ([string]::IsNullOrWhiteSpace($Model)) { $Model = "grok-imagine-image" }
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Get-EnvFirst @("GROK_IMAGEN_OUT_DIR", "PROXY_IMAGEN_OUT_DIR")
  if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = (Join-Path (Get-Location) "images") }
}
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ([string]::IsNullOrWhiteSpace($Name)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $Name = "$(Get-Slug $Prompt)-$stamp"
} else {
  $Name = Get-Slug $Name
}

$bodyObj = @{
  model  = $Model
  prompt = $Prompt
  n      = 1
}
$bodyJson = $bodyObj | ConvertTo-Json -Depth 5 -Compress
$headers = @{
  Authorization  = "Bearer $ApiKey"
  "Content-Type" = "application/json; charset=utf-8"
}

try {
  $resp = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec $TimeoutSec
} catch {
  $msg = $_.Exception.Message
  if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = "$msg | $($_.ErrorDetails.Message)" }
  throw "Image generation request failed: $msg"
}

$item = $null
if ($resp.data -and $resp.data.Count -gt 0) { $item = $resp.data[0] }
elseif ($resp.url) { $item = $resp }

if (-not $item) {
  throw "Unexpected response (no data): $($resp | ConvertTo-Json -Depth 6 -Compress)"
}

$ext = "jpg"
$mime = $item.mime_type
if ($mime -match "png") { $ext = "png" }
elseif ($mime -match "webp") { $ext = "webp" }
elseif ($mime -match "jpeg|jpg") { $ext = "jpg" }

$outPath = Join-Path $OutDir "$Name.$ext"

if ($item.url) {
  Invoke-WebRequest -Uri $item.url -OutFile $outPath -TimeoutSec $TimeoutSec | Out-Null
} elseif ($item.b64_json) {
  [IO.File]::WriteAllBytes($outPath, [Convert]::FromBase64String($item.b64_json))
} else {
  throw "Response has neither url nor b64_json"
}

# Workspace-relative path (forward slashes) for agent replies
$cwd = (Get-Location).Path
$rel = $outPath
if ($outPath.StartsWith($cwd, [System.StringComparison]::OrdinalIgnoreCase)) {
  $rel = $outPath.Substring($cwd.Length).TrimStart('\', '/')
}
$rel = ($rel -replace '\\', '/')

# file:// URI works in some terminals / browsers
$full = (Resolve-Path $outPath).Path
$fileUri = "file:///" + ($full -replace '\\', '/')

if ($Open) {
  try { Start-Process -FilePath $full } catch { Write-Warning "Open failed: $_" }
}

$result = [ordered]@{
  ok            = $true
  path          = $full
  relative_path = $rel
  file_uri      = $fileUri
  url           = $item.url
  model         = $Model
  endpoint      = $endpoint
  bytes         = (Get-Item $outPath).Length
  mime          = $mime
  opened        = [bool]$Open
}

if ($Json) {
  $result | ConvertTo-Json -Compress
} else {
  # Human-friendly multi-line so TUI can pick up https:// and file://
  if ($item.url) { Write-Output "URL: $($item.url)" }
  Write-Output "FILE: $fileUri"
  Write-Output "PATH: $rel"
}
