name 'windows_admin'
default_source :supermarket
run_list 'windows_admin::default'
cookbook 'windows_admin', path: '../cookbooks/windows_admin'
