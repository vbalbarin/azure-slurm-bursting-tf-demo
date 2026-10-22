private_name = node['windows_admin']['cyclecloud_private_name']
secret_id = node['windows_admin']['certificate_secret_id']
raise 'CycleCloud private name is required' if private_name.to_s.empty?
raise 'CycleCloud CA certificate secret ID is required' if secret_id.to_s.empty?

directory ::File.dirname(node['windows_admin']['certificate_path']) do
  rights :full_control, 'Administrators'
  inherits false
end

powershell_script 'install-cyclecloud-private-trust' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'
    az keyvault secret download --id '#{secret_id}' --file '#{node['windows_admin']['certificate_path']}' --encoding base64
    Import-Certificate -FilePath '#{node['windows_admin']['certificate_path']}' -CertStoreLocation Cert:\\LocalMachine\\Root | Out-Null
    Remove-Item -Force '#{node['windows_admin']['certificate_path']}'
  POWERSHELL
  sensitive true
  not_if "powershell -NoProfile -Command \"Get-ChildItem Cert:\\LocalMachine\\Root | Where-Object { $_.Subject -match 'CN=#{private_name}' }\""
end

powershell_script 'verify-cyclecloud-private-dns' do
  code "Resolve-DnsName -Name '#{private_name}' -DnsOnly -ErrorAction Stop | Out-Null"
end
