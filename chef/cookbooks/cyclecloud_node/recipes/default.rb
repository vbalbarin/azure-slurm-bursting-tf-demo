require 'json'
require 'uri'

specification_values = {
  'private_name' => begin
    URI(node['cyclecloudUrl']).host if node['cyclecloudUrl']
  end,
  'cluster_name' => node['clusterName'],
  'burst_region' => node['burstRegion'],
  'scheduler_private_address' => node['schedulerPrivateAddress'],
  'burst_cidr' => node['burstCidr'],
  'slurm_uid' => node.dig('slurmIdentity', 'uid'),
  'slurm_gid' => node.dig('slurmIdentity', 'gid'),
  'munge_uid' => node.dig('mungeIdentity', 'uid'),
  'munge_gid' => node.dig('mungeIdentity', 'gid'),
  'hpc_user_name' => node.dig('hpcUser', 'name'),
  'hpc_user_uid' => node.dig('hpcUser', 'uid'),
  'hpc_user_gid' => node.dig('hpcUser', 'gid'),
  'hpc_user_home' => node.dig('hpcUser', 'home'),
}
specification_values.each do |key, value|
  node.default['cyclecloud'][key] = value unless value.nil?
end

required = %w(
  private_name cluster_name burst_region scheduler_private_address burst_cidr
  slurm_uid slurm_gid munge_uid munge_gid hpc_user_name hpc_user_uid hpc_user_gid
  hpc_user_home
)
missing = required.select { |key| node['cyclecloud'][key].nil? || node['cyclecloud'][key].to_s.empty? }
raise "Missing required CycleCloud specification values: #{missing.join(', ')}" unless missing.empty?

raise 'CycleCloud cluster name must be cross-region-demo' unless node['cyclecloud']['cluster_name'] == 'cross-region-demo'
raise 'Invalid Slurm identity' unless [node['cyclecloud']['slurm_uid'], node['cyclecloud']['slurm_gid']] == [11100, 11100]
raise 'Invalid Munge identity' unless [node['cyclecloud']['munge_uid'], node['cyclecloud']['munge_gid']] == [11101, 11101]
unless [
  node['cyclecloud']['hpc_user_name'],
  node['cyclecloud']['hpc_user_uid'],
  node['cyclecloud']['hpc_user_gid'],
  node['cyclecloud']['hpc_user_home'],
] == ['hpcuser01', 11200, 11200, '/shared/home/hpcuser01']
  raise 'Invalid HPC user specification'
end

package %w(python3 jq)

ruby_block 'require-cyclecloud-8.9.3' do
  block { raise 'CycleCloud version skew: expected exactly 8.9.3' }
  not_if "rpm -q --qf '%{VERSION}' cyclecloud | grep -Fqx '8.9.3'"
end

directory '/var/cache/slurm-demo' do
  owner 'root'
  group 'root'
  mode '0700'
end

remote_file node['cyclecloud']['project_archive'] do
  source node['cyclecloud']['slurm_project_uri']
  checksum node['cyclecloud']['slurm_project_sha256']
  owner 'root'
  group 'root'
  mode '0600'
  sensitive true
end

execute 'install-cyclecloud-slurm-project-4.0.11' do
  command lazy {
    "cyclecloud project upload '#{node['cyclecloud']['project_archive']}' " \
      "--name '#{node['cyclecloud']['project_name']}'"
  }
  not_if "test -f '#{node['cyclecloud']['project_root']}/version' && " \
         "grep -Fqx '4.0.11' '#{node['cyclecloud']['project_root']}/version'"
end

ruby_block 'reject-cyclecloud-slurm-project-version-skew' do
  block do
    version_file = ::File.join(node['cyclecloud']['project_root'], 'version')
    raise 'CycleCloud Slurm project version file is missing' unless ::File.file?(version_file)
    raise 'CycleCloud Slurm project version skew' unless ::File.read(version_file).strip == '4.0.11'
  end
end

execute 'verify-staged-headless-template-tool' do
  command "PYTHONPATH='#{node['cyclecloud']['processor_root']}' python3 -m headless_template --help >/dev/null"
end

template "#{node['cyclecloud']['headless_template']}.overrides" do
  source 'slurm-headless-overrides.txt.erb'
  owner 'cyclecloud'
  group 'cyclecloud'
  mode '0640'
end

execute 'generate-validated-headless-template' do
  command lazy {
    candidate = "#{node['cyclecloud']['headless_template']}.candidate"
    "rm -f '#{candidate}' && " \
      "PYTHONPATH='#{node['cyclecloud']['processor_root']}' python3 -m headless_template transform " \
      "--source '#{node['cyclecloud']['source_template']}' " \
      "--destination '#{candidate}' " \
      "--validator 'cyclecloud project validate {candidate}'"
  }
end

execute 'activate-validated-headless-template' do
  command lazy {
    candidate = "#{node['cyclecloud']['headless_template']}.candidate"
    "cat '#{node['cyclecloud']['headless_template']}.overrides' >>'#{candidate}' && " \
      "cyclecloud project validate '#{candidate}' && " \
      "chown cyclecloud:cyclecloud '#{candidate}' && chmod 0640 '#{candidate}' && " \
      "mv -f '#{candidate}' '#{node['cyclecloud']['headless_template']}'"
  }
  only_if "test -f '#{node['cyclecloud']['headless_template']}.candidate'"
end

file node['cyclecloud']['inventory_path'] do
  content JSON.pretty_generate(
    cyclecloud: '8.9.3',
    project: '4.0.11',
    projectSha256: node['cyclecloud']['slurm_project_sha256']
  ) + "\n"
  owner 'cyclecloud'
  group 'cyclecloud'
  mode '0600'
end

template '/etc/cyclecloud/slurm-cluster.properties' do
  source 'cluster.properties.erb'
  owner 'cyclecloud'
  group 'cyclecloud'
  mode '0600'
end

ruby_block 'require-cyclecloud-bootstrap' do
  block do
    raise 'CycleCloud first-run bootstrap is incomplete: CLI configuration or Azure provider account is unavailable'
  end
  not_if "test -s '#{node['cyclecloud']['cli_config']}' && " \
         "test '#{node['cyclecloud']['cli_config']}' -ef /root/.cycle/config.ini && " \
         "! cyclecloud account list 2>&1 | grep -Fqx 'No accounts found'"
end

execute 'import-headless-slurm-cluster' do
  command lazy {
    "cyclecloud import_cluster '#{node['cyclecloud']['cluster_name']}' " \
      "-f '#{node['cyclecloud']['headless_template']}' -c /etc/cyclecloud/slurm-cluster.properties"
  }
  not_if "cyclecloud show_cluster '#{node['cyclecloud']['cluster_name']}' >/dev/null 2>&1"
end

execute 'verify-exactly-one-headless-slurm-cluster' do
  command lazy {
    'test "$(cyclecloud cluster list --output json | ' \
      "jq '[.[] | select(.Name == \"#{node['cyclecloud']['cluster_name']}\")] | length')\" -eq 1"
  }
end
