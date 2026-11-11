# Gruvbox dark, matching the gruvbox theme of setup-desktop-environment.
@{
  Description = 'Gruvbox dark: blue focus, yellow text, forest wallpaper'

  # GlazeWM tab bars and window borders (sway's client.* colours).
  Placeholders = @{
    tab_font_family = 'Cascadia Mono'
    tab_font_size = '12px'
    tab_focused_background = '#458588'
    tab_focused_border = '#458588'
    tab_focused_text = '#1d2021'
    tab_focused_inactive_background = '#1d2021'
    tab_focused_inactive_border = '#1d2021'
    tab_focused_inactive_text = '#d79921'
    tab_unfocused_background = '#1d2021'
    tab_unfocused_border = '#1d2021'
    tab_unfocused_text = '#d79921'
    focused_border = '#458588'
    other_border = '#1d2021'
  }

  # Flow Launcher: theme name (themes\<name>\flowlauncher.xaml is installed
  # under this name) and font.
  FlowTheme = 'Gruvbox'
  FlowFont = 'Cascadia Mono'

  # Windows look.
  DarkMode = $true
  # Accent palette from lightest to darkest (8 shades), and the accent.
  AccentPalette = @('#fbf1c7', '#fabd2f', '#fabd2f', '#d79921', '#504945', '#3c3836', '#282828', '#1d2021')
  Accent = '#d79921'
  StartColor = '#3c3836'
  # Accent colour on Start and taskbar (dark mode only).
  AccentOnTaskbar = $true
  # Accent colour on window title bars.
  AccentOnTitleBars = $false
  DesktopColor = '#282828'
  Wallpaper = 'wallpaper_default_gruvbox.jpg'
}
