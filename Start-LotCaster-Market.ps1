param(
  [int]$Port = 5173,
  [switch]$NoListen
)

$ErrorActionPreference = "Stop"

# Load the existing LotCaster server, data migration, and functions without
# opening the TCP listener. Market Compare then overrides only the behaviors
# required for mixed New / Used / Certified inventory support.
. "$PSScriptRoot\Start-InventoryTool.ps1" -Port $Port -NoListen

$script:OriginalNormalizeSettingsObject = ${function:Normalize-SettingsObject}
$script:OriginalParseAutoTraderVehicles = ${function:Parse-AutoTraderVehicles}
$script:OriginalScrapeInventory = ${function:Scrape-Inventory}

function Get-MarketInventoryCondition($Value) {
  $text = (Clean-Text $Value).ToLower()
  if ($text -match "certified|cpo|carbravo") { return "certified" }
  if ($text -match "new") { return "new" }
  return "used"
}

function Normalize-SettingsObject($Settings) {
  $normalized = & $script:OriginalNormalizeSettingsObject $Settings
  $value = [string]$normalized.inventoryUrl
  try {
    $uri = [Uri]$value
    if ($uri.Host -match "(^|\.)autotrader\.com$" -and $uri.AbsolutePath -match "/100009092/") {
      $builder = [UriBuilder]$uri
      $query = [System.Web.HttpUtility]::ParseQueryString($builder.Query)
      $query["listingType"] = "NEW,USED,CERTIFIED"
      $builder.Query = $query.ToString()
      Set-ObjectValue $normalized "inventoryUrl" $builder.Uri.AbsoluteUri
    }
  } catch {}
  return $normalized
}

function Get-AutoTraderListingTypeMap($Html) {
  $map = @{}
  $match = [regex]::Match([string]$Html, "<script[^>]+id=[""']__NEXT_DATA__[""'][^>]*>([\s\S]*?)</script>", "IgnoreCase")
  if (-not $match.Success) { return $map }
  try {
    $root = [System.Web.HttpUtility]::HtmlDecode($match.Groups[1].Value) | ConvertFrom-Json
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($root)
    $visited = 0
    while ($queue.Count -gt 0 -and $visited -lt 60000) {
      $node = $queue.Dequeue()
      $visited++
      if ($null -eq $node -or $node -is [string] -or $node -is [ValueType]) { continue }
      if ($node -is [System.Collections.IEnumerable] -and $node -isnot [pscustomobject]) {
        foreach ($child in $node) { if ($null -ne $child) { $queue.Enqueue($child) } }
        continue
      }
      $props = $node.PSObject.Properties
      $vin = ""
      foreach ($name in @("vin", "VIN", "vehicleIdentificationNumber")) {
        if ($props[$name]) { $vin = (Clean-Text $props[$name].Value).ToUpper(); break }
      }
      if ($vin -match "^[A-HJ-NPR-Z0-9]{17}$" -and $props["listingType"]) {
        $listingType = Clean-Text $props["listingType"].Value
        if ($listingType) { $map[$vin] = $listingType }
      }
      foreach ($prop in $props) {
        if ($null -ne $prop.Value -and $prop.Value -isnot [string] -and $prop.Value -isnot [ValueType]) {
          $queue.Enqueue($prop.Value)
        }
      }
    }
  } catch {}
  return $map
}

function Parse-AutoTraderVehicles($Html, $BaseUrl) {
  $listingTypes = Get-AutoTraderListingTypeMap $Html

  # The legacy parser intentionally rejected NEW records. Feed it a temporary
  # in-memory representation where NEW satisfies that legacy gate, then restore
  # the real listing condition on each normalized vehicle by VIN. The source
  # HTML and original server file are never modified.
  $acceptedHtml = [regex]::Replace(
    [string]$Html,
    '("listingType"\s*:\s*")NEW(")',
    '$1USED_NEW$2',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  )
  $vehicles = @(& $script:OriginalParseAutoTraderVehicles $acceptedHtml $BaseUrl)
  foreach ($vehicle in $vehicles) {
    $vin = ([string]$vehicle.vin).ToUpper()
    $rawType = $(if ($listingTypes.ContainsKey($vin)) { $listingTypes[$vin] } else { "USED" })
    Set-ObjectValue $vehicle "inventoryCondition" (Get-MarketInventoryCondition $rawType)
  }
  return $vehicles
}

function Scrape-Inventory($Settings, [int]$Attempt = 1) {
  $normalized = Normalize-SettingsObject $Settings
  $source = [string]$normalized.inventoryUrl
  if ($source -match "autotrader\.com" -and $source -match "100009092") {
    # Walker's direct website fallback only exposes used inventory. Returning a
    # controlled refresh failure here makes the existing LotCaster UI use its
    # browser-helper fallback, which can load the mixed AutoTrader dealer view.
    throw "Mixed New / Used / Certified Walker inventory uses the LotCaster browser helper for refresh."
  }
  return & $script:OriginalScrapeInventory $normalized $Attempt
}

# Give existing pre-feature records a stable condition so the new filter is
# immediately useful before the first mixed inventory refresh.
try {
  $store = Read-JsonFile $StoreFile (Empty-Store)
  $changed = $false
  foreach ($vehicle in @($store.vehicles) + @($store.removed)) {
    if (-not $vehicle.PSObject.Properties["inventoryCondition"] -or -not $vehicle.inventoryCondition) {
      Set-ObjectValue $vehicle "inventoryCondition" "used"
      $changed = $true
    }
  }
  if ($changed) { Write-JsonFile $StoreFile $store }
} catch {}

if ($NoListen) { return }

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $Port)
$listener.Start()
$localIp = $null
try {
  $localIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1 -ExpandProperty IPAddress)
} catch {
  $localIp = $null
}
Write-Host "LotCaster running (Market Compare enabled):"
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
