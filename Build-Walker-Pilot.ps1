$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $root "releases"
$releaseName = "LotCaster-Walker-Pilot-2026-07-31.zip"
$releasePath = Join-Path $releaseDir $releaseName
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ("lotcaster-walker-pilot-" + [Guid]::NewGuid().ToString("N"))
$stage = Join-Path $stageRoot "LotCaster-Walker-Pilot"

try {
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $stage "data") -Force | Out-Null
  New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

  foreach ($folder in @("public", "facebook-helper")) {
    Copy-Item -LiteralPath (Join-Path $root $folder) -Destination $stage -Recurse -Force
  }

  foreach ($file in @(
    "1-START-LOTCASTER.cmd",
    "2-INSTALL-DESKTOP-ICON.cmd",
    "Create-LotCaster-Desktop-Icon.ps1",
    "Launch-LotCaster.vbs",
    "Start-InventoryTool.ps1",
    "LotCaster-Facebook-Helper.zip"
  )) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage -Force
  }

  Copy-Item -LiteralPath (Join-Path $root "data\settings.json") -Destination (Join-Path $stage "data\settings.json") -Force

  $startHere = @'
LOTCASTER — WALKER PILOT
========================

1. Double-click 1-START-LOTCASTER.cmd.
2. Create the local owner login when asked on first launch.
3. In Edge, load the facebook-helper folder as an unpacked extension.
4. Refresh inventory and confirm prices say Verified posting price.
5. Review every field and photo before manually publishing.

Private development accounts, sessions, team records, and inventory history are
intentionally excluded from this package.
'@
  [IO.File]::WriteAllText((Join-Path $stage "START HERE.txt"), $startHere, [Text.UTF8Encoding]::new($false))

  $checkScript = @'
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
[void][ScriptBlock]::Create((Get-Content -Raw (Join-Path $root "Start-InventoryTool.ps1")))
$manifest = Get-Content -Raw (Join-Path $root "facebook-helper\manifest.json") | ConvertFrom-Json
if ([version]$manifest.version -lt [version]"1.8.0") { throw "The browser helper is outdated." }
Write-Host "Walker pilot files passed validation." -ForegroundColor Green
'@
  [IO.File]::WriteAllText((Join-Path $stage "CHECK-WALKER-PILOT.ps1"), $checkScript, [Text.UTF8Encoding]::new($false))

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage "CHECK-WALKER-PILOT.ps1")
  if ($LASTEXITCODE -ne 0) { throw "The staged Walker pilot failed validation." }

  Compress-Archive -LiteralPath $stage -DestinationPath $releasePath -CompressionLevel Optimal -Force
  $archive = Get-Item -LiteralPath $releasePath
  Write-Host "Walker pilot created:" -ForegroundColor Green
  Write-Host $archive.FullName
  Write-Host "Size: $([Math]::Round($archive.Length / 1MB, 2)) MB"
} finally {
  $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $resolvedStage = [IO.Path]::GetFullPath($stageRoot)
  if ($resolvedStage.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Leaf $resolvedStage) -like "lotcaster-walker-pilot-*") {
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue
  }
}

