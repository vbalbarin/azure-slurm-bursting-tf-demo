control 'external-slurm-scheduler' do
  impact 1.0
  describe user('slurm') do
    its('uid') { should eq 11100 }
    its('gid') { should eq 11100 }
  end
  describe user('munge') do
    its('uid') { should eq 11101 }
    its('gid') { should eq 11101 }
  end
  %w(munge nfs-server slurmctld).each do |service_name|
    describe service(service_name) do
      it { should be_enabled }
      it { should be_running }
    end
  end
  describe file('/etc/exports.d/slurm.exports') do
    its('content') { should match(%r{/sched}) }
    its('content') { should match(%r{/shared}) }
  end
  describe file('/etc/azslurm.conf') do
    its('mode') { should cmp '0600' }
    its('content') { should match(/ReturnProxyEnabled=false/) }
  end
end
