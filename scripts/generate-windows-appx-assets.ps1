$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "build\icon-aura.png"
$outputDir = Join-Path $repoRoot "build\appx"

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
  throw "Aura icon source is missing: $sourcePath"
}

[void](New-Item -ItemType Directory -Path $outputDir -Force)
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)

function Write-AppxIcon {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][int]$CanvasWidth,
    [Parameter(Mandatory = $true)][int]$CanvasHeight,
    [Parameter(Mandatory = $true)][int]$ArtworkSize
  )

  $bitmap = New-Object System.Drawing.Bitmap $CanvasWidth, $CanvasHeight, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $left = [int](($CanvasWidth - $ArtworkSize) / 2)
    $top = [int](($CanvasHeight - $ArtworkSize) / 2)
    $graphics.DrawImage($sourceImage, $left, $top, $ArtworkSize, $ArtworkSize)
    $targetPath = Join-Path $outputDir $FileName
    $bitmap.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

try {
  Write-AppxIcon -FileName "StoreLogo.png" -CanvasWidth 50 -CanvasHeight 50 -ArtworkSize 50
  Write-AppxIcon -FileName "Square44x44Logo.png" -CanvasWidth 44 -CanvasHeight 44 -ArtworkSize 44
  Write-AppxIcon -FileName "Square150x150Logo.png" -CanvasWidth 150 -CanvasHeight 150 -ArtworkSize 150
  Write-AppxIcon -FileName "Wide310x150Logo.png" -CanvasWidth 310 -CanvasHeight 150 -ArtworkSize 150
}
finally {
  $sourceImage.Dispose()
}

Write-Output "Generated AppX Aura assets in $outputDir"
