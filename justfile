set shell := ["bash", "-cu"]

default:
  @just --list

# Show available tasks
list:
  @just --list

# Install Ansible collections used by this project
install-collections:
  ansible-galaxy collection install -r requirements.yml

# Create local Python virtualenv and install baseline dependencies
venv:
  python3 -m venv .venv
  source .venv/bin/activate
  pip install --upgrade pip
  pip install ansible google-auth requests

# Copy and encrypt vault example if needed
init-vault:
  test -f inventories/prod/group_vars/all/vault.yml || cp inventories/prod/group_vars/all/vault.yml.example inventories/prod/group_vars/all/vault.yml
  ansible-vault encrypt inventories/prod/group_vars/all/vault.yml

# Provision GCP network and instances
provision:
  ansible-playbook playbooks/01_provision_gcp.yml

# Bootstrap VM OS prerequisites
bootstrap:
  ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/02_bootstrap_os.yml

# Install RKE2 control-plane and workers
k8s:
  ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/03_install_rke2.yml

# Install ingress-nginx
ingress:
  ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/04_install_ingress.yml

# Install cert-manager + ClusterIssuer
certs:
  ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/05_install_cert_manager.yml

# Install Rancher
rancher:
  ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/06_install_rancher.yml

# Run post-deployment checks
postchecks:
  ansible-playbook -i inventories/prod/hosts.generated.yml playbooks/07_postchecks.yml

# Run the full sequence after provisioning
deploy: bootstrap k8s ingress certs rancher postchecks

# Provision and deploy end-to-end
all: provision deploy
