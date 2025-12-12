# NVIDIA GPU Driver Installation Role

This role automatically installs NVIDIA GPU drivers on nodes with NVIDIA GPUs.

## Features

- Automatic GPU detection using `lspci`
- Skips installation if no NVIDIA GPU is detected
- Checks if driver is already installed
- Blacklists nouveau driver
- Installs required kernel packages
- Downloads driver from configurable web server
- Silent installation with no user interaction
- Post-installation verification

## Configuration

Configure the following variables in `group_vars/all.yml`:

```yaml
# Enable NVIDIA driver installation (default: false)
enable_nvidia_driver_install: false

# NVIDIA driver version to install
nvidia_driver_version: "550.142"

# Web server URL hosting the driver files
nvidia_driver_download_url: "http://192.168.135.71:8080/nvidia"

# Driver filename (auto-generated from version)
nvidia_driver_filename: "NVIDIA-Linux-x86_64-{{ nvidia_driver_version }}.run"

# Installation options
nvidia_driver_install_options: "--silent --no-questions --ui=none --disable-nouveau"
```

## Usage

### Install NVIDIA drivers on all nodes with GPUs

```bash
ansible-playbook -i inventory.ini site.yml --tags install-nvidia-driver
```

### Install NVIDIA drivers and complete system setup

```bash
# Enable in group_vars/all.yml first:
# enable_nvidia_driver_install: true

ansible-playbook -i inventory.ini site.yml
```

### Install only on specific hosts

```bash
ansible-playbook -i inventory.ini site.yml --tags install-nvidia-driver --limit gpu-workers
```

## Prerequisites

1. **Web Server Setup**: Host the NVIDIA driver `.run` file on a web server
   ```bash
   # Example: Using Apache HTTP server
   mkdir -p /var/www/html/nvidia
   wget https://us.download.nvidia.com/XFree86/Linux-x86_64/550.142/NVIDIA-Linux-x86_64-550.142.run \
     -O /var/www/html/nvidia/NVIDIA-Linux-x86_64-550.142.run
   ```

2. **Network Access**: Ensure target nodes can access the web server

3. **Kernel Compatibility**: The role installs required kernel packages automatically

## Installation Process

The role performs the following steps:

1. Detects NVIDIA GPU using `lspci`
2. Checks if driver is already installed
3. Installs kernel, kernel-headers, and build tools
4. Creates blacklist configuration for nouveau driver
5. Regenerates initramfs (dracut/update-initramfs)
6. Downloads NVIDIA driver from web server
7. Runs silent installation
8. Verifies installation with `nvidia-smi`
9. Cleans up temporary files

## Post-Installation

**Important**: A system reboot is recommended to fully activate the NVIDIA driver and ensure the nouveau driver is blacklisted.

```bash
# Reboot nodes after driver installation
ansible -i inventory.ini gpu-workers -m reboot
```

## GPU Operator Integration

After installing the driver, you can deploy the NVIDIA GPU Operator with driver disabled:

```bash
helm install gpu-operator ./gpu-operator \
  -n gpu-operator \
  --create-namespace \
  --set driver.enabled=false
```

This is configured in `group_vars/all.yml`:

```yaml
enable_gpu_operator: false
gpu_operator_namespace: "gpu-operator"
gpu_operator_chart_path: "./gpu-operator"
gpu_operator_driver_enabled: false
```

## Troubleshooting

### Check if GPU is detected

```bash
ansible -i inventory.ini all -m shell -a "lspci | grep -i nvidia"
```

### Verify driver installation

```bash
ansible -i inventory.ini all -m shell -a "nvidia-smi"
```

### Check nouveau is blacklisted

```bash
ansible -i inventory.ini all -m shell -a "lsmod | grep nouveau"
# Should return empty if blacklisted successfully
```

### View driver installation logs

```bash
# On the target node
cat /var/log/nvidia-installer.log
```

## Supported Operating Systems

- RHEL/CentOS 8.x, 9.x
- Ubuntu 20.04, 22.04, 24.04

## Notes

- The role automatically detects the OS family and uses the appropriate package manager
- Installation is skipped on nodes without NVIDIA GPUs
- Driver installation requires kernel packages, which are installed automatically
- The nouveau driver is blacklisted to prevent conflicts
- A reboot is recommended after installation
