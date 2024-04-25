# kubernetes-kubeadm

kubernetes-kubeadm/
├── group_vars
│   └── all.yml
├── inventory.ini
├── README.md
├── roles
│   ├── common
│   │   ├── handlers
│   │   │   └── main.yml
│   │   ├── tasks
│   │   │   └── main.yml
│   │   ├── templates
│   │   └── vars
│   │       └── main.yml
│   ├── install_cert_manager
│   │   └── tasks
│   │       └── main.yml
│   ├── install_docker
│   │   ├── handlers
│   │   │   └── main.yml
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       └── daemon.json.j2
│   ├── install_harbor
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   ├── install_istio
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   ├── install_master
│   │   ├── tasks
│   │   │   └── main.yml
│   │   ├── templates
│   │   │   └── kube-config.yaml.j2
│   │   └── vars
│   │       └── main.yml
│   ├── install_metal_lb
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   ├── install_OS_package
│   │   ├── tasks
│   │   │   └── main.yml
│   │   ├── templates
│   │   └── vars
│   │       └── main.yml
│   ├── install_rook-ceph
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   ├── install_tools
│   │   └── tasks
│   │       └── main.yml
│   ├── intall_flannel
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       └── kube-flannel.yml.j2
│   ├── remove_master_taint
│   │   └── tasks
│   │       └── main.yml
│   ├── sysctl
│   │   ├── handlers
│   │   │   └── main.yml
│   │   ├── tasks
│   │   │   └── main.yml
│   │   └── templates
│   │       └── k8s.conf.j2
│   └── worker
│       ├── tasks
│       │   └── main.yml
│       └── vars
│           └── main.yml
└── site.yml
