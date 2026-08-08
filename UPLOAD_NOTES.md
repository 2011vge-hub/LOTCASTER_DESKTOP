# LotCaster Upload Notes

This folder is the working LotCaster project.

## Keep For Upload

- `public/`
- `facebook-helper/`
- `tests/`
- `Start-InventoryTool.ps1`
- `Start-InventoryTool.ps1`
- `package.json`
- `README.md`
- `docs/`
- launcher files in the root folder

## Do Not Upload Publicly

The `data/` folder contains local dealership inventory, login hashes, team accounts, access records, and generated CSV files. It is intentionally ignored by `.gitignore`.

## Desktop Icon

The desktop icon should launch `Launch-LotCaster.vbs`. A clean portable copy also includes:

- `1-START-LOTCASTER.cmd`
- `2-INSTALL-DESKTOP-ICON.cmd`
- `Create-LotCaster-Desktop-Icon.ps1`

Run `2-INSTALL-DESKTOP-ICON.cmd` from the folder you want the shortcut to launch.

## Portable Copy

The clean portable folder is:

`C:\Users\Gage\Documents\Codex\LotCaster`

A zipped transfer copy is:

`C:\Users\Gage\Documents\Codex\LotCaster-Portable-2026-07-20.zip`

## Archived Copy

The old duplicated app folder was moved under `archive/` so it is out of the way but still recoverable if needed.
