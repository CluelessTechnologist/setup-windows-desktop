<#
.SYNOPSIS
  Sets up a tiling desktop on Windows 11: GlazeWM (with sway-style tabs),
  a Zebar bar, Flow Launcher and a theme (gruvbox or win95).

.DESCRIPTION
  Run without parameters, it asks which theme to use and whether to remap
  the left Windows key, like the prompts of the setup-desktop-environment
  Ansible playbooks, then shows a summary before changing anything.

  Everything is per user. Existing config files are backed up before they
  are replaced, to %LOCALAPPDATA%\setup-windows-desktop\backup\<timestamp>.

  Steps (each can be skipped with -Skip):
    Apps       Installs the Visual C++ runtime, Git, Vim, Zebar and Flow
               Launcher (plus Firefox with -Firefox Yes and AutoHotkey with
               -KeyRemap AutoHotkey) with winget, unless already installed.
               Adds Vim to PATH.
    GlazeWM    Downloads the GlazeWM release zip from GitHub, checks its
               SHA256 and unpacks it to -InstallDir.
    Dotfiles   Writes the GlazeWM, Zebar, Flow Launcher and Windows
               Terminal configs for the chosen theme.
    Theme      Light or dark mode, accent colours, small taskbar and the
               theme's wallpaper.
    Autostart  Adds shortcuts to the Startup folder for GlazeWM (which
               starts Zebar), Flow Launcher and the key remap.

  Run it in your own desktop session, not over SSH or as another user.

.PARAMETER Theme
  A folder name under themes\ (gruvbox, win95). Asked for if left out.

.PARAMETER KeyRemap
  'AutoHotkey' makes the left Windows key act as Alt, so the alt+...
  bindings can be pressed with the Windows key like a sway Mod4 setup.
  'None' leaves the keyboard alone. Asked for if left out.

.PARAMETER Firefox
  'Yes' installs Firefox, which alt+f1 starts. Asked for if left out.

.PARAMETER Skip
  Steps to leave out, e.g. -Skip Apps,Theme.

.PARAMETER Unattended
  Don't ask anything. Uses -Theme gruvbox, -KeyRemap None and -Firefox Yes
  unless they are given.

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

.PARAMETER RestartExplorer
  Restart Explorer at the end of the Theme step, without asking. The
  taskbar only picks up light/dark mode, its size and accent colour when
  Explorer starts. Without this, the script asks when those settings
  changed. Open File Explorer windows are closed.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\deploy.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Theme win95 -KeyRemap None -Unattended
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Theme,

  [ValidateSet('None', 'AutoHotkey')]
  [string]$KeyRemap,

  [ValidateSet('Yes', 'No')]
  [string]$Firefox,

  # Validated below: `powershell -File` passes "Apps,Theme" as one string.
  [string[]]$Skip = @(),

  [switch]$Unattended,

  [string]$GlazeWMRepository = 'CluelessTechnologist/glazewm',

  [string]$GlazeWMVersion = 'latest',

  [string]$InstallDir = "$env:LOCALAPPDATA\Programs\glazewm-tabs",

  [switch]$NoStart,

  [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'
$Skip = @($Skip -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$allSteps = 'Apps', 'GlazeWM', 'Dotfiles', 'Theme', 'Autostart'
foreach ($step in $Skip) {
  if ($allSteps -notcontains $step) {
    throw "Unknown step '$step' in -Skip. Steps: $($allSteps -join ', ')."
  }
}
$ProgressPreference = 'SilentlyContinue'  # Makes Invoke-WebRequest fast.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = $PSScriptRoot
$dotfiles = Join-Path $repo 'dotfiles'
$backupDir = Join-Path $env:LOCALAPPDATA "setup-windows-desktop\backup\$(Get-Date -Format yyyyMMdd-HHmmss)"
$glazeDir = Join-Path $HOME '.glzr'
$flowDir = Join-Path $env:APPDATA 'FlowLauncher'
$startupDir = [Environment]::GetFolderPath('Startup')
$utf8 = New-Object Text.UTF8Encoding $false

function Write-Step([string]$text) {
  Write-Host "==> $text" -ForegroundColor Yellow
}

function Test-Step([string]$name) {
  -not ($Skip -contains $name)
}

# Asks to pick one of $options; Enter picks $default.
function Read-Choice([string]$question, [string[]]$options, [string]$default) {
  while ($true) {
    $answer = (Read-Host "$question ($($options -join '/')) [$default]").Trim()
    if (-not $answer) { return $default }
    $match = $options | Where-Object { $_ -eq $answer }
    if ($match) { return $match }
    Write-Host "    Please answer one of: $($options -join ', ')"
  }
}

# Backs up a file that is about to be replaced.
function Backup-File([string]$path) {
  $relative = $path.Substring((Split-Path $path -Qualifier).Length).TrimStart('\')
  $backup = Join-Path $backupDir $relative
  New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
  Copy-Item $path $backup -Force
  Write-Host "    backed up $path"
}

# SHA256 of a file, lowercase hex. (Get-FileHash returns nothing under
# -WhatIf in Windows PowerShell, so it can't be used for comparisons.)
function Get-Sha256([string]$path) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $sha.ComputeHash([IO.File]::ReadAllBytes($path))
    -join ($bytes | ForEach-Object { $_.ToString('x2') })
  } finally {
    $sha.Dispose()
  }
}

# Copies a file into place, backing up the file it replaces.
function Install-File([string]$from, [string]$to) {
  if ((Test-Path $to) -and (Get-Sha256 $to) -eq (Get-Sha256 $from)) {
    Write-Host "    $to (unchanged)"
    return
  }
  if (-not $PSCmdlet.ShouldProcess($to, "Copy $from")) { return }

  if (Test-Path $to) { Backup-File $to }
  New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
  Copy-Item $from $to -Force
  Write-Host "    $to"
}

# Writes text to a file (UTF-8 without BOM), backing up the file it replaces.
function Install-Content([string]$content, [string]$to) {
  if ((Test-Path $to) -and [IO.File]::ReadAllText($to) -eq $content) {
    Write-Host "    $to (unchanged)"
    return
  }
  if (-not $PSCmdlet.ShouldProcess($to, 'Write')) { return }

  if (Test-Path $to) { Backup-File $to }
  New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
  [IO.File]::WriteAllText($to, $content, $utf8)
  Write-Host "    $to"
}

# Fills in the {{name}} placeholders of a template file.
function Expand-Template([string]$path, [hashtable]$values) {
  $text = [IO.File]::ReadAllText($path)
  foreach ($key in $values.Keys) {
    $text = $text.Replace("{{$key}}", $values[$key])
  }
  $missing = [regex]::Matches($text, '\{\{(\w+)\}\}') | ForEach-Object { $_.Groups[1].Value }
  if ($missing) { throw "No value for {{$($missing -join '}}, {{')}} in $path." }
  $text
}

# Whether an app is installed: by its program file, its "App Paths" entry
# (which installers register wherever they install to, and which
# shell-exec uses to find e.g. firefox), its command, or else by asking
# winget (which also finds many apps installed without winget).
function Test-Installed($package) {
  foreach ($path in $package.Paths) {
    if (Test-Path $path) { return $true }
  }
  foreach ($root in 'HKCU:', 'HKLM:') {
    if ($package.AppPath -and (Test-Path "$root\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$($package.AppPath)")) {
      return $true
    }
  }
  if ($package.Command -and (Get-Command $package.Command -ErrorAction SilentlyContinue)) {
    return $true
  }
  winget list --id $package.Id -e --accept-source-agreements | Out-Null
  $LASTEXITCODE -eq 0
}

function Install-WingetPackage($package) {
  if (Test-Installed $package) {
    Write-Host "    $($package.Name) is already installed"
    return
  }
  if ($PSCmdlet.ShouldProcess($package.Id, 'winget install')) {
    winget install --id $package.Id -e --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install $($package.Id) (exit $LASTEXITCODE)." }
  }
}

# Stops processes by name. A process running as administrator can't be
# stopped from a normal PowerShell, so that gets a clear message.
function Stop-App([string[]]$names, [string]$label) {
  foreach ($process in Get-Process $names -ErrorAction SilentlyContinue) {
    try {
      $process | Stop-Process -Force -ErrorAction Stop
    } catch {
      throw "Could not stop $label ($($process.Name), PID $($process.Id)); it probably runs as administrator. Close it, or run this script as administrator, and run the script again."
    }
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
  Stop-App 'glazewm', 'glazewm-watcher' 'GlazeWM'
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

function ConvertTo-Rgb([string]$hex) {
  [Convert]::ToByte($hex.Substring(1, 2), 16)
  [Convert]::ToByte($hex.Substring(3, 2), 16)
  [Convert]::ToByte($hex.Substring(5, 2), 16)
}

# Registry colours are stored as 0xAABBGGRR.
function ConvertTo-Abgr([string]$hex) {
  $r, $g, $b = ConvertTo-Rgb $hex
  [BitConverter]::ToInt32([byte[]]($r, $g, $b, 0xFF), 0)
}

if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
  throw "Only x64 Windows is supported (this is $env:PROCESSOR_ARCHITECTURE)."
}
if ([Environment]::OSVersion.Version.Build -lt 22000) {
  Write-Warning 'This is not Windows 11. Window borders and the small taskbar need Windows 11.'
}

# Session 0 (SSH, services) has no desktop: stopping GlazeWM from there
# would close the user's window manager, and apps started there are
# invisible.
if ((Get-Process -Id $PID).SessionId -eq 0 -and -not $WhatIfPreference) {
  throw 'Run this in your own desktop session, not over SSH or as a service. -WhatIf works anywhere.'
}

# Choices: from parameters, else asked. -Unattended (and -WhatIf) use the
# defaults instead of asking.
$themes = @((Get-ChildItem (Join-Path $repo 'themes') -Directory).Name)
$ask = -not $Unattended -and -not $WhatIfPreference
if ($ask -and -not [Environment]::UserInteractive -and (-not $Theme -or -not $KeyRemap -or -not $Firefox)) {
  throw 'Cannot ask questions here. Pass -Theme, -KeyRemap and -Firefox, or -Unattended for the defaults.'
}

if (-not $Theme) {
  if ($ask) {
    foreach ($name in $themes) {
      $description = (Import-PowerShellDataFile (Join-Path $repo "themes\$name\theme.psd1")).Description
      Write-Host "    $name - $description"
    }
    $Theme = Read-Choice 'Choose theme' $themes 'gruvbox'
  } else {
    $Theme = 'gruvbox'
  }
}
if ($themes -notcontains $Theme) {
  throw "Unknown theme '$Theme'. Available: $($themes -join ', ')."
}
if (-not $KeyRemap) {
  $KeyRemap = if ($ask) {
    $remap = Read-Choice 'Make the left Windows key act as Alt with AutoHotkey?' @('yes', 'no') 'no'
    if ($remap -eq 'yes') { 'AutoHotkey' } else { 'None' }
  } else {
    'None'
  }
}
if (-not $Firefox) {
  $Firefox = if ($ask) {
    $answer = Read-Choice 'Install Firefox (started with alt+f1)?' @('yes', 'no') 'yes'
    if ($answer -eq 'yes') { 'Yes' } else { 'No' }
  } else {
    'Yes'
  }
}

$themeDir = Join-Path $repo "themes\$Theme"
$themeConfig = Import-PowerShellDataFile (Join-Path $themeDir 'theme.psd1')
$steps = $allSteps | Where-Object { Test-Step $_ }

Write-Host ''
Write-Host "Theme:     $Theme"
Write-Host "Key remap: $KeyRemap"
Write-Host "Firefox:   $Firefox"
Write-Host "Steps:     $($steps -join ', ')"
Write-Host "GlazeWM:   $GlazeWMRepository ($GlazeWMVersion) -> $InstallDir"
Write-Host ''
if ($ask -and [Environment]::UserInteractive -and (Read-Choice 'Continue?' @('yes', 'no') 'yes') -eq 'no') {
  Write-Host 'Nothing was changed.'
  return
}

$glazeExe = Join-Path $InstallDir 'glazewm.exe'
$flowExe = Join-Path $env:LOCALAPPDATA 'FlowLauncher\Flow.Launcher.exe'
$ahkScript = Join-Path $HOME '.config\autohotkey\lwin-to-alt.ahk'

if (Test-Step 'Apps') {
  Write-Step 'Installing apps with winget'
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is missing. Install "App Installer" from the Microsoft Store and run this again.'
  }

  # The Vim installer installs per user (Programs\Vim) or, as admin, for
  # all users (Program Files\Vim\vim92).
  $vimPaths = @(
    "$env:LOCALAPPDATA\Programs\Vim\vim.exe"
    "$env:ProgramFiles\Vim\vim*\vim.exe"
    "${env:ProgramFiles(x86)}\Vim\vim*\vim.exe"
  )
  $packages = @(
    # GlazeWM needs the Visual C++ runtime (vcruntime140.dll), which a fresh
    # Windows doesn't have.
    @{
      Name = 'Visual C++ runtime'; Id = 'Microsoft.VCRedist.2015+.x64'
      Paths = @("$env:windir\System32\vcruntime140.dll")
    }
    @{ Name = 'Git'; Id = 'Git.Git'; Command = 'git'; Paths = @("$env:ProgramFiles\Git\cmd\git.exe") }
    @{
      Name = 'Vim'; Id = 'vim.vim'; Command = 'vim'
      Paths = $vimPaths
    }
    @{ Name = 'Zebar'; Id = 'glzr-io.zebar'; Command = 'zebar'; Paths = @("$env:ProgramFiles\glzr.io\Zebar\zebar.exe") }
    @{ Name = 'Flow Launcher'; Id = 'Flow-Launcher.Flow-Launcher'; Paths = @($flowExe) }
  )
  if ($KeyRemap -eq 'AutoHotkey') {
    $packages += @{
      Name = 'AutoHotkey'; Id = 'AutoHotkey.AutoHotkey'
      Paths = @("$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
    }
  }
  if ($Firefox -eq 'Yes') {
    $packages += @{
      Name = 'Firefox'; Id = 'Mozilla.Firefox'; AppPath = 'firefox.exe'
      Paths = @(
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
        "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe"
      )
    }
  }
  foreach ($package in $packages) {
    Install-WingetPackage $package
  }

  # The Vim installer doesn't put vim on PATH. An all-users install has the
  # version in its folder (Vim\vim92), so other Vim folders are replaced in
  # the user PATH.
  $vim = $vimPaths | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } |
    Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1
  if ($vim) {
    # Read the raw value, so entries like %USERPROFILE%\... stay unexpanded.
    $environment = Get-Item 'HKCU:\Environment'
    $userPath = $environment.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $entries = @($userPath -split ';' | Where-Object { $_ })
    $newPath = if ($entries -contains $vim.DirectoryName) {
      $userPath
    } else {
      (@($entries | Where-Object { $_ -notmatch '\\Vim(\\vim\d+)?\\?$' }) + $vim.DirectoryName) -join ';'
    }

    if ($newPath -eq $userPath) {
      Write-Host "    Vim is on PATH ($($vim.DirectoryName))"
    } elseif ($PSCmdlet.ShouldProcess('user PATH', "Add $($vim.DirectoryName)")) {
      Set-ItemProperty 'HKCU:\Environment' -Name Path -Value $newPath -Type ExpandString
      # Tell Explorer, so terminals started from now on get the new PATH.
      Add-Type -Name Environment -Namespace SetupDesktop -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, string l, uint flags, uint timeout, out IntPtr result);
'@
      $result = [IntPtr]::Zero
      [SetupDesktop.Environment]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, 'Environment', 2, 5000, [ref]$result) | Out-Null
      Write-Host "    Added $($vim.DirectoryName) to PATH. Open a new terminal to use vim."
    }
  }

  # Installers add their folders (e.g. Zebar's) to PATH in the registry, but
  # this process still has the old PATH, and GlazeWM inherits it from here
  # to run `shell-exec zebar`.
  $env:Path = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine')
    [Environment]::GetEnvironmentVariable('Path', 'User')
  ) -join ';'
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
      $actual = Get-Sha256 $zip
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
  Write-Step "Writing dotfiles ($Theme)"
  Install-Content (Expand-Template "$dotfiles\glazewm\config.yaml" $themeConfig.Placeholders) `
    "$glazeDir\glazewm\config.yaml"

  Install-File "$dotfiles\zebar\settings.json" "$glazeDir\zebar\settings.json"
  foreach ($file in Get-ChildItem "$dotfiles\zebar\desktop-bar" -File) {
    Install-File $file.FullName "$glazeDir\zebar\desktop-bar\$($file.Name)"
  }
  Install-File "$themeDir\zebar.css" "$glazeDir\zebar\desktop-bar\styles.css"

  # Flow Launcher rewrites Settings.json when it exits, so it's stopped
  # first and started again afterwards. Only the keys in
  # dotfiles\flowlauncher\settings.json, the theme and the fonts are
  # changed; the rest of the user's settings are kept.
  $flowRunning = [bool](Get-Process Flow.Launcher -ErrorAction SilentlyContinue)
  if ($flowRunning -and $PSCmdlet.ShouldProcess('Flow Launcher', 'Stop')) {
    Stop-App 'Flow.Launcher' 'Flow Launcher'
    Start-Sleep 1
  }
  Install-File "$themeDir\flowlauncher.xaml" "$flowDir\Themes\$($themeConfig.FlowTheme).xaml"

  $flowSettings = "$flowDir\Settings\Settings.json"
  if ($PSCmdlet.ShouldProcess($flowSettings, 'Merge Flow Launcher settings')) {
    $current = if (Test-Path $flowSettings) { Get-Content $flowSettings -Raw } else { '' }
    $settings = if ($current) { $current | ConvertFrom-Json } else { New-Object PSObject }

    $overrides = Get-Content "$dotfiles\flowlauncher\settings.json" -Raw | ConvertFrom-Json
    $overrides | Add-Member Theme $themeConfig.FlowTheme -Force
    foreach ($font in 'QueryBoxFont', 'ResultFont', 'ResultSubFont') {
      $overrides | Add-Member $font $themeConfig.FlowFont -Force
    }

    # Flow writes its own JSON formatting, so compare values, not text.
    $changed = $false
    foreach ($property in $overrides.PSObject.Properties) {
      $old = $settings.PSObject.Properties[$property.Name]
      if (-not $old -or (ConvertTo-Json $old.Value -Compress) -ne (ConvertTo-Json $property.Value -Compress)) {
        $changed = $true
      }
      $settings | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
    }

    if (-not $changed) {
      Write-Host "    $flowSettings (unchanged)"
    } else {
      if ($current) { Backup-File $flowSettings }
      New-Item -ItemType Directory -Force (Split-Path $flowSettings) | Out-Null
      [IO.File]::WriteAllText($flowSettings, ($settings | ConvertTo-Json -Depth 32), $utf8)
      Write-Host "    $flowSettings (merged)"
    }
  }
  if ($flowRunning -and (Test-Path $flowExe) -and $PSCmdlet.ShouldProcess('Flow Launcher', 'Start')) {
    Start-Process $flowExe
  }

  # A fragment adds the colour scheme and applies it to the built-in
  # PowerShell and Command Prompt profiles, without editing settings.json.
  Install-File "$themeDir\windows-terminal.json" `
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\setup-windows-desktop\theme.json"

  if ($KeyRemap -eq 'AutoHotkey') {
    Install-File "$dotfiles\autohotkey\lwin-to-alt.ahk" $ahkScript
  }
}

if ((Test-Step 'Theme') -and $PSCmdlet.ShouldProcess('Windows look', "Apply $Theme")) {
  Write-Step "Applying the $Theme look"
  $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  $accent = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
  $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
  $advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  $desktop = 'HKCU:\Control Panel\Desktop'

  # The taskbar reads these only when Explorer starts.
  $taskbarValues = {
    $values = foreach ($item in @(
        @($personalize, 'SystemUsesLightTheme'), @($personalize, 'ColorPrevalence'),
        @($advanced, 'TaskbarSize'), @($accent, 'AccentColorMenu'), @($accent, 'StartColorMenu'))) {
      (Get-ItemProperty $item[0] -ErrorAction SilentlyContinue).($item[1])
    }
    $values -join ','
  }
  $taskbarBefore = & $taskbarValues

  # Light or dark mode, separately for apps and the system (taskbar, Start).
  Set-ItemProperty $personalize -Name AppsUseLightTheme -Value ([int](-not $themeConfig.AppsDarkMode)) -Type DWord
  Set-ItemProperty $personalize -Name SystemUsesLightTheme -Value ([int](-not $themeConfig.SystemDarkMode)) -Type DWord

  # Accent colour and its palette of shades, used by Start, the taskbar and
  # (if enabled) window title bars.
  Set-ItemProperty $desktop -Name AutoColorization -Value '0'
  $bytes = foreach ($color in $themeConfig.AccentPalette) { ConvertTo-Rgb $color; 0 }
  New-Item -Force $accent | Out-Null
  Set-ItemProperty $accent -Name AccentPalette -Value ([byte[]]$bytes) -Type Binary
  Set-ItemProperty $accent -Name AccentColorMenu -Value (ConvertTo-Abgr $themeConfig.Accent) -Type DWord
  Set-ItemProperty $accent -Name StartColorMenu -Value (ConvertTo-Abgr $themeConfig.StartColor) -Type DWord
  Set-ItemProperty $dwm -Name AccentColor -Value (ConvertTo-Abgr $themeConfig.Accent) -Type DWord
  Set-ItemProperty $dwm -Name ColorPrevalence -Value ([int][bool]$themeConfig.AccentOnTitleBars) -Type DWord
  Set-ItemProperty $personalize -Name ColorPrevalence -Value ([int][bool]$themeConfig.AccentOnTaskbar) -Type DWord

  # Settings > Personalization > Taskbar > Taskbar size: Small. Applies the
  # next time Explorer starts (sign out and in).
  Set-ItemProperty $advanced -Name TaskbarSize -Value 1 -Type DWord

  # The theme's wallpaper, scaled to fill the screen, on the desktop colour.
  $wallpaper = Join-Path ([Environment]::GetFolderPath('MyPictures')) $themeConfig.Wallpaper
  Install-File "$repo\wallpapers\$($themeConfig.Wallpaper)" $wallpaper

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
  $r, $g, $b = ConvertTo-Rgb $themeConfig.DesktopColor
  Set-ItemProperty 'HKCU:\Control Panel\Colors' -Name Background -Value "$r $g $b"
  [SetupDesktop]::SetSysColors(1, @(1), @([int]$r + 256 * $g + 65536 * $b)) | Out-Null  # COLOR_DESKTOP
  Set-ItemProperty $desktop -Name WallpaperStyle -Value '10'  # Fill
  Set-ItemProperty $desktop -Name TileWallpaper -Value '0'
  [SetupDesktop]::SystemParametersInfo(0x14, 0, $wallpaper, 3) | Out-Null  # SPI_SETDESKWALLPAPER

  [SetupDesktop]::Broadcast('ImmersiveColorSet')
  [SetupDesktop]::Broadcast('WindowsThemeElement')

  $taskbarChanged = (& $taskbarValues) -ne $taskbarBefore
  if ($RestartExplorer -or $taskbarChanged) {
    $restart = $RestartExplorer -or ($ask -and [Environment]::UserInteractive -and
      (Read-Choice 'Restart Explorer now so the taskbar picks up the change? Open File Explorer windows will close.' @('yes', 'no') 'yes') -eq 'yes')
    if ($restart) {
      # Stop only the Explorer process that owns the taskbar; Windows starts
      # the shell again by itself.
      Add-Type -Name Taskbar -Namespace SetupDesktop -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
'@
      $shellPid = 0
      [SetupDesktop.Taskbar]::GetWindowThreadProcessId([SetupDesktop.Taskbar]::FindWindow('Shell_TrayWnd', $null), [ref]$shellPid) | Out-Null
      if ($shellPid) { Stop-Process -Id $shellPid -Force }
      Start-Sleep 5
      if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
      Write-Host '    Explorer restarted.'
    } else {
      Write-Host '    Sign out and in (or rerun with -RestartExplorer) for the taskbar to change.'
    }
  }
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
