# Security

Homeport has no backend, no accounts and no telemetry. The only secrets are the ones the skill generates for *your* installation (`params.json`, the WireGuard keys, the REALITY private key), and they live on your machine and your server.

**Never commit `params.json` or the `out/` directory** — they are in `.gitignore` for that reason. If you paste a hosting API token into a chat, revoke it when the setup is done; the skill reminds you to.

To report a vulnerability in the scripts or installers, open a GitHub issue with the label `security`, or message [@bepatientlikeme](https://t.me/bepatientlikeme) if it shouldn't be public yet.
