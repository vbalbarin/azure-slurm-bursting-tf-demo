require 'etc'
require 'json'

required = %w(
  version project_version integration_uri integration_sha256 cluster_name
  scheduler_private_name scheduler_private_address burst_cidr cyclecloud_url
)
missing = required.select { |key| node['slurm'][key].nil? || node['slurm'][key].to_s.empty? }
raise "Missing required Slurm attributes: #{missing.join(', ')}" unless missing.empty?
raise 'CycleCloud Slurm release must be exactly 4.0.11' unless node['slurm']['project_version'] == '4.0.11'
raise 'Slurm package version must be exactly 26.05.4-1.el9' unless node['slurm']['version'] == '26.05.4-1.el9'
raise 'CycleCloud Slurm integration digest mismatch' unless node['slurm']['integration_sha256'] == 'f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36'
raise 'CycleCloud endpoint must be private HTTPS' unless node['slurm']['cyclecloud_url'].match?(%r{\Ahttps://[^/]+\.cyclecloud\.internal/?\z})
raise 'Scheduler private name must use shared private DNS' unless node['slurm']['scheduler_private_name'].match?(/\A[a-z0-9-]+\.cyclecloud\.internal\z/)
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
%w(python3.11 python3.11-pip python3.11-devel).each do |package_name|
  package package_name
end

directory '/var/cache/slurm-demo' do
  owner 'root'
  group 'root'
  mode '0700'
end

yum_repository 'microsoft-slurm-el9-insiders' do
  description 'Microsoft Slurm EL9 insiders'
  baseurl 'https://packages.microsoft.com/yumrepos/slurm-el9-insiders'
  gpgkey 'https://packages.microsoft.com/keys/microsoft.asc'
  gpgcheck true
  repo_gpgcheck false
  enabled true
end

%w(slurm slurm-slurmctld slurm-slurmdbd slurm-slurmrestd).each do |package_name|
  package package_name do
    version node['slurm']['version']
  end
end

remote_file '/var/cache/slurm-demo/azure-slurm-pkg-4.0.11.tar.gz' do
  source node['slurm']['integration_uri']
  checksum node['slurm']['integration_sha256']
  owner 'root'
  group 'root'
  mode '0400'
  sensitive true
end

directory '/opt/azure-slurm-integration/4.0.11' do
  owner 'root'
  group 'root'
  mode '0700'
  recursive true
end

execute 'install-azure-slurm-integration-4.0.11-without-jetpack' do
  command <<~COMMAND
    set -eu
    tar --extract --gzip \
      --file /var/cache/slurm-demo/azure-slurm-pkg-4.0.11.tar.gz \
      --directory /opt/azure-slurm-integration/4.0.11 \
      --strip-components=1
    cd /opt/azure-slurm-integration/4.0.11
    AZSLURM_PYTHON_PATH=/usr/bin/python3.11 ./install.sh --no-jetpack
  COMMAND
  creates '/opt/azurehpc/slurm/venv/bin/azslurm'
  sensitive true
end

execute 'assign-azure-slurm-integration-to-slurm' do
  command 'chown -R slurm:slurm /opt/azurehpc/slurm'
  only_if 'test -d /opt/azurehpc/slurm'
  not_if "test \"$(stat -c '%U:%G' /opt/azurehpc/slurm)\" = slurm:slurm"
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
  mode '0755'
end

{
  '/var/spool/slurmctld' => %w(slurm slurm 0700),
  '/var/spool/slurmd' => %w(slurm slurm 0755),
  '/var/log/slurmctld' => %w(slurm slurm 0755),
  '/var/log/slurmd' => %w(slurm slurm 0755),
  "/sched/#{node['slurm']['cluster_name']}" => %w(slurm slurm 0755),
}.each do |path, (owner, group, mode)|
  directory path do
    owner owner
    group group
    mode mode
    recursive true
  end
end

template '/etc/slurm/slurm.conf' do
  source 'slurm.conf.erb'
  owner 'slurm'
  group 'slurm'
  mode '0644'
  notifies :run, 'execute[validate-slurm-configuration]', :immediately
  notifies :restart, 'service[slurmctld]', :delayed
end

execute 'publish-shared-slurm-configuration' do
  command lazy {
    'install -o slurm -g slurm -m 0644 /etc/slurm/slurm.conf ' \
      "'/sched/#{node['slurm']['cluster_name']}/slurm.conf'"
  }
  not_if "cmp -s /etc/slurm/slurm.conf '/sched/#{node['slurm']['cluster_name']}/slurm.conf'"
end

link '/etc/slurm/gres.conf' do
  to "/sched/#{node['slurm']['cluster_name']}/gres.conf"
  owner 'slurm'
  group 'slurm'
  only_if { node['slurm']['integration_ready'] }
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
