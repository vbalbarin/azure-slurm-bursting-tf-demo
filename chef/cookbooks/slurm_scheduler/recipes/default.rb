require 'etc'
require 'json'

required = %w(version project_version project_uri project_sha256 cluster_name scheduler_private_address burst_cidr cyclecloud_url)
missing = required.select { |key| node['slurm'][key].nil? || node['slurm'][key].to_s.empty? }
raise "Missing required Slurm attributes: #{missing.join(', ')}" unless missing.empty?
raise 'CycleCloud Slurm release must be exactly 4.0.11' unless node['slurm']['project_version'] == '4.0.11'
raise 'CycleCloud Slurm artifact digest mismatch' unless node['slurm']['project_sha256'] == 'a489f4c5ec2404dc02a09792af5f32f4683e164327d89c4c2dfc8d9a30402482'
raise 'CycleCloud endpoint must be private HTTPS' unless node['slurm']['cyclecloud_url'].match?(%r{\Ahttps://[^/]+\.cyclecloud\.internal/?\z})
raise 'Acceptance node limit must be exactly one' unless node['slurm']['max_acceptance_nodes'] == 1
raise 'Return proxy must be disabled for direct peering' if node['slurm']['return_proxy_enabled']

mount '/proc' do
  device 'proc'
  fstype 'proc'
  options %w(defaults hidepid=2)
  action %i(mount enable)
end

{
  'slurm' => [node['slurm']['uid'], node['slurm']['gid']],
  'munge' => [node['munge']['uid'], node['munge']['gid']],
}.each do |name, (uid, gid)|
  ruby_block "reject-conflicting-#{name}-identity" do
    block do
      existing_user = Etc.getpwnam(name)
      raise "#{name} UID conflict" unless existing_user.uid == uid
      raise "#{name} GID conflict" unless existing_user.gid == gid
    rescue ArgumentError
      nil
    end
  end

  group name do
    gid gid
  end

  user name do
    uid uid
    gid gid
    system true
    shell '/sbin/nologin'
  end
end

package 'munge'
package 'nfs-utils'

directory '/var/cache/slurm-demo' do
  owner 'root'
  group 'root'
  mode '0700'
end

remote_file '/var/cache/slurm-demo/azure-slurm-install-pkg-4.0.11.tar.gz' do
  source node['slurm']['project_uri']
  checksum node['slurm']['project_sha256']
  owner 'root'
  group 'root'
  mode '0400'
  sensitive true
end

directory '/opt/azure-slurm/4.0.11' do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
end

file '/var/cache/slurm-demo/azure-slurm-install-config.json' do
  content lazy {
    JSON.pretty_generate(
      'cluster_name' => node['slurm']['cluster_name'],
      'node_name' => 'scheduler',
      'ipaddress' => node['slurm']['scheduler_private_address'],
      'slurm' => {
        'version' => node['slurm']['version'],
        'max_node_count' => node['slurm']['max_acceptance_nodes'],
        'user' => {
          'name' => 'slurm', 'group' => 'slurm',
          'uid' => node['slurm']['uid'], 'gid' => node['slurm']['gid']
        },
      },
      'munge' => {
        'user' => {
          'name' => 'munge', 'group' => 'munge',
          'uid' => node['munge']['uid'], 'gid' => node['munge']['gid']
        },
      },
      'cyclecloud' => { 'monitoring' => { 'enabled' => false } },
      'azure' => { 'metadata' => { 'compute' => { 'vmSize' => 'scheduler', 'version' => '9' } } }
    ) + "\n"
  }
  owner 'root'
  group 'root'
  mode '0600'
end

execute 'install-azure-slurm-4.0.11' do
  command lazy {
    'tar --extract --gzip --file /var/cache/slurm-demo/azure-slurm-install-pkg-4.0.11.tar.gz ' \
      '--directory /opt/azure-slurm/4.0.11 --strip-components=1 && ' \
      '/opt/azure-slurm/4.0.11/install.sh --mode scheduler ' \
      '--bootstrap-config /var/cache/slurm-demo/azure-slurm-install-config.json && ' \
      'touch /opt/azure-slurm/4.0.11/.installed'
  }
  creates '/opt/azure-slurm/4.0.11/.installed'
  sensitive true
end

package 'slurm' do
  version node['slurm']['version']
end

node['slurm']['shared_paths'].each do |path|
  directory path do
    owner 'slurm'
    group 'slurm'
    mode '0755'
    recursive true
  end
end

template '/etc/exports.d/slurm.exports' do
  source 'exports.erb'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :run, 'execute[validate-nfs-exports]', :immediately
  notifies :restart, 'service[nfs-server]', :delayed
end

execute 'validate-nfs-exports' do
  command 'exportfs -ra'
  action :nothing
end

directory '/etc/slurm' do
  owner 'slurm'
  group 'slurm'
  mode '0750'
end

template '/etc/slurm/slurm.conf' do
  source 'slurm.conf.erb'
  owner 'slurm'
  group 'slurm'
  mode '0640'
  notifies :run, 'execute[validate-slurm-configuration]', :immediately
  notifies :restart, 'service[slurmctld]', :delayed
end

execute 'validate-slurm-configuration' do
  command 'slurmctld -t -f /etc/slurm/slurm.conf'
  action :nothing
  only_if { node['slurm']['integration_ready'] }
end

template '/etc/azslurm.conf' do
  source 'azslurm.conf.erb'
  owner 'root'
  group 'root'
  mode '0600'
  sensitive true
end

include_recipe 'slurm_scheduler::demo_user'

%w(munge nfs-server slurmctld).each do |service_name|
  service service_name do
    action(node['slurm']['integration_ready'] ? %i(enable start) : :nothing)
  end
end
