' start-hidden.vbs - run a command with no visible window (no console, no flash).
' Usage:  wscript.exe "start-hidden.vbs" "C:\path\to\script.cmd"
'
' Used from the Windows Startup folder so every service (gateway, bridges,
' logon self-heal) starts fully invisible at login. Window style 0 = hidden;
' bWaitOnReturn = False means wscript exits immediately and the command keeps
' running on its own.
Option Explicit
Dim sh, target
If WScript.Arguments.Count < 1 Then
  WScript.Echo "usage: wscript start-hidden.vbs <path-to-cmd>"
  WScript.Quit 1
End If
Set sh = CreateObject("WScript.Shell")
target = WScript.Arguments(0)
sh.Run """" & target & """", 0, False
