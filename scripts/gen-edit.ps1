<#
.SYNOPSIS
  Edit an image via mid-relay OpenAI/xAI-compatible POST /v1/images/edits (JSON body).

.NOTES
  xAI does NOT use multipart form-data (OpenAI SDK images.edit). Body is application/json:
    { model, prompt, image: { url, type: "image_url" } }
  Source image: public HTTPS URL or data: URI (local path is base64-encoded).

.EXAMPLE
  .\gen-edit.ps1 -Prompt "pencil sketch with detailed shading" -ImagePath .\images\sunset-cat.jpg -Open -Json

.EXAMPLE
  .\gen-edit.ps1 -Prompt "make it rainy night" -ImageUrl "https://imgen.x.ai/..." -Name cat-rain -Json
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Prompt,

  [string]$ImagePath = "",
  [string]$ImageUrl = "",
  [string]$OutDir = "",
  [string]$Name = "",
  [string]$Model = "",
  [string]$BaseUrl = "",
  [string]$ApiKey = "",
  [string]$AspectRatio = "",
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
  if ([string]::IsNullOrWhiteSpace($s)) { $s = "edit" }
  if ($s.Length -gt 48) { $s = $s.Substring(0, 48).TrimEnd("-") }
  return $s
}

if ([string]::IsNullOrWhiteSpace($ImagePath) -and [string]::IsNullOrWhiteSpace($ImageUrl)) {
  throw "Provide -ImagePath and/or -ImageUrl (source image required for edits)."
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = Get-EnvFirst @(
    "GROK_EDIT_BASE_URL", "GROK_IMAGEN_BASE_URL",
    "PROXY_IMAGEN_BASE_URL", "ANTHROPIC_BASE_URL"
  )
  if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = "https://codexone.aieania.tech"
  }
}
$BaseUrl = $BaseUrl.TrimEnd("/")
if ($BaseUrl.EndsWith("/v1")) {
  $endpoint = "$BaseUrl/images/edits"
} else {
  $endpoint = "$BaseUrl/v1/images/edits"
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $ApiKey = Get-EnvFirst @(
    "GROK_EDIT_API_KEY", "GROK_IMAGEN_API_KEY", "PROXY_IMAGEN_API_KEY",
    "GROK_API_KEY", "THIRD_PARTY_API_KEY", "XAI_API_KEY"
  )
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw "No API key. Set GROK_API_KEY (or GROK_EDIT_API_KEY)."
}

if ([string]::IsNullOrWhiteSpace($Model)) {
  $Model = Get-EnvFirst @("GROK_EDIT_MODEL", "PROXY_EDIT_MODEL", "GROK_IMAGEN_MODEL")
  # Docs default for edits; some relays also accept grok-imagine-image / grok-imagine-edit
  if ([string]::IsNullOrWhiteSpace($Model)) { $Model = "grok-imagine-image-quality" }
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Get-EnvFirst @("GROK_EDIT_OUT_DIR", "GROK_IMAGEN_OUT_DIR", "PROXY_IMAGEN_OUT_DIR")
  if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = (Join-Path (Get-Location) "images") }
}
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ([string]::IsNullOrWhiteSpace($Name)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $Name = "edit-$(Get-Slug $Prompt)-$stamp"
} else {
  $Name = Get-Slug $Name
}

# Resolve source to URL string (https or data:)
$sourceUrl = $ImageUrl
if (-not [string]::IsNullOrWhiteSpace($ImagePath)) {
  $ImagePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ImagePath)
  if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "ImagePath not found: $ImagePath"
  }
  if ([string]::IsNullOrWhiteSpace($sourceUrl)) {
    $bytes = [IO.File]::ReadAllBytes($ImagePath)
    $b64 = [Convert]::ToBase64String($bytes)
    $ext = [IO.Path]::GetExtension($ImagePath).ToLowerInvariant()
    $mime = switch ($ext) {
      ".png" { "image/png" }
      ".webp" { "image/webp" }
      ".gif" { "image/gif" }
      default { "image/jpeg" }
    }
    $sourceUrl = "data:$mime;base64,$b64"
  }
}

if ([string]::IsNullOrWhiteSpace($sourceUrl)) {
  throw "Could not resolve source image URL."
}

$bodyObj = [ordered]@{
  model  = $Model
  prompt = $Prompt
  image  = [ordered]@{
    url  = $sourceUrl
    type = "image_url"
  }
  n      = 1
}
if (-not [string]::IsNullOrWhiteSpace($AspectRatio)) {
  $bodyObj.aspect_ratio = $AspectRatio
}

$bodyJson = $bodyObj | ConvertTo-Json -Depth 6 -Compress
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
  throw "Image edit request failed: $msg"
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

$cwd = (Get-Location).Path
$rel = $outPath
if ($outPath.StartsWith($cwd, [System.StringComparison]::OrdinalIgnoreCase)) {
  $rel = $outPath.Substring($cwd.Length).TrimStart('\', '/')
}
$rel = ($rel -replace '\\', '/')

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
  source_path   = if ($ImagePath) { $ImagePath } else { $null }
  source_url    = if ($ImageUrl) { $ImageUrl } else { $null }
  opened        = [bool]$Open
}

if ($Json) {
  $result | ConvertTo-Json -Compress
} else {
  if ($item.url) { Write-Output "URL: $($item.url)" }
  Write-Output "FILE: $fileUri"
  Write-Output "PATH: $rel"
}
