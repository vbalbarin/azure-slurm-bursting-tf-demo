require 'json'

required = %w(package_uri private_name certificate_secret_id cluster_name burst_region burst_vm_size burst_image_urn scheduler_private_address)
missing = required.select { |key| node['cyclecloud'][key].nil? || node['cyclecloud'][key].to_s.empty? }
raise "Missing required CycleCloud attributes: #{missing.join(', ')}" unless missing.empty?

package %w(python3 openssl jq)

remote_file '/var/tmp/cyclecloud.rpm' do
  source node['cyclecloud']['package_uri']
  mode '0600'
  sensitive true
end

rpm_package 'cyclecloud' do
  source '/var/tmp/cyclecloud.rpm'
  version node['cyclecloud']['version']
  action :install
end

directory '/etc/cyclecloud/tls' do
  owner 'root'
  group 'root'
  mode '0700'
  recursive true
end

execute 'retrieve-cyclecloud-private-certificate' do
  command lazy {
    "az keyvault secret download --id '#{node['cyclecloud']['certificate_secret_id']}' " \
      '--file /etc/cyclecloud/tls/cyclecloud.pfx --encoding base64'
  }
  creates '/etc/cyclecloud/tls/cyclecloud.pfx'
  sensitive true
end

directory node['cyclecloud']['processor_root'] do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
end

execute 'install-headless-template-processor' do
  command "python3 -m pip install --no-deps --no-index #{node['cyclecloud']['processor_root']}"
  not_if 'headless-template --help >/dev/null 2>&1'
end

ruby_block 'discover-and-check-slurm-project' do
  block do
    source = node['cyclecloud']['source_template']
    raise "Release-matched Slurm template not found: #{source}" unless ::File.file?(source)

    version_file = ::File.join(node['cyclecloud']['project_root'], 'version')
    raise "Slurm project version file not found: #{version_file}" unless ::File.file?(version_file)

    project_version = ::File.read(version_file).strip
    raise 'Discovered Slurm project version is empty' if project_version.empty?
    slurm_version = ::File.read(source)[/SlurmVersion\s*=\s*([^\s]+)/, 1]
    raise 'Slurm version was not discoverable from the selected template' if slurm_version.to_s.empty?

    node.run_state['slurm_versions'] = {
      cyclecloud: node['cyclecloud']['version'],
      project: project_version,
      slurm: slurm_version,
    }
  end
end

file node['cyclecloud']['inventory_path'] do
  content lazy { JSON.pretty_generate(node.run_state.fetch('slurm_versions')) + "\n" }
  owner 'cyclecloud'
  group 'cyclecloud'
  mode '0640'
end

execute 'generate-validated-headless-template' do
  command lazy {
    'headless-template transform ' \
      "--source '#{node['cyclecloud']['source_template']}' " \
      "--destination '#{node['cyclecloud']['headless_template']}' " \
      "--validator 'cyclecloud project validate {candidate}'"
  }
end

template "#{node['cyclecloud']['headless_template']}.overrides" do
  source 'slurm-headless-overrides.txt.erb'
  owner 'cyclecloud'
  group 'cyclecloud'
  mode '0640'
end

template '/etc/cyclecloud/slurm-cluster.properties' do
  source 'cluster.properties.erb'
  owner 'cyclecloud'
  group 'cyclecloud'
  mode '0600'
  sensitive true
end

execute 'import-headless-slurm-cluster' do
  command lazy {
    "cyclecloud import_cluster '#{node['cyclecloud']['cluster_name']}' " \
      "-f '#{node['cyclecloud']['headless_template']}' -c /etc/cyclecloud/slurm-cluster.properties"
  }
  environment 'CYCLECLOUD_CREDENTIAL_FILE' => node['cyclecloud']['credential_file']
  sensitive true
  not_if "cyclecloud show_cluster '#{node['cyclecloud']['cluster_name']}' >/dev/null 2>&1"
end

execute 'grant-demonstration-user-cluster-access' do
  command lazy {
    "cyclecloud locker grant '#{node['cyclecloud']['cluster_name']}' " \
      "'#{node['cyclecloud']['demo_username']}'"
  }
  environment 'CYCLECLOUD_CREDENTIAL_FILE' => node['cyclecloud']['credential_file']
  sensitive true
  not_if "cyclecloud locker list '#{node['cyclecloud']['cluster_name']}' | " \
         "grep -Fx '#{node['cyclecloud']['demo_username']}'"
end

file '/var/tmp/cyclecloud.rpm' do
  action :delete
end
