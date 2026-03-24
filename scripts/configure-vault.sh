#!/bin/bash

set -euo pipefail

ROOT_TOKEN=$(cat .vault-root-token)

if lsof -i :8200 > /dev/null 2>&1; then
    echo "Port 8200 in use. Free it first: lsof -ti :8200 | xargs kill"
    exit
fi

kubectl port-forward svc/vault -n vault 8200:8200 &
PF_PID=$!
sleep 3

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="$ROOT_TOKEN"

K8S_HOST="https://kubernetes.default.svc"

# Get CA cert from vault pod's mounted service account (in-cluster CA)
KUBE_CA_CERT=$(kubectl exec -n vault vault-0 -- \\
  cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)

kubectl create serviceaccount vault-auth -n vault 2>/dev/null || true

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-token-reviewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: vault
EOF

SA_JWT=$(kubectl create token vault-auth -n vault --duration=8670h)

vault auth enable kubernetes 2>/dev/null || true

vault write auth/kubernetes/config token_reviewer_jwt="$SA_JWT" kubernetes_host="$K8S_HOST" kubernetes_ca_cert="$KUBE_CA_CERT"

echo "Enter HuggingFace Token (from huggingface.co/settings/tokens:)"
read -s HF_TOKEN
vault secrets enable -path=secret kv-v2 2>/dev/null || true
vault kv put secret/llm/credentials hf_token="$HF_TOKEN"


vault policy write vllm-policy - <<'EOF'
path "secret/data/llm/*" {
  capabilities = ["read"]
}

path "secret/metadata/llm/*" {
  capabilities = ["list"]
}
EOF

# Role: binds vllm-sa service account in llm-serving namespace
vault write auth/kubernetes/role/vllm \
  bound_service_account_names=vllm-sa \
  bound_service_account_namespaces=llm-serving \
  policies=vllm-policy \
  ttl=1h \
  max_ttl=24h

echo "Vault configured successfully"

# Clean up port-forward
kill $PF_PID 2>/dev/null || true