# Moltbot (OpenClaw)

Personal AI assistant gateway with Azure OpenAI integration via LiteLLM.

## Vault Setup (Required)

Before deploying, create the Vault secret:

```bash
vault kv put secret/infrastructure/moltbot \
  gateway_token="$(openssl rand -hex 32)" \
  discord_bot_token="" \
  slack_bot_token="" \
  slack_app_token=""
```

## Discord Integration

1. Create Discord application at https://discord.com/developers/applications
2. Go to "Bot" section, click "Add Bot"
3. Enable "Message Content Intent" under Privileged Gateway Intents
4. Copy bot token
5. Store in Vault:
   ```bash
   vault kv patch secret/infrastructure/moltbot \
     discord_bot_token="<your-bot-token>"
   ```
6. Generate invite URL with permissions: Send Messages, Read Message History, Use Slash Commands
7. Invite bot to your Discord server
8. Restart Moltbot deployment:
   ```bash
   kubectl -n moltbot rollout restart deploy/moltbot
   ```

## Verification

```bash
# Check deployment
kubectl -n moltbot get pods

# View logs
kubectl -n moltbot logs deploy/moltbot

# Check external secrets
kubectl -n moltbot get externalsecrets
```

## Access

Gateway UI: https://moltbot.lionfish-caiman.ts.net (Tailscale only)
