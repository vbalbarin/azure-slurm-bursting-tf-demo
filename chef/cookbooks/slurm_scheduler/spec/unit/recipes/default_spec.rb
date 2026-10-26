require 'chefspec'

describe 'slurm_scheduler::default' do
  platform 'almalinux', '9'
  override_attributes['slurm'] = {
    'version' => '24.11.5',
    'project_version' => '4.0.11',
    'cluster_name' => 'cross-region-demo',
    'scheduler_private_address' => '10.10.0.4',
    'burst_cidr' => '10.20.0.0/16',
    'cyclecloud_url' => 'https://demo.cyclecloud.internal',
    'integration_ready' => true,
  }
  let(:chef_run) { chef_runner.converge('slurm_scheduler::default') }

  it { is_expected.to create_user('slurm').with(uid: 11100, gid: 11100) }
  it { is_expected.to create_user('munge').with(uid: 11101, gid: 11101) }
  it { is_expected.to create_user('hpcuser01').with(uid: 11200, gid: 11200, home: '/shared/home/hpcuser01') }
  it { is_expected.to mount_mount('/proc').with(options: %w(defaults hidepid=2)) }
  it { is_expected.to enable_mount('/proc') }
  it { is_expected.to run_execute('generate-preserved-hpcuser01-ed25519-key') }
  it { is_expected.to create_remote_file('/var/cache/slurm-demo/azure-slurm-install-pkg-4.0.11.tar.gz') }
  it { is_expected.to run_execute('install-azure-slurm-4.0.11') }
  it { is_expected.to install_package('slurm').with(version: '24.11.5') }
  it { is_expected.to install_package('munge') }
  it { is_expected.to install_package('nfs-utils') }
  it { is_expected.to create_template('/etc/exports.d/slurm.exports') }
  it { is_expected.to create_template('/etc/slurm/slurm.conf').with(mode: '0640') }
  it { is_expected.to create_template('/etc/azslurm.conf').with(mode: '0600') }
  it { is_expected.to enable_service('slurmctld') }
  it { is_expected.to start_service('slurmctld') }

  it 'uses direct peering and the one-node acceptance limit' do
    expect(chef_run.node['slurm']['return_proxy_enabled']).to be false
    expect(chef_run.node['slurm']['max_acceptance_nodes']).to eq 1
  end

  it 'preserves an existing workload-user key' do
    resource = chef_run.execute('generate-preserved-hpcuser01-ed25519-key')
    expect(resource.not_if).not_to be_empty
  end
end
