# GCP + RKE2 + Rancher Automation Plan (Ansible)

## 1) Architecture Diagram

```text
                                    +-------------------------------+
                                    |          Internet             |
                                    +-------------------------------+
                                                   |
                                            DNS A Record
                                      rancher.example.com
                                                   |
                                          +----------------+
                                          | GCP Static IP   |
                                          +----------------+
                                                   |
                                      TCP 80/443 (Firewall)
                                                   |
                 +----------------------------------------------------------------+
                 | VPC: rancher-vpc (10.42.0.0/24)                                |
                 | Subnet: rancher-subnet                                          |
                 | Zone: us-central1-a                                             |
                 |                                                                |
                 |   +---------------------+   +---------------------+            |
                 |   | cp1 (RKE2 server)   |   | cp2 (RKE2 server)   |            |
                 |   | etcd + control-plane|   | etcd + control-plane|            |
                 |   +---------------------+   +---------------------+            |
                 |              \                    /                             |
                 |               \                  /                              |
                 |                +----------------+                               |
                 |                | cp3 (RKE2 svr) |                               |
                 |                | etcd + ctrlpln |                               |
                 |                +----------------+                               |
                 |                        |                                         |
                 |      +--------------------------------------------+             |
                 |      | Kubernetes Services                         |             |
                 |      | - ingress-nginx (LoadBalancer)              |             |
                 |      | - cert-manager + ClusterIssuer(LE)          |             |
                 |      | - Rancher (Helm, cattle-system)             |             |
                 |      +--------------------------------------------+             |
                 |                        |                                         |
                 |   +---------------------+   +---------------------+             |
                 |   | wk1 (RKE2 agent)    |   | wk2 (RKE2 agent)    |             |
                 |   +---------------------+   +---------------------+             |
                 +----------------------------------------------------------------+
```

## 2) Detailed Implementation Plan

### Platform choice: **RKE2 (selected)**
- Chosen over RKE1 because RKE2 is the current Rancher-recommended, CNCF-conformant Kubernetes distribution with stronger defaults, integrated components, and a better long-term support path.
- RKE1 is maintenance/legacy oriented for many use-cases and not recommended for new greenfield deployments.

### Phases
1. **Bootstrap toolchain and secrets**
   - Install Ansible collections (`google.cloud`, `kubernetes.core`).
   - Create/secure Vault file containing `rke2_token`, Rancher bootstrap password, and optionally GCP service account JSON.
2. **Provision GCP resources (IaC via Ansible)**
   - VPC + subnet.
   - Minimal firewall rules.
   - Reserve static external IP for Rancher endpoint.
   - Create 3 control-plane and 2 worker Ubuntu 22.04 instances.
   - Generate dynamic inventory with discovered IPs.
3. **Host baseline hardening**
   - Install base packages and kernel requirements.
   - Disable swap and apply Kubernetes sysctl settings.
4. **Kubernetes cluster deployment with RKE2**
   - Install/configure RKE2 server on control planes (HA etcd/control-plane).
   - Join workers as RKE2 agents.
5. **Ingress + certificates + Rancher installation**
   - Install ingress-nginx by Helm.
   - Install cert-manager and Let’s Encrypt `ClusterIssuer`.
   - Deploy Rancher using Helm with TLS secret from cert-manager.
6. **Validation and operational checks**
   - Verify node readiness, system pods, ingress LB status, cert issuance, and Rancher rollout.
7. **Operations and day-2 guidance**
   - Add backup strategy for etcd snapshots.
   - Add monitoring/logging and CIS hardening if required.

## 3) Required GCP Resources

- **VPC**: `rancher-vpc`
- **Subnet**: `rancher-subnet` (`10.42.0.0/24`)
- **Instances (5 total)**:
  - `cp1`, `cp2`, `cp3` (control-plane/etcd)
  - `wk1`, `wk2` (workers)
- **Firewall rules**:
  - `rancher-admin-ingress`: allow `22, 6443, 9345` from admin CIDRs only.
  - `rancher-public-web`: allow `80,443` from internet.
- **Static external IP**: `rancher-public-ip`
- **Service account**: `rancher-node-sa@PROJECT_ID.iam.gserviceaccount.com`
- **Least-privilege IAM roles (minimum practical set)**:
  - For provisioning identity used by Ansible:
    - `roles/compute.admin`
    - `roles/iam.serviceAccountUser`
    - `roles/compute.networkAdmin`
    - `roles/compute.securityAdmin`
  - For VM runtime service account (node-level), keep minimal and avoid broad cloud-platform usage where possible.

## 4) Variables Checklist

Core variables already modeled in `inventories/prod/group_vars/all.yml`:
- `gcp_project_id`
- `gcp_region`
- `gcp_zone`
- `gcp_credentials_file`
- `gcp_network_name`
- `gcp_subnet_name`
- `gcp_subnet_cidr`
- `gcp_cluster_tags`
- `gcp_machine_type`
- `gcp_disk_size_gb`
- `gcp_image_family`
- `gcp_image_project`
- `gcp_ssh_user`
- `gcp_ssh_public_key_file`
- `gcp_instance_sa_name`
- `gcp_rancher_address_name`
- `rancher_fqdn`
- `rke2_version`
- `kubeconfig_path`
- `ingress_nginx_chart_version`
- `cert_manager_chart_version`
- `rancher_chart_version`
- `letsencrypt_server`
- `letsencrypt_email`
- `admin_cidrs`

Sensitive variables in Vault (`inventories/prod/group_vars/all/vault.yml`):
- `vault_rke2_token`
- `vault_rancher_bootstrap_password`
- optionally `vault_gcp_service_account_json`

## 5) Step-by-Step Runbook (local machine)

```bash
# 0) Prerequisites
python3 -m venv .venv
source .venv/bin/activate
pip install ansible google-auth requests
ansible-galaxy collection install -r requirements.yml

# 1) Configure variables
cp inventories/prod/group_vars/all/vault.yml.example inventories/prod/group_vars/all/vault.yml
ansible-vault encrypt inventories/prod/group_vars/all/vault.yml
vi inventories/prod/group_vars/all.yml

# 2) Authenticate for GCP API (service account json)
export GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/ansible-sa.json

# 3) Provision GCP infra + generate inventory
ansible-playbook playbooks/01_provision_gcp.yml

# 4) Use generated inventory for remaining plays
ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/02_bootstrap_os.yml
ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/03_install_rke2.yml
ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/04_install_ingress.yml
ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/05_install_cert_manager.yml
ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/06_install_rancher.yml
ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/07_postchecks.yml

# (Optional) one-shot
ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/site.yml
```

DNS step:
- Point `A` record of `rancher_fqdn` to the reserved static IP (`gcp_rancher_address_name`).

## 6) Validation Steps

```bash
# Cluster health
kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide
kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -A

# Ingress external endpoint
kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n ingress-nginx get svc ingress-nginx-controller

# Cert-manager and certificate
kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n cert-manager get pods
kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n cattle-system get certificate,secret

# Rancher rollout and URL
kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n cattle-system rollout status deploy/rancher
curl -Ik https://rancher.example.com
```

Success criteria:
- 5/5 nodes in `Ready`.
- `ingress-nginx-controller` has external IP/hostname.
- `rancher-tls` certificate is `Ready=True`.
- `https://<rancher_fqdn>` returns `200/302` with valid TLS chain.

## 7) Troubleshooting Guide

1. **RKE2 server join fails (`9345` unreachable)**
   - Confirm firewall allows control-plane traffic only from admin/private ranges.
   - Validate private IP route and `server:` URL in `/etc/rancher/rke2/config.yaml`.

2. **Nodes not Ready / CNI issues**
   - Check `journalctl -u rke2-server -f` and `journalctl -u rke2-agent -f`.
   - Verify kernel modules/sysctl from `common` role applied.

3. **Ingress has no external IP**
   - `kubectl -n ingress-nginx describe svc ingress-nginx-controller`.
   - Verify GCP quotas and subnet capacity.

4. **Certificate stuck in Pending**
   - Ensure DNS A record points to ingress external IP.
   - Check `kubectl describe challenge -A` and cert-manager logs.

5. **Rancher pods CrashLoopBackOff**
   - Validate TLS secret (`tls-rancher-ingress`) exists in `cattle-system`.
   - Inspect Helm values and chart compatibility with Kubernetes version.

6. **Ansible auth/API failures**
   - Validate `gcp_credentials_file` path and service account IAM bindings.
   - Run with `-vvv` and inspect GCP permission denied details.
