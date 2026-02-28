# PowerShell Script to generate Installer BMPs
Add-Type -AssemblyName System.Drawing

$installerDir = "C:\Users\koray\Desktop\Newcord\installer"

function Create-GradientBmp {
    param([int]$width, [int]$height, [string]$filename, [string]$text)

    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    
    # Create gradient brush (Deep Space / Cosmic Theme)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $color2 = [System.Drawing.Color]::FromArgb(255, 108, 92, 231) # Accent Primary Purple
    $brush = New-Object System.Drawing.SolidBrush($color2)
    
    $graphics.FillRectangle($brush, $rect)

    # Draw Text if provided
    if ($text) {
        $font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
        $brushText = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        
        # Center text vertically, but rotated for banner? No, just horizontal text near bottom or string format
        $stringFormat = New-Object System.Drawing.StringFormat
        $stringFormat.Alignment = [System.Drawing.StringAlignment]::Center
        $stringFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
        
        $rectF = New-Object System.Drawing.RectangleF(0, 0, $width, $height)
        $graphics.DrawString($text, $font, $brushText, $rectF, $stringFormat)
    }

    $graphics.Dispose()
    
    $outPath = Join-Path $installerDir $filename
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose()
    Write-Host "Created $outPath"
}

# WizardImageFile: 164x314 (Left Banner)
Create-GradientBmp -width 164 -height 314 -filename "banner.bmp" -text "Antarcticom"

# WizardSmallImageFile: 55x55 (Top Right Logo)
Create-GradientBmp -width 55 -height 55 -filename "logo.bmp" -text "AC"

Write-Host "Done."
