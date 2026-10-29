# Build a Wireshark 4.6.9 Windows installer inside the Windows 11 guest.
# Matches the Wireshark 4.6.9 Windows CI job: VS 2022, Qt 6.8.3, NSIS 3.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$WiresharkRef = 'v4.6.9'
$QtVersion = '6.8.3'
$Base = 'C:\Development'
$SourceDir = Join-Path $Base 'wireshark'
$BuildDir = Join-Path $Base 'wsbuild64'
$QtRoot = Join-Path $Base 'Qt'
$LogDir = Join-Path $Base 'logs'
$LogFile = Join-Path $LogDir 'build-windows-installer.log'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Invoke-Checked {
    param([Parameter(Mandatory = $true)][string[]]$Command)
    $exe = $Command[0]
    $argList = @()
    if ($Command.Length -gt 1) {
        $argList = $Command[1..($Command.Length - 1)]
    }
    Write-Log ("run {0} {1}" -f $exe, ($argList -join ' '))
    & $exe @argList
    if ($LASTEXITCODE -ne 0) {
        throw ("{0} exited {1}" -f $exe, $LASTEXITCODE)
    }
}

function Import-VsDevEnvironment {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe was not found at $vswhere"
    }
    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $installPath) {
        throw 'Visual Studio C++ tools are not installed.'
    }
    $devCmd = Join-Path $installPath 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path $devCmd)) {
        throw "VsDevCmd.bat was not found at $devCmd"
    }
    Write-Log "Importing $devCmd"
    $captured = cmd /c "`"$devCmd`" -arch=x64 -host_arch=x64 >nul && set"
    foreach ($entry in $captured) {
        if ($entry -match '^(.*?)=(.*)$') {
            Set-Item -Path ("Env:{0}" -f $Matches[1]) -Value $Matches[2]
        }
    }
}

New-Item -ItemType Directory -Force -Path $Base, $LogDir, $QtRoot | Out-Null
Set-Content -Path $LogFile -Value ''

Write-Log "Wireshark $WiresharkRef Windows installer build"

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log 'Installing Chocolatey'
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:Path = "$env:Path;$env:ALLUSERSPROFILE\chocolatey\bin"
}

$chocoPackages = @('git', 'cmake', 'python', 'nsis', 'xsltproc', 'winflexbison3')
foreach ($package in $chocoPackages) {
    Write-Log "Installing $package"
    & choco install -y --no-progress $package
    if ($LASTEXITCODE -ne 0) {
        throw "choco install $package exited $LASTEXITCODE"
    }
}

$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
& git config --system core.longpaths true

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$hasMsvc = $false
if (Test-Path $vswhere) {
    $existing = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($existing) { $hasMsvc = $true }
}
if (-not $hasMsvc) {
    $bootstrap = Join-Path $env:TEMP 'vs_buildtools.exe'
    Write-Log 'Downloading Visual Studio 2022 Build Tools'
    Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' -OutFile $bootstrap
    $vsArgs = @(
        '--quiet', '--wait', '--norestart', '--nocache',
        '--add', 'Microsoft.VisualStudio.Workload.VCTools',
        '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.22621',
        '--add', 'Microsoft.VisualStudio.Component.VC.CMake.Project',
        '--includeRecommended'
    )
    Write-Log 'Installing Visual Studio 2022 Build Tools with the Windows 11 SDK'
    $proc = Start-Process -FilePath $bootstrap -ArgumentList $vsArgs -Wait -PassThru
    if ($proc.ExitCode -eq 3010) {
        Write-Log 'Visual Studio setup requested a reboot. Continuing in this session.'
    } elseif ($proc.ExitCode -ne 0) {
        throw "Visual Studio Build Tools exited $($proc.ExitCode)"
    }
}

Import-VsDevEnvironment

$qtPrefix = $null
foreach ($candidate in @(
        (Join-Path $QtRoot "$QtVersion\msvc2022_64"),
        (Join-Path $QtRoot "$QtVersion\win64_msvc2022_64")
    )) {
    if (Test-Path (Join-Path $candidate 'bin\qmake.exe')) {
        $qtPrefix = $candidate
        break
    }
}
if (-not $qtPrefix) {
    Write-Log "Installing Qt $QtVersion with aqtinstall"
    & python -m pip install --upgrade pip aqtinstall
    if ($LASTEXITCODE -ne 0) { throw "pip install aqtinstall exited $LASTEXITCODE" }
    & python -m aqt install-qt windows desktop $QtVersion win64_msvc2022_64 -m qt5compat -O $QtRoot
    if ($LASTEXITCODE -ne 0) { throw "aqt install-qt exited $LASTEXITCODE" }
    $qtPrefix = Join-Path $QtRoot "$QtVersion\msvc2022_64"
}
if (-not (Test-Path (Join-Path $qtPrefix 'bin\qmake.exe'))) {
    throw "Qt qmake.exe was not found under $qtPrefix"
}
Write-Log "Qt prefix $qtPrefix"

$env:WIRESHARK_BASE_DIR = Join-Path $Base 'wireshark-libs'
$env:CMAKE_PREFIX_PATH = $qtPrefix
$env:WIRESHARK_VERSION_EXTRA = '-Win11Docker'
$env:PLATFORM = 'x64'
New-Item -ItemType Directory -Force -Path $env:WIRESHARK_BASE_DIR, $BuildDir | Out-Null

if (-not (Test-Path (Join-Path $SourceDir '.git'))) {
    Write-Log "Cloning Wireshark $WiresharkRef"
    Invoke-Checked -Command @(
        'git', 'clone', '--depth', '1', '--branch', $WiresharkRef,
        'https://gitlab.com/wireshark/wireshark.git', $SourceDir
    )
}

$cache = Join-Path $BuildDir 'CMakeCache.txt'
if (-not (Test-Path $cache)) {
    Push-Location $BuildDir
    try {
        Invoke-Checked -Command @(
            'cmake', '-G', 'Visual Studio 17 2022', '-A', 'x64',
            '-DCMAKE_SYSTEM_VERSION=10.0.22621.0',
            "-DWIRESHARK_BASE_DIR=$env:WIRESHARK_BASE_DIR",
            "-DCMAKE_PREFIX_PATH=$qtPrefix",
            $SourceDir
        )
    } finally {
        Pop-Location
    }
}

Push-Location $BuildDir
try {
    Invoke-Checked -Command @('cmake', '--build', '.', '--config', 'RelWithDebInfo', '--', '/m')
    Invoke-Checked -Command @('msbuild', '/m', '/p:Configuration=RelWithDebInfo', 'wireshark_nsis_prep.vcxproj')
    Invoke-Checked -Command @('msbuild', '/m', '/p:Configuration=RelWithDebInfo', 'wireshark_nsis.vcxproj')
} finally {
    Pop-Location
}

$produced = Get-ChildItem -Path (Join-Path $BuildDir 'packaging\nsis') -Filter 'Wireshark-*-x64.exe' -File
if (-not $produced) {
    throw 'NSIS did not produce a Wireshark x64 installer.'
}

$destinations = @(
    'Z:\',
    'C:\Users\Public\Desktop\Shared',
    'C:\Users\Docker\Desktop\Shared',
    'C:\OEM'
)
foreach ($installer in $produced) {
    foreach ($dest in $destinations) {
        if (Test-Path $dest) {
            Copy-Item -Force $installer.FullName (Join-Path $dest $installer.Name)
            Write-Log ("copied {0} to {1}" -f $installer.Name, $dest)
        }
    }
}

Write-Log 'Windows installer build finished.'
$produced | ForEach-Object { Write-Log $_.FullName }
