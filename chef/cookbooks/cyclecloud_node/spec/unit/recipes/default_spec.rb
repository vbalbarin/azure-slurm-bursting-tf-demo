require 'chefspec'

describe 'cyclecloud_node::default' do
  platform 'almalinux', '9'
  override_attributes['cyclecloud'] = {
    'private_name' => 'cyclecloud.internal',
    'cluster_name' => 'cross-region-demo',
    'burst_region' => 'westus3',
    'burst_zone' => '1',
    'burst_vm_size' => 'Standard_HB120rs_v3',
    'burst_image_urn' => 'almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110',
    'scheduler_private_address' => '10.10.0.4',
    'burst_cidr' => '10.20.0.0/24',
    'slurm_uid' => 11100,
    'slurm_gid' => 11100,
    'munge_uid' => 11101,
    'munge_gid' => 11101,
    'hpc_user_name' => 'hpcuser01',
    'hpc_user_uid' => 11200,
    'hpc_user_gid' => 11200,
    'hpc_user_home' => '/shared/home/hpcuser01',
  }
  let(:chef_run) { chef_runner.converge('cyclecloud_node::default') }
  before do
    stub_command('headless-template --help >/dev/null 2>&1').and_return(false)
    stub_command("rpm -q --qf '%{VERSION}' cyclecloud | grep -Fqx '8.9.3'").and_return(true)
    stub_command("test -f '/opt/cycle/jetpack/system/projects/slurm/version' && grep -Fqx '4.0.11' '/opt/cycle/jetpack/system/projects/slurm/version'").and_return(false)
    stub_command("test -f '/opt/cycle/jetpack/system/projects/slurm/templates/slurm-headless.txt.candidate'").and_return(true)
    stub_command(
      "test -s '/etc/cyclecloud/cli.ini' && test '/etc/cyclecloud/cli.ini' -ef /root/.cycle/config.ini && ! cyclecloud account list 2>&1 | grep -Fqx 'No accounts found'"
    ).and_return(true)
    stub_command(
      "cyclecloud show_cluster 'cross-region-demo' >/dev/null 2>&1"
    ).and_return(false)
  end

  it { is_expected.not_to run_ruby_block('require-cyclecloud-8.9.3') }
  it do
    is_expected.to create_remote_file('/var/cache/slurm-demo/azure-slurm-pkg-4.0.11.tar.gz').with(
      source: 'https://github.com/Azure/cyclecloud-slurm/releases/download/4.0.11/azure-slurm-pkg-4.0.11.tar.gz',
      checksum: 'f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36',
      mode: '0600'
    )
  end
  it { is_expected.to run_execute('install-cyclecloud-slurm-project-4.0.11') }
  it do
    is_expected.to run_execute('generate-validated-headless-template').with(
      command: /--destination '.*\.candidate'.*cyclecloud project validate \{candidate\}/
    )
  end
  it { is_expected.to run_execute('activate-validated-headless-template') }
  it do
    is_expected.to render_file(
      '/opt/cycle/jetpack/system/projects/slurm/templates/slurm-headless.txt.overrides'
    ).with_content('hpc.user.uid = 11200')
  end
  it { is_expected.to create_template('/etc/cyclecloud/slurm-cluster.properties').with(mode: '0600') }
  it { is_expected.not_to run_ruby_block('require-cyclecloud-bootstrap') }
  it { is_expected.to run_execute('import-headless-slurm-cluster') }
  it do
    is_expected.to run_execute('import-headless-slurm-cluster').with(
      command: /cross-region-demo/
    )
  end
end
