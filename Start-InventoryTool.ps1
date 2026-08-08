param(
  [int]$Port = 5173,
  [switch]$NoListen
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Web
Add-Type -AssemblyName System.Security
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PublicDir = Join-Path $Root "public"
$DataDir = Join-Path $Root "data"
$StoreFile = Join-Path $DataDir "inventory.json"
$SettingsFile = Join-Path $DataDir "settings.json"
$AutoCsvFile = Join-Path $DataDir "walker-auto-import.csv"
$AuthFile = Join-Path $DataDir "auth.json"
$TeamFile = Join-Path $DataDir "team.json"
$DealerAccessFile = Join-Path $DataDir "dealer-access.json"
$MasterMarkerFile = Join-Path $DataDir ".lotcaster-master"
$Sessions = @{}
$HostedSessions = @{}
$HostedSetupMarkerFile = Join-Path $DataDir ".lotcaster-hosted-setup"
$HostedSessionsFile = Join-Path $DataDir "hosted-sessions.dat"
$SupabaseUrl = if ($env:LOTCASTER_SUPABASE_URL) { $env:LOTCASTER_SUPABASE_URL.TrimEnd("/") } else { "https://onnhjezwunjxrngjybbf.supabase.co" }
$SupabasePublishableKey = if ($env:LOTCASTER_SUPABASE_PUBLISHABLE_KEY) { $env:LOTCASTER_SUPABASE_PUBLISHABLE_KEY } else { "sb_publishable_x7-LPtuNbKE9gb0PPsFe4A_WagTZ4eI" }
$HostedAuthEnabled = $env:LOTCASTER_AUTH_MODE -ne "local"

$DefaultSettings = [ordered]@{
  dealershipName = "Walker Chevrolet"
  inventoryUrl = "https://www.autotrader.com/car-dealers/nashville-tn/100009092/walker-chevrolet?listingType=USED"
  docFee = ""
  sourcePriceIncludesDocFee = $false
  city = ""
  listingFooter = "Message me for current availability, mileage, and appointment details. Vehicle availability and pricing can change."
  requestDelayMs = 650
}

$MimeTypes = @{
  ".html" = "text/html; charset=utf-8"
  ".js" = "text/javascript; charset=utf-8"
  ".css" = "text/css; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".svg" = "image/svg+xml"
  ".png" = "image/png"
  ".ico" = "image/x-icon"
  ".webmanifest" = "application/manifest+json; charset=utf-8"
}

function Initialize-Data {
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  if (-not (Test-Path $SettingsFile)) {
    $DefaultSettings | ConvertTo-Json -Depth 8 | Set-Content -Path $SettingsFile -Encoding UTF8
  }
  if (-not (Test-Path $StoreFile)) {
    Empty-Store | ConvertTo-Json -Depth 8 | Set-Content -Path $StoreFile -Encoding UTF8
  }
  if (-not (Test-Path $TeamFile)) {
    [ordered]@{ users = @(); activity = @() } | ConvertTo-Json -Depth 8 | Set-Content -Path $TeamFile -Encoding UTF8
  }
  Migrate-InventoryData
}

function Empty-Store {
  [ordered]@{ scrapedAt = $null; sourceUrl = ""; warnings = @(); importResult = $null; autoCsvAvailable = $false; vehicles = @(); removed = @() }
}

function Read-JsonFile($Path, $Fallback) {
  try {
    if (Test-Path $Path) {
      return Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
  } catch {}
  return $Fallback
}

function Write-JsonFile($Path, $Value) {
  $Value | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding UTF8
}

function New-RandomBytes([int]$Count) {
  $bytes = New-Object byte[] $Count
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return $bytes
}

function Get-PasswordHash($Password, $SaltBytes) {
  $derive = [Security.Cryptography.Rfc2898DeriveBytes]::new(
    [string]$Password,
    [byte[]]$SaltBytes,
    120000,
    [Security.Cryptography.HashAlgorithmName]::SHA256
  )
  try { return $derive.GetBytes(32) } finally { $derive.Dispose() }
}

function Test-SecureEqual($Left, $Right) {
  if ($Left.Length -ne $Right.Length) { return $false }
  $difference = 0
  for ($i = 0; $i -lt $Left.Length; $i++) { $difference = $difference -bor ($Left[$i] -bxor $Right[$i]) }
  return $difference -eq 0
}

function New-Session($Email) {
  $token = [Convert]::ToBase64String((New-RandomBytes 32)).TrimEnd("=").Replace("+", "-").Replace("/", "_")
  $Sessions[$token] = [ordered]@{ email = $Email; expiresAt = (Get-Date).ToUniversalTime().AddHours(12) }
  return $token
}

function Get-CookieValue($Request, $Name) {
  $cookie = [string]$Request.headers["cookie"]
  $match = [regex]::Match($cookie, "(?:^|;\s*)$([regex]::Escape($Name))=([^;]+)")
  if (-not $match.Success) { return "" }
  return $match.Groups[1].Value
}

function Invoke-SupabaseRequest($Path, $Method = "GET", $Body = $null, $AccessToken = "") {
  $headers = @{ apikey = $SupabasePublishableKey }
  if ($AccessToken) { $headers["Authorization"] = "Bearer $AccessToken" }
  $params = @{
    Uri = "$SupabaseUrl$Path"
    Method = $Method
    Headers = $headers
    UseBasicParsing = $true
    ErrorAction = "Stop"
  }
  if ($null -ne $Body) {
    $params["ContentType"] = "application/json"
    $params["Body"] = ($Body | ConvertTo-Json -Depth 12 -Compress)
  }
  try {
    $response = Invoke-WebRequest @params
    if (-not $response.Content) { return [pscustomobject]@{} }
    return $response.Content | ConvertFrom-Json
  } catch {
    $message = $_.Exception.Message
    try {
      $stream = $_.Exception.Response.GetResponseStream()
      if ($stream) {
        $reader = [IO.StreamReader]::new($stream)
        $errorBody = $reader.ReadToEnd() | ConvertFrom-Json
        if ($errorBody.msg) { $message = [string]$errorBody.msg }
        elseif ($errorBody.error_description) { $message = [string]$errorBody.error_description }
        elseif ($errorBody.message) { $message = [string]$errorBody.message }
      }
    } catch {}
    throw $message
  }
}

function Invoke-HostedAdmin($Request, $Action, $Body = $null) {
  $session = Get-HostedSession $Request
  if (-not $session) { throw "Sign in is required." }
  $payload = [ordered]@{ action = $Action }
  if ($null -ne $Body) {
    foreach ($property in $Body.PSObject.Properties) {
      $payload[$property.Name] = $property.Value
    }
  }
  return Invoke-SupabaseRequest "/functions/v1/lotcaster-admin" "POST" $payload $session.accessToken
}

function Add-LocalInventoryMetrics($HostedTeam) {
  $store = Read-JsonFile $StoreFile (Empty-Store)
  foreach ($user in @($HostedTeam.users)) {
    $assigned = @($store.vehicles | Where-Object { [string]$_.assignedToId -eq [string]$user.id })
    $user.assigned = $assigned.Count
    $user.prepared = @($assigned | Where-Object { $_.preparedAt }).Count
    $user.posted = @($assigned | Where-Object { $_.facebookPostedAt }).Count
    $user.overdue = @($assigned | Where-Object {
      $_.assignmentDueAt -and -not $_.facebookPostedAt -and ([DateTime]$_.assignmentDueAt) -lt (Get-Date)
    }).Count
  }
  $HostedTeam.totals = [ordered]@{
    assigned = @($store.vehicles | Where-Object { $_.assignedToId }).Count
    prepared = @($store.vehicles | Where-Object { $_.preparedAt }).Count
    posted = @($store.vehicles | Where-Object { $_.facebookPostedAt }).Count
    unassigned = @($store.vehicles | Where-Object { -not $_.assignedToId }).Count
  }
  $localActivity = @((Read-TeamData).activity)
  if ($localActivity.Count) {
    $HostedTeam.activity = @($localActivity + @($HostedTeam.activity) | Sort-Object { [DateTime]$_.createdAt } -Descending | Select-Object -First 100)
  }
  return $HostedTeam
}

function Save-HostedSessions {
  if (-not $HostedAuthEnabled) { return }
  try {
    $active = @()
    $now = (Get-Date).ToUniversalTime()
    foreach ($entry in $HostedSessions.GetEnumerator()) {
      if ([DateTime]$entry.Value.absoluteExpiresAt -gt $now) {
        $active += [ordered]@{
          token = [string]$entry.Key
          accessToken = [string]$entry.Value.accessToken
          refreshToken = [string]$entry.Value.refreshToken
          accessExpiresAt = ([DateTime]$entry.Value.accessExpiresAt).ToString("o")
          absoluteExpiresAt = ([DateTime]$entry.Value.absoluteExpiresAt).ToString("o")
          rememberDevice = [bool]$entry.Value.rememberDevice
        }
      }
    }
    $plain = [Text.Encoding]::UTF8.GetBytes(($active | ConvertTo-Json -Depth 6 -Compress))
    $entropy = [Text.Encoding]::UTF8.GetBytes("LotCaster hosted sessions v1")
    $protected = [Security.Cryptography.ProtectedData]::Protect($plain, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($HostedSessionsFile, $protected)
  } catch {
    # Authentication still works for the current process if Windows session
    # persistence is unavailable.
  }
}

function Load-HostedSessions {
  if (-not $HostedAuthEnabled -or -not (Test-Path $HostedSessionsFile)) { return }
  try {
    $entropy = [Text.Encoding]::UTF8.GetBytes("LotCaster hosted sessions v1")
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
      [IO.File]::ReadAllBytes($HostedSessionsFile),
      $entropy,
      [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    $entries = @(([Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json))
    $now = (Get-Date).ToUniversalTime()
    foreach ($entry in $entries) {
      $absoluteExpiresAt = [DateTime]::Parse([string]$entry.absoluteExpiresAt).ToUniversalTime()
      if ($absoluteExpiresAt -le $now) { continue }
      $HostedSessions[[string]$entry.token] = [ordered]@{
        accessToken = [string]$entry.accessToken
        refreshToken = [string]$entry.refreshToken
        accessExpiresAt = [DateTime]::Parse([string]$entry.accessExpiresAt).ToUniversalTime()
        absoluteExpiresAt = $absoluteExpiresAt
        rememberDevice = [bool]$entry.rememberDevice
      }
    }
  } catch {
    # Ignore unreadable or obsolete encrypted session state.
  }
}

function New-HostedSession($AuthResponse, [bool]$RememberDevice) {
  if (-not $AuthResponse.access_token -or -not $AuthResponse.refresh_token) { return $null }
  $token = [Convert]::ToBase64String((New-RandomBytes 32)).TrimEnd("=").Replace("+", "-").Replace("/", "_")
  $now = (Get-Date).ToUniversalTime()
  $HostedSessions[$token] = [ordered]@{
    accessToken = [string]$AuthResponse.access_token
    refreshToken = [string]$AuthResponse.refresh_token
    userId = $(if ($AuthResponse.user -and $AuthResponse.user.id) { [string]$AuthResponse.user.id } else { "" })
    accessExpiresAt = $now.AddSeconds([Math]::Max(60, [int]$AuthResponse.expires_in - 60))
    absoluteExpiresAt = $now.AddHours($(if ($RememberDevice) { 24 * 30 } else { 12 }))
    rememberDevice = $RememberDevice
  }
  Save-HostedSessions
  return $token
}

function Remove-HostedSessionsForUser($UserId) {
  if (-not $UserId) { return }
  $remove = @()
  foreach ($entry in $HostedSessions.GetEnumerator()) {
    if ([string]$entry.Value.userId -eq [string]$UserId) { $remove += [string]$entry.Key }
  }
  foreach ($token in $remove) { $HostedSessions.Remove($token) | Out-Null }
  if ($remove.Count) { Save-HostedSessions }
}

function Get-HostedSession($Request) {
  $token = Get-CookieValue $Request "lotcaster_session"
  if (-not $token -or -not $HostedSessions.ContainsKey($token)) { return $null }
  $session = $HostedSessions[$token]
  $now = (Get-Date).ToUniversalTime()
  if ($session.absoluteExpiresAt -le $now) {
    $HostedSessions.Remove($token) | Out-Null
    Save-HostedSessions
    return $null
  }
  if ($session.accessExpiresAt -le $now) {
    try {
      $refreshed = Invoke-SupabaseRequest "/auth/v1/token?grant_type=refresh_token" "POST" @{ refresh_token = $session.refreshToken }
      $session.accessToken = [string]$refreshed.access_token
      $session.refreshToken = [string]$refreshed.refresh_token
      $session.accessExpiresAt = $now.AddSeconds([Math]::Max(60, [int]$refreshed.expires_in - 60))
      Save-HostedSessions
    } catch {
      $HostedSessions.Remove($token) | Out-Null
      Save-HostedSessions
      return $null
    }
  }
  return [ordered]@{ token = $token; accessToken = $session.accessToken; rememberDevice = $session.rememberDevice }
}

function Get-HostedUser($Request) {
  if ($Request.hostedUser) { return $Request.hostedUser }
  $session = Get-HostedSession $Request
  if (-not $session) { return $null }
  try {
    $authUser = Invoke-SupabaseRequest "/auth/v1/user" "GET" $null $session.accessToken
    $profileRows = @(Invoke-SupabaseRequest "/rest/v1/profiles?id=eq.$($authUser.id)&select=id,email,display_name,state,must_change_password" "GET" $null $session.accessToken)
    $profile = $profileRows | Select-Object -First 1
    if (-not $profile -or [string]$profile.state -ne "active") { return $null }
    $platformRows = @(Invoke-SupabaseRequest "/rest/v1/platform_memberships?user_id=eq.$($authUser.id)&select=role" "GET" $null $session.accessToken)
    $dealerRows = @(Invoke-SupabaseRequest "/rest/v1/dealership_memberships?user_id=eq.$($authUser.id)&state=eq.active&select=dealership_id,role" "GET" $null $session.accessToken)
    $platform = $platformRows | Select-Object -First 1
    $dealer = $dealerRows | Select-Object -First 1
    $role = if ($platform) { [string]$platform.role } elseif ($dealer) { [string]$dealer.role } else { "unassigned" }
    $user = [ordered]@{
      id = [string]$profile.id
      name = [string]$profile.display_name
      email = [string]$profile.email
      role = $role
      status = [string]$profile.state
      mustChangePassword = [bool]$profile.must_change_password
      dealershipId = $(if ($dealer) { [string]$dealer.dealership_id } else { "" })
      hosted = $true
    }
    $Request.hostedUser = $user
    return $user
  } catch {
    return $null
  }
}

function Get-HostedAuthSummary($Request) {
  $user = Get-HostedUser $Request
  if (-not $user) {
    return [ordered]@{
      setupRequired = -not (Test-Path $HostedSetupMarkerFile)
      authenticated = $false
      loginEmail = "2011vge@gmail.com"
      hosted = $true
    }
  }
  return [ordered]@{
    setupRequired = $false
    authenticated = $true
    hosted = $true
    user = $user
    license = [ordered]@{ status = "active"; plan = "hosted"; expiresAt = $null }
  }
}

function Get-HostedCookieHeader($Token, [bool]$RememberDevice) {
  $header = "lotcaster_session=$Token; HttpOnly; SameSite=Lax; Path=/"
  if ($RememberDevice) { $header += "; Max-Age=2592000" }
  return $header
}

function Get-Session($Request) {
  $cookie = [string]$Request.headers["cookie"]
  $match = [regex]::Match($cookie, "(?:^|;\s*)walker_session=([^;]+)")
  if (-not $match.Success) { return $null }
  $token = $match.Groups[1].Value
  $session = $Sessions[$token]
  if (-not $session) { return $null }
  if ($session.expiresAt -lt (Get-Date).ToUniversalTime()) {
    $Sessions.Remove($token)
    return $null
  }
  return [ordered]@{ token = $token; email = $session.email }
}

function Get-AuthSummary($Request) {
  $auth = Read-JsonFile $AuthFile $null
  if (-not $auth) { return [ordered]@{ setupRequired = $true; authenticated = $false } }
  $session = Get-Session $Request
  if (-not $session) {
    return [ordered]@{
      setupRequired = $false
      authenticated = $false
      loginEmail = $(if ([string]$auth.user.role -eq "master") { $auth.user.email } else { "" })
    }
  }
  $user = Get-UserByEmail $session.email
  if (-not $user -or [string]$user.status -eq "inactive") {
    return [ordered]@{ setupRequired = $false; authenticated = $false; loginEmail = "" }
  }
  return [ordered]@{
    setupRequired = $false
    authenticated = $true
    user = Get-PublicUser $user
    license = $auth.license
  }
}

function Read-TeamData {
  return Read-JsonFile $TeamFile ([ordered]@{ users = @(); activity = @() })
}

function Get-UserByEmail($Email) {
  $email = (Clean-Text $Email).ToLower()
  $auth = Read-JsonFile $AuthFile $null
  if ($auth -and [string]$auth.user.email -eq $email) {
    if (-not $auth.user.id) { Set-ObjectValue $auth.user "id" "owner" }
    if (-not $auth.user.status) { Set-ObjectValue $auth.user "status" "active" }
    return $auth.user
  }
  $team = Read-TeamData
  return @($team.users) | Where-Object { [string]$_.email -eq $email } | Select-Object -First 1
}

function Get-PublicUser($User) {
  return [ordered]@{
    id = [string]$User.id
    name = [string]$User.name
    email = [string]$User.email
    role = [string]$User.role
    status = $(if ($User.status) { [string]$User.status } else { "active" })
  }
}

function Get-CurrentUser($Request) {
  if ($HostedAuthEnabled) { return Get-HostedUser $Request }
  $session = Get-Session $Request
  if (-not $session) { return $null }
  return Get-UserByEmail $session.email
}

function Test-MasterAccess($Request) {
  $user = Get-CurrentUser $Request
  return $user -and [string]$user.role -eq "master"
}

function Test-PlatformDealerAdminAccess($Request) {
  $user = Get-CurrentUser $Request
  return $user -and [string]$user.role -in @("master", "lotcaster_general_manager")
}

function Test-TeamManagerAccess($Request) {
  $user = Get-CurrentUser $Request
  return $user -and [string]$user.role -in @("master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support", "owner", "manager")
}

function Test-VehicleAccess($Request, $Vehicle) {
  $user = Get-CurrentUser $Request
  if (-not $user) { return $false }
  if ([string]$user.role -ne "salesperson") { return $true }
  return [string]$Vehicle.assignedToId -eq [string]$user.id
}

function Get-VisibleStore($Store, $User) {
  if ([string]$User.role -eq "salesperson") {
    $Store.vehicles = @($Store.vehicles | Where-Object { [string]$_.assignedToId -eq [string]$User.id })
    $Store.removed = @($Store.removed | Where-Object { [string]$_.assignedToId -eq [string]$User.id })
  }
  return $Store
}

function Add-TeamActivity($Type, $Vehicle, $User, $Details = "") {
  $team = Read-TeamData
  $entry = [ordered]@{
    id = [Guid]::NewGuid().ToString("N")
    type = $Type
    vehicleId = $(if ($Vehicle) { [string]$Vehicle.id } else { "" })
    vehicleTitle = $(if ($Vehicle) { [string]$Vehicle.title } else { "" })
    userId = $(if ($User) { [string]$User.id } else { "" })
    userName = $(if ($User) { [string]$User.name } else { "" })
    details = Clean-Text $Details
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
  }
  $team.activity = @(@($entry) + @($team.activity) | Select-Object -First 500)
  Write-JsonFile $TeamFile $team
}

function Get-TeamSummary {
  $team = Read-TeamData
  $store = Read-JsonFile $StoreFile (Empty-Store)
  $users = @($team.users | ForEach-Object { Get-PublicUser $_ })
  $members = foreach ($user in $users) {
    $assigned = @($store.vehicles | Where-Object { [string]$_.assignedToId -eq [string]$user.id })
    [ordered]@{
      id = $user.id
      name = $user.name
      email = $user.email
      role = $user.role
      status = $user.status
      assigned = $assigned.Count
      prepared = @($assigned | Where-Object { $_.preparedAt }).Count
      posted = @($assigned | Where-Object { $_.facebookPostedAt }).Count
      overdue = @($assigned | Where-Object { $_.assignmentDueAt -and -not $_.facebookPostedAt -and [datetime]$_.assignmentDueAt -lt (Get-Date).ToUniversalTime() }).Count
      createdAt = (@($team.users) | Where-Object { $_.id -eq $user.id } | Select-Object -First 1).createdAt
    }
  }
  return [ordered]@{
    users = @($members)
    activity = @($team.activity | Select-Object -First 100)
    totals = [ordered]@{
      assigned = @($store.vehicles | Where-Object { $_.assignedToId }).Count
      prepared = @($store.vehicles | Where-Object { $_.preparedAt }).Count
      posted = @($store.vehicles | Where-Object { $_.facebookPostedAt }).Count
      unassigned = @($store.vehicles | Where-Object { -not $_.assignedToId }).Count
    }
  }
}

function Read-DealerAccess {
  return Read-JsonFile $DealerAccessFile ([ordered]@{ dealers = @() })
}

function Set-ObjectValue($Object, $Name, $Value) {
  if ($Object -is [System.Collections.IDictionary]) {
    $Object[$Name] = $Value
  } else {
    $Object | Add-Member -Force -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Clean-Text($Value) {
  if ($null -eq $Value) { return "" }
  $text = [System.Web.HttpUtility]::HtmlDecode([string]$Value)
  return (($text -replace "\s+", " ").Trim())
}

function Clean-Description($Value) {
  if ($null -eq $Value) { return "" }
  $text = [System.Web.HttpUtility]::HtmlDecode([string]$Value) -replace "`r`n?", "`n"
  $lines = @($text -split "`n" | ForEach-Object { ($_ -replace "[\t ]+", " ").Trim() })
  return (($lines -join "`n") -replace "`n{3,}", "`n`n").Trim()
}

function Clean-Price($Value) {
  $text = Clean-Text $Value
  if (-not $text) { return "" }
  $match = [regex]::Match($text, "[\d,.]+")
  if ($match.Success) { return "$" + ($match.Value -replace "\.00$", "") }
  return $text
}

function Clean-Mileage($Value) {
  $text = Clean-Text $Value
  if (-not $text) { return "" }
  $match = [regex]::Match($text, "[\d,]+")
  if ($match.Success) { return "$($match.Value) miles" }
  return $text
}

function Resolve-Url($Value, $BaseUrl) {
  $text = Clean-Text $Value
  if (-not $text) { return "" }
  try { return ([Uri]::new([Uri]$BaseUrl, $text)).AbsoluteUri } catch { return $text }
}

function Normalize-InventoryUrl($Value) {
  $text = Clean-Text $Value
  if (-not $text) { return "" }
  try {
    $builder = [UriBuilder]$text
    $query = [System.Web.HttpUtility]::ParseQueryString($builder.Query)
    foreach ($key in @($query.AllKeys)) {
      if (-not $key) { continue }
      if ($key -match "^(utm_.+|msockid|fbclid|gclid|dclid|cmp|campaign|source|referrer)$") {
        $query.Remove($key)
      }
    }
    $builder.Query = $query.ToString()
    return $builder.Uri.AbsoluteUri
  } catch {
    return $text
  }
}

function Normalize-SettingsObject($Settings) {
  Set-ObjectValue $Settings "inventoryUrl" (Normalize-InventoryUrl $Settings.inventoryUrl)
  Set-ObjectValue $Settings "docFee" (Clean-Text $Settings.docFee)
  $includesDocFee = $false
  if ($Settings.PSObject.Properties["sourcePriceIncludesDocFee"]) {
    try { $includesDocFee = [System.Convert]::ToBoolean($Settings.sourcePriceIncludesDocFee) } catch { $includesDocFee = $false }
  }
  Set-ObjectValue $Settings "sourcePriceIncludesDocFee" $includesDocFee
  return $Settings
}

function Merge-PhotoSets($Existing, $Incoming, $BaseUrl = "") {
  $photos = New-Object System.Collections.Generic.List[string]
  foreach ($candidate in @($Existing) + @($Incoming)) {
    $url = Normalize-PhotoUrl $candidate $BaseUrl
    if ($url -match "^https?://" -and -not $photos.Contains($url)) { $photos.Add($url) }
  }
  return $photos.ToArray()
}

function Normalize-PhotoUrl($Value, $BaseUrl = "") {
  $decoded = [System.Web.HttpUtility]::HtmlDecode([string]$Value)
  $decoded = ($decoded -replace "\\u002[fF]", "/" -replace "\\/", "/" -replace '^"+|"+$', "").Trim()
  if (-not $decoded) { return "" }
  $url = Resolve-Url $decoded $BaseUrl
  try {
    $builder = [UriBuilder]$url
    $builder.Fragment = ""
    return $builder.Uri.AbsoluteUri
  } catch {
    return $url
  }
}

function Test-LikelyVehicleImageUrl($Value) {
  $text = Clean-Text $Value
  if ($text -notmatch "^https?://" -and $text -notmatch "^(//|/|\.{1,2}/)") { return $false }
  if ($text -match "\.(svg|gif|ico)(\?|$)") { return $false }
  if ($text -match "(logo|sprite|placeholder|transparent|blank|favicon|map|avatar|badge|block-images|error-message|no[-_ ]image|image[-_ ]not[-_ ]available)") { return $false }
  if ($text -match "\.(jpe?g|png|webp)(\?|$)") { return $true }
  try {
    $uri = [uri]$text
    return $uri.Host -match "^(images?|photos?|media|cdn)[.-]" -and $uri.AbsolutePath -match "/(images?|photos?|media|vehicles?)/"
  } catch {
    return $false
  }
}

function Add-ImageCandidate($Photos, $Value, $BaseUrl) {
  $url = Normalize-PhotoUrl $Value $BaseUrl
  if ($url -and (Test-LikelyVehicleImageUrl $url) -and -not $Photos.Contains($url)) {
    $Photos.Add($url) | Out-Null
  }
}

function Get-ImageUrlsFromObject($Value, $BaseUrl, [int]$Depth = 0) {
  $photos = New-Object System.Collections.Generic.List[string]
  if ($Depth -gt 8 -or $null -eq $Value) { return @() }
  if ($Value -is [string]) {
    Add-ImageCandidate $photos $Value $BaseUrl
    return $photos.ToArray()
  }
  if ($Value -is [array]) {
    foreach ($item in @($Value)) {
      foreach ($url in @(Get-ImageUrlsFromObject $item $BaseUrl ($Depth + 1))) { Add-ImageCandidate $photos $url $BaseUrl }
    }
    return $photos.ToArray()
  }
  if ($Value -is [pscustomobject]) {
    foreach ($prop in $Value.PSObject.Properties) {
      if ($prop.Name -match "(image|photo|picture|media|source|src|url|href|thumbnail)" -or $prop.Value -is [array] -or $prop.Value -is [pscustomobject]) {
        foreach ($url in @(Get-ImageUrlsFromObject $prop.Value $BaseUrl ($Depth + 1))) { Add-ImageCandidate $photos $url $BaseUrl }
      }
    }
  }
  return $photos.ToArray()
}

function Get-ImageUrlsFromHtml($Html, $BaseUrl) {
  $photos = New-Object System.Collections.Generic.List[string]
  foreach ($match in [regex]::Matches($Html, "(?:src|data-src|data-lazy|data-original|data-url|href)=[""']([^""']+)[""']", "IgnoreCase")) {
    Add-ImageCandidate $photos $match.Groups[1].Value $BaseUrl
  }
  foreach ($match in [regex]::Matches($Html, "https?:\\/\\/[^""'\\<\\>\s]+\.(?:jpg|jpeg|png|webp)(?:\?[^""'\\<\\>\s]*)?", "IgnoreCase")) {
    Add-ImageCandidate $photos ($match.Value -replace "\\/", "/") $BaseUrl
  }
  return $photos.ToArray()
}

function Get-BodyType($Value, $Title, $Model) {
  $explicit = (Clean-Text $Value).ToLower()
  if ($explicit -in @("car", "truck", "suv", "van", "unknown")) { return $explicit }
  $text = "$(Clean-Text $Title) $(Clean-Text $Model)".ToLower()
  if ($text -match "\b(truck|pickup|silverado|sierra|f-?150|f-?250|f-?350|ram\s*(1500|2500|3500)|tacoma|tundra|ridgeline|frontier|ranger|colorado|canyon|maverick|titan)\b") { return "truck" }
  if ($text -match "\b(suv|crossover|suburban|tahoe|equinox|traverse|trailblazer|blazer|explorer|expedition|escape|edge|bronco|rav4|highlander|4runner|sequoia|pilot|passport|cr-v|hr-v|rogue|pathfinder|murano|armada|telluride|sorento|sportage|palisade|tucson|santa fe|grand cherokee|wrangler|compass|renegade|durango|escalade|xt[456]|enclave|encore|envision|acadia|terrain|yukon)\b") { return "suv" }
  if ($text -match "\b(van|minivan|transit|express|savana|odyssey|sienna|pacifica|carnival|promaster)\b") { return "van" }
  if ($text -match "\b(car|sedan|coupe|hatchback|wagon|convertible|malibu|camry|corolla|accord|civic|altima|sentra|maxima|charger|challenger|mustang|camaro|impala|cruze|sonata|elantra|forte|k5|prius|versa)\b") { return "car" }
  return "unknown"
}

function Get-BodyStyle($Value, $BodyType, $Title) {
  $explicit = Clean-Text $Value
  if ($explicit) { return $explicit }
  $text = (Clean-Text $Title).ToLower()
  if ($text -match "\b(coupe)\b") { return "Coupe" }
  if ($text -match "\b(convertible)\b") { return "Convertible" }
  if ($text -match "\b(hatchback)\b") { return "Hatchback" }
  if ($text -match "\b(wagon)\b") { return "Wagon" }
  if ($text -match "\b(minivan)\b") { return "Minivan" }
  if ($BodyType -eq "truck") { return "Truck" }
  if ($BodyType -eq "suv") { return "SUV" }
  if ($BodyType -eq "van") { return "Van" }
  if ($BodyType -eq "car") { return "Sedan" }
  return ""
}

function Get-FuelType($Value, $Title) {
  $text = "$(Clean-Text $Value) $(Clean-Text $Title)".ToLower()
  if (-not $text.Trim()) { return "" }
  if ($text -match "\b(plug.?in|phev)\b") { return "Plug-In Hybrid" }
  if ($text -match "\b(electric|ev|battery)\b") { return "Electric" }
  if ($text -match "\b(hybrid|hev)\b") { return "Hybrid" }
  if ($text -match "\b(diesel|duramax|powerstroke|cummins|tdi)\b") { return "Diesel" }
  if ($text -match "\b(flex\s*fuel|e85|ffv)\b") { return "Flex Fuel" }
  if ($text -match "\b(gasoline|gas|petrol|unleaded)\b") { return "Gasoline" }
  return ""
}

function Get-SimpleVehicleColor($Value) {
  $text = (Clean-Text $Value).ToLower()
  if (-not $text) { return "" }
  if ($text -match "\b(black|ebony|onyx|charcoal|jet)\b") { return "Black" }
  if ($text -match "\b(white|pearl|ivory|summit|alabaster|frost|snow)\b") { return "White" }
  if ($text -match "\b(silver|steel|aluminum|aluminium|ingot|metallic)\b" -and $text -notmatch "\bblue|red|green|brown|orange|gold|purple\b") { return "Silver" }
  if ($text -match "\b(gray|grey|graphite|slate|magnetic|granite|carbon|ash)\b") { return "Gray" }
  if ($text -match "\b(red|maroon|burgundy|crimson|ruby|scarlet|cherry)\b") { return "Red" }
  if ($text -match "\b(blue|navy|aqua|azure|sapphire)\b") { return "Blue" }
  if ($text -match "\b(brown|tan|beige|sand|mocha|cocoa|kalahari|taupe)\b") { return "Brown" }
  if ($text -match "\b(gold|champagne)\b") { return "Gold" }
  if ($text -match "\b(green|olive|emerald)\b") { return "Green" }
  if ($text -match "\b(orange|copper|bronze)\b") { return "Orange" }
  if ($text -match "\b(yellow)\b") { return "Yellow" }
  if ($text -match "\b(purple|plum|violet)\b") { return "Purple" }
  return "Other"
}

function Get-ScrapeUrl($Value) {
  $url = [Uri](Normalize-InventoryUrl $Value)
  if ($url.Host -notmatch "(^|\.)autotrader\.com$") { return $url.AbsoluteUri }

  $builder = [UriBuilder]$url
  $query = [System.Web.HttpUtility]::ParseQueryString($builder.Query)
  if (-not $query["numRecords"] -or [int]$query["numRecords"] -lt 100) {
    $query["numRecords"] = "100"
  }
  $builder.Query = $query.ToString()
  return $builder.Uri.AbsoluteUri
}

function Test-DealerFeesIncluded($Value) {
  try {
    $text = if ($Value -is [string]) { $Value } else { $Value | ConvertTo-Json -Depth 12 -Compress }
    return [string]$text -match '(?i)\b(dealer\s+fees?\s+(are\s+)?included|includes?\s+dealer\s+fees?|fees?\s+included)\b|"(dealerFeesIncluded|feesIncluded)"\s*:\s*true'
  } catch {
    return $false
  }
}

function Test-DateIsToday($Value) {
  if (-not $Value) { return $false }
  try {
    return ([DateTimeOffset]::Parse([string]$Value).ToLocalTime().Date -eq [DateTimeOffset]::Now.Date)
  } catch {
    return $false
  }
}

function Normalize-Vehicle($Raw, $BaseUrl) {
  $title = Clean-Text $(if ($Raw.title) { $Raw.title } else { "$($Raw.year) $($Raw.make) $($Raw.model) $($Raw.trim)" })
  $yearMatch = [regex]::Match($title, "\b(19|20)\d{2}\b")
  $idSource = Clean-Text $(if ($Raw.vin) { $Raw.vin } elseif ($Raw.stock) { $Raw.stock } elseif ($Raw.url) { $Raw.url } else { $title })
  $id = ($idSource.ToLower() -replace "[^a-z0-9]+", "-").Trim("-")
  $primaryImage = Resolve-Url $Raw.image $BaseUrl
  $images = @(Merge-PhotoSets -Existing @($primaryImage) -Incoming @($Raw.images) -BaseUrl $BaseUrl)
  $bodyType = Get-BodyType $Raw.bodyType $title $Raw.model
  [ordered]@{
    id = $id
    title = $title
    year = Clean-Text $(if ($Raw.year) { $Raw.year } elseif ($yearMatch.Success) { $yearMatch.Value } else { "" })
    make = Clean-Text $Raw.make
    model = Clean-Text $Raw.model
    trim = Clean-Text $Raw.trim
    price = Clean-Price $Raw.price
    sourcePriceIncludesDocFee = [bool]($Raw.sourcePriceIncludesDocFee -eq $true)
    mileage = Clean-Mileage $Raw.mileage
    vin = (Clean-Text $Raw.vin).ToUpper()
    stock = Clean-Text $Raw.stock
    url = Resolve-Url $Raw.url $BaseUrl
    facebookListingType = "Car/Truck"
    bodyType = $bodyType
    bodyStyle = Get-BodyStyle $Raw.bodyStyle $bodyType $title
    exteriorColor = Get-SimpleVehicleColor $Raw.exteriorColor
    interiorColor = Get-SimpleVehicleColor $Raw.interiorColor
    fuelType = Get-FuelType $Raw.fuelType $title
    condition = "Excellent"
    customDescription = Clean-Description $Raw.customDescription
    image = $(if ($images.Count) { $images[0] } else { "" })
    images = @($images)
  }
}

function Get-MoneyAmount($Value) {
  $text = ([string]$Value) -replace "[^0-9.]", ""
  $amount = 0.0
  if ([double]::TryParse($text, [ref]$amount)) { return $amount }
  return 0
}

function Format-Money($Value) {
  $amount = [double]$Value
  if ($amount -le 0) { return "" }
  return '$' + ([Math]::Round($amount)).ToString("N0")
}

function Get-PostingPriceInfo($Vehicle, $Settings) {
  $base = Get-MoneyAmount $Vehicle.price
  $docFee = Get-MoneyAmount $Settings.docFee
  $includesDocFee = $false
  if ($Vehicle.sourcePriceIncludesDocFee -eq $true) {
    $includesDocFee = $true
  } elseif ($Settings.PSObject.Properties["sourcePriceIncludesDocFee"]) {
    $includesDocFee = [System.Convert]::ToBoolean($Settings.sourcePriceIncludesDocFee)
  }
  $posting = $(if ($base -gt 0) { $base + $(if ($includesDocFee) { 0 } else { $docFee }) } else { 0 })
  return [ordered]@{
    base = $base
    docFee = $docFee
    includesDocFee = $includesDocFee
    posting = $posting
    baseText = Format-Money $base
    docFeeText = Format-Money $docFee
    postingText = Format-Money $posting
  }
}

function Build-MarketplaceText($Vehicle, $Settings) {
  $lines = New-Object System.Collections.Generic.List[string]
  $priceInfo = Get-PostingPriceInfo $Vehicle $Settings
  Set-ObjectValue $Vehicle "sourcePrice" $priceInfo.baseText
  Set-ObjectValue $Vehicle "postingPrice" $priceInfo.postingText
  Set-ObjectValue $Vehicle "docFee" $priceInfo.docFeeText
  Set-ObjectValue $Vehicle "sourcePriceIncludesDocFee" $priceInfo.includesDocFee
  if ($Vehicle.title) { $lines.Add([string]$Vehicle.title) }
  if ($priceInfo.postingText) { $lines.Add("Price: $($priceInfo.postingText)") }
  elseif ($Vehicle.price) { $lines.Add("Price: $($Vehicle.price)") }
  if ($priceInfo.docFee -gt 0) {
    if ($priceInfo.includesDocFee) {
      $lines.Add("Dealer doc fee: $($priceInfo.docFeeText). Website/source price is marked as already including this doc fee. Taxes, title, registration, and government fees extra.")
    } else {
      $lines.Add("Website/source price: $($priceInfo.baseText). Dealer doc fee: $($priceInfo.docFeeText). Posting price includes the dealer doc fee. Taxes, title, registration, and government fees extra.")
    }
  }
  if ($Vehicle.mileage) { $lines.Add("Mileage: $($Vehicle.mileage)") }
  if ($Vehicle.stock) { $lines.Add("Stock #: $($Vehicle.stock)") }
  if ($Vehicle.vin) { $lines.Add("VIN: $($Vehicle.vin)") }
  if ($Vehicle.bodyType -and $Vehicle.bodyType -ne "unknown") { $lines.Add("Category: $(([string]$Vehicle.bodyType).ToUpper())") }
  if ($Vehicle.bodyStyle) { $lines.Add("Body style: $($Vehicle.bodyStyle)") }
  if ($Vehicle.exteriorColor) { $lines.Add("Exterior color: $($Vehicle.exteriorColor)") }
  if ($Vehicle.interiorColor) { $lines.Add("Interior color: $($Vehicle.interiorColor)") }
  if ($Vehicle.fuelType) { $lines.Add("Fuel type: $($Vehicle.fuelType)") }
  $lines.Add("Condition: $(if ($Vehicle.condition) { $Vehicle.condition } else { "Excellent" })")
  if ($Vehicle.url) { $lines.Add("Details: $($Vehicle.url)") }
  $lines.Add("")
  $dealerLine = "$($Settings.dealershipName)$(if ($Settings.city) { " - $($Settings.city)" })"
  if ($dealerLine.Trim()) { $lines.Add($dealerLine) }
  if ($Settings.listingFooter) { $lines.Add([string]$Settings.listingFooter) }
  return (($lines.ToArray()) -join "`n").Trim()
}

function Migrate-InventoryData {
  $store = Read-JsonFile $StoreFile (Empty-Store)
  $changed = $false
  foreach ($vehicle in @($store.vehicles) + @($store.removed)) {
    if ($vehicle.facebookListingType -ne "Car/Truck") {
      Set-ObjectValue $vehicle "facebookListingType" "Car/Truck"
      $changed = $true
    }
    $photos = @(Merge-PhotoSets -Existing @($vehicle.images) -Incoming @($vehicle.image))
    if (@($vehicle.images).Count -ne $photos.Count -or ($photos.Count -and $vehicle.image -ne $photos[0])) {
      Set-ObjectValue $vehicle "images" @($photos)
      Set-ObjectValue $vehicle "image" $(if ($photos.Count) { $photos[0] } else { "" })
      $changed = $true
    }
    if (-not $vehicle.bodyType -or $vehicle.bodyType -eq "unknown") {
      $bodyType = Get-BodyType "" $vehicle.title $vehicle.model
      if ($bodyType -ne "unknown" -or -not $vehicle.bodyType) {
        Set-ObjectValue $vehicle "bodyType" $bodyType
        $changed = $true
      }
    }
    if (-not $vehicle.bodyStyle) {
      Set-ObjectValue $vehicle "bodyStyle" (Get-BodyStyle "" $vehicle.bodyType $vehicle.title)
      $changed = $true
    }
  }
  if ($changed) { Write-JsonFile $StoreFile $store }
}

function Parse-JsonLdVehicles($Html, $BaseUrl) {
  $vehicles = New-Object System.Collections.Generic.List[object]
  $matches = [regex]::Matches($Html, "<script[^>]+type=[""']application/ld\+json[""'][^>]*>([\s\S]*?)</script>", "IgnoreCase")
  foreach ($match in $matches) {
    try {
      $json = [System.Web.HttpUtility]::HtmlDecode($match.Groups[1].Value) | ConvertFrom-Json
      $stack = New-Object System.Collections.Stack
      $stack.Push($json)
      while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        if ($null -eq $item) { continue }
        if ($item -is [array]) {
          foreach ($child in $item) { $stack.Push($child) }
          continue
        }
        if ($item -is [pscustomobject]) {
          foreach ($prop in $item.PSObject.Properties) {
            if ($prop.Value -is [array] -or $prop.Value -is [pscustomobject]) { $stack.Push($prop.Value) }
          }
          $type = [string]$item.'@type'
          if (($type + " " + [string]$item.name) -notmatch "Vehicle|Car|Auto") { continue }
          $name = Clean-Text $(if ($item.name) { $item.name } else { "$($item.vehicleModelDate) $($item.brand.name) $($item.model)" })
          if (-not $name) { continue }
          $raw = [ordered]@{
            title = $name
            year = $item.vehicleModelDate
            make = $(if ($item.brand.name) { $item.brand.name } else { $item.brand })
            model = $item.model
            price = $(if ($item.offers.price) { $item.offers.price } else { $item.price })
            url = $(if ($item.url) { $item.url } else { $item.offers.url })
            image = $(if ($item.image -is [array]) { $item.image[0] } else { $item.image })
            images = @(Get-ImageUrlsFromObject $item $BaseUrl)
            mileage = $(if ($item.mileageFromOdometer.value) { $item.mileageFromOdometer.value } else { $item.mileage })
            vin = $item.vehicleIdentificationNumber
            stock = $(if ($item.sku) { $item.sku } else { $item.productID })
            bodyStyle = $item.bodyType
            exteriorColor = $item.color
          }
          $vehicles.Add((Normalize-Vehicle $raw $BaseUrl)) | Out-Null
        }
      }
    } catch {}
  }
  return $vehicles
}

function Test-ObjectHasVehicleSignal($Value) {
  if ($null -eq $Value -or -not ($Value -is [pscustomobject])) { return $false }
  foreach ($name in @("vin", "VIN", "vehicleIdentificationNumber", "stock", "stockNumber", "year", "make", "model", "mileage", "odometer")) {
    if ($Value.PSObject.Properties[$name]) { return $true }
  }
  return $false
}

function Parse-AppDataVehicles($Html, $BaseUrl) {
  $vehicles = New-Object System.Collections.Generic.List[object]
  $matches = [regex]::Matches($Html, "<script[^>]+id=[""']__NEXT_DATA__[""'][^>]*>([\s\S]*?)</script>|<script[^>]+id=[""']__NUXT_DATA__[""'][^>]*>([\s\S]*?)</script>|<script[^>]+type=[""']application/json[""'][^>]*>([\s\S]*?)</script>", "IgnoreCase")
  foreach ($match in $matches) {
    $jsonText = ""
    foreach ($groupIndex in 1..3) {
      if ($match.Groups[$groupIndex].Success) { $jsonText = $match.Groups[$groupIndex].Value; break }
    }
    if (-not $jsonText) { continue }
    try {
      $json = [System.Web.HttpUtility]::HtmlDecode($jsonText) | ConvertFrom-Json
      $stack = New-Object System.Collections.Stack
      $stack.Push($json)
      while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        if ($null -eq $item) { continue }
        if ($item -is [array]) {
          foreach ($child in $item) { $stack.Push($child) }
          continue
        }
        if (-not ($item -is [pscustomobject])) { continue }
        foreach ($prop in $item.PSObject.Properties) {
          if ($prop.Value -is [array] -or $prop.Value -is [pscustomobject]) { $stack.Push($prop.Value) }
        }
        if (-not (Test-ObjectHasVehicleSignal $item)) { continue }
        $title = Clean-Text $(if ($item.title) { $item.title } elseif ($item.name) { $item.name } elseif ($item.vehicleTitle) { $item.vehicleTitle } elseif ($item.displayName) { $item.displayName } else { "" })
        $vin = Clean-Text $(if ($item.vin) { $item.vin } elseif ($item.VIN) { $item.VIN } else { $item.vehicleIdentificationNumber })
        $stock = Clean-Text $(if ($item.stock) { $item.stock } elseif ($item.stockNumber) { $item.stockNumber } else { $item.stock_number })
        if (-not $title -and -not $vin -and -not $stock) { continue }
        $raw = [ordered]@{
          title = $title
          year = $item.year
          make = $item.make
          model = $item.model
          trim = $item.trim
          price = $(if ($item.price) { $item.price } elseif ($item.internetPrice) { $item.internetPrice } else { $item.salePrice })
          mileage = $(if ($item.mileage) { $item.mileage } else { $item.odometer })
          vin = $vin
          stock = $stock
          url = $(if ($item.url) { $item.url } elseif ($item.vdpUrl) { $item.vdpUrl } else { $item.permalink })
          image = $(if ($item.image) { $item.image } elseif ($item.photo) { $item.photo } else { $item.thumbnail })
          images = @(Get-ImageUrlsFromObject $item $BaseUrl)
          bodyType = $(if ($item.bodyType) { $item.bodyType } elseif ($item.bodyStyle) { $item.bodyStyle } else { $item.vehicleType })
          bodyStyle = $(if ($item.bodyStyleName) { $item.bodyStyleName } else { $item.bodyStyle })
          exteriorColor = $(if ($item.exteriorColor) { $item.exteriorColor } elseif ($item.color.exteriorColor) { $item.color.exteriorColor } else { $item.color })
          interiorColor = $(if ($item.interiorColor) { $item.interiorColor } else { $item.color.interiorColor })
          fuelType = $(if ($item.fuelType) { $item.fuelType } else { $item.fuel })
          sourcePriceIncludesDocFee = Test-DealerFeesIncluded $item
        }
        $vehicles.Add((Normalize-Vehicle $raw $BaseUrl)) | Out-Null
      }
    } catch {}
  }
  return $vehicles
}

function Parse-CardVehicles($Html, $BaseUrl) {
  $vehicles = New-Object System.Collections.Generic.List[object]
  $matches = [regex]::Matches($Html, "<article[\s\S]*?</article>|<li[\s\S]*?vehicle[\s\S]*?</li>|<div[\s\S]{0,8000}?(?:vin|stock|vehicle-card|inventory)[\s\S]{0,8000}?</div>", "IgnoreCase")
  foreach ($match in $matches) {
    $block = $match.Value
    $text = Clean-Text ($block -replace "<[^>]*>", " ")
    if ($text -notmatch "\b(19|20)\d{2}\b" -or $text -notmatch "\b(vin|stock|mi\.?|miles|odometer|\$)\b") { continue }
    $heading = [regex]::Match($block, "<h[1-4][^>]*>([\s\S]*?)</h[1-4]>", "IgnoreCase")
    $title = ""
    if ($heading.Success) { $title = Clean-Text ($heading.Groups[1].Value -replace "<[^>]*>", " ") }
    if (-not $title) {
      $titleMatch = [regex]::Match($text, "\b((?:19|20)\d{2}\s+[A-Z][A-Za-z0-9-]+(?:\s+[A-Z][A-Za-z0-9-]+){1,5})\b")
      if ($titleMatch.Success) { $title = $titleMatch.Groups[1].Value }
    }
    if (-not $title) { continue }
    $href = [regex]::Match($block, "<a[^>]+href=[""']([^""']+)[""']", "IgnoreCase")
    $src = [regex]::Match($block, "(?:src|data-src)=[""']([^""']+)[""']", "IgnoreCase")
    $blockImages = @(Get-ImageUrlsFromHtml $block $BaseUrl)
    $raw = [ordered]@{
      title = $title
      price = [regex]::Match($text, "\$[\d,]+").Value
      mileage = [regex]::Match($text, "([\d,]+)\s*(?:mi\.?|miles|odometer)", "IgnoreCase").Groups[1].Value
      vin = [regex]::Match($text, "\bVIN[:\s#]*([A-HJ-NPR-Z0-9]{11,17})\b", "IgnoreCase").Groups[1].Value
      stock = [regex]::Match($text, "\bStock[:\s#]*([A-Z0-9-]{3,})\b", "IgnoreCase").Groups[1].Value
      url = $(if ($href.Success) { $href.Groups[1].Value } else { "" })
      image = $(if ($src.Success) { $src.Groups[1].Value } else { "" })
      images = $blockImages
      sourcePriceIncludesDocFee = Test-DealerFeesIncluded $text
    }
    $vehicles.Add((Normalize-Vehicle $raw $BaseUrl)) | Out-Null
  }
  return $vehicles
}

function Parse-AutoTraderVehicles($Html, $BaseUrl) {
  $vehicles = New-Object System.Collections.Generic.List[object]
  $match = [regex]::Match($Html, "<script[^>]+id=[""']__NEXT_DATA__[""'][^>]*>([\s\S]*?)</script>", "IgnoreCase")
  if (-not $match.Success) { return $vehicles }

  try {
    $data = [System.Web.HttpUtility]::HtmlDecode($match.Groups[1].Value) | ConvertFrom-Json
    $state = $data.props.pageProps.__eggsState
    $inventoryItems = New-Object System.Collections.Generic.List[object]
    if ($state -and $state.inventory -and @($state.inventory.PSObject.Properties).Count -gt 0) {
      foreach ($prop in $state.inventory.PSObject.Properties) {
        if ($prop.Value) {
          $inventoryItems.Add([pscustomobject]@{ key = $prop.Name; item = $prop.Value }) | Out-Null
        }
      }
    } else {
      # AutoTrader periodically moves the inventory collection within
      # __NEXT_DATA__. Find vehicle-shaped records without depending on one
      # release-specific property path.
      $queue = New-Object System.Collections.Queue
      $queue.Enqueue($data)
      $visited = 0
      while ($queue.Count -gt 0 -and $visited -lt 50000) {
        $node = $queue.Dequeue()
        $visited++
        if ($null -eq $node -or $node -is [string] -or $node -is [ValueType]) { continue }
        if ($node -is [System.Collections.IEnumerable] -and $node -isnot [pscustomobject]) {
          foreach ($child in $node) { if ($null -ne $child) { $queue.Enqueue($child) } }
          continue
        }
        $props = $node.PSObject.Properties
        $vinValue = ""
        foreach ($vinName in @("vin", "VIN", "vehicleIdentificationNumber")) {
          if ($props[$vinName]) { $vinValue = Clean-Text $props[$vinName].Value; break }
        }
        $yearValue = if ($props["year"]) { Clean-Text $props["year"].Value } elseif ($props["modelYear"]) { Clean-Text $props["modelYear"].Value } else { "" }
        if ($vinValue -match "^[A-HJ-NPR-Z0-9]{17}$" -and $yearValue -match "^(19|20)\d{2}$") {
          $itemKey = if ($props["id"]) { [string]$props["id"].Value } elseif ($props["listingId"]) { [string]$props["listingId"].Value } else { $vinValue }
          $inventoryItems.Add([pscustomobject]@{ key = $itemKey; item = $node }) | Out-Null
          continue
        }
        foreach ($prop in $props) {
          if ($null -ne $prop.Value -and $prop.Value -isnot [string] -and $prop.Value -isnot [ValueType]) {
            $queue.Enqueue($prop.Value)
          }
        }
      }
    }
    if (-not $inventoryItems.Count) { return $vehicles }

    $urls = $null
    try { $urls = $state.'dealerdetails.urls'.results } catch {}
    $seenVins = @{}

    foreach ($entry in $inventoryItems) {
      $item = $entry.item
      $itemId = if ($item.id) { $item.id } elseif ($item.listingId) { $item.listingId } else { $entry.key }
      $itemVin = if ($item.vin) { $item.vin } elseif ($item.VIN) { $item.VIN } else { $item.vehicleIdentificationNumber }
      $itemYear = if ($item.year) { $item.year } else { $item.modelYear }
      $makeName = if ($item.make.name) { $item.make.name } elseif ($item.make) { $item.make } elseif ($item.makeName) { $item.makeName } else { "" }
      $modelName = if ($item.model.name) { $item.model.name } elseif ($item.model) { $item.model } elseif ($item.modelName) { $item.modelName } else { "" }
      if (-not $item -or -not $itemId -or -not $itemVin -or -not $itemYear -or -not $makeName -or -not $modelName) { continue }
      if ($seenVins[[string]$itemVin]) { continue }
      $seenVins[[string]$itemVin] = $true
      if ($item.listingType -and [string]$item.listingType -notmatch "USED|CERTIFIED") { continue }

      $listingPath = ""
      if ($urls -and $urls.PSObject.Properties[$entry.key]) { $listingPath = $urls.PSObject.Properties[$entry.key].Value }
      if (-not $listingPath -and $item.url) { $listingPath = $item.url }
      if (-not $listingPath -and $item.vehicleDetailsUrl) { $listingPath = $item.vehicleDetailsUrl }
      if (-not $listingPath) { $listingPath = "/cars-for-sale/vehicle/$itemId" }

      $image = ""
      $images = New-Object System.Collections.Generic.List[string]
      try {
        if ($item.images.sources -and @($item.images.sources).Count) {
          $primaryIndex = 0
          if ($item.images.primary -is [int]) { $primaryIndex = [int]$item.images.primary }
          $image = @($item.images.sources)[$primaryIndex].src
          if (-not $image) { $image = @($item.images.sources)[0].src }
          foreach ($source in @($item.images.sources)) {
            Add-ImageCandidate $images $source.src $BaseUrl
            Add-ImageCandidate $images $source.href $BaseUrl
            Add-ImageCandidate $images $source.url $BaseUrl
          }
        }
      } catch {}
      foreach ($url in @(Get-ImageUrlsFromObject $item $BaseUrl)) { Add-ImageCandidate $images $url $BaseUrl }

      $salePrice = Get-MoneyAmount $(if ($item.pricingDetail.salePrice) { $item.pricingDetail.salePrice } elseif ($item.salePrice) { $item.salePrice } elseif ($item.price) { $item.price } else { $item.pricing.salePrice })
      $displayPrice = Get-MoneyAmount $(if ($item.pricingDetail.displayPrice) { $item.pricingDetail.displayPrice } elseif ($item.displayPrice) { $item.displayPrice } elseif ($item.pricing.displayPrice) { $item.pricing.displayPrice } else { $item.price })
      $dealerFeesTotal = Get-MoneyAmount $(if ($item.pricingDetail.dealerFeesTotal) { $item.pricingDetail.dealerFeesTotal } elseif ($item.dealerFeesTotal) { $item.dealerFeesTotal } else { $item.pricing.dealerFeesTotal })
      $formulaIncludesFee = $salePrice -gt 0 -and $displayPrice -gt 0 -and $dealerFeesTotal -gt 0 -and [Math]::Abs(($salePrice + $dealerFeesTotal) - $displayPrice) -le 2
      $sourcePriceIncludesDocFee = (Test-DealerFeesIncluded $item) -or $formulaIncludesFee
      $price = ""
      $priceCandidates = if ($sourcePriceIncludesDocFee) {
        @($displayPrice, $salePrice, $item.pricingDetail.preFeeDerivedPrice, $item.pricingDetail.incentive, $item.pricing.price)
      } else {
        @($salePrice, $displayPrice, $item.pricingDetail.preFeeDerivedPrice, $item.pricingDetail.incentive, $item.pricing.price)
      }
      foreach ($candidate in $priceCandidates) {
        if ($candidate) {
          $price = $candidate
          break
        }
      }

      $trim = ""
      if ($item.trim.name) { $trim = $item.trim.name } elseif ($item.trim) { $trim = $item.trim } elseif ($item.atTrim.name) { $trim = $item.atTrim.name }
      $title = "$itemYear $makeName $modelName $trim"

      $raw = [ordered]@{
        title = $title
        year = $itemYear
        make = $makeName
        model = $modelName
        trim = $trim
        price = $price
        mileage = $(if ($item.mileage.value) { $item.mileage.value } else { $item.mileage })
        vin = $itemVin
        stock = $(if ($item.stockId) { $item.stockId } elseif ($item.stockNumber) { $item.stockNumber } else { $item.stock })
        url = $listingPath
        image = $image
        images = @($images.ToArray())
        bodyType = $(if ($item.bodyStyles.name) { $item.bodyStyles.name } elseif ($item.bodyStyle.name) { $item.bodyStyle.name } elseif ($item.bodyType) { $item.bodyType } else { "" })
        bodyStyle = $(if ($item.bodyStyles.name) { $item.bodyStyles.name } elseif ($item.bodyStyleSubType.name) { $item.bodyStyleSubType.name } else { "" })
        exteriorColor = $(if ($item.color.exteriorColor) { $item.color.exteriorColor } else { $item.color.exteriorColorSimple })
        interiorColor = $(if ($item.color.interiorColor) { $item.color.interiorColor } else { $item.color.interiorColorSimple })
        fuelType = $(if ($item.fuelType.name) { $item.fuelType.name } elseif ($item.fuelType) { $item.fuelType } elseif ($item.fuel) { $item.fuel } else { "" })
        sourcePriceIncludesDocFee = $sourcePriceIncludesDocFee
      }
      $vehicles.Add((Normalize-Vehicle $raw $BaseUrl)) | Out-Null
    }
  } catch {}

  return $vehicles
}

function Get-LabeledDealerPrice($Block, $ClassPattern) {
  $matches = [regex]::Matches($Block, '<(?:dt|dd)[^>]*class=["''][^"'']*(' + $ClassPattern + ')[^"'']*["''][^>]*>([\s\S]*?)</(?:dt|dd)>', 'IgnoreCase')
  foreach ($match in $matches) {
    if ($match.Groups[2].Value -match 'price-value') { return Get-MoneyAmount (Clean-Text ($match.Groups[2].Value -replace '<[^>]*>', ' ')) }
  }
  return 0
}

function Parse-DealerComVehicles($Html, $BaseUrl) {
  if ($Html -notmatch 'vehicle-card-body') { return @() }
  $parts = [regex]::Split($Html, '(?=<div[^>]+class=["''][^"'']*vehicle-card-body)', 'IgnoreCase')
  $vehicles = @()
  foreach ($block in @($parts | Select-Object -Skip 1)) {
    $titleMatch = [regex]::Match($block, 'class=["''][^"'']*vehicle-card-title[\s\S]*?</h2>', 'IgnoreCase')
    $title = Clean-Text ($titleMatch.Value -replace '<[^>]*>', ' ')
    $finalPrice = Get-LabeledDealerPrice $block 'final-price|internetPrice'
    if (-not $title -or $finalPrice -le 0) { continue }
    $retail = Get-LabeledDealerPrice $block 'msrp|retail'
    $discount = Get-LabeledDealerPrice $block 'discount'
    $sourceDocFee = Get-LabeledDealerPrice $block 'invoicePrice|doc-fee'
    $text = Clean-Text ($block -replace '<[^>]*>', ' ')
    $formulaIncludesFee = $retail -gt 0 -and $discount -gt 0 -and $sourceDocFee -gt 0 -and [Math]::Abs(($retail - $discount + $sourceDocFee) - $finalPrice) -le 2
    $raw = [ordered]@{
      title = $title
      price = $finalPrice
      mileage = [regex]::Match($text, '([\d,]+)\s*miles', 'IgnoreCase').Groups[1].Value
      vin = [regex]::Match($block, 'data-vin=["'']([A-HJ-NPR-Z0-9]{17})', 'IgnoreCase').Groups[1].Value
      stock = [regex]::Match($text, 'Stock\s*#\s*([A-Z0-9-]+)', 'IgnoreCase').Groups[1].Value
      url = [regex]::Match($block, 'href=["'']([^"'']*/used/[^"'']+\.htm)', 'IgnoreCase').Groups[1].Value
      images = @(Get-ImageUrlsFromHtml $block $BaseUrl)
      sourcePriceIncludesDocFee = (Test-DealerFeesIncluded $text) -or $formulaIncludesFee
    }
    $vehicles += Normalize-Vehicle $raw $BaseUrl
  }
  return @($vehicles)
}

function Get-AutoTraderPhotos($VehicleUrl) {
  return @((Get-AutoTraderDetailData $VehicleUrl).photos)
}

function Parse-AutoTraderDetailHtml($Html, $DetailUrl) {
  $photos = New-Object System.Collections.Generic.List[string]
  $fuelType = ""
  $match = [regex]::Match([string]$Html, "<script[^>]+id=[""']__NEXT_DATA__[""'][^>]*>([\s\S]*?)</script>", "IgnoreCase")
  if ($match.Success) {
    try {
      $data = [System.Web.HttpUtility]::HtmlDecode($match.Groups[1].Value) | ConvertFrom-Json
      $candidates = New-Object System.Collections.Generic.List[object]
      $state = $data.props.pageProps.__eggsState
      foreach ($property in @($state.inventory.PSObject.Properties)) {
        if ($property.Value) { $candidates.Add($property.Value) | Out-Null }
      }
      if ($state.birf.pageData.page.vehicle) { $candidates.Add($state.birf.pageData.page.vehicle) | Out-Null }
      if ($data.props.pageProps.vehicle) { $candidates.Add($data.props.pageProps.vehicle) | Out-Null }
      foreach ($item in $candidates) {
        if (-not $fuelType) {
          $fuelType = Get-FuelType $(if ($item.fuelType.name) { $item.fuelType.name } elseif ($item.fuelType) { $item.fuelType } elseif ($item.fuel) { $item.fuel } else { "" }) $item.title
        }
        foreach ($url in @(Get-ImageUrlsFromObject $item $DetailUrl)) { Add-ImageCandidate $photos $url $DetailUrl }
      }
    } catch {}
  }
  foreach ($url in @(Get-ImageUrlsFromHtml ([string]$Html) $DetailUrl)) { Add-ImageCandidate $photos $url $DetailUrl }
  return [ordered]@{ photos = @($photos.ToArray()); fuelType = $fuelType }
}

function Get-AutoTraderDetailData($VehicleUrl) {
  $detailUrl = $VehicleUrl
  $listingIdMatch = [regex]::Match([string]$VehicleUrl, "(?:listingId=|/vehicle/)(\d+)")
  if ($listingIdMatch.Success) {
    $detailUrl = "https://www.autotrader.com/cars-for-sale/vehicle/$($listingIdMatch.Groups[1].Value)"
  }
  $headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
    "Accept-Language" = "en-US,en;q=0.9"
  }
  $response = Invoke-WebRequest -Uri $detailUrl -Headers $headers -MaximumRedirection 5 -UseBasicParsing
  return Parse-AutoTraderDetailHtml ([string]$response.Content) $detailUrl
}

function Get-GenericDetailData($VehicleUrl) {
  $detailUrl = Resolve-Url $VehicleUrl $VehicleUrl
  $headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
    "Accept-Language" = "en-US,en;q=0.9"
  }
  $response = Invoke-WebRequest -Uri $detailUrl -Headers $headers -MaximumRedirection 5 -UseBasicParsing
  $html = [string]$response.Content
  $photos = New-Object System.Collections.Generic.List[string]
  foreach ($url in @(Get-ImageUrlsFromHtml $html $detailUrl)) { Add-ImageCandidate $photos $url $detailUrl }
  foreach ($match in [regex]::Matches($html, "<script[^>]+type=[""']application/ld\+json[""'][^>]*>([\s\S]*?)</script>", "IgnoreCase")) {
    try {
      $json = [System.Web.HttpUtility]::HtmlDecode($match.Groups[1].Value) | ConvertFrom-Json
      foreach ($url in @(Get-ImageUrlsFromObject $json $detailUrl)) { Add-ImageCandidate $photos $url $detailUrl }
    } catch {}
  }
  return [ordered]@{ photos = @($photos.ToArray()); fuelType = "" }
}

function Dedupe-Vehicles($Vehicles) {
  $map = @{}
  foreach ($vehicle in $Vehicles) {
    if (-not $vehicle.id -or -not $vehicle.title) { continue }
    $map[$vehicle.id] = $vehicle
  }
  return @($map.Values | Sort-Object title)
}

function Get-SourceIdentity($SourceUrl) {
  try {
    $uri = [uri][string]$SourceUrl
    $path = ($uri.AbsolutePath.Trim("/") -split "/" | Select-Object -First 4) -join "/"
    return "$($uri.Host.ToLower())/$path"
  } catch {
    return (Clean-Text $SourceUrl).ToLower()
  }
}

function Get-SourceWarnings($SourceUrl) {
  $sourceHost = ""
  try { $sourceHost = ([uri][string]$SourceUrl).Host.ToLower() } catch {}
  if ($sourceHost -match "(^|\.)autotrader\.com$") {
    return @("AutoTrader import is supported for dealer inventory pages and requests up to 100 used vehicles.")
  }
  if ($sourceHost -match "(^|\.)cars\.com$|(^|\.)cargurus\.com$") {
    return @("Cars.com and CarGurus are saved as dealer sources, but need dedicated import adapters for reliable full inventory pulls. Use CSV/manual import for this source until that adapter is added.")
  }
  return @("Generic website import is experimental. It works only when the page exposes vehicle data in readable listings or structured data.")
}

function Scrape-Inventory($Settings, [int]$Attempt = 1) {
  Start-Sleep -Milliseconds ([int]$Settings.requestDelayMs)
  $headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
    "Accept-Language" = "en-US,en;q=0.9"
    "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  }
  $requestUrls = @((Get-ScrapeUrl $Settings.inventoryUrl))
  if ($Settings.inventoryUrl -match "autotrader\.com" -and $Settings.inventoryUrl -match "100009092") {
    # Prefer Walker's authoritative, fee-inclusive sale price. AutoTrader can
    # return a successful shell page without usable inventory data.
    $requestUrls = @("https://www.walkerchevrolet.com/used-inventory/index.htm") + $requestUrls
  }
  $response = $null
  $errors = @()
  foreach ($requestUrl in @($requestUrls | Select-Object -Unique)) {
    try {
      $candidate = Invoke-WebRequest -Uri $requestUrl -Headers $headers -MaximumRedirection 5 -UseBasicParsing
      $candidateHtml = [string]$candidate.Content
      if ($candidateHtml.Length -lt 20000 -and $candidateHtml -match "(?i)(page unavailable|access denied|attention required|captcha|verify (you are|that you are) human|bot detection)") {
        $errors += "$(([Uri]$requestUrl).Host) blocked the automated inventory request"
        continue
      }
      $response = $candidate
      break
    } catch {
      $statusCode = $_.Exception.Response.StatusCode.value__
      $detail = if ($statusCode) { "HTTP $statusCode" } else { $_.Exception.Message }
      $errors += "$(([Uri]$requestUrl).Host): $detail"
    }
  }
  if (-not $response) {
    throw "The inventory source blocked live refresh ($($errors -join '; ')). Saved inventory is still available. Use an authorized dealer CSV/feed if this continues."
  }
  $baseUrl = $response.BaseResponse.ResponseUri.AbsoluteUri
  $html = [string]$response.Content
  $vehicles = New-Object System.Collections.Generic.List[object]
  $dealerComVehicles = @(Parse-DealerComVehicles $html $baseUrl)
  $autoTraderVehicles = @(Parse-AutoTraderVehicles $html $baseUrl)
  if ($dealerComVehicles.Count) {
    foreach ($vehicle in $dealerComVehicles) { $vehicles.Add($vehicle) | Out-Null }
  } elseif ($autoTraderVehicles.Count) {
    foreach ($vehicle in $autoTraderVehicles) { $vehicles.Add($vehicle) | Out-Null }
  } else {
    foreach ($vehicle in (Parse-JsonLdVehicles $html $baseUrl)) { $vehicles.Add($vehicle) | Out-Null }
    foreach ($vehicle in (Parse-AppDataVehicles $html $baseUrl)) { $vehicles.Add($vehicle) | Out-Null }
    foreach ($vehicle in (Parse-CardVehicles $html $baseUrl)) { $vehicles.Add($vehicle) | Out-Null }
  }
  $deduped = Dedupe-Vehicles $vehicles
  if (-not $deduped.Count) {
    if ($Attempt -lt 2) {
      Start-Sleep -Milliseconds 1200
      return Scrape-Inventory $Settings ($Attempt + 1)
    }
    throw "No vehicles were detected. Existing saved inventory was left unchanged. Confirm the Inventory Source URL or try again later."
  }
  foreach ($vehicle in $deduped) {
    $vehicle.marketplaceText = Build-MarketplaceText $vehicle $Settings
  }
  [ordered]@{ sourceUrl = $baseUrl; warnings = @(Get-SourceWarnings $baseUrl); vehicles = @($deduped) }
}

function Merge-Inventory($Scraped, [bool]$VerifyPrices = $true) {
  $previousStore = Read-JsonFile $StoreFile (Empty-Store)
  $sameSource = (Get-SourceIdentity $previousStore.sourceUrl) -eq (Get-SourceIdentity $Scraped.sourceUrl)
  $previousMap = @{}
  if ($sameSource) {
    foreach ($vehicle in @($previousStore.vehicles)) { $previousMap[$vehicle.id] = $vehicle }
  }
  $now = (Get-Date).ToUniversalTime().ToString("o")
  $vehicles = @()
  $newCount = 0
  $updatedCount = 0
  foreach ($vehicle in @($Scraped.vehicles)) {
    $previous = $previousMap[$vehicle.id]
    $mergedPhotos = @(Merge-PhotoSets -Existing @($previous.images) -Incoming @($vehicle.images))
    if (-not $mergedPhotos.Count) { $mergedPhotos = @(Merge-PhotoSets -Existing @($previous.image) -Incoming @($vehicle.image)) }
    Set-ObjectValue $vehicle "images" @($mergedPhotos)
    Set-ObjectValue $vehicle "image" $(if ($mergedPhotos.Count) { $mergedPhotos[0] } else { "" })
    if ((-not $vehicle.bodyType -or $vehicle.bodyType -eq "unknown") -and $previous.bodyType) {
      Set-ObjectValue $vehicle "bodyType" $previous.bodyType
    }
    foreach ($field in @(
      "bodyStyle", "exteriorColor", "interiorColor", "fuelType", "condition", "customDescription",
      "assignedToId", "assignedToName", "assignedToEmail", "assignedAt",
      "assignedById", "assignedByName", "assignmentDueAt", "workflowStatus",
      "preparedAt", "preparedById", "preparedByName", "postedById", "postedByName"
    )) {
      if ((-not $vehicle.$field) -and $previous.$field) { Set-ObjectValue $vehicle $field $previous.$field }
    }
    Set-ObjectValue $vehicle "exteriorColor" (Get-SimpleVehicleColor $vehicle.exteriorColor)
    Set-ObjectValue $vehicle "interiorColor" (Get-SimpleVehicleColor $vehicle.interiorColor)
    Set-ObjectValue $vehicle "status" $(if ($previous) { "seen" } else { "new" })
    Set-ObjectValue $vehicle "firstSeenAt" $(if ($previous.firstSeenAt) { $previous.firstSeenAt } else { $now })
    Set-ObjectValue $vehicle "lastSeenAt" $now
    Set-ObjectValue $vehicle "priceVerifiedAt" $(if ($VerifyPrices -and $vehicle.price) { $now } else { $previous.priceVerifiedAt })
    Set-ObjectValue $vehicle "facebookPostedAt" $(if ($previous.facebookPostedAt) { $previous.facebookPostedAt } else { $null })
    if ($previous) { $updatedCount++ } else { $newCount++ }
    $vehicles += $vehicle
  }
  $currentIds = @{}
  foreach ($vehicle in $vehicles) { $currentIds[$vehicle.id] = $true }
  $removed = @()
  if ($sameSource) {
    foreach ($vehicle in @($previousStore.vehicles)) {
      if (-not $currentIds.ContainsKey($vehicle.id)) {
        Set-ObjectValue $vehicle "status" "removed"
        if (-not $vehicle.removedAt) { Set-ObjectValue $vehicle "removedAt" $now }
        $removed += $vehicle
      }
    }
  }
  [ordered]@{
    scrapedAt = $now
    sourceUrl = $Scraped.sourceUrl
    warnings = @($Scraped.warnings)
    importResult = [ordered]@{
      sourceChecked = $Scraped.sourceUrl
      vehiclesFound = @($Scraped.vehicles).Count
      newVehicles = $newCount
      updatedVehicles = $updatedCount
      missingVehicles = @($removed).Count
    }
    autoCsvAvailable = @($vehicles).Count -gt 0
    vehicles = @($vehicles)
    removed = @($removed)
  }
}

function Get-RefreshFallbackStore($Settings, $ErrorMessage) {
  $store = Read-JsonFile $StoreFile (Empty-Store)
  $message = Clean-Text $ErrorMessage
  Set-ObjectValue $store "refreshFailed" $true
  Set-ObjectValue $store "refreshAttemptedAt" ((Get-Date).ToUniversalTime().ToString("o"))
  Set-ObjectValue $store "warnings" @("Live inventory could not be refreshed right now. Showing saved inventory. $message")
  if (-not $store.sourceUrl) { Set-ObjectValue $store "sourceUrl" $Settings.inventoryUrl }
  if (-not $store.importResult) {
    Set-ObjectValue $store "importResult" ([ordered]@{
      sourceChecked = $Settings.inventoryUrl
      vehiclesFound = @($store.vehicles).Count
      newVehicles = 0
      updatedVehicles = @($store.vehicles).Count
      missingVehicles = @($store.removed).Count
    })
  }
  return $store
}

function ConvertTo-CsvText($Vehicles) {
  $columns = @(
    "id", "status", "workflowStatus", "title", "year", "make", "model", "trim",
    "bodyType", "bodyStyle", "exteriorColor", "interiorColor", "fuelType", "condition", "price", "sourcePrice",
    "postingPrice", "docFee", "sourcePriceIncludesDocFee", "mileage",
    "vin", "stock", "url", "image", "images", "customDescription",
    "assignedToName", "assignedToEmail", "assignedAt", "assignmentDueAt",
    "preparedByName", "preparedAt", "postedByName", "facebookPostedAt",
    "firstSeenAt", "lastSeenAt", "removedAt", "marketplaceText"
  )
  $rows = New-Object System.Collections.Generic.List[string]
  $rows.Add(($columns -join ",")) | Out-Null
  foreach ($vehicle in @($Vehicles)) {
    $cells = foreach ($column in $columns) {
      $value = if ($column -eq "images") { @($vehicle.images) -join "|" } else { [string]$vehicle.$column }
      '"' + ($value -replace '"', '""') + '"'
    }
    $rows.Add(($cells -join ",")) | Out-Null
  }
  return ($rows -join "`n")
}

function Write-AutoCsv($Vehicles) {
  (ConvertTo-CsvText $Vehicles) + "`n" | Set-Content -Path $AutoCsvFile -Encoding UTF8
}

function Normalize-Header($Value) {
  $header = ([string]$Value).Trim([char]0xFEFF).Trim().ToLower() -replace "[^a-z0-9]+", ""
  if ($header -eq "valuetitle") { return "title" }
  return $header
}

function Get-Field($Row, [string[]]$Names) {
  $props = @{}
  if ($Row -is [System.Collections.IDictionary]) {
    foreach ($key in $Row.Keys) { $props[(Normalize-Header $key)] = $Row[$key] }
  } else {
    foreach ($prop in $Row.PSObject.Properties) {
      $props[(Normalize-Header $prop.Name)] = $prop.Value
    }
  }
  foreach ($name in $Names) {
    $key = Normalize-Header $name
    if ($props.ContainsKey($key) -and (Clean-Text $props[$key])) { return $props[$key] }
  }
  return ""
}

function Convert-CsvRowToVehicle($Row, $Settings) {
  $raw = [ordered]@{
    title = Get-Field $Row @("title", "vehicle", "name")
    year = Get-Field $Row @("year")
    make = Get-Field $Row @("make")
    model = Get-Field $Row @("model")
    trim = Get-Field $Row @("trim")
    price = Get-Field $Row @("price", "sale price", "internet price")
    mileage = Get-Field $Row @("mileage", "miles", "odometer")
    vin = Get-Field $Row @("vin")
    stock = Get-Field $Row @("stock", "stock #", "stock number")
    url = Get-Field $Row @("url", "details url", "vehicle url", "link")
    image = Get-Field $Row @("image", "photo", "photo url", "image url")
    images = @((Get-Field $Row @("images", "photo urls", "image urls")) -split "\|" | Where-Object { Clean-Text $_ })
    bodyType = Get-Field $Row @("bodyType", "body type", "category", "vehicle type")
    bodyStyle = Get-Field $Row @("bodyStyle", "body style")
    exteriorColor = Get-Field $Row @("exteriorColor", "exterior color", "color")
    interiorColor = Get-Field $Row @("interiorColor", "interior color")
    fuelType = Get-Field $Row @("fuelType", "fuel type", "fuel")
    condition = $(if (Get-Field $Row @("condition", "vehicle condition")) { Get-Field $Row @("condition", "vehicle condition") } else { "Excellent" })
    customDescription = Get-Field $Row @("customDescription", "custom description")
  }
  $vehicle = Normalize-Vehicle $raw $Settings.inventoryUrl
  $listing = Get-Field $Row @("marketplaceText", "marketplace text", "listing", "description")
  $vehicle.marketplaceText = $(if ($listing) { $listing } else { Build-MarketplaceText $vehicle $Settings })
  return $vehicle
}

function ConvertFrom-CsvText($CsvText) {
  Add-Type -AssemblyName Microsoft.VisualBasic
  $normalizedText = ([string]$CsvText) -replace "\\r\\n", "`r`n" -replace "\\n", "`n" -replace "\\r", "`r"
  $reader = [System.IO.StringReader]::new($normalizedText)
  $parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($reader)
  $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
  $parser.SetDelimiters(",")
  $parser.HasFieldsEnclosedInQuotes = $true
  try {
    if ($parser.EndOfData) { return @() }
    $headers = @($parser.ReadFields() | ForEach-Object { Normalize-Header $_ })
    $rows = New-Object System.Collections.Generic.List[object]
    while (-not $parser.EndOfData) {
      $fields = @($parser.ReadFields())
      if (-not ($fields | Where-Object { (Clean-Text $_) })) { continue }
      $row = [ordered]@{}
      for ($i = 0; $i -lt $headers.Count; $i++) {
        $row[$headers[$i]] = $(if ($i -lt $fields.Count) { $fields[$i] } else { "" })
      }
      $rows.Add($row) | Out-Null
    }
    return $rows.ToArray()
  } finally {
    $parser.Close()
    $reader.Dispose()
  }
}

function Get-TitleFromLine($Line) {
  $lineText = Clean-Text $Line
  if ($lineText -match "(?i)\b(search|filter|sort|payment|dealer|inventory|favorites|view details|sponsored|advertisement)\b") { return "" }
  $match = [regex]::Match($lineText, "\b((?:19|20)\d{2}\s+[A-Z][A-Za-z0-9-]+(?:\s+[A-Za-z0-9][A-Za-z0-9./+-]+){1,7})\b")
  if (-not $match.Success) { return "" }
  $title = Clean-Text $match.Groups[1].Value
  $title = [regex]::Replace($title, "\s+(for sale|details|used|certified|new)\b.*$", "", "IgnoreCase")
  return $title
}

function ConvertFrom-PageText($PageText, $Settings) {
  $text = [System.Web.HttpUtility]::HtmlDecode([string]$PageText)
  $text = $text -replace "<br\s*/?>", "`n" -replace "</(?:div|li|article|section|p|h[1-6])>", "`n" -replace "<[^>]*>", " "
  $lines = @($text -split "\r?\n" | ForEach-Object { Clean-Text $_ } | Where-Object { $_ })
  $titleIndexes = New-Object System.Collections.Generic.List[int]
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if (Get-TitleFromLine $lines[$i]) { $titleIndexes.Add($i) }
  }

  $vehicles = @()
  $seen = @{}
  for ($i = 0; $i -lt $titleIndexes.Count; $i++) {
    $start = $titleIndexes[$i]
    $nextStart = if ($i -lt $titleIndexes.Count - 1) { $titleIndexes[$i + 1] } else { [Math]::Min($lines.Count, $start + 24) }
    $end = [Math]::Min($nextStart, $start + 24)
    if ($end -le $start) { continue }
    $chunkLines = @($lines[$start..($end - 1)])
    $chunk = Clean-Text ($chunkLines -join " ")
    $title = Get-TitleFromLine $lines[$start]
    if (-not $title) { continue }
    $price = [regex]::Match($chunk, "\$[\d,]{3,}").Value
    $mileage = [regex]::Match($chunk, "([\d,]{1,7})\s*(?:mi\.?|miles|mileage)", "IgnoreCase").Groups[1].Value
    $vin = [regex]::Match($chunk, "\b([A-HJ-NPR-Z0-9]{17})\b", "IgnoreCase").Groups[1].Value
    $stock = [regex]::Match($chunk, "(?:stock|stk|stock #|stock number)[:#\s]*([A-Z0-9-]{3,})", "IgnoreCase").Groups[1].Value
    if (-not $price -and -not $mileage -and -not $vin -and -not $stock) { continue }
    $key = $(if ($vin) { $vin.ToLower() } elseif ($stock) { $stock.ToLower() } else { ($title + "|" + $price + "|" + $mileage).ToLower() })
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $raw = [ordered]@{
      title = $title
      price = $price
      mileage = $mileage
      vin = $vin
      stock = $stock
      url = $Settings.inventoryUrl
    }
    $vehicle = Normalize-Vehicle $raw $Settings.inventoryUrl
    $vehicle.marketplaceText = Build-MarketplaceText $vehicle $Settings
    $vehicles += $vehicle
  }
  return $vehicles
}

function Read-HttpRequest($Client) {
  $stream = $Client.GetStream()
  $buffer = New-Object byte[] 65536
  $received = New-Object System.Collections.Generic.List[byte]
  do {
    $count = $stream.Read($buffer, 0, $buffer.Length)
    if ($count -le 0) { break }
    for ($i = 0; $i -lt $count; $i++) { $received.Add($buffer[$i]) }
    $text = [Text.Encoding]::UTF8.GetString($received.ToArray())
    $headerEnd = $text.IndexOf("`r`n`r`n")
    if ($headerEnd -ge 0) {
      $headerText = $text.Substring(0, $headerEnd)
      $contentLength = 0
      if ($headerText -match "Content-Length:\s*(\d+)") { $contentLength = [int]$Matches[1] }
      $bodyBytes = $received.Count - ($headerEnd + 4)
      if ($bodyBytes -ge $contentLength) { break }
    }
  } while ($stream.DataAvailable -or $true)

  $raw = [Text.Encoding]::UTF8.GetString($received.ToArray())
  $parts = $raw -split "`r`n`r`n", 2
  $lines = $parts[0] -split "`r`n"
  $requestLine = $lines[0] -split " "
  $headers = @{}
  foreach ($line in ($lines | Select-Object -Skip 1)) {
    $separator = $line.IndexOf(":")
    if ($separator -gt 0) {
      $headers[$line.Substring(0, $separator).Trim().ToLower()] = $line.Substring($separator + 1).Trim()
    }
  }
  [ordered]@{
    method = $requestLine[0]
    path = $requestLine[1]
    body = $(if ($parts.Count -gt 1 -and $parts[1]) { $parts[1] } else { "" })
    headers = $headers
    stream = $stream
  }
}

function Send-Response($Stream, $StatusCode, $ContentType, $Body, $ExtraHeaders = @{}) {
  $reason = @{ 200 = "OK"; 400 = "Bad Request"; 401 = "Unauthorized"; 403 = "Forbidden"; 404 = "Not Found"; 409 = "Conflict"; 500 = "Internal Server Error" }[$StatusCode]
  if (-not $reason) { $reason = "OK" }
  $bytes = if ($Body -is [byte[]]) {
    $Body
  } elseif ($Body -is [System.Array] -and $Body.Count -and $Body[0] -is [byte]) {
    [byte[]]$Body
  } else {
    [Text.Encoding]::UTF8.GetBytes([string]$Body)
  }
  $headers = "HTTP/1.1 $StatusCode $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n"
  foreach ($key in $ExtraHeaders.Keys) { $headers += "$key`: $($ExtraHeaders[$key])`r`n" }
  $headers += "`r`n"
  $headerBytes = [Text.Encoding]::ASCII.GetBytes($headers)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  $Stream.Write($bytes, 0, $bytes.Length)
}

function Send-Json($Stream, $Value, $StatusCode = 200) {
  Send-Response $Stream $StatusCode "application/json; charset=utf-8" ($Value | ConvertTo-Json -Depth 20)
}

function Handle-Request($Request) {
  $pathOnly = (($Request.path -split "\?", 2)[0])
  if ($HostedAuthEnabled -and $pathOnly -eq "/api/auth/status" -and $Request.method -eq "GET") {
    return Send-Json $Request.stream (Get-HostedAuthSummary $Request)
  }
  if ($HostedAuthEnabled -and $pathOnly -eq "/api/auth/setup" -and $Request.method -eq "POST") {
    if (Test-Path $HostedSetupMarkerFile) { return Send-Json $Request.stream @{ error = "Master setup is already complete." } 409 }
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $name = Clean-Text $body.name
    $email = (Clean-Text $body.email).ToLower()
    $password = [string]$body.password
    if (-not $name -or $email -ne "2011vge@gmail.com" -or $password.Length -lt 10) {
      return Send-Json $Request.stream @{ error = "Use the authorized LotCaster Master email and a password of at least 10 characters." } 400
    }
    try {
      $result = Invoke-SupabaseRequest "/auth/v1/signup?redirect_to=http://127.0.0.1:$Port/" "POST" @{
        email = $email
        password = $password
        data = @{ display_name = $name }
      }
      New-Item -ItemType File -Force -Path $HostedSetupMarkerFile | Out-Null
      if (-not $result.access_token) {
        return Send-Json $Request.stream @{
          setupRequired = $false
          authenticated = $false
          hosted = $true
          confirmationRequired = $true
          loginEmail = $email
          message = "Check 2011vge@gmail.com for the confirmation email, then return here and sign in."
        }
      }
      $remember = [bool]$body.rememberDevice
      $token = New-HostedSession $result $remember
      $summaryRequest = [ordered]@{ headers = @{ cookie = "lotcaster_session=$token" } }
      return Send-Response $Request.stream 200 "application/json; charset=utf-8" ((Get-HostedAuthSummary $summaryRequest) | ConvertTo-Json -Depth 10) @{
        "Set-Cookie" = Get-HostedCookieHeader $token $remember
      }
    } catch {
      return Send-Json $Request.stream @{ error = $_.Exception.Message } 400
    }
  }
  if ($HostedAuthEnabled -and $pathOnly -eq "/api/auth/login" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    try {
      $result = Invoke-SupabaseRequest "/auth/v1/token?grant_type=password" "POST" @{
        email = (Clean-Text $body.email).ToLower()
        password = [string]$body.password
      }
      $remember = [bool]$body.rememberDevice
      $token = New-HostedSession $result $remember
      $summaryRequest = [ordered]@{ headers = @{ cookie = "lotcaster_session=$token" } }
      $summary = Get-HostedAuthSummary $summaryRequest
      if (-not $summary.authenticated) { throw "This account is not active in LotCaster. Ask your immediate manager for assistance." }
      return Send-Response $Request.stream 200 "application/json; charset=utf-8" ($summary | ConvertTo-Json -Depth 10) @{
        "Set-Cookie" = Get-HostedCookieHeader $token $remember
      }
    } catch {
      return Send-Json $Request.stream @{ error = $_.Exception.Message } 401
    }
  }
  if ($HostedAuthEnabled -and $pathOnly -eq "/api/auth/recover" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    try {
      Invoke-SupabaseRequest "/auth/v1/recover?redirect_to=http://127.0.0.1:$Port/" "POST" @{ email = (Clean-Text $body.email).ToLower() } | Out-Null
    } catch {}
    return Send-Json $Request.stream @{ ok = $true; message = "If that email has an active LotCaster account, password instructions have been sent." }
  }
  if ($HostedAuthEnabled -and $pathOnly -eq "/api/auth/complete-link" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $accessToken = [string]$body.accessToken
    $refreshToken = [string]$body.refreshToken
    $linkType = [string]$body.type
    $password = [string]$body.password
    if (-not $accessToken -or -not $refreshToken -or $linkType -notin @("invite", "recovery", "signup")) {
      return Send-Json $Request.stream @{ error = "This email link is incomplete or expired. Request a new link." } 400
    }
    if ($linkType -in @("invite", "recovery") -and $password.Length -lt 10) {
      return Send-Json $Request.stream @{ error = "Create a password of at least 10 characters." } 400
    }
    try {
      $authUser = Invoke-SupabaseRequest "/auth/v1/user" "GET" $null $accessToken
      if (-not $authUser.id) { throw "This email link is invalid or expired." }
      if ($password) {
        Invoke-SupabaseRequest "/auth/v1/user" "PUT" @{ password = $password } $accessToken | Out-Null
      }
      $authResponse = [ordered]@{
        access_token = $accessToken
        refresh_token = $refreshToken
        expires_in = $(if ([int]$body.expiresIn -gt 0) { [int]$body.expiresIn } else { 3600 })
        user = $authUser
      }
      $remember = [bool]$body.rememberDevice
      $token = New-HostedSession $authResponse $remember
      $summaryRequest = [ordered]@{ headers = @{ cookie = "lotcaster_session=$token" } }
      $summary = Get-HostedAuthSummary $summaryRequest
      if (-not $summary.authenticated) { throw "This account has not been activated in LotCaster." }
      return Send-Response $Request.stream 200 "application/json; charset=utf-8" ($summary | ConvertTo-Json -Depth 10) @{
        "Set-Cookie" = Get-HostedCookieHeader $token $remember
      }
    } catch {
      return Send-Json $Request.stream @{ error = $_.Exception.Message } 400
    }
  }
  if ($HostedAuthEnabled -and $pathOnly -eq "/api/auth/logout" -and $Request.method -eq "POST") {
    $session = Get-HostedSession $Request
    if ($session) {
      try { Invoke-SupabaseRequest "/auth/v1/logout?scope=local" "POST" @{} $session.accessToken | Out-Null } catch {}
      $HostedSessions.Remove($session.token) | Out-Null
      Save-HostedSessions
    }
    return Send-Response $Request.stream 200 "application/json; charset=utf-8" '{"authenticated":false}' @{
      "Set-Cookie" = "lotcaster_session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0"
    }
  }
  if (-not $HostedAuthEnabled -and $pathOnly -eq "/api/auth/status" -and $Request.method -eq "GET") {
    return Send-Json $Request.stream (Get-AuthSummary $Request)
  }
  if (-not $HostedAuthEnabled -and $pathOnly -eq "/api/auth/setup" -and $Request.method -eq "POST") {
    if (Test-Path $AuthFile) { return Send-Json $Request.stream @{ error = "Owner setup is already complete." } 409 }
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $name = Clean-Text $body.name
    $email = (Clean-Text $body.email).ToLower()
    $password = [string]$body.password
    if (-not $name -or $email -notmatch "^[^@\s]+@[^@\s]+\.[^@\s]+$" -or $password.Length -lt 10) {
      return Send-Json $Request.stream @{ error = "Enter a name, valid email, and password of at least 10 characters." } 400
    }
    $salt = New-RandomBytes 16
    $auth = [ordered]@{
      user = [ordered]@{
        id = "owner"
        name = $name
        email = $email
        role = $(if ($name.ToUpper() -eq "LOTCASTER" -and (Test-Path $MasterMarkerFile)) { "master" } else { "owner" })
        status = "active"
        passwordSalt = [Convert]::ToBase64String($salt)
        passwordHash = [Convert]::ToBase64String((Get-PasswordHash $password $salt))
        createdAt = (Get-Date).ToUniversalTime().ToString("o")
      }
      license = [ordered]@{
        status = "trial"
        plan = "internal"
        expiresAt = (Get-Date).ToUniversalTime().AddDays(30).ToString("o")
      }
    }
    Write-JsonFile $AuthFile $auth
    $token = New-Session $email
    $summaryRequest = [ordered]@{ headers = @{ cookie = "walker_session=$token" } }
    return Send-Response $Request.stream 200 "application/json; charset=utf-8" ((Get-AuthSummary $summaryRequest) | ConvertTo-Json -Depth 10) @{
      "Set-Cookie" = "walker_session=$token; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200"
    }
  }
  if (-not $HostedAuthEnabled -and $pathOnly -eq "/api/auth/login" -and $Request.method -eq "POST") {
    $auth = Read-JsonFile $AuthFile $null
    if (-not $auth) { return Send-Json $Request.stream @{ error = "Owner setup is required." } 400 }
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $email = (Clean-Text $body.email).ToLower()
    $loginUser = Get-UserByEmail $email
    if (-not $loginUser -or [string]$loginUser.status -eq "inactive") {
      return Send-Json $Request.stream @{ error = "Email or password is incorrect." } 401
    }
    $salt = [Convert]::FromBase64String([string]$loginUser.passwordSalt)
    $expected = [Convert]::FromBase64String([string]$loginUser.passwordHash)
    $actual = Get-PasswordHash ([string]$body.password) $salt
    if (-not (Test-SecureEqual $actual $expected)) {
      return Send-Json $Request.stream @{ error = "Email or password is incorrect." } 401
    }
    $token = New-Session $email
    $summaryRequest = [ordered]@{ headers = @{ cookie = "walker_session=$token" } }
    return Send-Response $Request.stream 200 "application/json; charset=utf-8" ((Get-AuthSummary $summaryRequest) | ConvertTo-Json -Depth 10) @{
      "Set-Cookie" = "walker_session=$token; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200"
    }
  }
  if (-not $HostedAuthEnabled -and $pathOnly -eq "/api/auth/logout" -and $Request.method -eq "POST") {
    $session = Get-Session $Request
    if ($session) { $Sessions.Remove($session.token) | Out-Null }
    return Send-Response $Request.stream 200 "application/json; charset=utf-8" '{"authenticated":false}' @{
      "Set-Cookie" = "walker_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0"
    }
  }
  if ($pathOnly.StartsWith("/api/") -and $HostedAuthEnabled -and -not (Get-HostedSession $Request)) {
    return Send-Json $Request.stream @{ error = "Sign in is required." } 401
  }
  if ($pathOnly.StartsWith("/api/") -and -not $HostedAuthEnabled -and -not (Get-Session $Request)) {
    return Send-Json $Request.stream @{ error = "Sign in is required." } 401
  }
  $currentApiUser = Get-CurrentUser $Request
  if ($pathOnly.StartsWith("/api/") -and (-not $currentApiUser -or [string]$currentApiUser.role -notin @(
    "master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support", "owner", "manager", "salesperson"
  ))) {
    return Send-Json $Request.stream @{ error = "This account has not been assigned an active LotCaster role." } 403
  }
  if ([string]$currentApiUser.role -eq "salesperson" -and (
    ($pathOnly -eq "/api/settings" -and $Request.method -ne "GET") -or $pathOnly -in @(
    "/api/scrape", "/api/auto-import", "/api/manual", "/api/import", "/api/import-page", "/api/import-html",
    "/api/export.csv", "/api/auto-import.csv"
  ))) {
    return Send-Json $Request.stream @{ error = "Manager access is required for inventory administration." } 403
  }
  if ($pathOnly.StartsWith("/api/admin/") -and -not (Test-PlatformDealerAdminAccess $Request)) {
    return Send-Json $Request.stream @{ error = "LotCaster dealer administration access is required." } 403
  }
  if ($pathOnly -eq "/api/team" -and $Request.method -eq "GET") {
    if (-not (Test-TeamManagerAccess $Request)) { return Send-Json $Request.stream @{ error = "Manager access is required." } 403 }
    if ($HostedAuthEnabled) {
      try { return Send-Json $Request.stream (Add-LocalInventoryMetrics (Invoke-HostedAdmin $Request "list_team")) }
      catch { return Send-Json $Request.stream @{ error = $_.Exception.Message } 400 }
    }
    return Send-Json $Request.stream (Get-TeamSummary)
  }
  if ($pathOnly -eq "/api/team/users" -and $Request.method -eq "POST") {
    if (-not (Test-TeamManagerAccess $Request)) { return Send-Json $Request.stream @{ error = "Manager access is required." } 403 }
    $currentUser = Get-CurrentUser $Request
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    if ($HostedAuthEnabled) {
      try { return Send-Json $Request.stream (Invoke-HostedAdmin $Request "invite_team_user" $body) }
      catch { return Send-Json $Request.stream @{ error = $_.Exception.Message } 400 }
    }
    $name = Clean-Text $body.name
    $email = (Clean-Text $body.email).ToLower()
    $password = [string]$body.password
    $role = if ([string]$body.role -eq "manager") { "manager" } else { "salesperson" }
    if ([string]$currentUser.role -eq "manager") { $role = "salesperson" }
    if (-not $name -or $email -notmatch "^[^@\s]+@[^@\s]+\.[^@\s]+$" -or $password.Length -lt 8) {
      return Send-Json $Request.stream @{ error = "Enter a name, valid email, and temporary password of at least 8 characters." } 400
    }
    if (Get-UserByEmail $email) { return Send-Json $Request.stream @{ error = "That email is already registered." } 409 }
    $salt = New-RandomBytes 16
    $team = Read-TeamData
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $user = [ordered]@{
      id = [Guid]::NewGuid().ToString("N")
      name = $name
      email = $email
      role = $role
      status = "active"
      passwordSalt = [Convert]::ToBase64String($salt)
      passwordHash = [Convert]::ToBase64String((Get-PasswordHash $password $salt))
      createdAt = $now
      createdBy = [string]$currentUser.id
    }
    $team.users = @($team.users) + $user
    Write-JsonFile $TeamFile $team
    Add-TeamActivity "user_created" $null $currentUser "$name added as $role"
    return Send-Json $Request.stream (Get-TeamSummary)
  }
  if ($pathOnly -eq "/api/team/user-status" -and $Request.method -eq "POST") {
    if (-not (Test-TeamManagerAccess $Request)) { return Send-Json $Request.stream @{ error = "Manager access is required." } 403 }
    $currentUser = Get-CurrentUser $Request
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    if ($HostedAuthEnabled) {
      try {
        $result = Invoke-HostedAdmin $Request "set_user_state" $body
        if ([string]$body.status -eq "inactive") { Remove-HostedSessionsForUser ([string]$body.id) }
        return Send-Json $Request.stream $result
      }
      catch { return Send-Json $Request.stream @{ error = $_.Exception.Message } 400 }
    }
    $team = Read-TeamData
    $user = @($team.users) | Where-Object { $_.id -eq [string]$body.id } | Select-Object -First 1
    if (-not $user) { return Send-Json $Request.stream @{ error = "Team member was not found." } 404 }
    if ([string]$currentUser.role -eq "manager" -and [string]$user.role -ne "salesperson") {
      return Send-Json $Request.stream @{ error = "Managers may only update salesperson access." } 403
    }
    $status = if ([string]$body.status -eq "inactive") { "inactive" } else { "active" }
    Set-ObjectValue $user "status" $status
    Write-JsonFile $TeamFile $team
    Add-TeamActivity "user_status" $null $currentUser "$($user.name) set to $status"
    return Send-Json $Request.stream (Get-TeamSummary)
  }
  if ($pathOnly -eq "/api/team/reset-password" -and $Request.method -eq "POST") {
    if (-not (Test-TeamManagerAccess $Request)) { return Send-Json $Request.stream @{ error = "Manager access is required." } 403 }
    $currentUser = Get-CurrentUser $Request
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    if ($HostedAuthEnabled) {
      try {
        $result = Invoke-HostedAdmin $Request "send_password_reset" $body
        Remove-HostedSessionsForUser ([string]$body.id)
        return Send-Json $Request.stream $result
      }
      catch { return Send-Json $Request.stream @{ error = $_.Exception.Message } 400 }
    }
    $password = [string]$body.password
    if ($password.Length -lt 8) { return Send-Json $Request.stream @{ error = "Temporary password must be at least 8 characters." } 400 }
    $team = Read-TeamData
    $user = @($team.users) | Where-Object { $_.id -eq [string]$body.id } | Select-Object -First 1
    if (-not $user) { return Send-Json $Request.stream @{ error = "Team member was not found." } 404 }
    if ([string]$currentUser.role -eq "manager" -and [string]$user.role -ne "salesperson") {
      return Send-Json $Request.stream @{ error = "Managers may only reset salesperson passwords." } 403
    }
    $salt = New-RandomBytes 16
    Set-ObjectValue $user "passwordSalt" ([Convert]::ToBase64String($salt))
    Set-ObjectValue $user "passwordHash" ([Convert]::ToBase64String((Get-PasswordHash $password $salt)))
    Set-ObjectValue $user "passwordUpdatedAt" ((Get-Date).ToUniversalTime().ToString("o"))
    Write-JsonFile $TeamFile $team
    Add-TeamActivity "password_reset" $null $currentUser "$($user.name) login password reset"
    return Send-Json $Request.stream (Get-TeamSummary)
  }
  if ($pathOnly -eq "/api/team/assign" -and $Request.method -eq "POST") {
    if (-not (Test-TeamManagerAccess $Request)) { return Send-Json $Request.stream @{ error = "Manager access is required." } 403 }
    $currentUser = Get-CurrentUser $Request
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $store = Read-JsonFile $StoreFile (Empty-Store)
    $vehicle = @($store.vehicles) | Where-Object { $_.id -eq [string]$body.vehicleId } | Select-Object -First 1
    if (-not $vehicle) { return Send-Json $Request.stream @{ error = "Vehicle was not found." } 404 }
    $team = if ($HostedAuthEnabled) {
      try { Add-LocalInventoryMetrics (Invoke-HostedAdmin $Request "list_team") }
      catch { return Send-Json $Request.stream @{ error = $_.Exception.Message } 400 }
    } else {
      Get-TeamSummary
    }
    $assignee = @($team.users) | Where-Object { $_.id -eq [string]$body.userId -and $_.role -eq "salesperson" -and $_.status -eq "active" } | Select-Object -First 1
    if ($body.userId -and -not $assignee) { return Send-Json $Request.stream @{ error = "Select an active salesperson." } 400 }
    $now = (Get-Date).ToUniversalTime().ToString("o")
    Set-ObjectValue $vehicle "assignedToId" $(if ($assignee) { [string]$assignee.id } else { "" })
    Set-ObjectValue $vehicle "assignedToName" $(if ($assignee) { [string]$assignee.name } else { "" })
    Set-ObjectValue $vehicle "assignedToEmail" $(if ($assignee) { [string]$assignee.email } else { "" })
    Set-ObjectValue $vehicle "assignedAt" $(if ($assignee) { $now } else { $null })
    Set-ObjectValue $vehicle "assignedById" ([string]$currentUser.id)
    Set-ObjectValue $vehicle "assignedByName" ([string]$currentUser.name)
    Set-ObjectValue $vehicle "assignmentDueAt" $(if ($assignee -and $body.dueAt) { [string]$body.dueAt } else { $null })
    Set-ObjectValue $vehicle "workflowStatus" $(if ($assignee) { "assigned" } else { "ready" })
    Write-JsonFile $StoreFile $store
    Add-TeamActivity $(if ($assignee) { "assigned" } else { "unassigned" }) $vehicle $currentUser $(if ($assignee) { "Assigned to $($assignee.name)" } else { "Assignment removed" })
    $updatedTeam = if ($HostedAuthEnabled) { Add-LocalInventoryMetrics (Invoke-HostedAdmin $Request "list_team") } else { Get-TeamSummary }
    return Send-Json $Request.stream @{ store = $store; team = $updatedTeam }
  }
  if ($pathOnly -eq "/api/admin/dealers" -and $Request.method -eq "GET") {
    if ($HostedAuthEnabled) {
      try { return Send-Json $Request.stream (Invoke-HostedAdmin $Request "list_dealers") }
      catch { return Send-Json $Request.stream @{ error = $_.Exception.Message } 400 }
    }
    return Send-Json $Request.stream (Read-DealerAccess)
  }
  if ($pathOnly -eq "/api/admin/dealers" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    if ($HostedAuthEnabled) {
      try { return Send-Json $Request.stream (Invoke-HostedAdmin $Request "create_dealer" $body) }
      catch { return Send-Json $Request.stream @{ error = $_.Exception.Message } 400 }
    }
    $name = Clean-Text $body.name
    $email = (Clean-Text $body.ownerEmail).ToLower()
    if (-not $name -or $email -notmatch "^[^@\s]+@[^@\s]+\.[^@\s]+$") {
      return Send-Json $Request.stream @{ error = "Enter a dealership name and valid owner email." } 400
    }
    $registry = Read-DealerAccess
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $dealer = [ordered]@{
      id = [Guid]::NewGuid().ToString("N")
      name = $name
      ownerEmail = $email
      plan = Clean-Text $(if ($body.plan) { $body.plan } else { "pilot" })
      status = "active"
      expiresAt = $(if ($body.expiresAt) { [string]$body.expiresAt } else { $null })
      notes = Clean-Text $body.notes
      createdAt = $now
      updatedAt = $now
    }
    $registry.dealers = @($registry.dealers) + $dealer
    Write-JsonFile $DealerAccessFile $registry
    return Send-Json $Request.stream $registry
  }
  if ($pathOnly -eq "/api/admin/dealer-status" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    if ($HostedAuthEnabled) {
      try { return Send-Json $Request.stream (Invoke-HostedAdmin $Request "set_dealer_state" $body) }
      catch { return Send-Json $Request.stream @{ error = $_.Exception.Message } 400 }
    }
    $registry = Read-DealerAccess
    $dealer = @($registry.dealers) | Where-Object { $_.id -eq [string]$body.id } | Select-Object -First 1
    if (-not $dealer) { return Send-Json $Request.stream @{ error = "Dealer was not found." } 404 }
    $status = if ([string]$body.status -eq "suspended") { "suspended" } else { "active" }
    Set-ObjectValue $dealer "status" $status
    Set-ObjectValue $dealer "updatedAt" (Get-Date).ToUniversalTime().ToString("o")
    Write-JsonFile $DealerAccessFile $registry
    return Send-Json $Request.stream $registry
  }
  if ($pathOnly -eq "/api/settings" -and $Request.method -eq "GET") {
    return Send-Json $Request.stream (Read-JsonFile $SettingsFile $DefaultSettings)
  }
  if ($pathOnly -eq "/api/settings" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $current = Read-JsonFile $SettingsFile $DefaultSettings
    foreach ($prop in $body.PSObject.Properties) { $current | Add-Member -Force -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
    $current = Normalize-SettingsObject $current
    Write-JsonFile $SettingsFile $current
    return Send-Json $Request.stream $current
  }
  if ($pathOnly -eq "/api/inventory" -and $Request.method -eq "GET") {
    $store = Read-JsonFile $StoreFile (Empty-Store)
    return Send-Json $Request.stream (Get-VisibleStore $store (Get-CurrentUser $Request))
  }
  if ($pathOnly -eq "/api/scrape" -and $Request.method -eq "POST") {
    $currentUser = Get-CurrentUser $Request
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    foreach ($prop in $body.PSObject.Properties) { $settings | Add-Member -Force -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
    $settings = Normalize-SettingsObject $settings
    Write-JsonFile $SettingsFile $settings
    try {
      $scraped = Scrape-Inventory $settings
      $store = Merge-Inventory $scraped
      Write-JsonFile $StoreFile $store
    } catch {
      $store = Get-RefreshFallbackStore $settings $_.Exception.Message
    }
    return Send-Json $Request.stream (Get-VisibleStore $store $currentUser)
  }
  if ($pathOnly -eq "/api/auto-import" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    foreach ($prop in $body.PSObject.Properties) { $settings | Add-Member -Force -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
    $settings = Normalize-SettingsObject $settings
    Write-JsonFile $SettingsFile $settings
    try {
      $scraped = Scrape-Inventory $settings
      $store = Merge-Inventory $scraped
      $store.autoCsvAvailable = @($store.vehicles).Count -gt 0
      Write-JsonFile $StoreFile $store
    } catch {
      $store = Get-RefreshFallbackStore $settings $_.Exception.Message
    }
    Write-AutoCsv $store.vehicles
    return Send-Json $Request.stream $store
  }
  if ($pathOnly -eq "/api/manual" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    foreach ($prop in $body.PSObject.Properties) {
      if ($prop.Name -ne "vehicle" -and $prop.Name -ne "csvText") {
        $settings | Add-Member -Force -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
      }
    }
    $settings = Normalize-SettingsObject $settings
    Write-JsonFile $SettingsFile $settings
    $vehicle = Normalize-Vehicle $body.vehicle $settings.inventoryUrl
    if (-not $vehicle.title) { throw "Vehicle title is required." }
    $vehicle.marketplaceText = Build-MarketplaceText $vehicle $settings
    $scraped = [ordered]@{ sourceUrl = $settings.inventoryUrl; warnings = @(); vehicles = @($vehicle) }
    $store = Merge-Inventory $scraped $false
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    return Send-Json $Request.stream $store
  }
  if ($pathOnly -eq "/api/import" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    foreach ($prop in $body.PSObject.Properties) {
      if ($prop.Name -ne "vehicle" -and $prop.Name -ne "csvText") {
        $settings | Add-Member -Force -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
      }
    }
    $settings = Normalize-SettingsObject $settings
    Write-JsonFile $SettingsFile $settings
    $rows = @()
    if ($body.csvText) { $rows = @(ConvertFrom-CsvText $body.csvText) }
    $vehicles = @()
    foreach ($row in $rows) {
      $vehicle = Convert-CsvRowToVehicle $row $settings
      if ($vehicle.title -and $vehicle.title -ne "title" -and $vehicle.title -notmatch "PSPath=") { $vehicles += $vehicle }
    }
    if (-not @($vehicles).Count) { throw "No vehicle rows were found in that CSV." }
    $scraped = [ordered]@{ sourceUrl = "CSV import"; warnings = @(); vehicles = @($vehicles) }
    $store = Merge-Inventory $scraped $false
    $store.autoCsvAvailable = $true
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    return Send-Json $Request.stream $store
  }
  if ($pathOnly -eq "/api/import-page" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    foreach ($prop in $body.PSObject.Properties) {
      if ($prop.Name -ne "pageText") {
        $settings | Add-Member -Force -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
      }
    }
    $settings = Normalize-SettingsObject $settings
    Write-JsonFile $SettingsFile $settings
    $vehicles = @(ConvertFrom-PageText $body.pageText $settings)
    if (-not @($vehicles).Count) {
      throw "No vehicle listings were found in the pasted page text. Copy the visible listing results, not just the page link."
    }
    $scraped = [ordered]@{
      sourceUrl = "Pasted page import"
      warnings = @("Pasted page import is a fallback for unsupported websites. Review each listing before posting.")
      vehicles = @($vehicles)
    }
    $store = Merge-Inventory $scraped $false
    $store.autoCsvAvailable = $true
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    return Send-Json $Request.stream $store
  }
  if ($pathOnly -eq "/api/import-html" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    foreach ($prop in $body.PSObject.Properties) {
      if ($prop.Name -notin @("html", "pages", "sourceUrl")) { $settings | Add-Member -Force -NotePropertyName $prop.Name -NotePropertyValue $prop.Value }
    }
    $settings = Normalize-SettingsObject $settings
    $sourceUrl = if ($body.sourceUrl) { [string]$body.sourceUrl } else { $settings.inventoryUrl }
    $pageInputs = @()
    if ($body.pages -and @($body.pages).Count) {
      $pageInputs = @($body.pages)
    } else {
      $pageInputs = @([pscustomobject]@{ url = $sourceUrl; html = [string]$body.html })
    }
    $collected = @()
    foreach ($page in $pageInputs) {
      $pageUrl = if ($page.url) { [string]$page.url } else { $sourceUrl }
      $pageVehicles = @(Parse-DealerComVehicles ([string]$page.html) $pageUrl)
      if (-not $pageVehicles.Count) { $pageVehicles = @(Parse-AutoTraderVehicles ([string]$page.html) $pageUrl) }
      $collected += @($pageVehicles)
    }
    $vehicles = @(Dedupe-Vehicles $collected)
    if (-not $vehicles.Count) {
      $diagnostic = Join-Path $DataDir "last-unparsed-inventory-source.html"
      [System.IO.File]::WriteAllText($diagnostic, [string]$body.html, [System.Text.UTF8Encoding]::new($false))
      throw "The browser helper retrieved the source, but no vehicle listings could be parsed. A local diagnostic copy was saved for repair."
    }
    foreach ($vehicle in $vehicles) { $vehicle.marketplaceText = Build-MarketplaceText $vehicle $settings }
    $scraped = [ordered]@{ sourceUrl = $sourceUrl; warnings = @("Inventory and prices were verified through the LotCaster browser helper."); vehicles = @($vehicles) }
    $store = Merge-Inventory $scraped
    Write-JsonFile $SettingsFile $settings
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    return Send-Json $Request.stream $store
  }
  if ($pathOnly -eq "/api/facebook-status" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $store = Read-JsonFile $StoreFile (Empty-Store)
    $vehicle = @($store.vehicles) | Where-Object { $_.id -eq [string]$body.id } | Select-Object -First 1
    if (-not $vehicle) { throw "Vehicle was not found." }
    if (-not (Test-VehicleAccess $Request $vehicle)) { return Send-Json $Request.stream @{ error = "This vehicle is not assigned to you." } 403 }
    if ($body.posted -and -not (Test-DateIsToday $vehicle.priceVerifiedAt)) {
      return Send-Json $Request.stream @{ error = "Today's price has not been verified. Refresh inventory successfully before marking this vehicle published." } 409
    }
    $currentUser = Get-CurrentUser $Request
    $postedAt = if ($body.posted) { (Get-Date).ToUniversalTime().ToString("o") } else { $null }
    Set-ObjectValue $vehicle "facebookPostedAt" $postedAt
    Set-ObjectValue $vehicle "postedById" $(if ($body.posted) { [string]$currentUser.id } else { "" })
    Set-ObjectValue $vehicle "postedByName" $(if ($body.posted) { [string]$currentUser.name } else { "" })
    Set-ObjectValue $vehicle "workflowStatus" $(if ($body.posted) { "posted" } elseif ($vehicle.preparedAt) { "prepared" } elseif ($vehicle.assignedToId) { "assigned" } else { "ready" })
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    Add-TeamActivity $(if ($body.posted) { "posted" } else { "unposted" }) $vehicle $currentUser $(if ($body.posted) { "Marked posted" } else { "Returned to posting queue" })
    return Send-Json $Request.stream (Get-VisibleStore $store $currentUser)
  }
  if ($pathOnly -eq "/api/vehicle-category" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $store = Read-JsonFile $StoreFile (Empty-Store)
    $vehicle = @($store.vehicles) | Where-Object { $_.id -eq [string]$body.id } | Select-Object -First 1
    if (-not $vehicle) { throw "Vehicle was not found." }
    if (-not (Test-VehicleAccess $Request $vehicle)) { return Send-Json $Request.stream @{ error = "This vehicle is not assigned to you." } 403 }
    $bodyType = Get-BodyType $body.bodyType $vehicle.title $vehicle.model
    Set-ObjectValue $vehicle "bodyType" $bodyType
    Set-ObjectValue $vehicle "facebookListingType" "Car/Truck"
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    Set-ObjectValue $vehicle "marketplaceText" (Build-MarketplaceText $vehicle $settings)
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    return Send-Json $Request.stream @{ id = $vehicle.id; bodyType = $bodyType; vehicle = $vehicle }
  }
  if ($pathOnly -eq "/api/vehicle-details" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $store = Read-JsonFile $StoreFile (Empty-Store)
    $vehicle = @($store.vehicles) | Where-Object { $_.id -eq [string]$body.id } | Select-Object -First 1
    if (-not $vehicle) { throw "Vehicle was not found." }
    if (-not (Test-VehicleAccess $Request $vehicle)) { return Send-Json $Request.stream @{ error = "This vehicle is not assigned to you." } 403 }
    $currentUser = Get-CurrentUser $Request
    $bodyType = Get-BodyType $body.bodyType $vehicle.title $vehicle.model
    Set-ObjectValue $vehicle "bodyType" $bodyType
    Set-ObjectValue $vehicle "facebookListingType" "Car/Truck"
    Set-ObjectValue $vehicle "bodyStyle" (Get-BodyStyle $body.bodyStyle $bodyType $vehicle.title)
    Set-ObjectValue $vehicle "exteriorColor" (Get-SimpleVehicleColor $body.exteriorColor)
    Set-ObjectValue $vehicle "interiorColor" (Get-SimpleVehicleColor $body.interiorColor)
    Set-ObjectValue $vehicle "fuelType" (Get-FuelType $body.fuelType $vehicle.title)
    if ([string]$currentUser.role -ne "salesperson") {
      Set-ObjectValue $vehicle "condition" $(if ($body.condition) { Clean-Text $body.condition } else { "Excellent" })
    }
    Set-ObjectValue $vehicle "customDescription" (Clean-Description $body.customDescription)
    Set-ObjectValue $vehicle "preparedAt" (Get-Date).ToUniversalTime().ToString("o")
    Set-ObjectValue $vehicle "preparedById" ([string]$currentUser.id)
    Set-ObjectValue $vehicle "preparedByName" ([string]$currentUser.name)
    if (-not $vehicle.facebookPostedAt) { Set-ObjectValue $vehicle "workflowStatus" "prepared" }
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    Set-ObjectValue $vehicle "marketplaceText" (Build-MarketplaceText $vehicle $settings)
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    Add-TeamActivity "prepared" $vehicle $currentUser "Listing details saved"
    return Send-Json $Request.stream @{ id = $vehicle.id; vehicle = $vehicle }
  }
  if ($pathOnly -eq "/api/vehicle-photos" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $store = Read-JsonFile $StoreFile (Empty-Store)
    $vehicle = @($store.vehicles) | Where-Object { $_.id -eq [string]$body.id } | Select-Object -First 1
    if (-not $vehicle) { throw "Vehicle was not found." }
    if (-not (Test-VehicleAccess $Request $vehicle)) { return Send-Json $Request.stream @{ error = "This vehicle is not assigned to you." } 403 }
    if ($vehicle.url -notmatch "^https?://") { throw "This vehicle does not have a supported detail page." }
    $details = if ($vehicle.url -match "^https://(www\.)?autotrader\.com/") { Get-AutoTraderDetailData $vehicle.url } else { Get-GenericDetailData $vehicle.url }
    $discoveredPhotos = @($details.photos)
    $photos = @(Merge-PhotoSets -Existing @($vehicle.images) -Incoming @($discoveredPhotos))
    if (-not $photos.Count -and $vehicle.image) { $photos = @($vehicle.image) }
    Set-ObjectValue $vehicle "images" $photos
    if ($photos.Count) { Set-ObjectValue $vehicle "image" $photos[0] }
    if ($details.fuelType -and -not $vehicle.fuelType) { Set-ObjectValue $vehicle "fuelType" $details.fuelType }
    if (-not $vehicle.condition) { Set-ObjectValue $vehicle "condition" "Excellent" }
    $settings = Read-JsonFile $SettingsFile $DefaultSettings
    Set-ObjectValue $vehicle "marketplaceText" (Build-MarketplaceText $vehicle $settings)
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    Add-TeamActivity "photos_updated" $vehicle (Get-CurrentUser $Request) "$($photos.Count) vehicle photos available"
    return Send-Json $Request.stream @{ id = $vehicle.id; images = $photos; vehicle = $vehicle }
  }
  if ($pathOnly -eq "/api/import-vehicle-html" -and $Request.method -eq "POST") {
    $body = if ($Request.body) { $Request.body | ConvertFrom-Json } else { [pscustomobject]@{} }
    $store = Read-JsonFile $StoreFile (Empty-Store)
    $vehicle = @($store.vehicles) | Where-Object { $_.id -eq [string]$body.id } | Select-Object -First 1
    if (-not $vehicle) { return Send-Json $Request.stream @{ error = "Vehicle was not found." } 404 }
    if (-not (Test-VehicleAccess $Request $vehicle)) { return Send-Json $Request.stream @{ error = "This vehicle is not assigned to you." } 403 }
    $sourceUrl = if ($body.sourceUrl) { [string]$body.sourceUrl } else { [string]$vehicle.url }
    $details = Parse-AutoTraderDetailHtml ([string]$body.html) $sourceUrl
    $photos = @(Merge-PhotoSets -Existing @($vehicle.images) -Incoming @($details.photos))
    if (-not $photos.Count -and $vehicle.image) { $photos = @($vehicle.image) }
    Set-ObjectValue $vehicle "images" $photos
    if ($photos.Count) { Set-ObjectValue $vehicle "image" $photos[0] }
    if ($details.fuelType -and -not $vehicle.fuelType) { Set-ObjectValue $vehicle "fuelType" $details.fuelType }
    Write-JsonFile $StoreFile $store
    Write-AutoCsv $store.vehicles
    Add-TeamActivity "photos_updated" $vehicle (Get-CurrentUser $Request) "$($photos.Count) vehicle photos available through browser helper"
    return Send-Json $Request.stream @{ id = $vehicle.id; images = $photos; vehicle = $vehicle }
  }
  if ($pathOnly -eq "/api/export.csv" -and $Request.method -eq "GET") {
    $store = Read-JsonFile $StoreFile (Empty-Store)
    return Send-Response $Request.stream 200 "text/csv; charset=utf-8" (ConvertTo-CsvText $store.vehicles) @{ "Content-Disposition" = 'attachment; filename="lotcaster-inventory.csv"' }
  }
  if ($pathOnly -eq "/api/auto-import.csv" -and $Request.method -eq "GET") {
    $store = Read-JsonFile $StoreFile (Empty-Store)
    if (-not (Test-Path $AutoCsvFile)) { Write-AutoCsv $store.vehicles }
    return Send-Response $Request.stream 200 "text/csv; charset=utf-8" (Get-Content -Path $AutoCsvFile -Raw) @{ "Content-Disposition" = 'attachment; filename="lotcaster-latest-import.csv"' }
  }

  $relativePath = if ($pathOnly -eq "/") { "index.html" } else { [Uri]::UnescapeDataString($pathOnly.TrimStart("/")) }
  $filePath = [IO.Path]::GetFullPath((Join-Path $PublicDir $relativePath))
  $publicRoot = [IO.Path]::GetFullPath($PublicDir).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $filePath.StartsWith($publicRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $filePath)) {
    return Send-Json $Request.stream @{ error = "Not found" } 404
  }
  $ext = [IO.Path]::GetExtension($filePath)
  $contentType = if ($MimeTypes.ContainsKey($ext)) { $MimeTypes[$ext] } else { "application/octet-stream" }
  $headers = @{}
  if ($ext -in @(".html", ".js", ".css") -or $relativePath -eq "sw.js") { $headers["Cache-Control"] = "no-store" }
  $content = if ($ext -in @(".png", ".ico")) { [IO.File]::ReadAllBytes($filePath) } else { Get-Content -Path $filePath -Raw }
  Send-Response $Request.stream 200 $contentType $content $headers
}

Initialize-Data
Load-HostedSessions
if ($NoListen) { return }
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $Port)
$listener.Start()
$localIp = $null
try {
  $localIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1 -ExpandProperty IPAddress)
} catch {
  $localIp = $null
}
Write-Host "LotCaster running:"
Write-Host "  Windows: http://localhost:$Port"
if ($localIp) {
  Write-Host "  iPhone:  http://$localIp`:$Port"
} else {
  Write-Host "  iPhone:  open http://YOUR-WINDOWS-IP:$Port after finding your IPv4 address with ipconfig"
}
Write-Host "Press Ctrl+C to stop."

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $request = Read-HttpRequest $client
    Handle-Request $request
  } catch {
    try { Send-Json $client.GetStream() @{ error = $_.Exception.Message } 500 } catch {}
  } finally {
    $client.Close()
  }
}
