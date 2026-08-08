$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\Start-InventoryTool.ps1" -NoListen

function Assert-Equal($Actual, $Expected, $Message) {
  if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', received '$Actual'." }
}

$html = @'
<div class="vehicle-card-body">
  <h2 class="vehicle-card-title"><a href="/used/GMC/2024-GMC-Sierra-1500-test.htm"><span>2024 GMC Sierra 1500 AT4</span></a></h2>
  <div class="highlight-badge">33,373 miles</div>
  <dl class="pricing-detail">
    <dt class="msrp"><span class="price-label">Retail Price</span></dt><dd class="msrp"><span class="price-value">$59,987</span></dd>
    <dt class="discount"><span class="price-label">Dealer Discount</span></dt><dd class="discount"><span class="price-value">-$7,999</span></dd>
    <dt class="invoicePrice"><span class="price-label">Doc Fee</span></dt><dd class="invoicePrice"><span class="price-value">$789</span></dd>
    <dt class="final-price internetPrice"><span class="price-label">Walker Sale Price</span></dt><dd class="final-price internetPrice"><span class="price-value">$52,777</span></dd>
  </dl>
  <div data-vin="3GTUUEEL9RG256670">Stock # TZ213345A</div>
</div>
'@
$vehicles = @(Parse-DealerComVehicles $html "https://www.walkerchevrolet.com/used-inventory/index.htm")
Assert-Equal $vehicles.Count 1 "Dealer.com fixture should produce one vehicle."
Assert-Equal $vehicles[0].price '$52777' "The labeled final sale price must be selected."
Assert-Equal $vehicles[0].sourcePriceIncludesDocFee $true "Retail minus discount plus doc fee equals final price, so the fee is included."
Assert-Equal $vehicles[0].bodyType 'truck' "The GMC Sierra must be categorized as a truck."
$settings = [pscustomobject]@{ docFee = '789'; sourcePriceIncludesDocFee = $false; dealershipName='Walker Chevrolet'; city='Franklin, TN'; listingFooter='Verify availability.' }
$pricing = Get-PostingPriceInfo $vehicles[0] $settings
Assert-Equal $pricing.postingText '$52,777' "An included doc fee must never be added twice."
$description = Build-MarketplaceText $vehicles[0] $settings
if ($description -notmatch 'Price: \$52,777' -or $description -match '55,765') { throw "Generated listing description contains the wrong price." }

$autoTraderHtml = @'
<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"__eggsState":{"inventory":{"781249239":{"id":781249239,"vin":"3GTUUEEL9RG256670","year":2024,"make":{"name":"GMC"},"model":{"name":"Sierra 1500"},"trim":{"name":"AT4"},"listingType":"USED","stockId":"TZ213345A","mileage":{"value":"33,373"},"pricingDetail":{"salePrice":51988,"displayPrice":52777,"dealerFeesTotal":789}}},"dealerdetails.urls":{"results":{"781249239":"/cars-for-sale/vehicle/781249239"}}}}}}</script>
'@
$autoTraderVehicles = @(Parse-AutoTraderVehicles $autoTraderHtml "https://www.autotrader.com/")
Assert-Equal $autoTraderVehicles.Count 1 "AutoTrader structured payload should produce one vehicle."
Assert-Equal $autoTraderVehicles[0].price '$52777' "AutoTrader salePrice must be selected."
Assert-Equal $autoTraderVehicles[0].sourcePriceIncludesDocFee $true "AutoTrader's displayed price formula must detect that the dealer fee is already included."
Assert-Equal (Get-PostingPriceInfo $autoTraderVehicles[0] $settings).postingText '$52,777' "AutoTrader's fee-inclusive sale price must remain $52,777."
Assert-Equal (Test-LikelyVehicleImageUrl 'https://images.autotrader.com/hn/c/vehicle-photo.jpg') $true "A real AutoTrader JPEG must be accepted as a photo."
Assert-Equal (Test-LikelyVehicleImageUrl 'https://www.autotrader.com/car-dealers/franklin-tn/100009092/NO_ACCIDENTS') $false "An AutoTrader HTML route must never be accepted as a photo."
Assert-Equal (Test-LikelyVehicleImageUrl 'https://www.autocheck.com/vehiclehistory/?vin=TEST') $false "A vehicle-history page must never be accepted as a photo."
Assert-Equal (Test-LikelyVehicleImageUrl 'https://www.autotrader.com/cars-for-sale/vehicle/block-images/error-message-icon.png') $false "AutoTrader's image error placeholder must never be accepted as a vehicle photo."

$notIncluded = Normalize-Vehicle ([ordered]@{title='2024 GMC Sierra 1500 AT4';vin='TESTVIN1234567890';price='52777'}) 'https://example.com'
Assert-Equal (Get-PostingPriceInfo $notIncluded $settings).postingText '$53,566' "Only the portal-configured $789 fee should be added when no inclusion signal exists."
Write-Host "Pricing regression checks passed."
