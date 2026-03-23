#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
ANSIBLE_DIR="$SCRIPT_DIR/../ansible"

chmod +x "${BASH_SOURCE[0]}"


echo "REading IPs from Terraform Cloud State..."

cd "$TF_DIR"

CTRL=$(terraform output -raw control_plane_ip)
W1=$(terraform output -json worker_ips | python3 -c "import json,sys; print(json.load(sys.stdin)[0])")
W2=$(terraform output -json worker_ips | python3 -c "import json,sys; print(json.load(sys.stdin)[1])")

#Private IP (workers will use this to join the cluster; using the public IP for k3s_url was failing because SG allows 6443 from VPC CIDR only.)
CTRL_PRIVATE=$(terraform output -raw control_plane_private_ip)


echo "Control Plane Public IP: $CTRL"
echo "Control Plane Private IP: $CTRL_PRIVATE"
echo "Worker 1: $W1"
echo "Worker 2: $W2"

echo "Scanning host keys (safe first-connect verification)..."

for IP in "$CTRL" "$W1" "$W2"; do
    ssh-keygen -R "$IP" 2>/dev/null || true

    ssh-keyscan -H -T 10 "$IP" >> ~/.ssh/known_hosts 2>/dev/null
    echo "✓ Scanned $IP"
done

cat > "$ANSIBLE_DIR/inventory.ini" << EOF
[control_plane]
${CTRL} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k3s_ed25519 k3s_private_ip=${CTRL_PRIVATE}

[workers]
${W1} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k3s_ed25519
${W2} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k3s_ed25519
EOF

echo "Inventory written to $ANSIBLE_DIR/inventory.ini"

echo "Testing connectivity..."
ansible all -i "$ANSIBLE_DIR/inventory.ini" -m ping