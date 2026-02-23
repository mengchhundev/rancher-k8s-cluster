# Rancher on GCP with Ansible (RKE2 HA)

Production-style Infrastructure-as-Code scaffold to provision 5 Ubuntu 22.04 VMs on GCP, build an HA RKE2 Kubernetes cluster, and install Rancher with TLS via cert-manager + Let’s Encrypt.

## Quick start
1. Review and set variables in `inventories/prod/group_vars/all.yml`.
2. Create/encrypt `inventories/prod/group_vars/all/vault.yml`.
3. Install dependencies:
   - `ansible-galaxy collection install -r requirements.yml`
4. Run provisioning then cluster setup playbooks.

## Task runner
A `justfile` is included to simplify common workflows:
- `just provision`
- `just deploy`
- `just all`

See full implementation plan, architecture, runbook, validation, and troubleshooting in:
- `docs/PROJECT_PLAN.md`
