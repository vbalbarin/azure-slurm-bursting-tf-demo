require 'json'
require 'uri'

specification_values = {
  'private_name' => begin
    URI(node['cyclecloudUrl']).host if node['cyclecloudUrl']
  end,
  'cluster_name' => node['clusterName'],
  'burst_region' => node['burstRegion'],
  'burst_zone' => node['burstZone'],
  'burst_vm_size' => node['burstVmSize'],
  'burst_image_name' => node['burstImageName'],
  'burst_subnet_id' => node['burstSubnetId'],
  'locker_identity_resource_id' => node['lockerIdentityResourceId'],
  'registered_slurm_project_version' => node['registeredSlurmProjectVersion'],
  'slurm_version' => node['slurmTemplateVersion'],
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
  private_name cluster_name burst_region burst_zone burst_vm_size burst_image_name
  burst_subnet_id locker_identity_resource_id registered_slurm_project_version
  slurm_version scheduler_private_address burst_cidr
  slurm_uid slurm_gid munge_uid munge_gid hpc_user_name hpc_user_uid hpc_user_gid
  hpc_user_home
)
missing = required.select { |key| node['cyclecloud'][key].nil? || node['cyclecloud'][key].to_s.empty? }
raise "Missing required CycleCloud specification values: #{missing.join(', ')}" unless missing.empty?

raise 'CycleCloud cluster name must be cross-region-demo' unless node['cyclecloud']['cluster_name'] == 'cross-region-demo'
raise 'Registered Slurm project compatibility must be exactly 4.0.9' unless node['cyclecloud']['registered_slurm_project_version'] == '4.0.9'
raise 'Slurm template version must be exactly 26.05.4' unless node['cyclecloud']['slurm_version'] == '26.05.4'
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
  not_if "/opt/cycle_server/cycle_server version | grep -Eq '^8\\.9\\.3-[0-9]+$'"
end

directory '/var/cache/slurm-demo' do
  owner 'root'
  group 'root'
  mode '0700'
end

directory '/var/lib/slurm-demo/projects' do
  owner 'root'
  group 'root'
  mode '0700'
  recursive true
end

remote_file node['cyclecloud']['project_source_archive'] do
  source node['cyclecloud']['slurm_project_source_uri']
  checksum node['cyclecloud']['slurm_project_source_sha256']
  owner 'root'
  group 'root'
  mode '0600'
  sensitive true
end

execute 'stage-cyclecloud-slurm-project-4.0.11' do
  command lazy {
    project_root = node['cyclecloud']['project_root']
    project_parent = ::File.dirname(project_root)
    source_commit = node['cyclecloud']['slurm_project_commit']
    <<~COMMAND
      set -eu
      staging="$(mktemp -d '#{project_parent}/.cyclecloud-slurm.XXXXXX')"
      trap 'rm -rf "$staging"' EXIT
      tar --extract --gzip --file '#{node['cyclecloud']['project_source_archive']}' \
        --strip-components 1 --directory "$staging"
      grep -Eq '^version[[:space:]]*=[[:space:]]*4\\.0\\.11[[:space:]]*$' "$staging/project.ini"
      printf '%s\n' '#{source_commit}' >"$staging/.source-commit"
      chmod 0600 "$staging/.source-commit"
      rm -rf '#{project_root}'
      mv "$staging" '#{project_root}'
      trap - EXIT
    COMMAND
  }
  not_if "grep -Fqx '#{node['cyclecloud']['slurm_project_commit']}' " \
         "'#{node['cyclecloud']['project_root']}/.source-commit' 2>/dev/null && " \
         "grep -Eq '^version[[:space:]]*=[[:space:]]*4\\.0\\.11[[:space:]]*$' " \
         "'#{node['cyclecloud']['project_root']}/project.ini'"
end

directory "#{node['cyclecloud']['project_root']}/blobs" do
  owner 'root'
  group 'root'
  mode '0700'
end

slurm_project_blobs = {
  'azure-slurm-pkg-4.0.11.tar.gz' => [
    node['cyclecloud']['slurm_runtime_uri'],
    node['cyclecloud']['slurm_runtime_sha256'],
  ],
  'azure-slurm-install-pkg-4.0.11.tar.gz' => [
    node['cyclecloud']['slurm_install_uri'],
    node['cyclecloud']['slurm_install_sha256'],
  ],
  'azure_slurm_exporter-0.3.0.tar.gz' => [
    node['cyclecloud']['slurm_exporter_uri'],
    node['cyclecloud']['slurm_exporter_sha256'],
  ],
}

slurm_project_blobs.each do |name, (uri, checksum)|
  remote_file "#{node['cyclecloud']['project_root']}/blobs/#{name}" do
    source uri
    checksum checksum
    owner 'root'
    group 'root'
    mode '0600'
    sensitive true
  end
end

execute 'upload-cyclecloud-slurm-project-4.0.11' do
  command lazy {
    marker = "#{node['cyclecloud']['project_root']}/.uploaded-version"
    <<~COMMAND
      set -eu
      locker_count="$(cyclecloud locker list | awk 'NF { count++ } END { print count + 0 }')"
      test "$locker_count" -eq 1
      locker="$(cyclecloud locker list | awk 'NF { print $1 }')"
      cd '#{node['cyclecloud']['project_root']}'
      cyclecloud project upload "$locker"
      temporary='#{marker}.tmp'
      printf '%s\n' '4.0.11' >"$temporary"
      chmod 0600 "$temporary"
      mv -f "$temporary" '#{marker}'
    COMMAND
  }
  not_if "grep -Fqx '4.0.11' '#{node['cyclecloud']['project_root']}/.uploaded-version' 2>/dev/null"
end

execute 'require-staged-headless-template-tool' do
  command "echo 'Headless template tool is unavailable' >&2; exit 1"
  not_if "PYTHONPATH='#{node['cyclecloud']['processor_root']}' " \
         'python3 -m headless_template --help >/dev/null 2>&1'
end

template node['cyclecloud']['headless_overrides'] do
  source 'slurm-headless-overrides.txt.erb'
  owner 'root'
  group 'root'
  mode '0600'
end

execute 'compose-headless-template-input' do
  command lazy {
    temporary = "#{node['cyclecloud']['headless_input']}.tmp"
    <<~COMMAND
      set -eu
      trap 'rm -f "#{temporary}"' EXIT
      cat '#{node['cyclecloud']['source_template']}' '#{node['cyclecloud']['headless_overrides']}' >'#{temporary}'
      chmod 0600 '#{temporary}'
      mv -f '#{temporary}' '#{node['cyclecloud']['headless_input']}'
      trap - EXIT
    COMMAND
  }
  not_if "test -f '#{node['cyclecloud']['headless_input']}' && " \
         "cat '#{node['cyclecloud']['source_template']}' '#{node['cyclecloud']['headless_overrides']}' | " \
         "cmp -s - '#{node['cyclecloud']['headless_input']}'"
end

headless_validator = '/usr/bin/env ' \
                     "PYTHONPATH=#{node['cyclecloud']['processor_root']} " \
                     'python3 -m headless_template validate ' \
                     "--slurm-project-version #{node['cyclecloud']['registered_slurm_project_version']} " \
                     '{candidate}'
headless_check = <<~COMMAND
  set -eu
  temporary="$(mktemp '#{::File.dirname(node['cyclecloud']['headless_template'])}/.slurm-headless-check.XXXXXX')"
  trap 'rm -f "$temporary"' EXIT
  PYTHONPATH='#{node['cyclecloud']['processor_root']}' python3 -m headless_template transform \
    --source '#{node['cyclecloud']['headless_input']}' \
    --destination "$temporary" \
    --slurm-project-version '#{node['cyclecloud']['registered_slurm_project_version']}' \
    --validator '#{headless_validator}' >/dev/null
  cmp -s "$temporary" '#{node['cyclecloud']['headless_template']}'
COMMAND

execute 'generate-validated-headless-template' do
  command lazy {
    "PYTHONPATH='#{node['cyclecloud']['processor_root']}' python3 -m headless_template transform " \
      "--source '#{node['cyclecloud']['headless_input']}' " \
      "--destination '#{node['cyclecloud']['headless_template']}' " \
      "--slurm-project-version '#{node['cyclecloud']['registered_slurm_project_version']}' " \
      "--validator '#{headless_validator}'"
  }
  not_if headless_check
end

directory ::File.dirname(node['cyclecloud']['inventory_path']) do
  owner 'root'
  group 'root'
  mode '0700'
  recursive true
end

file node['cyclecloud']['inventory_path'] do
  content JSON.pretty_generate(
    cyclecloud: '8.9.3',
    project: '4.0.11',
    projectCommit: node['cyclecloud']['slurm_project_commit'],
    projectSourceSha256: node['cyclecloud']['slurm_project_source_sha256'],
    runtimeSha256: node['cyclecloud']['slurm_runtime_sha256'],
    installSha256: node['cyclecloud']['slurm_install_sha256'],
    exporterSha256: node['cyclecloud']['slurm_exporter_sha256']
  ) + "\n"
  owner 'root'
  group 'root'
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
    <<~COMMAND
      set -eu
      credential_count="$(cyclecloud account list | awk 'NF { count++ } END { print count + 0 }')"
      test "$credential_count" -eq 1
      credentials="$(cyclecloud account list | awk 'NF { print $1 }')"
      cyclecloud import_cluster '#{node['cyclecloud']['cluster_name']}' \
        -c Slurm -f '#{node['cyclecloud']['headless_template']}' \
        -P Credentials="$credentials"
    COMMAND
  }
  not_if "cyclecloud show_cluster '#{node['cyclecloud']['cluster_name']}' >/dev/null 2>&1"
end

execute 'start-headless-slurm-cluster' do
  command "cyclecloud start_cluster '#{node['cyclecloud']['cluster_name']}'"
  not_if "cyclecloud show_cluster '#{node['cyclecloud']['cluster_name']}' | grep -Fq ': started'"
end

execute 'verify-exactly-one-headless-slurm-cluster' do
  command "echo 'Headless Slurm cluster is unavailable' >&2; exit 1"
  not_if "cyclecloud show_cluster '#{node['cyclecloud']['cluster_name']}' >/dev/null 2>&1"
end
