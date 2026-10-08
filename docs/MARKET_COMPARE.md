# LotCaster Market Compare v1

## Purpose

Market Compare gives a salesperson a fast, dealership-facing view of how a LotCaster inventory vehicle is positioned against similar retail listings.

## Inventory condition filter

The LotCaster browser helper adds an inventory condition filter with:

- All inventory
- New
- Used
- Certified

Walker Chevrolet inventory refresh is upgraded to request New, Used, and Certified AutoTrader dealer inventory through the existing browser-helper flow. Existing records created before this feature default to Used until a mixed inventory refresh provides an explicit listing condition.

## Comparison matching

For Used and Certified vehicles:

1. Tier 1 — same year, make, model, and trim; mileage within +/- 5,000 miles.
2. Tier 2 — same year, make, model, and trim; mileage within +/- 10,000 miles.
3. Tier 3 — same year, make, model, and trim outside that mileage band.
4. Tier 4 — same year, make, and model with a different trim.

For New vehicles, mileage is not used as a comparison constraint. Exact year/make/model/trim is Tier 1.

## Output

Market Compare displays up to 12 ranked comparable listings and calculates:

- Market low
- Market median
- Market average
- Market high
- Our price versus market median
- Exact and strong comp counts
- Comparison confidence score

When the source exposes the data, each comp can also show dealer, distance, fuel type, drivetrain, engine, transmission, colors, features/packages, and a link to the source listing.

## Architecture

The comparison request reuses LotCaster's existing browser-helper architecture. The helper opens a targeted AutoTrader search in a background browser tab, waits for the normal page load, reads structured listing state available to the loaded page, returns normalized comparison records to LotCaster, and closes the temporary tab.

The feature does not add randomized anti-detection behavior, fingerprint spoofing, CAPTCHA bypassing, or other bot-evasion logic.

## Runtime wrapper

`Start-LotCaster-Market.ps1` loads the existing `Start-InventoryTool.ps1` with `-NoListen`, overrides only the market-related behaviors, and starts the same local listener. `Launch-LotCaster.vbs` launches the market-aware wrapper.

The original server remains intact for straightforward rollback.
