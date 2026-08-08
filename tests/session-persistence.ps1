$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\Start-InventoryTool.ps1" -NoListen

$previousFile = $HostedSessionsFile
$HostedSessionsFile = Join-Path $PSScriptRoot "test-hosted-sessions.dat"
try {
  if (Test-Path $HostedSessionsFile) { Remove-Item -LiteralPath $HostedSessionsFile -Force }
  $HostedSessions.Clear()
  $token = New-HostedSession ([pscustomobject]@{
    access_token = "test-access-token"
    refresh_token = "test-refresh-token"
    expires_in = 3600
  }) $true
  if (-not (Test-Path $HostedSessionsFile)) { throw "Encrypted hosted-session file was not created." }
  $HostedSessions.Clear()
  Load-HostedSessions
  if (-not $HostedSessions.ContainsKey($token)) { throw "Remembered hosted session did not survive reload." }
  if ([string]$HostedSessions[$token].refreshToken -ne "test-refresh-token") { throw "Remembered refresh token was not restored." }
  Write-Host "Hosted session persistence checks passed."
} finally {
  $HostedSessions.Clear()
  if (Test-Path $HostedSessionsFile) { Remove-Item -LiteralPath $HostedSessionsFile -Force }
  $HostedSessionsFile = $previousFile
}
