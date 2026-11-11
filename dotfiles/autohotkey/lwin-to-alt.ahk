; Makes the left Windows key act as left Alt, so the alt+... GlazeWM
; bindings work on the Windows key like sway's Mod4. The real Alt keys and
; the right Windows key are unchanged; ctrl+esc still opens Start.
; Installed to ~\.config\autohotkey\ and started at logon by deploy.ps1 -KeyRemap AutoHotkey.
#Requires AutoHotkey v2.0
#SingleInstance Force

LWin::LAlt
