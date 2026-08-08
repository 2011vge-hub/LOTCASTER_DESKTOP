$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\Start-InventoryTool.ps1" -NoListen

function Assert($Condition, $Message) {
  if (-not $Condition) { throw $Message }
}

$currentSource = "https://www.autotrader.com/car-dealers/nashville-tn/100009092/walker-chevrolet?listingType=USED"
$normalized = Normalize-InventoryUrl $currentSource
Assert ($normalized -match "/100009092/walker-chevrolet") "Dealer identity was lost while normalizing the current AutoTrader source."
Assert ($normalized -match "listingType=USED") "Used-inventory filtering was lost while normalizing the current AutoTrader source."

$genericCapture = Get-Content -Raw (Join-Path $PSScriptRoot "..\data\last-unparsed-inventory-source.html")
Assert (@(Parse-AutoTraderVehicles $genericCapture $currentSource).Count -eq 0) "A generic dealer-search response must not verify inventory."

Assert (Test-DateIsToday ([DateTimeOffset]::Now.ToString("o"))) "A current verification timestamp was not accepted."
Assert (-not (Test-DateIsToday ([DateTimeOffset]::Now.AddDays(-1).ToString("o")))) "A stale verification timestamp was accepted."
Assert (-not (Test-DateIsToday "not-a-date")) "An invalid verification timestamp was accepted."

$serverText = Get-Content -Raw "$PSScriptRoot\..\Start-InventoryTool.ps1"
Assert ($serverText -match 'if \(\$pathOnly -eq "/api/scrape"[\s\S]{0,180}\$currentUser = Get-CurrentUser') "Refresh route does not initialize the current user."
Assert ($serverText -match 'vehicle-category"[\s\S]{0,700}Test-VehicleAccess') "Vehicle category route lacks assignment access enforcement."
Assert ($serverText -match 'facebook-status"[\s\S]{0,900}Test-DateIsToday') "Publication status lacks current-price enforcement."

$appText = Get-Content -Raw "$PSScriptRoot\..\public\app.js"
$indexText = Get-Content -Raw "$PSScriptRoot\..\public\index.html"
$helperBackgroundText = Get-Content -Raw "$PSScriptRoot\..\facebook-helper\background.js"
Assert ($helperBackgroundText -notmatch 'searchParams\.set\("numRecords",\s*"100"\)') "Browser helper still uses AutoTrader's redirecting numRecords=100 URL."
Assert ($helperBackgroundText -match 'searchParams\.set\("firstRecord"') "Browser helper does not paginate AutoTrader dealer inventory."
Assert ($helperBackgroundText -match 'pages\.push') "Browser helper does not return the collected dealer pages."
Assert ($appText -match 'pages:\s*source\.pages') "Client does not submit all collected inventory pages."
Assert ($serverText -match '"html",\s*"pages",\s*"sourceUrl"') "Server does not recognize multi-page browser-helper imports."
foreach ($role in @("lotcaster_general_manager", "lotcaster_manager", "lotcaster_support")) {
  Assert ($appText -match [regex]::Escape($role)) "Client role gates omit $role."
}
Assert ($serverText -match 'Invoke-HostedAdmin \$Request "list_team"[\s\S]{0,900}Select an active salesperson') "Hosted assignments do not validate against the hosted team."
Assert ($serverText -match '/api/auth/complete-link') "Email confirmation, invitation, and recovery links are not completed by the local app."
Assert ($appText -match 'completeEmailAuthLink') "The client does not complete Supabase email links."
Assert ($appText -match 'window\.open\("about:blank", "_blank"\)') "Facebook workflow does not reserve a tab during the trusted button click."
Assert ($appText.IndexOf('window.open("about:blank", "_blank")') -lt $appText.IndexOf('vehicle = await persistListingDetails(false)')) "Facebook tab is opened after an asynchronous save and may be blocked as a popup."
Assert ($appText -notmatch 'facebookTab\.opener\s*=\s*null') "Facebook workflow detaches the reserved tab before the asynchronous save can navigate it."
Assert ($appText -match 'if \(facebookTab\.closed\)') "Facebook workflow does not detect a reserved tab that was closed while listing details were saved."
Assert ($appText -match 'facebookTab\.location\.replace\(facebookUrl\)') "The reserved Facebook tab is not navigated after validation."
Assert ($appText -match 'els\.openFacebookButton\.disabled = true') "Facebook workflow does not prevent duplicate button clicks."
Assert ($appText -match 'getVehicleIdentityIssues\(vehicle\)') "Facebook launch does not validate year, make, model, and VIN identity."
Assert ($appText -match 'VIN model year \$\{decodedYear\} does not match \$\{year\}') "Facebook launch does not block a VIN/year mismatch."

$facebookHelperText = Get-Content -Raw "$PSScriptRoot\..\facebook-helper\facebook-form.js"
Assert ($facebookHelperText -notmatch 'isListingTypeSelected\(desired\) \|\| true') "Facebook listing-type selection still reports unconditional success."
Assert ($facebookHelperText -match 'return explicit === "car/truck" \? "Car/Truck" : ""') "Facebook category is not read exclusively from LotCaster's explicit Car/Truck field."
Assert ($serverText -match 'facebookListingType = "Car/Truck"') "Normalized LotCaster vehicles do not carry an explicit Facebook Car/Truck listing type."
Assert ($appText -match 'facebookListingType: "Car/Truck"') "The Facebook packet does not explicitly force the Car/Truck listing type."
Assert ($appText -match 'els\.postingBodyType\.value = "Car/Truck"') "The Listing Builder does not force its Facebook category to Car/Truck."
Assert ($indexText -match '<select id="postingBodyType">\s*<option value="Car/Truck">Car/Truck</option>\s*</select>') "The Listing Builder exposes a Facebook category other than Car/Truck."
Assert ($facebookHelperText -match 'return explicit === "car/truck" \? "Car/Truck" : ""') "The helper still infers Facebook category from SUV, Van, Truck, or another internal body type."
Assert ($appText -notmatch 'dealershipLocation') "The Facebook packet must not trigger Facebook's map-based location modal."
Assert ($facebookHelperText -notmatch 'fillLocationControl|labels: \["location"\]') "The Facebook helper must never automate Facebook's map-based location control."
Assert ($facebookHelperText -notmatch 'labels: \["vehicle type"\]') "Facebook Vehicle type must not use the generic field matcher, which can mistake Listing location for Vehicle type."
Assert ($facebookHelperText -match 'hasBlockingLocationDialog') "The helper lacks a safety stop for Facebook's Listing location modal."
Assert ($facebookHelperText -match 'hasBlockingLocationDialog\(\)\)[\s\S]{0,120}hideHelperOverlays\(\)') "The helper does not remove its overlays when Facebook opens the Listing location map."
Assert ($facebookHelperText -notmatch 'panel\.append\(title, body, actions\)') "The obsolete floating Facebook helper panel can still cover Facebook controls."
Assert ($facebookHelperText -notmatch 'chooseVehicleListingType|listingTypeInteractionAttempted') "The helper still attempts to click Facebook's Vehicle type control."
Assert ($facebookHelperText -match 'will not touch Facebook''s type or location controls') "The helper does not clearly instruct the user to select Car/Truck manually."
Assert ($facebookHelperText -match 'selectStrictFacebookOption') "The helper does not support Facebook's exact-label custom dropdowns."
Assert ($facebookHelperText -match 'if \(isForbiddenLocationTarget\(control\)\) return false') "Field matching does not reject Facebook location controls before filling."
Assert ($facebookHelperText -match 'maximumFillPasses = 4') "Facebook helper does not have a bounded retry limit."
Assert ($facebookHelperText -match 'field\.requiresIdentity && !vehicleIdentityMatches\(\)') "Facebook helper can fill model details before Year and Make are verified."
Assert ($facebookHelperText -match 'strictControlLabel\(control\) !== normalize\(field\.label\)') "Facebook custom controls are not matched by exact field label."
Assert ($facebookHelperText -match 'findStrictVehicleTypeControl') "Vehicle type selection still lacks an exact-control matcher."
Assert ($facebookHelperText -match 'isForbiddenLocationTarget') "Click handling does not permanently reject Facebook location controls."
Assert ($facebookHelperText -notmatch '\["pointerdown", "mousedown", "pointerup", "mouseup", "click"\]') "Click handling still sends duplicate click events."
Assert ($facebookHelperText -notmatch 'isListingTypeSelected\(listingType\) \|\| visibleDetailFields') "A visible Facebook form still incorrectly bypasses Vehicle type selection."
foreach ($facebookRoadLabel in @("car or truck", "cars or trucks", "cars and trucks", "cars & trucks")) {
  Assert ($facebookHelperText -match [regex]::Escape("aliases.add(`"$facebookRoadLabel`")")) "Facebook road-vehicle aliases omit '$facebookRoadLabel'."
}
Assert ($facebookHelperText -match 'exactOptionMatches\(fieldCurrentValue\(control, field\), desired\)') "Facebook listing-type confirmation does not verify the exact selected value."

$detailFixture = @'
<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"__eggsState":{"birf":{"pageData":{"page":{"vehicle":{"vin":"1C4SJVDP0RS100001","fuelType":{"name":"Gasoline"},"images":{"sources":[{"src":"https://images.autotrader.com/vehicle/wagoneer-1.jpg"},{"src":"https://images.autotrader.com/vehicle/wagoneer-2.jpg"},{"src":"https://images.autotrader.com/vehicle/wagoneer-3.jpg"}]}}}}}}}}}</script>
'@
$detail = Parse-AutoTraderDetailHtml $detailFixture "https://www.autotrader.com/cars-for-sale/vehicle/123"
Assert (@($detail.photos).Count -eq 3) "Rendered AutoTrader detail gallery did not preserve all valid vehicle photos."

Write-Host "Reliability audit checks passed."
