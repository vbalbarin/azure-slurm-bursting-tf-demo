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

control 'cyclecloud-bootstrap-contracts' do
  impact 1.0

  describe command('chef-client --version') do
    its('stdout') { should match(/\b18\.11\.11\b/) }
    its('exit_status') { should eq 0 }
  end

  describe file('/opt/slurm-demo/current') do
    it { should be_symlink }
    its('link_path') { should match(%r{\A/opt/slurm-demo/releases/[0-9a-f]{64}\z}) }
  end

  %w(
    /opt/slurm-demo/current/manifest.json
    /opt/slurm-demo/current/node-specification.json
    /opt/slurm-demo/current/chef/policyfiles/cyclecloud.lock.json
  ).each do |contract|
    describe file(contract) do
      it { should exist }
      its('owner') { should eq 'root' }
      its('mode') { should cmp '0444' }
    end
  end

  describe json('/opt/slurm-demo/current/manifest.json') do
    its(['role']) { should eq 'cyclecloud' }
    its(['policyName']) { should eq 'cyclecloud' }
    its(['policyRevision']) { should match(/\A[0-9a-f]{64}\z/) }
    its(['policyLockSha256']) { should match(/\A[0-9a-f]{64}\z/) }
  end

  describe json('/var/lib/slurm-demo/cyclecloud/state.json') do
    its(['state']) { should eq 'converged' }
    its(['attempt']) { should be_between 1, 2 }
    its(['detailCode']) { should eq 'chef_succeeded' }
  end

  describe file('/opt/cycle/jetpack/system/projects/slurm/version') do
    its('content') { should match(/\A4\.0\.11\s*\z/) }
  end

  describe command(
    "cyclecloud cluster list --output json | jq '[.[] | select(.Name == \"cross-region-demo\")] | length'"
  ) do
    its('stdout') { should match(/\A1\s*\z/) }
    its('exit_status') { should eq 0 }
  end

  %w(
    /run/cyclecloud-first-run
    /run/cyclecloud-chef-input
    /run/slurm-demo/cyclecloud
    /var/tmp/cyclecloud.rpm
  ).each do |temporary_path|
    describe file(temporary_path) do
      it { should_not exist }
    end
  end
end
