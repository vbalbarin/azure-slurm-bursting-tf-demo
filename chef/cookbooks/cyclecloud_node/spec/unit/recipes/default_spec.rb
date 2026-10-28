require 'chefspec'

describe 'cyclecloud_node::default' do
  platform 'almalinux', '9'
  override_attributes['cyclecloud'] = {
    'private_name' => 'cyclecloud.internal',
    'cluster_name' => 'cross-region-demo',
    'burst_region' => 'westus3',
    'burst_zone' => '1',
    'burst_vm_size' => 'Standard_HB120rs_v3',
    'burst_image_name' => 'almalinux9',
    'burst_subnet_id' => 'rg-demo-slurm/vnet-burst/snet-compute',
    'locker_identity_resource_id' => '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-demo-slurm/providers/Microsoft.ManagedIdentity/userAssignedIdentities/demo-cyclecloud-locker',
    'registered_slurm_project_version' => '4.0.9',
    'slurm_version' => '26.05.4',
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
    stub_command(%r{/opt/cycle_server/cycle_server version}).and_return(true)
    stub_command(/\.source-commit/).and_return(false)
    stub_command(/\.uploaded-version/).and_return(false)
    stub_command(/headless_template --help/).and_return(true)
    stub_command(/slurm-headless-input.*cmp -s/).and_return(false)
    stub_command(/\.slurm-headless-check/).and_return(false)
    stub_command(
      "test -s '/etc/cyclecloud/cli.ini' && test '/etc/cyclecloud/cli.ini' -ef /root/.cycle/config.ini && ! cyclecloud account list 2>&1 | grep -Fqx 'No accounts found'"
    ).and_return(true)
    stub_command(
      "cyclecloud show_cluster 'cross-region-demo' >/dev/null 2>&1"
    ).and_return(false)
    stub_command(
      "cyclecloud show_cluster 'cross-region-demo' | grep -Fq ': started'"
    ).and_return(false)
  end

  it { is_expected.not_to run_ruby_block('require-cyclecloud-8.9.3') }
  it do
    is_expected.to create_remote_file(
      '/var/cache/slurm-demo/cyclecloud-slurm-096cd7423f75b2043b6263fd66feb55c7d5192f2.tar.gz'
    ).with(
      source: 'https://codeload.github.com/Azure/cyclecloud-slurm/tar.gz/096cd7423f75b2043b6263fd66feb55c7d5192f2',
      checksum: '185b8959b38339c3f27a80e5d9409df5ed2f25d0c76976eb5f6e20e7a4e78df7',
      mode: '0600'
    )
  end
  it { is_expected.to run_execute('stage-cyclecloud-slurm-project-4.0.11') }
  it do
    is_expected.to create_remote_file(
      '/var/lib/slurm-demo/projects/cyclecloud-slurm-4.0.11/blobs/azure-slurm-pkg-4.0.11.tar.gz'
    ).with(
      checksum: 'f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36'
    )
  end
  it { is_expected.to run_execute('upload-cyclecloud-slurm-project-4.0.11') }
  it do
    is_expected.to run_execute('generate-validated-headless-template').with(
      command: /--destination '.*slurm-headless\.txt'.*headless_template validate .* \{candidate\}/
    )
  end
  it do
    is_expected.to render_file(
      '/var/lib/slurm-demo/projects/cyclecloud-slurm-4.0.11/templates/slurm-headless.overrides'
    ).with_content('DefaultValue = Standard_HB120rs_v3')
  end
  it do
    is_expected.to render_file(
      '/var/lib/slurm-demo/projects/cyclecloud-slurm-4.0.11/templates/slurm-headless.overrides'
    ).with_content('DefaultValue = 10.10.0.4')
  end
  it do
    is_expected.to render_file(
      '/var/lib/slurm-demo/projects/cyclecloud-slurm-4.0.11/templates/slurm-headless.overrides'
    ).with_content('DefaultValue = false')
  end
  it do
    is_expected.to render_file(
      '/var/lib/slurm-demo/projects/cyclecloud-slurm-4.0.11/templates/slurm-headless.overrides'
    ).with_content('DefaultValue = 1')
  end
  it { is_expected.to create_directory('/var/lib/cyclecloud').with(mode: '0700') }
  it { is_expected.not_to run_ruby_block('require-cyclecloud-bootstrap') }
  it { is_expected.to run_execute('import-headless-slurm-cluster') }
  it do
    is_expected.to run_execute('import-headless-slurm-cluster').with(
      command: /cross-region-demo.*-c Slurm.*slurm-headless\.txt.*-P Credentials/m
    )
  end
  it do
    is_expected.to run_execute('generate-validated-headless-template').with(
      command: /--slurm-project-version '4\.0\.9'/
    )
  end
end
