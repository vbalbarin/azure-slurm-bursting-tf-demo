control 'private-cyclecloud-administration' do
  impact 1.0
  private_name = input('cyclecloud_private_name')

  describe powershell("Resolve-DnsName -Name '#{private_name}' -DnsOnly") do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(/10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\./) }
  end
  describe powershell("Get-ChildItem Cert:\\LocalMachine\\Root | Where-Object { $_.Subject -match 'CN=#{private_name}' }") do
    its('stdout') { should_not eq '' }
  end
  describe port(443) do
    it { should_not be_listening }
  end
  describe file('C:\ProgramData\CycleCloud\cyclecloud.pfx') do
    it { should_not exist }
  end
end
