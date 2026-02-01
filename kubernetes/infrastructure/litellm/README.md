# LiteLLM Proxy

OpenAI-compatible proxy for Azure OpenAI.

## Vault Setup (Required)

Before deploying, create the Vault secret:

```bash
vault kv put secret/infrastructure/azure-openai \
  api_key="<your-azure-openai-key>" \
  endpoint="https://<resource>.openai.azure.com" \
  api_version="2024-02-15-preview" \
  deployment_name="gpt-4" \
  litellm_master_key="$(openssl rand -hex 32)"
```

## Verification

```bash
# Check deployment
kubectl -n litellm get pods

# Health check
kubectl -n litellm exec deploy/litellm -- curl -s localhost:4000/health

# Test API
kubectl -n litellm exec deploy/litellm -- curl -s \
  -H "Authorization: Bearer $LITELLM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"hello"}]}' \
  localhost:4000/v1/chat/completions
```

## Access

Internal service: `http://litellm.litellm.svc.cluster.local:4000`
