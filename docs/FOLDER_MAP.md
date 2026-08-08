# LotCaster Folder Map

This is the current clean layout for the project.

## Root Launch Files

- `1-START-LOTCASTER.cmd` starts LotCaster from this folder.
- `2-INSTALL-DESKTOP-ICON.cmd` creates or repairs the Windows desktop icon.
- `Launch-LotCaster.vbs` launches the local app silently and opens the browser.
- `Start-InventoryTool.ps1` is the primary local app server.
- `Start-InventoryTool.ps1` is the single supported server implementation.

## App Folders

- `public/` contains the LotCaster browser app, styling, logo, and generated helper download.
- `facebook-helper/` contains the Chrome/Edge helper extension.
- `data/` contains this computer's local inventory, accounts, settings, team records, and CSV data.
- `docs/` contains project reports, commercialization notes, and this map.
- `tests/` contains validation checks.
- `archive/` contains old backup copies and should not be used for normal launches.

## Transfer Note

For a dealer demo or transfer, copy the whole `LotCaster` folder. Keep `data/` only for private/local copies, not public GitHub uploads.
