# Security

Homeport has no backend, no accounts and no telemetry. The only secrets are the ones the skill generates for *your* installation (`params.json`, the WireGuard keys, the REALITY private key), and they live on your machine and your server.

**Never commit `params.json` or the `out/` directory** — they are in `.gitignore` for that reason. If you paste a hosting API token into a chat, revoke it when the setup is done; the skill reminds you to.

## Reporting a vulnerability

Report vulnerabilities in the skill, the scripts or the installers privately: open the **Security** tab of this repository and choose **Report a vulnerability** ([direct link](https://github.com/antongavrilov88/homeport-skill/security/advisories/new)). The report stays between you and the maintainer until an advisory is published. Don't open a public issue for it.

Bugs that aren't sensitive go to [issues](https://github.com/antongavrilov88/homeport-skill/issues). Never paste `params.json`, tokens, keys or server addresses into an issue.

Vulnerabilities in the website (the landing page) are reported in the [site repository](https://github.com/antongavrilov88/homeport/security/advisories/new).
