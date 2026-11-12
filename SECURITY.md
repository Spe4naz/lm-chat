# Security policy

LM Chat is a local-network client for LM Studio. It is not designed to be
exposed directly to the internet.

The companion LM Studio plugin is
[lm-computer](https://github.com/Spe4naz/lm-computer).

## Reporting a vulnerability

Please use GitHub's **Security advisories** for this repository. Do not open a
public issue with working credentials, private keys or a reproducible exploit
against someone else's machine.

## Secrets in this repository

The source tree must never contain live credentials:

- LM Studio API keys and bridge tokens are entered by the user and stored in the
  platform keystore (`flutter_secure_storage`), never in `lm_chat_data.json`.
- The `lm-computer` plugin generates its own token at first launch and stores it
  in `~/.config/lm-computer/token.txt` with mode `0600`.
- The `lms-gpu-bridge` service reads `BRIDGE_TOKEN` and `LMS_API_KEY` from
  `/etc/lm-gpu-bridge.env` (mode `0600`); the systemd unit contains no token.
- Test fixtures such as `test-token` and `secret-token` are not real
  credentials and are limited to `test/`.
- Build outputs (`dist/`, `build/`, plugin zips, keystores) are ignored by
  `.gitignore` and must not be committed.

If a real token was committed or shared, rotate it first, then remove it from
the repository history. Removing the file alone is not enough.

## Local network

The app, bridge and plugin are intended for a trusted LAN. If you expose ports
`1234`, `1235` or `1236` outside the LAN, put them behind a VPN or an
authenticated reverse proxy. The plugin intentionally requires a bearer token
for `/api` and `/mcp`.
