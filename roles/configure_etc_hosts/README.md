# Configure /etc/hosts Role

This role configures the `/etc/hosts` file on all nodes with inventory hosts and custom host mappings.

## Features

- Automatically adds all inventory hosts to `/etc/hosts`
- Supports registry host mappings via `registry_hosts` variable
- Supports custom host mappings via `custom_hosts` variable
- Maintains standard localhost entries

## Variables

### `registry_hosts`

Map registry domains to their IP addresses. These will be added to `/etc/hosts` for container registry access.

```yaml
registry_hosts:
  "harbor.runway.test": "192.168.135.28"
  "registry.example.com": "10.0.0.50"
```

### `custom_hosts`

Add any custom hostname-to-IP mappings that you need. These will be added to `/etc/hosts` on all nodes.

```yaml
custom_hosts:
  "myapp.example.com": "10.0.0.100"
  "db.example.com": "10.0.0.101"
  "api.example.com": "10.0.0.102"
```

## Usage

### Update /etc/hosts only

```bash
ansible-playbook site.yml --tags hosts-config
```

### Full common setup (includes /etc/hosts configuration)

```bash
ansible-playbook site.yml --tags common
```

### Using Make

```bash
make tag-etc-hosts
```

## Example Configuration

In `group_vars/all.yml`:

```yaml
# Registry hosts
registry_hosts:
  "harbor.runway.test": "192.168.135.28"
  "registry.internal": "172.16.0.10"

# Custom application hosts
custom_hosts:
  "app1.example.com": "10.0.1.100"
  "app2.example.com": "10.0.1.101"
  "database.example.com": "10.0.2.50"
```

## Generated /etc/hosts Format

```
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

# Ansible managed hosts
192.168.135.10 master01
192.168.135.11 worker01
192.168.135.12 worker02

# Registry hosts
192.168.135.28 harbor.runway.test
172.16.0.10 registry.internal

# Custom hosts
10.0.1.100 app1.example.com
10.0.1.101 app2.example.com
10.0.2.50 database.example.com
```
