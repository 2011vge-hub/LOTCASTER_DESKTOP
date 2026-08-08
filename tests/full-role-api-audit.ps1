$ErrorActionPreference = "Stop"

function Assert($Condition, $Message) {
  if (-not $Condition) { throw $Message }
}

function Invoke-Api($Uri, $Method = "GET", $Body = $null, $Session = $null, [int[]]$Expected = @(200)) {
  $params = @{
    Uri = $Uri
    Method = $Method
    UseBasicParsing = $true
    ErrorAction = "Stop"
  }
  if ($Session) { $params.WebSession = $Session }
  if ($null -ne $Body) {
    $params.ContentType = "application/json"
    $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
  }
  try {
    $response = Invoke-WebRequest @params
    $status = [int]$response.StatusCode
    $content = if ($response.Content) {
      try { $response.Content | ConvertFrom-Json } catch { $response.Content }
    } else { $null }
  } catch {
    if (-not $_.Exception.Response) { throw }
    $status = [int]$_.Exception.Response.StatusCode
    $reader = [IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
    $raw = $reader.ReadToEnd()
    $content = if ($raw) { $raw | ConvertFrom-Json } else { $null }
  }
  Assert ($Expected -contains $status) "Unexpected HTTP $status from $Method $Uri"
  return [ordered]@{ status = $status; content = $content }
}

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$auditRoot = Join-Path ([IO.Path]::GetTempPath()) ("lotcaster-role-audit-" + [Guid]::NewGuid().ToString("N"))
$auditRoot = [IO.Path]::GetFullPath($auditRoot)
Assert ($auditRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))) "Audit directory escaped the temporary folder."
$port = Get-Random -Minimum 5230 -Maximum 5790
$base = "http://127.0.0.1:$port"
$process = $null

try {
  New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
  Copy-Item (Join-Path $sourceRoot "Start-InventoryTool.ps1") $auditRoot
  Copy-Item (Join-Path $sourceRoot "public") $auditRoot -Recurse
  New-Item -ItemType Directory -Force -Path (Join-Path $auditRoot "data") | Out-Null

  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = "powershell.exe"
  $start.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$auditRoot\Start-InventoryTool.ps1`" -Port $port"
  $start.WorkingDirectory = $auditRoot
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $previousAuthMode = $env:LOTCASTER_AUTH_MODE
  $env:LOTCASTER_AUTH_MODE = "local"
  try {
    $process = [Diagnostics.Process]::Start($start)
  } finally {
    $env:LOTCASTER_AUTH_MODE = $previousAuthMode
  }

  $ready = $false
  foreach ($attempt in 1..40) {
    Start-Sleep -Milliseconds 250
    try {
      $status = Invoke-WebRequest "$base/api/auth/status" -UseBasicParsing -TimeoutSec 1
      if ($status.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
  }
  Assert $ready "Temporary LotCaster server did not start."
  Invoke-Api "$base/" "GET" $null $null @(200) | Out-Null
  Invoke-Api "$base/%2e%2e/data/auth.json" "GET" $null $null @(403, 404) | Out-Null

  $ownerSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
  $setup = Invoke-Api "$base/api/auth/setup" "POST" @{
    name = "Audit Owner"; email = "owner.audit@example.com"; password = "OwnerAudit#2026"
  } $ownerSession
  Assert ($setup.content.user.role -eq "owner") "Owner setup returned the wrong role."

  $team = Invoke-Api "$base/api/team/users" "POST" @{
    name = "Audit Manager"; email = "manager.audit@example.com"; role = "manager"; password = "ManagerAudit#2026"
  } $ownerSession
  $team = Invoke-Api "$base/api/team/users" "POST" @{
    name = "Audit Sales"; email = "sales.audit@example.com"; role = "salesperson"; password = "SalesAudit#2026"
  } $ownerSession
  $salesUser = @($team.content.users) | Where-Object role -eq "salesperson" | Select-Object -First 1
  Assert $salesUser "Salesperson creation failed."

  $manual = Invoke-Api "$base/api/manual" "POST" @{
    dealershipName = "Audit Dealer"
    inventoryUrl = "https://example.com/used"
    docFee = 789
    vehicle = @{
      title = "2024 Audit Motors Test SUV"
      price = 25000
      mileage = 1000
      vin = "1AUDITTEST0000001"
      stock = "AUDIT-1"
      image = "https://images.example.com/vehicles/audit-1.jpg"
      bodyType = "suv"
    }
  } $ownerSession
  $vehicle = @($manual.content.vehicles) | Select-Object -First 1
  Assert $vehicle "Manual vehicle creation failed."
  Assert (-not $vehicle.priceVerifiedAt) "Manual inventory was incorrectly marked price-verified."

  $assignment = Invoke-Api "$base/api/team/assign" "POST" @{
    vehicleId = $vehicle.id; userId = $salesUser.id; dueAt = (Get-Date).AddDays(1).ToString("yyyy-MM-dd")
  } $ownerSession
  Assert ($assignment.content.store.vehicles[0].assignedToId -eq $salesUser.id) "Vehicle assignment was not saved."

  $salesSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
  $salesLogin = Invoke-Api "$base/api/auth/login" "POST" @{
    email = "sales.audit@example.com"; password = "SalesAudit#2026"
  } $salesSession
  Assert ($salesLogin.content.user.role -eq "salesperson") "Salesperson login returned the wrong role."
  $visible = Invoke-Api "$base/api/inventory" "GET" $null $salesSession
  Assert (@($visible.content.vehicles).Count -eq 1) "Salesperson could not see their assigned vehicle."
  Invoke-Api "$base/api/settings" "POST" @{ docFee = 1 } $salesSession @(403) | Out-Null
  Invoke-Api "$base/api/export.csv" "GET" $null $salesSession @(403) | Out-Null
  Invoke-Api "$base/api/facebook-status" "POST" @{ id = $vehicle.id; posted = $true } $salesSession @(409) | Out-Null

  $managerSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
  $managerLogin = Invoke-Api "$base/api/auth/login" "POST" @{
    email = "manager.audit@example.com"; password = "ManagerAudit#2026"
  } $managerSession
  Assert ($managerLogin.content.user.role -eq "manager") "Manager login returned the wrong role."
  Invoke-Api "$base/api/admin/dealers" "GET" $null $managerSession @(403) | Out-Null
  $managerCreate = Invoke-Api "$base/api/team/users" "POST" @{
    name = "Forbidden Manager"; email = "forbidden.manager@example.com"; role = "manager"; password = "Forbidden#2026"
  } $managerSession
  Assert (@($managerCreate.content.users | Where-Object email -eq "forbidden.manager@example.com")[0].role -eq "salesperson") "A dealership manager created a peer manager."

  $deactivate = Invoke-Api "$base/api/team/user-status" "POST" @{
    id = $salesUser.id; status = "inactive"
  } $ownerSession
  Assert (@($deactivate.content.users | Where-Object id -eq $salesUser.id)[0].status -eq "inactive") "Salesperson deactivation failed."
  Invoke-Api "$base/api/auth/login" "POST" @{
    email = "sales.audit@example.com"; password = "SalesAudit#2026"
  } ([Microsoft.PowerShell.Commands.WebRequestSession]::new()) @(401) | Out-Null

  Write-Host "Full role/API audit passed."
} finally {
  if ($process -and -not $process.HasExited) { $process.Kill() }
  if (Test-Path -LiteralPath $auditRoot) {
    $resolved = [IO.Path]::GetFullPath($auditRoot)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and $resolved -like "*lotcaster-role-audit-*") {
      Remove-Item -LiteralPath $resolved -Recurse -Force
    }
  }
}
