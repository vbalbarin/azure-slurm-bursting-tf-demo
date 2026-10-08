raise 'Demonstration public key is required' if node['demo_user']['public_key'].to_s.empty?

group node['demo_user']['name'] do
  gid node['demo_user']['uid_gid']
end

user node['demo_user']['name'] do
  uid node['demo_user']['uid_gid']
  gid node['demo_user']['uid_gid']
  home node['demo_user']['home']
  manage_home false
  shell '/bin/bash'
end

directory node['demo_user']['home'] do
  owner node['demo_user']['name']
  group node['demo_user']['name']
  mode '0700'
  recursive true
end

directory "#{node['demo_user']['home']}/.ssh" do
  owner node['demo_user']['name']
  group node['demo_user']['name']
  mode '0700'
end

file "#{node['demo_user']['home']}/.ssh/authorized_keys" do
  content "#{node['demo_user']['public_key'].strip}\n"
  owner node['demo_user']['name']
  group node['demo_user']['name']
  mode '0600'
  sensitive true
end
