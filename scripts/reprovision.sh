#!/bin/bash

set -euo pipefail

SCRIPT_DIR = "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Applying Terraform ===="
cd terraform/
terraform apply -auto-approve

echo "=== Waiting for EC2 to boot ===="
sleep 100

echo "=== Generating Ansible Inventory ==="
cd ..
./scripts/generate-inventory.ssh

echo "=== Running Ansible Playbook ==="
cd ansible/
ansible-playbook -i inventory.ini playbook.yml

echo "=== Configuring kubectl ===="
cd ../terraform/
CTRL=$(terraform output -raw control_plane_ip)
cp /tmp/k3s.yml ~/.kube/config
sed -i "s|server: https://127.0.0.1:6443|server: https://${CTRL}:6443|g" ~/.kube/config
chmod 600 ~/.kube/config

echo ""
echo "=== Cluster ready. Do the follow next "
echo "1. Update DuckDNS IP to $CTRL"
echo "2. Reinstall HEML charts in the following order:"
echo "      helm upgrade --install ingress-nginx ..."
echo "      helm upgrade --install cert-manager ..."
echo "      helm upgrade --install vllm charts/vllm/ ..."
echo "      kubectl apply -f argocd/ ..."
echo "      helm upgrade --install kube-prometheus-stack ..."
echo "      helm install vault ..."

kubectl get nodes -o wide