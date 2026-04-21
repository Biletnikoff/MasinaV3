#Requires -RunAsAdministrator
<#
    MasinaV3 Ground Station Setup Script
    Run this in PowerShell as Administrator on the Windows PC.
    
    Prerequisites (install manually before running):
      - GStreamer MSVC x86_64: https://gstreamer.freedesktop.org/download/
        Install both runtime and development installers.
      - Visual Studio 2022 with C++ desktop development workload

    What it does:
      1. Downloads & extracts SDL2 development libraries
      2. Patches project files to use local SDK paths
      3. Compiles UDP_Server and UDP_Video (Release x64)
      4. Creates Windows Firewall rules for UDP 2222-2224
      5. Adds GStreamer to system PATH
      6. Creates desktop launch shortcuts
#>

$ErrorActionPreference = "Stop"
$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36"
$ROOT = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path "$ROOT\pc\UDP_Server\UDP_Server.sln")) {
    $ROOT = $PSScriptRoot
}

$SDK_DIR    = "C:\sdk"
$GST_DIR    = "C:\gstreamer\1.0\msvc_x86_64"
$SDL_DIR    = "$SDK_DIR\SDL2"
$DOWNLOAD   = "$env:TEMP\masina_setup"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " MasinaV3 Ground Station Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $DOWNLOAD | Out-Null
New-Item -ItemType Directory -Force -Path $SDK_DIR   | Out-Null

# -------------------------------------------------------------------
# 1. Check GStreamer
# -------------------------------------------------------------------
Write-Host "[1/6] Checking GStreamer..." -ForegroundColor Yellow

if (Test-Path "$GST_DIR\bin\gst-launch-1.0.exe") {
    Write-Host "  GStreamer found at $GST_DIR" -ForegroundColor Green
} else {
    Write-Host "  GStreamer not found at $GST_DIR" -ForegroundColor Red
    Write-Host "  Download and install both runtime + development MSVC x86_64 installers from:" -ForegroundColor Red
    Write-Host "  https://gstreamer.freedesktop.org/download/" -ForegroundColor Red
    Write-Host "  Then re-run this script." -ForegroundColor Red
    exit 1
}

# -------------------------------------------------------------------
# 2. SDL2
# -------------------------------------------------------------------
Write-Host "[2/6] SDL2..." -ForegroundColor Yellow

if (Test-Path "$SDL_DIR\include\SDL.h") {
    Write-Host "  SDL2 already present at $SDL_DIR" -ForegroundColor Green
} else {
    $sdlZip = "$DOWNLOAD\SDL2-devel.zip"
    $sdlUrl = "https://github.com/libsdl-org/SDL/releases/download/release-2.30.12/SDL2-devel-2.30.12-VC.zip"

    if (-not (Test-Path $sdlZip)) {
        Write-Host "  Downloading SDL2..."
        Invoke-WebRequest -Uri $sdlUrl -OutFile $sdlZip -UserAgent $UA
    }
    Write-Host "  Extracting SDL2..."
    Expand-Archive -Path $sdlZip -DestinationPath "$DOWNLOAD\sdl_extract" -Force
    $extracted = Get-ChildItem "$DOWNLOAD\sdl_extract" -Directory | Select-Object -First 1
    if ($extracted) {
        Move-Item -Path $extracted.FullName -Destination $SDL_DIR -Force
    }
    Write-Host "  SDL2 installed to $SDL_DIR" -ForegroundColor Green
}

# -------------------------------------------------------------------
# 3. Patch project files
# -------------------------------------------------------------------
Write-Host "[3/6] Patching project files..." -ForegroundColor Yellow

$serverProj = "$ROOT\pc\UDP_Server\UDP_Server.vcxproj"
$videoProj  = "$ROOT\pc\UDP_Video\UDP_Video.vcxproj"

if (Test-Path $serverProj) {
    $content = Get-Content $serverProj -Raw
    $content = $content -replace 'D:\\sdk\\SDL\\include', "$SDL_DIR\include"
    $content = $content -replace 'D:\\sdk\\SDL\\lib\\x64', "$SDL_DIR\lib\x64"
    Set-Content $serverProj -Value $content
    Write-Host "  Patched UDP_Server.vcxproj (SDL paths)" -ForegroundColor Green
}

if (Test-Path $videoProj) {
    $content = Get-Content $videoProj -Raw
    $content = $content -replace 'E:\\gstreamer\\1\.0\\mingw_x86_64', $GST_DIR
    Set-Content $videoProj -Value $content
    Write-Host "  Patched UDP_Video.vcxproj (GStreamer paths)" -ForegroundColor Green
}

# -------------------------------------------------------------------
# 4. Compile
# -------------------------------------------------------------------
Write-Host "[4/6] Compiling..." -ForegroundColor Yellow

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-Host "  ERROR: Visual Studio not found. Install Visual Studio 2022 with C++ workload first." -ForegroundColor Red
    Write-Host "  Download: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Red
    Write-Host "  After installing, re-run this script." -ForegroundColor Red
} else {
    $vsPath = (& $vswhere -latest -property installationPath 2>$null) | Select-Object -First 1
    $msbuild = $null

    if ($vsPath) {
        $msbuild = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
        if (-not (Test-Path $msbuild)) {
            $msbuild = Get-ChildItem "$vsPath\MSBuild" -Recurse -Filter "MSBuild.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        }
    }

    if ($msbuild -and (Test-Path $msbuild)) {
        $sln = "$ROOT\pc\UDP_Server\UDP_Server.sln"
        $outDir = "$ROOT\pc\UDP_Server\x64\Release"
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null

        if (Test-Path "$SDL_DIR\lib\x64\SDL2.dll") {
            Copy-Item "$SDL_DIR\lib\x64\SDL2.dll" -Destination $outDir -Force
            Write-Host "  Copied SDL2.dll to output directory" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: SDL2.dll not found at $SDL_DIR\lib\x64\" -ForegroundColor Red
        }

        Write-Host "  Building Release|x64..."
        & $msbuild $sln /p:Configuration=Release /p:Platform=x64 /m /v:minimal
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Build succeeded" -ForegroundColor Green
        } else {
            Write-Host "  Build failed. Open UDP_Server.sln in Visual Studio to debug." -ForegroundColor Red
        }
    } else {
        Write-Host "  MSBuild not found. Open UDP_Server.sln in Visual Studio and build manually." -ForegroundColor Red
    }
}

# -------------------------------------------------------------------
# 5. Firewall rules
# -------------------------------------------------------------------
Write-Host "[5/6] Firewall rules..." -ForegroundColor Yellow

$rules = @(
    @{ Name="MasinaV3 Video (UDP 2222) In";   Dir="Inbound";  Port=2222 },
    @{ Name="MasinaV3 Telemetry (UDP 2223) In"; Dir="Inbound";  Port=2223 },
    @{ Name="MasinaV3 Controls (UDP 2224) In";  Dir="Inbound";  Port=2224 },
    @{ Name="MasinaV3 Video (UDP 2222) Out";   Dir="Outbound"; Port=2222 },
    @{ Name="MasinaV3 Telemetry (UDP 2223) Out"; Dir="Outbound"; Port=2223 },
    @{ Name="MasinaV3 Controls (UDP 2224) Out";  Dir="Outbound"; Port=2224 }
)

foreach ($r in $rules) {
    $existing = Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Rule already exists: $($r.Name)" -ForegroundColor Green
    } else {
        New-NetFirewallRule -DisplayName $r.Name -Direction $r.Dir -Protocol UDP -LocalPort $r.Port -Action Allow | Out-Null
        Write-Host "  Created: $($r.Name)" -ForegroundColor Green
    }
}

# -------------------------------------------------------------------
# 6. Add GStreamer to PATH
# -------------------------------------------------------------------
Write-Host "[6/6] PATH & launchers..." -ForegroundColor Yellow

$gstBin = "$GST_DIR\bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -like "*$gstBin*") {
    Write-Host "  GStreamer already in PATH" -ForegroundColor Green
} else {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$gstBin", "Machine")
    $env:Path = "$env:Path;$gstBin"
    Write-Host "  Added $gstBin to system PATH" -ForegroundColor Green
}

Write-Host "  Creating launcher scripts..." -ForegroundColor Yellow

$desktop = [Environment]::GetFolderPath("Desktop")

$videoLauncher = @"
@echo off
echo Starting MasinaV3 Video Receiver...
echo Press Ctrl+C to stop.
"$GST_DIR\bin\gst-launch-1.0.exe" udpsrc port=2222 ! "application/x-rtp,encoding-name=H264,payload=96" ! rtph264depay ! avdec_h264 ! fpsdisplaysink sync=false
pause
"@
Set-Content "$desktop\MasinaV3_Video.bat" -Value $videoLauncher

$serverExe = "$ROOT\pc\UDP_Server\x64\Release\UDP_Server.exe"
$serverLauncher = @"
@echo off
echo Starting MasinaV3 Ground Station Server...
echo Connect your Xbox/PlayStation controller first!
echo.
if exist "$serverExe" (
    "$serverExe" %*
) else (
    echo ERROR: UDP_Server.exe not found at:
    echo   $serverExe
    echo Compile the project in Visual Studio first.
)
pause
"@
Set-Content "$desktop\MasinaV3_Server.bat" -Value $serverLauncher

$launchAll = @"
@echo off
echo ========================================
echo  MasinaV3 Ground Station
echo ========================================
echo.
echo Starting video receiver...
start "MasinaV3 Video" "$GST_DIR\bin\gst-launch-1.0.exe" udpsrc port=2222 ! "application/x-rtp,encoding-name=H264,payload=96" ! rtph264depay ! avdec_h264 ! fpsdisplaysink sync=false
timeout /t 2 >nul
echo Starting controls/telemetry server...
if exist "$serverExe" (
    start "MasinaV3 Server" "$serverExe"
) else (
    echo WARNING: UDP_Server.exe not found. Compile the project first.
)
echo.
echo Both services started. Close this window anytime.
echo To stop: close the video window and server console.
pause
"@
Set-Content "$desktop\MasinaV3_Launch.bat" -Value $launchAll

Write-Host "  Created desktop launchers" -ForegroundColor Green

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Setup Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Desktop shortcuts created:" -ForegroundColor White
Write-Host "  MasinaV3_Launch.bat  - Start everything (video + server)" -ForegroundColor White
Write-Host "  MasinaV3_Video.bat   - Video receiver only" -ForegroundColor White
Write-Host "  MasinaV3_Server.bat  - Controls/telemetry server only" -ForegroundColor White
Write-Host ""
Write-Host "Remaining manual steps:" -ForegroundColor Yellow
Write-Host "  1. Forward UDP ports 2222-2224 on your router to this PC's local IP" -ForegroundColor White
Write-Host "  2. Plug in your Xbox/PlayStation controller" -ForegroundColor White
Write-Host ""
