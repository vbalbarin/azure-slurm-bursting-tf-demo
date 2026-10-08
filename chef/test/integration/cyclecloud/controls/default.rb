control 'cyclecloud-private-node' do
  impact 1.0
  describe package('cyclecloud') do
    its('version') { should eq '8.9.3' }
  end
  describe file('/etc/cyclecloud/tls/cyclecloud.pfx') do
    it { should exist }
    its('mode') { should cmp '0600' }
  end
  describe file('/opt/cycle/jetpack/system/projects/slurm/templates/slurm-headless.txt') do
    it { should exist }
    its('content') { should match(/slurm\.user\.uid = 11100/) }
    its('content') { should match(/munge\.user\.uid = 11101/) }
    its('content') { should_not match(/\[\[node scheduler\]\]/) }
  end
end
