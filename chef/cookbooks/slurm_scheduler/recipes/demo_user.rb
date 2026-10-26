require 'etc'

raise 'Unexpected workload user name' unless node['demo_user']['name'] == 'hpcuser01'
raise 'Unexpected workload user identity' unless node['demo_user']['uid_gid'] == 11200
raise 'Unexpected workload user home' unless node['demo_user']['home'] == '/shared/home/hpcuser01'

ruby_block 'reject-conflicting-hpcuser01-identity' do
  block do
    account = Etc.getpwnam('hpcuser01')
    raise 'hpcuser01 UID conflict' unless account.uid == 11200
    raise 'hpcuser01 GID conflict' unless account.gid == 11200
    raise 'hpcuser01 home conflict' unless account.dir == '/shared/home/hpcuser01'
  rescue ArgumentError
    nil
  end
end

group 'hpcuser01' do
  gid 11200
end

user 'hpcuser01' do
  uid 11200
  gid 11200
  home '/shared/home/hpcuser01'
  manage_home false
  shell '/bin/bash'
end

directory '/shared/home/hpcuser01' do
  owner 'hpcuser01'
  group 'hpcuser01'
  mode '0700'
  recursive true
end

directory '/shared/home/hpcuser01/.ssh' do
  owner 'hpcuser01'
  group 'hpcuser01'
  mode '0700'
end

execute 'generate-preserved-hpcuser01-ed25519-key' do
  command 'ssh-keygen -q -t ed25519 -N "" -C hpcuser01@scheduler -f /shared/home/hpcuser01/.ssh/id_ed25519'
  user 'hpcuser01'
  group 'hpcuser01'
  environment('HOME' => '/shared/home/hpcuser01')
  umask '0077'
  not_if { ::File.exist?('/shared/home/hpcuser01/.ssh/id_ed25519') }
end

file '/shared/home/hpcuser01/.ssh/id_ed25519' do
  owner 'hpcuser01'
  group 'hpcuser01'
  mode '0600'
  sensitive true
  only_if { ::File.exist?('/shared/home/hpcuser01/.ssh/id_ed25519') }
end

file '/shared/home/hpcuser01/.ssh/id_ed25519.pub' do
  owner 'hpcuser01'
  group 'hpcuser01'
  mode '0644'
  only_if { ::File.exist?('/shared/home/hpcuser01/.ssh/id_ed25519.pub') }
end
