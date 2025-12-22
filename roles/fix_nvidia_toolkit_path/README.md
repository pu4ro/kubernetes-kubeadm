# Fix NVIDIA Toolkit Path Role

This role fixes the NVIDIA toolkit path in containerd configuration from `/usr/local/nvidia/toolkit` to `/usr/bin`.

## Purpose

When NVIDIA driver is installed via `.run` file (not package manager), the installer places binaries in `/usr/local/nvidia/toolkit`. However, containerd configuration may reference these binaries with the path `/usr/bin` for proper GPU support in containers.

This role performs the following operations:
1. Backs up the current containerd configuration
2. Replaces all occurrences of `/usr/local/nvidia/toolkit` with `/usr/bin`
3. Verifies the changes
4. Restarts containerd service to apply the changes

## When to Use

This role is **only needed** when:
- NVIDIA driver is installed via `.run` file (manual installation)
- NOT needed when driver is installed via package manager (yum/apt)

## Variables

### `fix_nvidia_toolkit_path`

Enable or disable fixing NVIDIA toolkit path in containerd config.

**Default:** `false`

```yaml
# In group_vars/all.yml
fix_nvidia_toolkit_path: true  # Enable to fix NVIDIA toolkit path
```

## Usage

### Method 1: Using Makefile (Recommended)

```bash
# Fix NVIDIA toolkit path
make fix-nvidia-toolkit-path
```

### Method 2: Using Ansible Tags

```bash
# Run only the fix-nvidia-toolkit-path role
ansible-playbook -i inventory.ini site.yml --tags fix-nvidia-toolkit-path
```

### Method 3: As Part of Full Playbook

1. Enable in `group_vars/all.yml`:
   ```yaml
   fix_nvidia_toolkit_path: true
   ```

2. Run the full playbook:
   ```bash
   ansible-playbook -i inventory.ini site.yml
   ```

## Prerequisites

- Containerd must be installed
- `/etc/containerd/config.toml` must exist
- NVIDIA driver installed via `.run` file

## What It Does

### Before

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  privileged_without_host_devices = false
  runtime_engine = ""
  runtime_root = ""
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/local/nvidia/toolkit/nvidia-container-runtime"
```

### After

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  privileged_without_host_devices = false
  runtime_engine = ""
  runtime_root = ""
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
```

## Manual Verification

After running this role, you can verify the changes:

```bash
# Check BinaryName paths
grep "BinaryName" /etc/containerd/config.toml

# Expected output should show /usr/bin paths, not /usr/local/nvidia/toolkit
```

## Backup

The role automatically creates a backup of the containerd configuration:
- `/etc/containerd/config.toml.bak` - Manual backup
- `/etc/containerd/config.toml.TIMESTAMP.backup` - Ansible replace module backup

## Troubleshooting

### Issue: Containerd fails to start after applying changes

**Solution:** Restore from backup:
```bash
sudo cp /etc/containerd/config.toml.bak /etc/containerd/config.toml
sudo systemctl restart containerd
```

### Issue: GPU pods still fail to start

**Possible causes:**
1. NVIDIA runtime binaries not in `/usr/bin`
2. NVIDIA container toolkit not installed
3. Check runtime binary location:
   ```bash
   which nvidia-container-runtime
   which nvidia-container-runtime-hook
   ```

### Issue: Path already correct

The role is idempotent - if the path is already correct (`/usr/bin`), no changes will be made and containerd won't be restarted.

## Related Roles

- `install_nvidia_driver` - Installs NVIDIA driver via `.run` file
- `install_containerd` - Installs and configures containerd

## Tags

- `nvidia` - NVIDIA-related tasks
- `fix-nvidia-toolkit-path` - This specific role

## Dependencies

None

## License

MIT

## Author

Generated for Kubernetes-kubeadm project
