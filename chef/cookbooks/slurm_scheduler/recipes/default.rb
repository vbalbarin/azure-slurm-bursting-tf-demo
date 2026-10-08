require 'etc'

required = %w(version project_version cluster_name scheduler_private_address burst_cidr cyclecloud_url)
missing = required.select { |key| node['slurm'][key].nil? || node['slurm'][key].to_s.empty? }
raise "Missing required Slurm attributes: #{missing.join(', ')}" unless missing.empty?
raise 'Acceptance node limit must be exactly one' unless node['slurm']['max_acceptance_nodes'] == 1
raise 'Return proxy must be disabled for direct peering' if node['slurm']['return_proxy_enabled']

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
package 'slurm' do
  version node['slurm']['version']
end
package 'azslurm' do
  version node['slurm']['project_version']
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
end

template '/etc/azslurm.conf' do
  source 'azslurm.conf.erb'
  owner 'slurm'
  group 'slurm'
  mode '0600'
  sensitive true
end

include_recipe 'slurm_scheduler::demo_user'

%w(munge nfs-server slurmctld).each do |service_name|
  service service_name do
    action %i(enable start)
  end
end
