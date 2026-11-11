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

  # Light mode with navy title bars, like Windows 95.
  DarkMode = $false
  AccentPalette = @('#c0c0ff', '#8080ff', '#4040c0', '#000080', '#000070', '#000060', '#000050', '#000040')
  Accent = '#000080'
  StartColor = '#000080'
  AccentOnTaskbar = $false
  AccentOnTitleBars = $true
  DesktopColor = '#008080'
  Wallpaper = 'wallpaper_default_win95.jpg'
}
