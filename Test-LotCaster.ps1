$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$node = "C:\Users\Gage\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
$nodeModules = "C:\Users\Gage\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\node_modules"
$pnpmNodeModules = Join-Path $nodeModules ".pnpm\node_modules"

Write-Host "Checking LotCaster..." -ForegroundColor Cyan
[void][ScriptBlock]::Create((Get-Content -Raw (Join-Path $root "Start-InventoryTool.ps1")))
if (Test-Path $node) {
  & $node --check (Join-Path $root "public\app.js")
  & $node --check (Join-Path $root "facebook-helper\background.js")
  & $node --check (Join-Path $root "facebook-helper\local-app.js")
  & $node --check (Join-Path $root "facebook-helper\facebook-form.js")
  $previousNodePath = $env:NODE_PATH
  try {
    $env:NODE_PATH = "$nodeModules;$pnpmNodeModules"
    & $node (Join-Path $root "tests\facebook-helper-flow-audit.cjs")
    if ($LASTEXITCODE -ne 0) { throw "Facebook helper flow audit failed." }
  } finally {
    $env:NODE_PATH = $previousNodePath
  }
}

Get-ChildItem (Join-Path $root "tests\*.ps1") |
  Sort-Object Name |
  ForEach-Object {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "$($_.Name) failed." }
  }

$response = Invoke-WebRequest "http://127.0.0.1:5173/api/auth/status" -UseBasicParsing -TimeoutSec 8
if ($response.StatusCode -ne 200) { throw "The running LotCaster health check failed." }

Write-Host ""
Write-Host "LotCaster passed every local system check." -ForegroundColor Green
