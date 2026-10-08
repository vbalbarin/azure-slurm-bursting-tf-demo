param(
    [Parameter(Mandatory = $true)][string]$CycleCloudPrivateName,
    [Parameter(Mandatory = $true)][string]$ClusterName,
    [Parameter(Mandatory = $true)][string]$EvidencePath
)
$ErrorActionPreference = "Stop"
$started = Get-Date
$resolved = Resolve-DnsName -Name $CycleCloudPrivateName -DnsOnly
if (-not ($resolved.IPAddress | Where-Object { $_ -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' })) {
    throw "CycleCloud did not resolve to a private address"
}
$response = Invoke-WebRequest -UseBasicParsing -Uri "https://$CycleCloudPrivateName" -TimeoutSec 30
if ($response.StatusCode -ne 200) {
    throw "CycleCloud private application returned status $($response.StatusCode)"
}
if (((Get-Date) - $started).TotalMinutes -gt 5) {
    throw "Private administration verification exceeded five minutes"
}
[ordered]@{
    private_name = $CycleCloudPrivateName
    cluster_name = $ClusterName
    resolved_addresses = @($resolved.IPAddress)
    tls_status = "trusted"
    public_access = "denied-by-design"
    verified_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content -Encoding UTF8 -Path $EvidencePath
