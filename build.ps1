# build.ps1

# Exit on any error
$ErrorActionPreference = 'Stop'

# --- Environment Setup ---
# The workflow YAML now handles setting these as environment variables.
$AsepriteVersion = $env:ASEPRITE_VERSION
$SkiaVersion = $env:SKIA_VERSION

Write-Host "Building Aseprite Version: $AsepriteVersion"
Write-Host "Using Skia Version: $SkiaVersion"

# Find MSVC environment. This is more robust than the original.
Write-Host "Setting up MSVC environment..."
$vswhere_path = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs_path = & $vswhere_path -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
if (-not $vs_path) {
    Write-Error "Visual Studio with NativeDesktop workload not found."
    exit 1
}
Import-Module (Join-Path $vs_path 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $vs_path -DevCmdArguments "-arch=amd64 -no_logo"
Write-Host "MSVC environment ready."


# --- Patch Aseprite Version ---
# This makes the built executable report the correct version instead of "1.x-dev"
Write-Host "Patching version in CMakeLists.txt..."
$cmakeFile = "aseprite/src/ver/CMakeLists.txt"
$versionString = $AsepriteVersion.Substring(1) # Remove the 'v' prefix
(Get-Content $cmakeFile -Raw).Replace('1.x-dev', $versionString) | Set-Content $cmakeFile -NoNewline


# --- Build Aseprite ---
Write-Host "Configuring build with CMake..."
if (Test-Path -Path "build") {
    Remove-Item -Recurse -Force "build"
}
New-Item -ItemType Directory -Path "build" | Out-Null

$skiaDir = (Get-Location).Path + "\skia-$SkiaVersion"
$skiaLibDir = $skiaDir + "\out\Release-x64"

# Note: -DENABLE_CCACHE=ON to use the ccache we set up in the workflow
$cmakeArgs = @(
    "-G", "Ninja",
    "-S", "aseprite",
    "-B", "build",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded",
    "-DENABLE_CCACHE=ON", # Enable ccache for faster builds
    "-DLAF_BACKEND=skia",
    "-DSKIA_DIR=$skiaDir",
    "-DSKIA_LIBRARY_DIR=$skiaLibDir",
    "-DSKIA_OPENGL_LIBRARY="
)
& cmake.exe $cmakeArgs

Write-Host "Compiling with Ninja..."
& ninja.exe -C build


# --- Create Output Folder ---
Write-Host "Packaging build..."
$outputDir = "output/aseprite-$AsepriteVersion"
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# Create portable marker file
New-Item -Path "$outputDir/aseprite.ini" -ItemType File -Value "# Portable mode" | Out-Null

# Copy build artifacts
Copy-Item -Path "aseprite/docs" -Destination $outputDir -Recurse -Force
Copy-Item -Path "build/bin/aseprite.exe" -Destination $outputDir -Force
Copy-Item -Path "build/bin/data" -Destination "$outputDir/data" -Recurse -Force

# Set output for artifact naming in workflow (already done in 'versions' step, but good practice)
echo "ASEPRITE_VERSION=$AsepriteVersion" >> $env:GITHUB_OUTPUT

Write-Host "Build and packaging complete. Output is in '$outputDir'."
