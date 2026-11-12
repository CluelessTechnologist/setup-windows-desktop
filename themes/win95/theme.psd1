# Windows 95, matching the win95 theme of setup-desktop-environment
# (Base16 Windows 95 by Fergus Collins, modified by CluelessTechnologist).
@{
  Description = 'Windows 95: grey bevelled bar, navy focus and title bars'

  # GlazeWM tab bars and window borders (sway's client.* colours).
  Placeholders = @{
    tab_font_family = 'Cascadia Mono'
    tab_font_size = '12px'
    tab_focused_background = '#001f7e'
    tab_focused_border = '#ffffff'
    tab_focused_text = '#327c7e'
    tab_focused_inactive_background = '#1c1c1c'
    tab_focused_inactive_border = '#1c1c1c'
    tab_focused_inactive_text = '#ffffff'
    tab_unfocused_background = '#383838'
    tab_unfocused_border = '#1c1c1c'
    tab_unfocused_text = '#ffffff'
    focused_border = '#001f7e'
    other_border = '#1c1c1c'
  }

  FlowTheme = 'Win95'
  FlowFont = 'Microsoft Sans Serif'

  # Light apps with navy title bars, like Windows 95. The system is in dark
  # mode only because Windows shows the accent on the taskbar only then: the
  # taskbar and Start get the 6th palette shade, Win95 grey #7e7e7e (with
  # white text and icons).
  AppsDarkMode = $false
  SystemDarkMode = $true
  AccentPalette = @('#c0c0ff', '#8080ff', '#4040c0', '#000080', '#a0a0a0', '#7e7e7e', '#5e5e5e', '#404040')
  Accent = '#000080'
  StartColor = '#7e7e7e'
  AccentOnTaskbar = $true
  AccentOnTitleBars = $true
  DesktopColor = '#008080'
  Wallpaper = 'wallpaper_default_win95.jpg'
}
