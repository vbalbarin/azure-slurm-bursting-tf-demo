require 'chefspec'

describe 'slurm_scheduler::default' do
  platform 'almalinux', '9'
  override_attributes['slurm'] = {
    'version' => '24.11.5',
    'project_version' => '3.0.8',
    'cluster_name' => 'demo',
    'scheduler_private_address' => '10.10.0.4',
    'burst_cidr' => '10.20.0.0/16',
    'cyclecloud_url' => 'https://cyclecloud.internal',
  }
  override_attributes['demo_user'] = {
    'public_key' => 'ssh-ed25519 AAAATEST',
    'home' => '/shared/home/slurmdemo',
  }
  let(:chef_run) { chef_runner.converge('slurm_scheduler::default') }

  it { is_expected.to create_user('slurm').with(uid: 11100, gid: 11100) }
  it { is_expected.to create_user('munge').with(uid: 11101, gid: 11101) }
  it { is_expected.to install_package('slurm').with(version: '24.11.5') }
  it { is_expected.to create_template('/etc/slurm/slurm.conf').with(mode: '0640') }
  it { is_expected.to enable_service('slurmctld') }
  it { is_expected.to start_service('slurmctld') }
end
