name 'slurm'
default_source :supermarket
run_list 'slurm_scheduler::default'
cookbook 'slurm_scheduler', path: '../cookbooks/slurm_scheduler'
