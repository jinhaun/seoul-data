' Runs a PowerShell script with no visible window (used by Task Scheduler).
' Usage: wscript.exe run_hidden.vbs "C:\path\to\script.ps1"
If WScript.Arguments.Count = 0 Then WScript.Quit 1
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """"
WScript.Quit sh.Run(cmd, 0, True)
