Option Explicit

Dim shell, fso, root, healthUrl, appUrl, command, attempt
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
healthUrl = "http://127.0.0.1:5173/api/auth/status"
appUrl = "http://127.0.0.1:5173/?app=lotcaster-market-v1"

If Not IsAppReady(healthUrl) Then
  command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & root & "\Start-LotCaster-Market.ps1"" -Port 5173"
  shell.Run command, 0, False

  For attempt = 1 To 40
    WScript.Sleep 250
    If IsAppReady(healthUrl) Then Exit For
  Next
End If

If IsAppReady(healthUrl) Then
  shell.Run appUrl, 1, False
Else
  MsgBox "LotCaster could not start. Return to Codex and report this message.", vbExclamation, "LotCaster"
End If

Function IsAppReady(url)
  On Error Resume Next
  Dim http
  Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
  http.setTimeouts 1000, 1000, 1000, 1000
  http.Open "GET", url, False
  http.Send
  IsAppReady = (Err.Number = 0 And http.Status = 200)
  Err.Clear
  On Error GoTo 0
End Function
