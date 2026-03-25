#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Step 1: Applying Terraform ==="
cd terraform/
terraform apply -auto-approve

echo "=== Step 2: Waiting 60s for EC2 instances to boot ==="
sleep 60

echo "=== Step 3: Generating Ansible inventory ==="
cd ..
./scripts/generate-inventory.sh

echo "=== Step 4: Running Ansible playbook (5-8 min) ==="
cd ansible/
ansible-playbook -i inventory.ini playbook.yml

echo "=== Step 5: Configuring kubectl ==="
cd ../terraform/
CTRL=$(terraform output -raw control_plane_ip)

# scp kubeconfig directly from node (not /tmp/k3s.yaml which requires full playbook)
scp -i ~/.ssh/k3s_ed25519 ubuntu@${CTRL}:/etc/rancher/k3s/k3s.yaml /tmp/k3s.yaml
mkdir -p ~/.kube
cp /tmp/k3s.yaml ~/.kube/config

# Detect if ISP blocks port 6443 — use tunnel method if blocked
nc -zv "$CTRL" 6443 -w 3 &>/dev/null && \
  sed -i "s|server: https://127.0.0.1:6443|server: https://${CTRL}:6443|g" ~/.kube/config || \
  sed -i "s|server: https://127.0.0.1:6443|server: https://localhost:6443|g" ~/.kube/config
chmod 600 ~/.kube/config

# Update k3s-tunnel alias with new public IP (IPs change after every reprovision)
if grep -q 'k3s-tunnel' ~/.zshrc; then
  sed -i "s|ubuntu@[0-9.]*|ubuntu@${CTRL}|g" ~/.zshrc
  source ~/.zshrc
  echo "  k3s-tunnel alias updated to: $CTRL"
fi

echo "=== Step 6: Update DuckDNS with new IP ==="
echo "  New control plane IP: $CTRL"
echo "  Run: curl -s \"https://www.duckdns.org/update?domains=YOUR_SUBDOMAIN&token=YOUR_TOKEN&ip=${CTRL}\""
echo "  Or update manually at https://www.duckdns.org"

echo "=== Step 7: Start tunnel and verify cluster ==="
# ISP blocks outbound port 6443 — use SSH tunnel
k3s-tunnel 2>/dev/null || ssh -i ~/.ssh/k3s_ed25519 -L 6443:localhost:6443 ubuntu@${CTRL} -N -f
sleep 3
kubectl get nodes -o wide

echo "=== Step 8: Reinstall Helm charts (in order) ==="
cd ..

# 8.0 — Global nginx security headers (do ONCE after nginx install)
kubectl apply -f - << 'HEADERS'
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-headers
  namespace: ingress-nginx
data:
  Strict-Transport-Security: "max-age=31536000; includeSubDomains"
  X-Content-Type-Options: "nosniff"
  X-Frame-Options: "DENY"
  X-XSS-Protection: "1; mode=block"
  Referrer-Policy: "strict-origin-when-cross-origin"
HEADERS
kubectl patch configmap ingress-nginx-controller -n ingress-nginx \
  --patch '"'"'{"data":{"add-headers":"ingress-nginx/custom-headers"}}'"'"'

# 8.1 — Nginx ingress + cert-manager
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.hostNetwork=true \
  --set controller.kind=DaemonSet \
  --set controller.daemonset.useHostPort=true \
  --set controller.config.use-forwarded-headers="true" \
  --set controller.config.proxy-body-size="50m"

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s

kubectl apply -f - << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# 8.2 — ollama / vLLM chart
kubectl create namespace llm-serving 2>/dev/null || true
kubectl label namespace llm-serving  kubernetes.io/metadata.name=llm-serving  --overwrite
kubectl label namespace ingress-nginx kubernetes.io/metadata.name=ingress-nginx --overwrite
kubectl label namespace cert-manager  kubernetes.io/metadata.name=cert-manager  --overwrite
kubectl create serviceaccount vllm-sa -n llm-serving 2>/dev/null || true

kubectl delete validatingwebhookconfiguration ingress-nginx-admission 2>/dev/null || true

helm upgrade --install vllm charts/vllm/ \
  --namespace llm-serving \
  --set prometheusRule.enabled=false \
  --set networkPolicy.enabled=false \
  --wait --timeout 30m

# 8.3 — ArgoCD
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "$ARGOCD_PASS" > .argocd-password && chmod 600 .argocd-password
kubectl apply -f argocd/application.yaml

# 8.4 — Observability (Prometheus + Grafana + Jaeger)
GRAFANA_PASS=$(cat .grafana-password 2>/dev/null || openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)
echo "$GRAFANA_PASS" > .grafana-password && chmod 600 .grafana-password
kubectl create namespace monitoring 2>/dev/null || true
kubectl label namespace monitoring kubernetes.io/metadata.name=monitoring --overwrite
kubectl create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_PASS" \
  -n monitoring 2>/dev/null || true

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.admin.existingSecret=grafana-admin-credentials \
  --set grafana.admin.userKey=admin-user \
  --set grafana.admin.passwordKey=admin-password

helm upgrade --install jaeger jaegertracing/jaeger \
  --namespace monitoring \
  --set allInOne.enabled=true \
  --set storage.type=memory \
  --set collector.enabled=false \
  --set query.enabled=false \
  --set agent.enabled=false \
  --set allInOne.resources.requests.memory=256Mi \
  --set allInOne.resources.limits.memory=512Mi

# 8.5 — Vault
kubectl create namespace vault 2>/dev/null || true
kubectl label namespace vault kubernetes.io/metadata.name=vault --overwrite
KMS_KEY_ID=$(cd terraform/ && terraform output -raw vault_kms_key_id)
AWS_REGION="us-east-1"
cat > vault-values.yaml << VEOF
server:
  dev:
    enabled: false
  ha:
    enabled: false
  dataStorage:
    enabled: true
    size: 1Gi
    storageClass: local-path
  seal:
    type: awskms
    config:
      region: "${AWS_REGION}"
      kms_key_id: "${KMS_KEY_ID}"
  affinity: ""
injector:
  enabled: true
VEOF

helm install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --values vault-values.yaml

echo "  Waiting for vault pod..."
sleep 30
kubectl get pods -n vault

echo ""
echo "=== Step 9: Initialize and unseal Vault ==="
echo "  If this is a fresh cluster (vault-init.json does not exist):"
echo "  kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3 -format=json > vault-init.json"
echo "  chmod 600 vault-init.json"
echo ""
echo "  Then unseal with 3 keys:"
echo "  for i in 0 1 2; do"
echo "    KEY=\$(cat vault-init.json | python3 -c "import json,sys; print(json.load(sys.stdin)['unseal_keys_b64'][\$i])")"
echo "    kubectl exec -n vault vault-0 -- vault operator unseal "\$KEY""
echo "  done"
echo ""
echo "  If vault-init.json already exists (reprovisioning):"
echo "  KMS auto-unseal should handle it automatically — check: kubectl exec -n vault vault-0 -- vault status"
echo ""
echo "=== Step 10: Configure Vault ==="
echo "  export HF_TOKEN="hf_your_token_here""
echo "  ./scripts/configure-vault.sh"
echo ""
echo "=== Reprovision complete ==="
kubectl get nodes -o wide
kubectl get pods -n llm-serving
kubectl get pods -n argocd
kubectl get pods -n monitoring
kubectl get pods -n vault