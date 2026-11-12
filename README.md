# Windows Desktop Bootstrap with PowerShell

## About

A Windows 11 take on [setup-desktop-environment](https://github.com/CluelessTechnologist/setup-desktop-environment), which bootstraps sway and i3 desktops with Ansible. When I have to use Windows I want the same workflow: a tiling window manager with tabs, a bar at the top, a keyboard launcher and a uniform look, with the same gruvbox and Windows 95 themes. One script sets that up, so a new machine looks and works the same in a few minutes.

Everything is per user. The script doesn't patch Windows, doesn't disable anything and keeps a backup of every config file it replaces.

| Component | Sway setup | This repo |
|---|---|---|
| Window manager | sway, `workspace_layout tabbed` | [GlazeWM](https://github.com/glzr-io/glazewm), using a [fork with sway-style tabs](https://github.com/CluelessTechnologist/glazewm) |
| Bar | waybar | [Zebar](https://github.com/glzr-io/zebar), styled like the waybar |
| Launcher | bemenu (`mod+d`) | [Flow Launcher](https://github.com/Flow-Launcher/Flow.Launcher) (`alt+d`) |
| Terminal colours | alacritty | Windows Terminal (colour scheme per theme) |
| Modifier | `Mod4` (Windows key) | `alt`, optionally also the left Windows key ([AutoHotkey](https://www.autohotkey.com/)) |
| Themes | gruvbox, win95 | gruvbox, win95: bar, tabs, launcher, terminal, light/dark mode, accent colours, wallpaper |

## Supported OSes

* Windows 11 x64 (tested on 26H2)

Windows 10 works for the most part, but window borders and the small taskbar need Windows 11.

## Quick start

In your own desktop session (not over SSH):

```powershell
git clone https://github.com/CluelessTechnologist/setup-windows-desktop
cd setup-windows-desktop
powershell -ExecutionPolicy Bypass -File .\deploy.ps1
```

Like the Ansible playbooks, the script asks a few questions first, then shows a summary and asks before it changes anything:

```
    gruvbox - Gruvbox dark: blue focus, yellow text, forest wallpaper
    win95 - Windows 95: grey bevelled bar, navy focus and title bars
Choose theme (gruvbox/win95) [gruvbox]:
Make the left Windows key act as Alt with AutoHotkey? (yes/no) [no]:
Install Firefox (started with alt+f1)? (yes/no) [yes]:
```

Without git, download the repository as a zip and run `deploy.ps1` from the unpacked folder. `-ExecutionPolicy Bypass` only applies to this one run; the machine's execution policy isn't changed.

To see what would happen without changing anything, add `-WhatIf`. Run the script again at any time to switch theme; files that are already right are left alone.

The taskbar only picks up light/dark mode, its size and colours when Explorer starts, so the script offers to restart Explorer when those changed. If you say no, sign out and back in later.

## Options

| Parameter | Default | |
|---|---|---|
| `-Theme gruvbox\|win95` | asked | Which theme to deploy (a folder under `themes/`). |
| `-KeyRemap None\|AutoHotkey` | asked | `AutoHotkey` also installs AutoHotkey and makes the left Windows key act as Alt. The Start menu stays on `ctrl+esc` and the right Windows key. |
| `-Firefox Yes\|No` | asked | Install Firefox, which `alt+f1` starts. |
| `-Unattended` | | Don't ask anything: `gruvbox`, `None` and `Yes` unless given. |
| `-Skip Apps,GlazeWM,Dotfiles,Theme,Autostart` | none | Leaves out steps, e.g. `-Skip Theme` to keep your current look. |
| `-GlazeWMVersion v3.10.1-tabs.2` | `latest` | A specific release of the fork. |
| `-GlazeWMRepository owner/repo` | `CluelessTechnologist/glazewm` | Installs GlazeWM from another fork. Its releases need a `*-x64.zip` and a `SHA256SUMS` file. |
| `-InstallDir <path>` | `%LOCALAPPDATA%\Programs\glazewm-tabs` | Where GlazeWM is unpacked. |
| `-NoStart` | | Don't start GlazeWM and Flow Launcher at the end. |
| `-RestartExplorer` | asked | Restart Explorer without asking, so the taskbar picks up light/dark mode, size and colours. Without it, the script asks when those changed. Open File Explorer windows close. |

## What the script changes

So you know exactly what you're running:

* **Apps (winget):** `Microsoft.VCRedist.2015+.x64` (the Visual C++ runtime, which GlazeWM needs), `Git.Git`, `vim.vim`, `glzr-io.zebar`, `Flow-Launcher.Flow-Launcher`, plus `Mozilla.Firefox` with `-Firefox Yes` and `AutoHotkey.AutoHotkey` with `-KeyRemap AutoHotkey`. Each one is skipped if it's already installed, also when it was installed with a normal installer instead of winget: the script looks for the program file, its "App Paths" registry entry and its command before asking winget. Most of them install for all users, so Windows may ask for admin rights.
* **PATH:** the Vim folder (`%LOCALAPPDATA%\Programs\Vim`, or e.g. `C:\Program Files\Vim\vim92` for an all-users install) is added to your user PATH, so `vim` works in any new terminal. An older Vim entry is replaced, and other entries are kept as they are.
* **GlazeWM:** the latest release zip of the fork, from GitHub. The download is checked against the release's `SHA256SUMS` before it's unpacked to `-InstallDir`. The binaries are built by the fork's [release workflow](https://github.com/CluelessTechnologist/glazewm/blob/fork/.github/workflows/fork-release.yaml) and are **not code signed**.
* **Config files:**
  * `~\.glzr\glazewm\config.yaml`, with the theme's colours filled in.
  * `~\.glzr\zebar\settings.json` and `~\.glzr\zebar\desktop-bar\`
  * `%APPDATA%\FlowLauncher\Themes\Gruvbox.xaml` or `Win95.xaml`, and a few keys in `%APPDATA%\FlowLauncher\Settings\Settings.json` (hotkey, theme, font, and skipping the first-run welcome guide). Your other Flow settings are kept.
  * A Windows Terminal fragment in `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\setup-windows-desktop\` that adds the theme's colour scheme to the built-in PowerShell and Command Prompt profiles. Your `settings.json` isn't touched.
  * `~\.config\autohotkey\lwin-to-alt.ahk` with `-KeyRemap AutoHotkey`.
* **Look (registry, `HKCU` only):** light or dark mode, the accent colour palette, accent on Start and taskbar (gruvbox) or on title bars (win95), small taskbar, desktop colour, and the theme's wallpaper copied to your Pictures folder.
* **Autostart:** shortcuts in your Startup folder (`shell:startup`) for GlazeWM, Flow Launcher and the key remap. GlazeWM starts Zebar itself.

Every file that gets replaced is first copied to `%LOCALAPPDATA%\setup-windows-desktop\backup\<timestamp>\`.

### Undoing it

1. Delete the shortcuts in `shell:startup` and exit GlazeWM (`alt+shift+e`).
2. Delete `%LOCALAPPDATA%\Programs\glazewm-tabs`.
3. Copy the files back from the backup folder, or delete the config files listed above.
4. Optionally uninstall the apps: `winget uninstall glzr-io.zebar` (and Flow Launcher, AutoHotkey).
5. Pick your old theme and wallpaper in Settings > Personalization.

## Keybindings

Like the sway config, with `alt` as the modifier:

| Keys | Action |
|---|---|
| `alt+h/j/k/l` or arrows | Focus left/down/up/right |
| `alt+shift+h/j/k/l` or arrows | Move window |
| `alt+1` ... `alt+0` | Workspace 1-10 |
| `alt+shift+1` ... `alt+shift+0` | Move window to workspace (focus stays) |
| `alt+w` / `alt+t` | Tabbed layout |
| `alt+e` / `alt+v` | Toggle split direction (a tabbed container goes back to tiles) |
| `alt+f` | Fullscreen |
| `alt+shift+space` | Toggle floating |
| `alt+space` | Cycle focus between tiling, floating and fullscreen windows |
| `alt+r` | Resize mode (`h/j/k/l`, `esc` to leave) |
| `alt+enter` | Windows Terminal |
| `alt+d` | Flow Launcher |
| `alt+f1` / `alt+f2` | Firefox / File Explorer |
| `alt+shift+q` | Close window |
| `alt+shift+r` | Reload config |
| `alt+shift+e` | Exit GlazeWM |

New workspaces start tabbed. The full list is in [dotfiles/glazewm/config.yaml](dotfiles/glazewm/config.yaml).

## Corporate laptops

The setup is meant to be light enough for a managed machine: per-user, no services, no Explorer patching. Still, check your company's rules first:

* The GlazeWM binaries are unsigned. AppLocker or WDAC policies can block them, and security software may flag a program that hooks the keyboard and moves windows.
* AutoHotkey is often blocked or flagged. Leave `-KeyRemap` at `None` there, or use [PowerToys Keyboard Manager](https://learn.microsoft.com/windows/powertoys/keyboard-manager) (made by Microsoft) to remap the key.
* GlazeWM can't manage windows that run as administrator, because unsigned builds can't use UIAccess.

## Repository layout

| Path | What |
|---|---|
| `deploy.ps1` | The deploy script |
| `dotfiles/glazewm/` | GlazeWM config, with `{{placeholders}}` for the theme's colours |
| `dotfiles/zebar/` | Zebar settings and the `desktop-bar` (layout only) |
| `dotfiles/flowlauncher/` | Flow Launcher settings that get merged in |
| `dotfiles/autohotkey/` | Left Windows key to Alt |
| `themes/<name>/` | A theme: `theme.psd1` (colours, light/dark, accent, wallpaper) and its bar style, Flow Launcher theme and Windows Terminal scheme |
| `wallpapers/` | Wallpapers |

To add a theme, copy `themes/gruvbox` to a new folder and change it. The script finds it by its folder name.

## Credits

* [GlazeWM](https://github.com/glzr-io/glazewm) and [Zebar](https://github.com/glzr-io/zebar) by glzr-io (GPL-3.0). The bar in `dotfiles/zebar/desktop-bar/` started from Zebar's starter pack.
* The [gruvbox](https://github.com/morhetz/gruvbox) palette by Pavel Pertsev (MIT).
* The win95 colours are the Base16 Windows 95 scheme by Fergus Collins, modified for setup-desktop-environment. The win95 terminal colours are the Hyper scheme from [alacritty-theme](https://github.com/alacritty/alacritty-theme).
* The wallpapers are the same ones as in [setup-desktop-environment](https://github.com/CluelessTechnologist/setup-desktop-environment).

## License

[MIT](LICENSE), except for two files derived from GPL-3.0 projects, which stay under [GPL-3.0](LICENSE-GPL-3.0.md):

* `dotfiles/glazewm/config.yaml`, based on GlazeWM's sample config.
* `dotfiles/zebar/desktop-bar/` and `themes/*/zebar.css`, based on Zebar's starter pack.
