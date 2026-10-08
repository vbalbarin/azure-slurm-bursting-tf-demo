$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $env:CHEF_POLICY_ARCHIVE_URI) {
    throw "CHEF_POLICY_ARCHIVE_URI is required"
}

$archive = Join-Path $env:TEMP "windows-admin-policy.zip"
Invoke-WebRequest -UseBasicParsing -Uri "$($env:CHEF_POLICY_ARCHIVE_URI)/windows_admin.zip" -OutFile $archive
$policyRoot = "C:\chef\windows_admin"
New-Item -ItemType Directory -Force -Path $policyRoot | Out-Null
Expand-Archive -Force -Path $archive -DestinationPath $policyRoot
Remove-Item -Force $archive
& chef-client --local-mode --policy-name windows_admin --policy-group demo
if ($LASTEXITCODE -ne 0) {
    throw "Chef Local convergence failed with exit code $LASTEXITCODE"
}
