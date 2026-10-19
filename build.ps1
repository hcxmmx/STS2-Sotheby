param(
    [Parameter(Mandatory=$true)][string]$GameDir,
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$AssetRoot,
    [string]$ModPack
)
$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$godotRoot = Join-Path $repoRoot 'Godot'
$localRoot = Join-Path $repoRoot 'build-local'
$outputRoot = Join-Path $repoRoot 'dist\SothebySkin'
New-Item -ItemType Directory -Path $localRoot,$outputRoot -Force | Out-Null
$env:APPDATA = $localRoot
$env:LOCALAPPDATA = $localRoot
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot 'asset_manifest.json') -Raw | ConvertFrom-Json
if ($AssetRoot) {
    $privateRoot = (Resolve-Path -LiteralPath $AssetRoot).Path
    foreach ($entry in $manifest.files) {
        $source = Join-Path $privateRoot $entry.path
        $target = Join-Path $godotRoot $entry.path
        if (-not (Test-Path -LiteralPath $source)) { throw "Missing private asset: $($entry.path)" }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) { Copy-Item -LiteralPath $source -Destination $target -Force }
    }
} else {
    if (-not $ModPack) { $ModPack = Join-Path $GameDir 'mods\SothebySkin\SothebySkin.pck' }
    $packPath = (Resolve-Path -LiteralPath $ModPack).Path
    & $Godot --headless --path $godotRoot --script (Join-Path $repoRoot 'tools\restore_assets.gd') -- $packPath
    if ($LASTEXITCODE -ne 0) { throw 'Local asset restoration failed.' }
}
foreach ($entry in $manifest.files) {
    $target = Join-Path $godotRoot $entry.path
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Private asset does not match this source version: $($entry.path)" }
}
& dotnet build (Join-Path $repoRoot 'Bridge\SothebySkin.csproj') -c Release "-p:Sts2Dir=$GameDir" --nologo -v minimal
if ($LASTEXITCODE -ne 0) { throw 'Bridge compilation failed.' }
$importLog = Join-Path $localRoot 'import.log'
& $Godot --headless --path $godotRoot --editor --import --quit --log-file $importLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR|SHADER ERROR|ERROR:')) { throw 'Resource import failed; see build-local/import.log.' }
& $Godot --headless --path $godotRoot --script (Join-Path $repoRoot 'tools\pack.gd') -- (Join-Path $outputRoot 'SothebySkin.pck')
if ($LASTEXITCODE -ne 0) { throw 'PCK generation failed.' }
Copy-Item -LiteralPath (Join-Path $repoRoot 'Bridge\bin\Release\net9.0\SothebySkin.dll'),(Join-Path $repoRoot 'SothebySkin.json'),(Join-Path $repoRoot 'README.md'),(Join-Path $repoRoot 'LICENSE'),(Join-Path $repoRoot 'ATTRIBUTION.md') -Destination $outputRoot -Force
Write-Output "Build complete: $outputRoot (not automatically installed)"
