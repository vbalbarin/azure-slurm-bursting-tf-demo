require 'chefspec'

describe 'cyclecloud_node::default' do
  platform 'almalinux', '9'
  override_attributes['cyclecloud'] = {
    'package_uri' => 'https://packages.example.invalid/cyclecloud.rpm',
    'private_name' => 'cyclecloud.internal',
    'cluster_name' => 'demo',
    'burst_region' => 'westus3',
    'burst_zone' => '1',
    'burst_vm_size' => 'Standard_HB120rs_v3',
    'burst_image_urn' => 'almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110',
    'scheduler_private_address' => '10.10.0.4',
  }
  let(:chef_run) { chef_runner.converge('cyclecloud_node::default') }
  before do
    stub_command('headless-template --help >/dev/null 2>&1').and_return(false)
    stub_command(
      "test -s '/etc/cyclecloud/cli.ini' && test '/etc/cyclecloud/cli.ini' -ef /root/.cycle/config.ini && ! cyclecloud account list 2>&1 | grep -Fqx 'No accounts found'"
    ).and_return(true)
    stub_command(
      "cyclecloud show_cluster 'demo' >/dev/null 2>&1"
    ).and_return(false)
  end

  it { is_expected.to install_rpm_package('cyclecloud').with(version: '8.9.3') }
  it { is_expected.to run_execute('generate-validated-headless-template') }
  it do
    is_expected.to render_file(
      '/opt/cycle/jetpack/system/projects/slurm/templates/slurm-headless.txt.overrides'
    ).with_content('ImageName = almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110')
  end
  it do
    is_expected.to render_file(
      '/opt/cycle/jetpack/system/projects/slurm/templates/slurm-headless.txt.overrides'
    ).with_content('Zone = 1')
  end
  it { is_expected.to create_template('/etc/cyclecloud/slurm-cluster.properties').with(mode: '0600') }
  it { is_expected.not_to run_ruby_block('require-cyclecloud-bootstrap') }
  it { is_expected.to run_execute('import-headless-slurm-cluster') }
end
