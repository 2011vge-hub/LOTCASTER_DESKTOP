# LotCaster

A local responsive dealership inventory app with owner authentication, protected inventory data, CSV export, and Facebook Marketplace listing preparation.

## Requirements

- Windows PowerShell.
- Your iPhone and Windows machine must be on the same Wi-Fi network if you want to use the app from the phone.

## Run

Use the **LotCaster** shortcut on your Windows desktop. The legacy command launcher remains available for the current pilot installation.

The launcher opens LotCaster in your browser.

For the clean portable copy, use:

`C:\Users\Gage\Documents\Codex\LotCaster`

Inside that folder:

- Double-click `1-START-LOTCASTER.cmd` to launch the app.
- Double-click `2-INSTALL-DESKTOP-ICON.cmd` to create or repair the Windows desktop icon.
- Copy the whole folder to move LotCaster to another computer.

## First Launch

The first launch asks you to create the installation owner account. Passwords are stored as salted PBKDF2 hashes, never as plain text. Later launches require sign-in before inventory, settings, photos, or exports can be accessed.

## Manual Run

```powershell
.\Start-InventoryTool.ps1
```

Open `http://localhost:5173` on Windows.

For iPhone, use the iPhone URL printed by the script, then open it in Safari. Use Safari's Share button and choose **Add to Home Screen** to install it like an app.

## Workflow

1. Confirm **Inventory Source** points to an authorized used-vehicle inventory page.
2. Press **Import Inventory** or **Refresh Inventory**.
3. Review the import result, then search or filter the vehicles.
4. Press **Build Listing Packet** on a vehicle.
5. Verify required fields, category, description, and available photos.
6. Copy the approved listing information or open the experimental Facebook workflow.
7. Complete final publishing manually and mark the vehicle posted in LotCaster.
8. Use **Export CSV** for a complete spreadsheet copy.

The app tracks active, new, and removed vehicles in `data/inventory.json`.

## Unsupported Inventory Websites

AutoTrader dealer inventory pages are the most reliable direct URL import source right now.

For Cars.com, CarGurus, or another website without a dedicated adapter:

1. Open the dealer inventory page in your browser.
2. Copy the visible vehicle listings on the page.
3. Paste that text into LotCaster's paste box.
4. Press **Import Pasted Page**.
5. Review the imported rows before preparing Facebook listings.

This fallback imports visible listing text only, so photos and some fields may still need review or manual cleanup.

Authentication and the local trial/license record are stored in `data/auth.json`. Keep the entire `data` folder backed up.

## Commercial Roadmap

See `docs/COMMERCIALIZATION.md` for the verified local foundation and the next steps for worker accounts, hosted licensing, Stripe billing, installers, USB distribution, and private Edge extension delivery.

See `UPLOAD_NOTES.md` before uploading the project to GitHub or sharing a copy.

## Phase 1 Validation

Run the read-only validation checks from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\phase1-validation.ps1
```

The checks cover Inventory Source URL normalization, stable vehicle identity, photo preservation and deduplication, category inference, and listing packet text.

## Local Team Workflow

Owners, masters, and managers can open **Team Dashboard** to:

- Create manager and salesperson logins.
- Activate or deactivate local team access.
- Review assigned, prepared, posted, and overdue counts.
- Review recent assignment and posting activity.

Managers assign vehicles from the assignment controls on each Inventory card. Salespeople only see vehicles assigned to their signed-in account. Saving listing details records the preparer; marking a vehicle posted records the signed-in poster.

Team accounts and activity are stored locally in `data/team.json`. This is a local prototype workflow, not hosted multi-dealer identity.

## Facebook Marketplace

LotCaster prepares listing packets and workflow records. It does not publish listings, control Facebook accounts, store Facebook credentials, automate buyer messages, or bypass Facebook's posting flow. Users must verify accuracy and have authorization to use all inventory data and photos.
