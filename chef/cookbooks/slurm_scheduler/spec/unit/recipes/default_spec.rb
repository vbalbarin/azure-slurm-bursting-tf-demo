require 'chefspec'

describe 'slurm_scheduler::default' do
  platform 'almalinux', '9'
  override_attributes['slurm'] = {
    'version' => '26.05.4-1.el9',
    'project_version' => '4.0.11',
    'integration_uri' => 'https://github.com/Azure/cyclecloud-slurm/releases/download/4.0.11/azure-slurm-pkg-4.0.11.tar.gz',
    'integration_sha256' => 'f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36',
    'cluster_name' => 'cross-region-demo',
    'scheduler_private_name' => 'slurmdemo-scheduler.cyclecloud.internal',
    'scheduler_private_address' => '10.10.0.4',
    'burst_cidr' => '10.20.0.0/16',
    'cyclecloud_url' => 'https://demo.cyclecloud.internal',
    'integration_ready' => true,
  }
  let(:chef_run) { chef_runner.converge('slurm_scheduler::default') }
  before do
    stub_command('test -d /opt/azurehpc/slurm').and_return(false)
    stub_command(
      "cmp -s /etc/slurm/slurm.conf '/sched/cross-region-demo/slurm.conf'"
    ).and_return(false)
  end

  it { is_expected.to create_user('slurm').with(uid: 11100, gid: 11100) }
  it { is_expected.to create_user('munge').with(uid: 11101, gid: 11101) }
  it { is_expected.to create_user('hpcuser01').with(uid: 11200, gid: 11200, home: '/shared/home/hpcuser01') }
  it { is_expected.to mount_mount('/proc').with(options: %w(defaults hidepid=2)) }
  it { is_expected.to enable_mount('/proc') }
  it { is_expected.to run_execute('generate-preserved-hpcuser01-ed25519-key') }
  it { is_expected.to create_yum_repository('microsoft-slurm-el9-insiders') }
  it { is_expected.to install_package('slurm').with(version: '26.05.4-1.el9') }
  it { is_expected.to install_package('slurm-slurmctld').with(version: '26.05.4-1.el9') }
  it { is_expected.to install_package('slurm-slurmdbd').with(version: '26.05.4-1.el9') }
  it { is_expected.to install_package('slurm-slurmrestd').with(version: '26.05.4-1.el9') }
  it { is_expected.to install_package('python3.11') }
  it { is_expected.to install_package('python3.11-pip') }
  it { is_expected.to install_package('python3.11-devel') }
  it { is_expected.to create_remote_file('/var/cache/slurm-demo/azure-slurm-pkg-4.0.11.tar.gz') }
  it { is_expected.to run_execute('install-azure-slurm-integration-4.0.11-without-jetpack') }
  it { is_expected.to install_package('munge') }
  it { is_expected.to install_package('nfs-utils') }
  it { is_expected.to create_template('/etc/exports.d/slurm.exports') }
  it { is_expected.to create_directory('/etc/slurm').with(mode: '0755') }
  it { is_expected.to create_template('/etc/slurm/slurm.conf').with(mode: '0644') }
  it { is_expected.to create_directory('/var/spool/slurmctld') }
  it { is_expected.to create_directory('/var/spool/slurmd') }
  it { is_expected.to create_directory('/var/log/slurmctld') }
  it { is_expected.to create_directory('/var/log/slurmd') }
  it { is_expected.to create_template('/etc/azslurm.conf').with(mode: '0600') }
  it { is_expected.to run_execute('publish-shared-slurm-configuration') }
  it { is_expected.to enable_service('slurmctld') }
  it { is_expected.to start_service('slurmctld') }

  it 'exports shared filesystems for privileged CycleCloud convergence' do
    expect(chef_run).to render_file('/etc/exports.d/slurm.exports')
      .with_content(%r{/sched .*\(rw,sync,no_root_squash,no_subtree_check\)})
    expect(chef_run).to render_file('/etc/exports.d/slurm.exports')
      .with_content(%r{/shared .*\(rw,sync,no_root_squash,no_subtree_check\)})
  end

  it 'renders a resolvable external controller without a stale static partition' do
    expect(chef_run).to render_file('/etc/slurm/slurm.conf')
      .with_content('SlurmctldHost=slurmdemo-scheduler.cyclecloud.internal')
    expect(chef_run).to render_file('/etc/slurm/slurm.conf')
      .with_content('SlurmctldAddr=10.10.0.4')
    expect(chef_run).not_to render_file('/etc/slurm/slurm.conf')
      .with_content(/PartitionName=.*burst-\[1\]/)
  end

  it 'uses direct peering and the one-node acceptance limit' do
    expect(chef_run.node['slurm']['return_proxy_enabled']).to be false
    expect(chef_run.node['slurm']['max_acceptance_nodes']).to eq 1
  end

  it 'preserves an existing workload-user key' do
    resource = chef_run.execute('generate-preserved-hpcuser01-ed25519-key')
    expect(resource.not_if).not_to be_empty
  end
end
