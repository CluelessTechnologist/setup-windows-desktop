<#
.SYNOPSIS
  Sets up a tiling desktop on Windows 11: GlazeWM (with sway-style tabs),
  a Zebar bar, Flow Launcher and a gruvbox look.

.DESCRIPTION
  Everything is per user and reversible. Existing config files are backed
  up before they are replaced, to
  %LOCALAPPDATA%\setup-windows-desktop\backup\<timestamp>.

  Steps (each can be skipped with -Skip):
    Apps       Installs Zebar and Flow Launcher (and AutoHotkey with
               -KeyRemap AutoHotkey) with winget.
    GlazeWM    Downloads the GlazeWM release zip from GitHub, checks its
               SHA256 and unpacks it to -InstallDir.
    Dotfiles   Copies the GlazeWM, Zebar, Flow Launcher and Windows
               Terminal configs into place.
    Theme      Dark mode, gruvbox accent colours, small taskbar and the
               wallpaper.
    Autostart  Adds shortcuts to the Startup folder for GlazeWM (which
               starts Zebar), Flow Launcher and the key remap.

  Run it in your own desktop session, not over SSH or as another user.

.PARAMETER Skip
  Steps to leave out, e.g. -Skip Apps,Theme.

.PARAMETER KeyRemap
  'AutoHotkey' makes the left Windows key act as Alt, so the alt+...
  bindings can be pressed with the Windows key like a sway Mod4 setup.
  'None' (default) leaves the keyboard alone.

.PARAMETER GlazeWMRepository
  GitHub repository to download GlazeWM from. Its releases must contain
  a '*-x64.zip' with glazewm.exe, glazewm-cli.exe and glazewm-watcher.exe,
  and a SHA256SUMS file.

.PARAMETER GlazeWMVersion
  Release tag to install, or 'latest'.

.PARAMETER InstallDir
  Where GlazeWM is unpacked.

.PARAMETER NoStart
  Don't start GlazeWM and Flow Launcher at the end.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\deploy.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -KeyRemap AutoHotkey -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateSet('Apps', 'GlazeWM', 'Dotfiles', 'Theme', 'Autostart')]
  [string[]]$Skip = @(),

  [ValidateSet('None', 'AutoHotkey')]
  [string]$KeyRemap = 'None',

  [string]$GlazeWMRepository = 'CluelessTechnologist/glazewm',

  [string]$GlazeWMVersion = 'latest',

  [string]$InstallDir = "$env:LOCALAPPDATA\Programs\glazewm-tabs",

  [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Makes Invoke-WebRequest fast.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = $PSScriptRoot
$dotfiles = Join-Path $repo 'dotfiles'
$backupDir = Join-Path $env:LOCALAPPDATA "setup-windows-desktop\backup\$(Get-Date -Format yyyyMMdd-HHmmss)"
$glazeDir = Join-Path $HOME '.glzr'
$flowDir = Join-Path $env:APPDATA 'FlowLauncher'
$startupDir = [Environment]::GetFolderPath('Startup')

function Write-Step([string]$text) {
  Write-Host "==> $text" -ForegroundColor Yellow
}

function Test-Step([string]$name) {
  -not ($Skip -contains $name)
}

# Copies a file into place, backing up the file it replaces.
function Install-File([string]$from, [string]$to) {
  if (-not $PSCmdlet.ShouldProcess($to, "Copy $from")) { return }

  if ((Test-Path $to) -and ((Get-FileHash $to).Hash -ne (Get-FileHash $from).Hash)) {
    $relative = $to.Substring((Split-Path $to -Qualifier).Length).TrimStart('\')
    $backup = Join-Path $backupDir $relative
    New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
    Copy-Item $to $backup -Force
    Write-Host "    backed up $to"
  }

  New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
  Copy-Item $from $to -Force
  Write-Host "    $to"
}

function Install-WingetPackage([string]$id) {
  winget list --id $id -e --accept-source-agreements | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "    $id is already installed"
    return
  }

  if ($PSCmdlet.ShouldProcess($id, 'winget install')) {
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install $id (exit $LASTEXITCODE)." }
  }
}

# Asks a running GlazeWM to exit, so its shutdown commands run and hidden
# windows are shown again, then makes sure it's gone.
function Stop-GlazeWM {
  $running = Get-Process glazewm -ErrorAction SilentlyContinue
  if (-not $running) { return }
  if (-not $PSCmdlet.ShouldProcess('GlazeWM', 'Stop')) { return }

  $cli = Join-Path (Split-Path $running[0].Path) 'glazewm-cli.exe'
  if (Test-Path $cli) {
    & $cli command wm-exit | Out-Null
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Process glazewm -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 300
    }
  }
  Get-Process glazewm, glazewm-watcher -ErrorAction SilentlyContinue | Stop-Process -Force
}

function New-StartupShortcut([string]$name, [string]$target, [string]$arguments = '') {
  $path = Join-Path $startupDir "$name.lnk"
  if (-not $PSCmdlet.ShouldProcess($path, "Create shortcut to $target")) { return }

  $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
  $shortcut.TargetPath = $target
  $shortcut.Arguments = $arguments
  $shortcut.Save()
  Write-Host "    $path"
}

# Registry colours are stored as 0xAABBGGRR.
function ConvertTo-Abgr([string]$hex) {
  $r = [Convert]::ToByte($hex.Substring(1, 2), 16)
  $g = [Convert]::ToByte($hex.Substring(3, 2), 16)
  $b = [Convert]::ToByte($hex.Substring(5, 2), 16)
  [BitConverter]::ToInt32([byte[]]($r, $g, $b, 0xFF), 0)
}

if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
  throw "Only x64 Windows is supported (this is $env:PROCESSOR_ARCHITECTURE)."
}
if ([Environment]::OSVersion.Version.Build -lt 22000) {
  Write-Warning 'This is not Windows 11. Window borders and the small taskbar need Windows 11.'
}

$glazeExe = Join-Path $InstallDir 'glazewm.exe'
$flowExe = Join-Path $env:LOCALAPPDATA 'FlowLauncher\Flow.Launcher.exe'
$ahkScript = Join-Path $HOME '.config\autohotkey\lwin-to-alt.ahk'

if (Test-Step 'Apps') {
  Write-Step 'Installing apps with winget'
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is missing. Install "App Installer" from the Microsoft Store and run this again.'
  }

  Install-WingetPackage 'glzr-io.zebar'
  Install-WingetPackage 'Flow-Launcher.Flow-Launcher'
  if ($KeyRemap -eq 'AutoHotkey') {
    Install-WingetPackage 'AutoHotkey.AutoHotkey'
  }
}

if (Test-Step 'GlazeWM') {
  Write-Step "Installing GlazeWM from $GlazeWMRepository ($GlazeWMVersion)"
  $api = "https://api.github.com/repos/$GlazeWMRepository/releases"
  $release = if ($GlazeWMVersion -eq 'latest') {
    Invoke-RestMethod "$api/latest"
  } else {
    Invoke-RestMethod "$api/tags/$GlazeWMVersion"
  }

  $zipAsset = $release.assets | Where-Object name -like '*-x64.zip' | Select-Object -First 1
  $sumsAsset = $release.assets | Where-Object name -eq 'SHA256SUMS' | Select-Object -First 1
  if (-not $zipAsset -or -not $sumsAsset) {
    throw "Release $($release.tag_name) has no '*-x64.zip' and SHA256SUMS."
  }

  $versionFile = Join-Path $InstallDir 'VERSION'
  $installed = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { '' }

  if ($installed -eq $release.tag_name) {
    Write-Host "    $($release.tag_name) is already installed"
  } elseif ($PSCmdlet.ShouldProcess($InstallDir, "Install GlazeWM $($release.tag_name)")) {
    $temp = Join-Path $env:TEMP "setup-windows-desktop-$PID"
    New-Item -ItemType Directory -Force $temp | Out-Null
    try {
      $zip = Join-Path $temp $zipAsset.name
      Invoke-WebRequest $zipAsset.browser_download_url -OutFile $zip -UseBasicParsing
      $sums = (Invoke-WebRequest $sumsAsset.browser_download_url -UseBasicParsing).Content
      if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) }

      $expected = $sums -split "`n" |
        Where-Object { $_ -match "^([0-9a-f]{64})\s+\*?$([regex]::Escape($zipAsset.name))\s*$" } |
        ForEach-Object { $Matches[1] } |
        Select-Object -First 1
      $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
      if (-not $expected -or $expected -ne $actual) {
        throw "SHA256 of $($zipAsset.name) doesn't match SHA256SUMS."
      }
      Write-Host "    SHA256 OK: $actual"

      Expand-Archive $zip (Join-Path $temp 'unpacked') -Force
      $files = Get-ChildItem (Join-Path $temp 'unpacked') -Recurse -Filter 'glazewm.exe' |
        Select-Object -First 1 | ForEach-Object { $_.Directory.FullName }

      Stop-GlazeWM
      New-Item -ItemType Directory -Force $InstallDir | Out-Null
      Copy-Item "$files\*" $InstallDir -Recurse -Force
      Set-Content $versionFile $release.tag_name
      Write-Host "    $($release.tag_name) -> $InstallDir"
    } finally {
      Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

if (Test-Step 'Dotfiles') {
  Write-Step 'Copying dotfiles'
  Install-File "$dotfiles\glazewm\config.yaml" "$glazeDir\glazewm\config.yaml"
  Install-File "$dotfiles\zebar\settings.json" "$glazeDir\zebar\settings.json"
  foreach ($file in Get-ChildItem "$dotfiles\zebar\gruvbox" -File) {
    Install-File $file.FullName "$glazeDir\zebar\gruvbox\$($file.Name)"
  }

  # Flow Launcher rewrites Settings.json when it exits, so it's stopped
  # first. Only the keys in dotfiles\flowlauncher\settings.json are
  # changed; the rest of the user's settings are kept.
  $flowRunning = [bool](Get-Process Flow.Launcher -ErrorAction SilentlyContinue)
  if ($flowRunning -and $PSCmdlet.ShouldProcess('Flow Launcher', 'Stop')) {
    Get-Process Flow.Launcher | Stop-Process -Force
    Start-Sleep 1
  }
  Install-File "$dotfiles\flowlauncher\Gruvbox.xaml" "$flowDir\Themes\Gruvbox.xaml"

  $flowSettings = "$flowDir\Settings\Settings.json"
  if ($PSCmdlet.ShouldProcess($flowSettings, 'Merge Flow Launcher settings')) {
    $current = if (Test-Path $flowSettings) { Get-Content $flowSettings -Raw } else { '' }
    $settings = if ($current) { $current | ConvertFrom-Json } else { New-Object PSObject }

    # Flow writes its own JSON formatting, so compare values, not text.
    $changed = $false
    $overrides = Get-Content "$dotfiles\flowlauncher\settings.json" -Raw | ConvertFrom-Json
    foreach ($property in $overrides.PSObject.Properties) {
      $old = $settings.PSObject.Properties[$property.Name]
      if (-not $old -or (ConvertTo-Json $old.Value -Compress) -ne (ConvertTo-Json $property.Value -Compress)) {
        $changed = $true
      }
      $settings | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
    }
    $merged = $settings | ConvertTo-Json -Depth 32

    if (-not $changed) {
      Write-Host "    $flowSettings (unchanged)"
    } else {
      if ($current) {
        $backup = Join-Path $backupDir 'FlowLauncher\Settings.json'
        New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
        Copy-Item $flowSettings $backup -Force
        Write-Host "    backed up $flowSettings"
      }
      New-Item -ItemType Directory -Force (Split-Path $flowSettings) | Out-Null
      Set-Content $flowSettings $merged -Encoding UTF8
      Write-Host "    $flowSettings (merged)"
    }
  }
  if ($flowRunning -and (Test-Path $flowExe) -and $PSCmdlet.ShouldProcess('Flow Launcher', 'Start')) {
    Start-Process $flowExe
  }

  # A fragment adds the colour scheme and applies it to the built-in
  # PowerShell and Command Prompt profiles, without editing settings.json.
  Install-File "$dotfiles\windows-terminal\gruvbox.json" `
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\gruvbox\gruvbox.json"

  if ($KeyRemap -eq 'AutoHotkey') {
    Install-File "$dotfiles\autohotkey\lwin-to-alt.ahk" $ahkScript
  }
}

if ((Test-Step 'Theme') -and $PSCmdlet.ShouldProcess('Windows look', 'Apply gruvbox theme')) {
  Write-Step 'Applying the gruvbox look'
  $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  $accent = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
  $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
  $advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  $desktop = 'HKCU:\Control Panel\Desktop'

  # Dark mode for apps and the system.
  Set-ItemProperty $personalize -Name AppsUseLightTheme -Value 0 -Type DWord
  Set-ItemProperty $personalize -Name SystemUsesLightTheme -Value 0 -Type DWord

  # Accent: gruvbox yellow, with the dark shades (used by the taskbar and
  # Start when the accent is shown there) replaced by gruvbox greys. Title
  # bars stay uncoloured.
  Set-ItemProperty $desktop -Name AutoColorization -Value '0'
  $palette = '#fbf1c7', '#fabd2f', '#fabd2f', '#d79921', '#504945', '#3c3836', '#282828', '#1d2021'
  $bytes = foreach ($color in $palette) {
    [Convert]::ToByte($color.Substring(1, 2), 16)
    [Convert]::ToByte($color.Substring(3, 2), 16)
    [Convert]::ToByte($color.Substring(5, 2), 16)
    0
  }
  New-Item -Force $accent | Out-Null
  Set-ItemProperty $accent -Name AccentPalette -Value ([byte[]]$bytes) -Type Binary
  Set-ItemProperty $accent -Name AccentColorMenu -Value (ConvertTo-Abgr '#d79921') -Type DWord
  Set-ItemProperty $accent -Name StartColorMenu -Value (ConvertTo-Abgr '#3c3836') -Type DWord
  Set-ItemProperty $dwm -Name ColorPrevalence -Value 0 -Type DWord
  Set-ItemProperty $personalize -Name ColorPrevalence -Value 1 -Type DWord

  # Settings > Personalization > Taskbar > Taskbar size: Small. Applies the
  # next time Explorer starts (sign out and in).
  Set-ItemProperty $advanced -Name TaskbarSize -Value 1 -Type DWord

  # Wallpaper scaled to fill the screen, on a #282828 background.
  $wallpaper = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'wallpaper_default_gruvbox.jpg'
  Install-File "$repo\wallpapers\wallpaper_default_gruvbox.jpg" $wallpaper

  Add-Type @'
using System; using System.Runtime.InteropServices;
public static class SetupDesktop {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern bool SystemParametersInfo(uint action, uint param, string value, uint flags);
  [DllImport("user32.dll")]
  public static extern bool SetSysColors(int count, int[] elements, int[] colors);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, string l, uint flags, uint timeout, out IntPtr result);
  public static void Broadcast(string what) { IntPtr r; SendMessageTimeout((IntPtr)0xffff, 0x1A, IntPtr.Zero, what, 2, 5000, out r); }
}
'@
  Set-ItemProperty 'HKCU:\Control Panel\Colors' -Name Background -Value '40 40 40'
  [SetupDesktop]::SetSysColors(1, @(1), @(0x282828)) | Out-Null  # COLOR_DESKTOP, 0x00BBGGRR
  Set-ItemProperty $desktop -Name WallpaperStyle -Value '10'  # Fill
  Set-ItemProperty $desktop -Name TileWallpaper -Value '0'
  [SetupDesktop]::SystemParametersInfo(0x14, 0, $wallpaper, 3) | Out-Null  # SPI_SETDESKWALLPAPER

  [SetupDesktop]::Broadcast('ImmersiveColorSet')
  [SetupDesktop]::Broadcast('WindowsThemeElement')
  Write-Host '    Done. Sign out and in for the taskbar size and colours.'
}

if (Test-Step 'Autostart') {
  Write-Step 'Adding Startup folder shortcuts'
  New-StartupShortcut 'GlazeWM' $glazeExe 'start'
  New-StartupShortcut 'Flow Launcher' $flowExe
  if ($KeyRemap -eq 'AutoHotkey') {
    New-StartupShortcut 'lwin-to-alt' $ahkScript
  }
}

if (-not $NoStart -and $PSCmdlet.ShouldProcess('GlazeWM, Flow Launcher', 'Start')) {
  Write-Step 'Starting the desktop'
  if ($KeyRemap -eq 'AutoHotkey' -and (Test-Path $ahkScript)) {
    Start-Process $ahkScript
  }
  if (-not (Get-Process Flow.Launcher -ErrorAction SilentlyContinue) -and (Test-Path $flowExe)) {
    Start-Process $flowExe
  }
  if (Test-Path $glazeExe) {
    # Restart, so a new config or binary is picked up.
    Stop-GlazeWM
    Start-Process $glazeExe -ArgumentList 'start'
  }
}

if (Test-Path $backupDir) {
  Write-Host "Replaced files were backed up to $backupDir"
}
