control 'external-slurm-scheduler-identities' do
  impact 1.0

  {
    'slurm' => [11100, 11100],
    'munge' => [11101, 11101],
    'hpcuser01' => [11200, 11200],
  }.each do |name, identity|
    describe user(name) do
      its('uid') { should eq identity.first }
      its('gid') { should eq identity[1] }
    end
  end

  describe user('hpcuser01') do
    its('home') { should eq '/shared/home/hpcuser01' }
    its('shell') { should eq '/bin/bash' }
  end
end

control 'external-slurm-scheduler-workload-key' do
  impact 1.0

  describe file('/shared/home/hpcuser01') do
    it { should be_directory }
    its('owner') { should eq 'hpcuser01' }
    its('group') { should eq 'hpcuser01' }
    its('mode') { should cmp '0700' }
  end
  describe file('/shared/home/hpcuser01/.ssh') do
    it { should be_directory }
    its('mode') { should cmp '0700' }
  end
  describe file('/shared/home/hpcuser01/.ssh/id_ed25519') do
    it { should be_file }
    its('owner') { should eq 'hpcuser01' }
    its('mode') { should cmp '0600' }
  end
  describe file('/shared/home/hpcuser01/.ssh/id_ed25519.pub') do
    it { should be_file }
    its('owner') { should eq 'hpcuser01' }
    its('mode') { should cmp '0644' }
    its('content') { should match(%r{^ssh-ed25519 [A-Za-z0-9+/]+={0,3}(?: .+)?\n$}) }
  end
end

control 'external-slurm-scheduler-release-and-services' do
  impact 1.0

  %w(munge nfs-utils slurm).each do |name|
    describe package(name) do
      it { should be_installed }
    end
  end
  describe file('/opt/azure-slurm/4.0.11/.installed') do
    it { should be_file }
  end
  %w(munge nfs-server slurmctld).each do |service_name|
    describe service(service_name) do
      it { should be_enabled }
      it { should be_running }
    end
  end
end

control 'external-slurm-scheduler-configuration' do
  impact 1.0

  describe file('/etc/exports.d/slurm.exports') do
    its('content') { should match(%r{^/sched\s+}) }
    its('content') { should match(%r{^/shared\s+}) }
    its('content') { should match(/no_root_squash/) }
  end
  describe file('/etc/slurm/slurm.conf') do
    its('owner') { should eq 'slurm' }
    its('mode') { should cmp '0644' }
    its('content') { should match(/^SlurmctldHost=.*\.cyclecloud\.internal$/) }
    its('content') { should match(/^SlurmctldAddr=\d+\.\d+\.\d+\.\d+$/) }
    its('content') { should_not match(/Nodes=burst-\[1\]/) }
    its('content') { should match(%r{/opt/azurehpc/slurm/resume_program\.sh}) }
  end
  describe file('/etc/azslurm.conf') do
    its('owner') { should eq 'root' }
    its('mode') { should cmp '0600' }
    its('content') { should match(/ReturnProxyEnabled=false/) }
    its('content') { should match(/MaxNodes=1/) }
    its('content') { should match(%r{CycleCloudUrl=https://[^/]+\.cyclecloud\.internal/?}) }
  end
  describe file('/opt/azurehpc/slurm/autoscale.json') do
    its('owner') { should eq 'slurm' }
    its('mode') { should cmp '0600' }
  end
  describe file('/sched/cross-region-demo/slurm.conf') do
    it { should be_file }
    its('owner') { should eq 'slurm' }
    its('mode') { should cmp '0644' }
  end
end

control 'external-slurm-scheduler-staged-contracts' do
  impact 1.0

  describe file('/opt/slurm-demo/current') do
    it { should be_symlink }
  end
  %w(manifest.json node-specification.json chef/policyfiles/slurm.lock.json).each do |path|
    describe file("/opt/slurm-demo/current/#{path}") do
      it { should be_file }
      its('owner') { should eq 'root' }
      its('mode') { should_not be_more_permissive_than('0444') }
    end
  end
  describe json('/var/lib/slurm-demo/scheduler/state.json') do
    its(['schemaVersion']) { should eq 1 }
    its(['role']) { should eq 'scheduler' }
    its(['state']) { should be_in %w(converged idempotency_verified) }
    its(['attempt']) { should be_in [1, 2] }
  end
end

control 'external-slurm-scheduler-secret-cleanup' do
  impact 1.0

  describe mount('/proc') do
    its('options') { should include 'hidepid=2' }
  end
  describe command('find /run/slurm-demo -maxdepth 1 -type f \\( -name "cyclecloud-password.*" -o -name "chef-attributes.*" -o -name "authorization.json" \\) -print') do
    its('stdout') { should eq '' }
    its('exit_status') { should eq 0 }
  end
  describe file('/run/azslurm/credentials') do
    it { should_not exist }
  end
end
