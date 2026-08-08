$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\Start-InventoryTool.ps1" -NoListen

function Assert-Equal($Actual, $Expected, $Message) {
  if ($Actual -ne $Expected) {
    throw "$Message Expected '$Expected' but received '$Actual'."
  }
}

function Assert-True($Condition, $Message) {
  if (-not $Condition) { throw $Message }
}

$normalizedUrl = Normalize-InventoryUrl "https://www.autotrader.com/car-dealers/example?listingType=USED&msockid=tracking&utm_source=test"
Assert-True ($normalizedUrl -match "listingType=USED") "Useful AutoTrader parameters must be preserved."
Assert-True ($normalizedUrl -notmatch "msockid|utm_source") "Known tracking parameters must be removed."

$photos = @(Merge-PhotoSets -Existing @("https://example.com/1.jpg", "https://example.com/2.jpg") -Incoming @("https://example.com/2.jpg", "https://example.com/3.jpg"))
Assert-Equal $photos.Count 3 "Photo merging must preserve and deduplicate richer galleries."
Assert-Equal $photos[0] "https://example.com/1.jpg" "Existing primary photo order must be preserved."

$first = Normalize-Vehicle @{ title = "2024 Chevrolet Silverado 1500"; vin = "1TESTVIN123456789"; image = "https://example.com/1.jpg" } "https://example.com"
$second = Normalize-Vehicle @{ title = "Updated title"; vin = "1TESTVIN123456789" } "https://example.com"
Assert-Equal $first.id $second.id "Vehicle identity must remain stable for the same VIN."
Assert-Equal $first.bodyType "truck" "Truck body type should be inferred from the vehicle title."
Assert-Equal $first.bodyStyle "Truck" "A truck should receive a useful default body style."

$suv = Normalize-Vehicle @{ title = "2023 Toyota RAV4"; stock = "TEST-2" } "https://example.com"
Assert-Equal $suv.bodyType "suv" "SUV body type should be inferred from the vehicle title."
Assert-Equal $suv.facebookListingType "Car/Truck" "Every LotCaster road vehicle must use Facebook's Car/Truck listing flow."

$settings = @{
  dealershipName = "Example Motors"
  city = "Franklin, TN"
  listingFooter = "Verify availability and pricing."
}
$listing = Build-MarketplaceText $first $settings
Assert-True ($listing -match "Category: TRUCK") "Listing packet text should include a known category."
Assert-True ($listing -match "Verify availability and pricing") "Listing packet text should include the dealership footer."

$custom = Normalize-Vehicle @{
  title = "2024 Example Coupe"
  stock = "CUSTOM-1"
  bodyType = "car"
  bodyStyle = "Coupe"
  exteriorColor = "Red Metallic"
  interiorColor = "Black"
  customDescription = "First paragraph.`n`nSecond paragraph."
} "https://example.com"
Assert-Equal $custom.bodyStyle "Coupe" "A supplied body style must be preserved."
Assert-Equal $custom.exteriorColor "Red" "Exterior color must be normalized to a Facebook-supported color."
Assert-True ($custom.customDescription -match "First paragraph\.`n`nSecond paragraph\.") "Custom descriptions must preserve paragraph breaks."

Write-Host "Phase 1 validation passed: URL normalization, identity, photo preservation, category inference, and listing text."
