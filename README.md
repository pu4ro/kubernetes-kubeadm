# kubernetes-kubeadm

### site.yml
```
- hosts: all  #Infra settings
  roles:
    - configure_repo                
    - common # set_timezone, set_kernel, tags=timezone                 
    - configure_sysctl           
    - install_os_package
    - install_docker
    - install_kubernetes
    - copy_config # docker_config_copy
    - configure_dns # tags=set_dns

- hosts: installs # runway back_ground install && runway install
  roles:
    - install_dnsmasq # set dns-server, tags=dns
    - install_flannel
    - install_tools # set k9s,kubectl,helm tags=tools
    - remove_master_taint
    - install_cert_manager
    - install_rook_ceph
    - install_istio
    - install_metal_lb
    - install_harbor
    - install_prometheus
    - install_ef # elastic & fluentd
    - install_knative
    - install_minio
    - install_argo
    - install_pypiserver
    - install_stream
    - install_backend
    - install_frontend
```


### how to deploy  
```
ansible-playbook -i inventory.ini site.yml
```