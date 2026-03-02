# PowerShell Script to generate Installer BMPs
Add-Type -AssemblyName System.Drawing

$installerDir = "C:\Users\koray\Desktop\Newcord\installer"
$iconPath = "C:\Users\koray\Desktop\Newcord\client\assets\icon.png"

function Create-ModernBmp {
    param([int]$width, [int]$height, [string]$filename, [bool]$isBanner)

    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    
    # Background color matches the app icon background (#0A0A0F)
    $bgColor = [System.Drawing.Color]::FromArgb(255, 10, 10, 15)
    $brush = New-Object System.Drawing.SolidBrush($bgColor)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $graphics.FillRectangle($brush, $rect)

    # Load and draw the app icon
    if (Test-Path $iconPath) {
        $iconBmp = [System.Drawing.Image]::FromFile($iconPath)
        
        # Calculate scaling and positioning to center the icon
        if ($isBanner) {
            # For banner (164x314), scale icon to fit width with some padding
            $iconSize = $width - 40
            $x = ($width - $iconSize) / 2
            $y = ($height - $iconSize) / 2
            $graphics.DrawImage($iconBmp, $x, $y, $iconSize, $iconSize)
        } else {
            # For small logo (55x55), scale to fit entirely
            $graphics.DrawImage($iconBmp, 0, 0, $width, $height)
        }
        
        $iconBmp.Dispose()
    }

    $graphics.Dispose()
    $brush.Dispose()
    
    $outPath = Join-Path $installerDir $filename
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose()
    Write-Host "Created $outPath"
}

# WizardImageFile: 164x314 (Left Banner)
Create-ModernBmp -width 164 -height 314 -filename "banner.bmp" -isBanner $true

# WizardSmallImageFile: 55x55 (Top Right Logo)
Create-ModernBmp -width 55 -height 55 -filename "logo.bmp" -isBanner $false

Write-Host "Done."
