param(
    [string]$Source = (Join-Path $PSScriptRoot "..\resources\icons\briefgcs-master.png")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sourcePath = (Resolve-Path $Source).Path

function New-IconBitmap([int]$Size) {
    $sourceImage = [System.Drawing.Image]::FromFile($sourcePath)
    try {
        $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $bitmap.SetResolution(72, 72)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Black)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.DrawImage($sourceImage, 0, 0, $Size, $Size)
        }
        finally {
            $graphics.Dispose()
        }
        return $bitmap
    }
    finally {
        $sourceImage.Dispose()
    }
}

function Get-PngBytes([int]$Size) {
    $bitmap = New-IconBitmap $Size
    $stream = New-Object System.IO.MemoryStream
    try {
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        # The leading comma prevents PowerShell from unrolling the byte array
        # when this helper is consumed by the ICO and ICNS container writers.
        return ,$stream.ToArray()
    }
    finally {
        $stream.Dispose()
        $bitmap.Dispose()
    }
}

function Save-Png([string]$RelativePath, [int]$Size) {
    $target = Join-Path $root $RelativePath
    $parent = Split-Path $target -Parent
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    [System.IO.File]::WriteAllBytes($target, (Get-PngBytes $Size))
}

function Save-Ico([string]$RelativePath, [int[]]$Sizes) {
    $images = @($Sizes | ForEach-Object { ,(Get-PngBytes $_) })
    $target = Join-Path $root $RelativePath
    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$Sizes.Count)
        $offset = 6 + (16 * $Sizes.Count)
        for ($i = 0; $i -lt $Sizes.Count; $i++) {
            $sizeByte = if ($Sizes[$i] -eq 256) { 0 } else { $Sizes[$i] }
            $writer.Write([byte]$sizeByte)
            $writer.Write([byte]$sizeByte)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$images[$i].Length)
            $writer.Write([uint32]$offset)
            $offset += $images[$i].Length
        }
        foreach ($image in $images) {
            $writer.Write($image)
        }
        [System.IO.File]::WriteAllBytes($target, $stream.ToArray())
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Write-BigEndianUInt32([System.IO.BinaryWriter]$Writer, [uint32]$Value) {
    $Writer.Write([byte](($Value -shr 24) -band 0xff))
    $Writer.Write([byte](($Value -shr 16) -band 0xff))
    $Writer.Write([byte](($Value -shr 8) -band 0xff))
    $Writer.Write([byte]($Value -band 0xff))
}

function Save-Icns([string]$RelativePath) {
    $representations = @(
        @{ Type = "icp4"; Size = 16 },
        @{ Type = "icp5"; Size = 32 },
        @{ Type = "icp6"; Size = 64 },
        @{ Type = "ic07"; Size = 128 },
        @{ Type = "ic08"; Size = 256 },
        @{ Type = "ic09"; Size = 512 },
        @{ Type = "ic10"; Size = 1024 }
    )
    $chunks = @($representations | ForEach-Object {
        @{ Type = $_.Type; Data = (Get-PngBytes $_.Size) }
    })
    $totalLength = 8
    foreach ($chunk in $chunks) { $totalLength += 8 + $chunk.Data.Length }

    $target = Join-Path $root $RelativePath
    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes("icns"))
        Write-BigEndianUInt32 $writer $totalLength
        foreach ($chunk in $chunks) {
            $writer.Write([System.Text.Encoding]::ASCII.GetBytes($chunk.Type))
            Write-BigEndianUInt32 $writer (8 + $chunk.Data.Length)
            $writer.Write($chunk.Data)
        }
        [System.IO.File]::WriteAllBytes($target, $stream.ToArray())
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$pngTargets = @{
    "resources\icons\qgroundcontrol.png" = 128
    "resources\icons\android_512x512.png" = 512
    "resources\icons\android_dev_512x512.png" = 512
    "deploy\linux\QGroundControl_256.png" = 256
    "deploy\ios\AppStoreIcon_1024x1024.png" = 1024
    "android\res\drawable-ldpi\icon.png" = 36
    "android\res\drawable-mdpi\icon.png" = 48
    "android\res\drawable-hdpi\icon.png" = 72
    "android\res\drawable-xhdpi\icon.png" = 96
    "android\res\drawable-xxhdpi\icon.png" = 144
    "android\res\drawable-xxxhdpi\icon.png" = 192
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-20.png" = 20
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-40.png" = 40
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-41.png" = 40
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-60.png" = 60
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-87.png" = 87
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-120.png" = 120
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-167.png" = 167
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-180.png" = 180
    "deploy\ios\Images.xcassets\AppIcon.appiconset\Icon-1024.png" = 1024
    "deploy\ios\Images.xcassets\AppIcon.appiconset\AppIcon29x29.png" = 29
    "deploy\ios\Images.xcassets\AppIcon.appiconset\AppIcon29x29@2x.png" = 58
    "deploy\ios\Images.xcassets\AppIcon.appiconset\AppIcon40x40~ipad.png" = 40
    "deploy\ios\Images.xcassets\AppIcon.appiconset\AppIcon40x40@2x.png" = 80
    "deploy\ios\Images.xcassets\AppIcon.appiconset\AppIcon60x60@2x.png" = 120
    "deploy\ios\Images.xcassets\AppIcon.appiconset\AppIcon76x76~ipad.png" = 76
    "deploy\ios\Images.xcassets\AppIcon.appiconset\AppIcon76x76@2x~ipad.png" = 152
    "custom\res\icons\custom_qgroundcontrol.png" = 512
    "custom\deploy\windows\qgroundcontrol.png" = 512
    "custom\android\res\drawable-ldpi\icon.png" = 36
    "custom\android\res\drawable-mdpi\icon.png" = 48
    "custom\android\res\drawable-hdpi\icon.png" = 72
    "custom\android\res\drawable-xhdpi\icon.png" = 96
    "custom\android\res\drawable-xxhdpi\icon.png" = 144
    "custom\android\res\drawable-xxxhdpi\icon.png" = 192
}

foreach ($target in $pngTargets.GetEnumerator()) {
    Save-Png $target.Key $target.Value
}

$icoSizes = @(16, 24, 32, 48, 64, 128, 256)
Save-Ico "resources\icons\qgroundcontrol.ico" $icoSizes
Save-Ico "deploy\windows\WindowsQGC.ico" $icoSizes
Save-Ico "custom\res\icons\custom_qgroundcontrol.ico" $icoSizes
Save-Ico "custom\deploy\windows\WindowsQGC.ico" $icoSizes
Save-Ico "custom\deploy\windows\qqgroundcontrol.ico" $icoSizes
Save-Icns "deploy\macos\qgroundcontrol.icns"
Save-Icns "deploy\macos\briechgroundcontrol.icns"
Save-Icns "custom\res\icons\custom_qgroundcontrol.icns"
Save-Icns "custom\res\icons\briechgroundcontrol.icns"

$linuxPng = Get-PngBytes 1024
$linuxPngBase64 = [Convert]::ToBase64String($linuxPng)
$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <image width="1024" height="1024" href="data:image/png;base64,$linuxPngBase64"/>
</svg>
"@
[System.IO.File]::WriteAllText((Join-Path $root "deploy\linux\QGroundControl.svg"), $svg, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $root "custom\res\icons\custom_qgroundcontrol.svg"), $svg, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $root "custom\res\icons\briechgroundcontrol.svg"), $svg, [System.Text.UTF8Encoding]::new($false))

Write-Host "Generated app icons from $sourcePath"
