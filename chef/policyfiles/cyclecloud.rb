name 'cyclecloud'
default_source :supermarket
run_list 'cyclecloud_node::default'
cookbook 'cyclecloud_node', path: '../cookbooks/cyclecloud_node'
