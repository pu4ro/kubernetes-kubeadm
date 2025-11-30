# Repository Guidelines

## Project Structure & Module Organization
- `site.yml` chains the roles in `roles/` (install_containerd, install_kubernetes, install_flannel, etc.); keep new features self-contained within a role and expose them via tags.
- `group_vars/all.yml` stores cluster defaults (versions, VIP, registry credentials); rely on inventory overrides rather than editing tasks.
- `inventory.ini` defines `masters`, `workers`, `installs`, and `pre-installs`; place host-specific facts there, and update docs in `ADD-WORKER-GUIDE.md` or scripts in `utils/` whenever workflows change.

## Build, Test, and Development Commands
- `ansible-playbook -i inventory.ini site.yml` — performs the full install flow driven by the values in `group_vars`.
- `ansible-playbook -i inventory.ini site.yml --tags sysctl,packages,container` — runs only OS prep tasks while iterating on kernel or containerd fixes.
- `ansible-playbook -i inventory.ini site.yml --limit master1` (or `--limit workers`) — targets specific hosts when validating HA join paths.
- `ansible-playbook -i inventory.ini reset_cluster.yml` — cleans nodes and kube-vip VIPs; run it after destructive tests.
- Set `ANSIBLE_STDOUT_CALLBACK=debug` temporarily for richer module output when diagnosing failures.

## Coding Style & Naming Conventions
- Use two-space YAML indentation, lowercase `snake_case` variable names (e.g., `containerd_data_base_dir`), and dash-separated role directories.
- Prefer native modules for idempotency; wrap unavoidable `shell` usage with `creates`/`removes` and `changed_when`.
- Surface tunables through `defaults/main.yml` and name handlers after the service they restart for quick traceability.

## Testing Guidelines
- Run `ansible-playbook -i inventory.ini site.yml --syntax-check` to catch YAML or template errors before review.
- Validate idempotency with `ansible-playbook -i inventory.ini site.yml --check --diff` against a lab inventory.
- Exercise the specific tags you touched (e.g., `--tags k8s-certs`, `--tags coredns-hosts`) and attach the final task summary screenshot or log to your PR.

## Commit & Pull Request Guidelines
- Mirror the repo’s Conventional Commit prefixes (`fix:`, `refactor:`, `feat:`) and keep subjects concise.
- Squash debug commits so each change set maps to a single concern (e.g., kube-vip cleanup, containerd tuning).
- PRs should summarize the change, list touched files/variables, include the exact validation commands and inventory, note any manual follow-up steps, and request reviewers from each affected subsystem.
