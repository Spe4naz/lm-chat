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

## Updates

Auto-update uses the public GitHub Releases API for `Spe4naz/lm-chat`. The app
accepts only an allowlisted asset name and an HTTPS `github.com` URL, caps the
download at 400 MB, applies an overall deadline, verifies the SHA-256 digest
from the GitHub API, and deletes a partial file on failure.

Android releases must be signed with the same key as the installed app. The app
compares the signing certificate of the downloaded APK with the installed one
before opening the system installer, and release builds fail unless
`android/key.properties` is configured. The Windows installer is verified with
Authenticode before it runs; an unsigned installer is rejected.

## Cleartext HTTP

Android's network security config cannot express "cleartext only for RFC1918
addresses", and the app must reach arbitrary LAN IPs over HTTP. The manifest
therefore keeps cleartext enabled, while every network call validates the host
in `lib/models.dart`: public HTTP endpoints are rejected and only HTTPS is
allowed outside the local network. API keys and bridge tokens are never sent to
a public cleartext host.

## CI checks

Every push runs gitleaks, CodeQL (Python), an OSV dependency scan and an SBOM
job (SPDX). Pull requests also run dependency review with a high-severity
threshold. Results are uploaded to the repository's **Security → Code scanning**
tab where the integration supports SARIF.

## Local network

The app, bridge and plugin are intended for a trusted LAN. If you expose ports
`1234`, `1235`, `1236` or `1237` outside the LAN, put them behind a VPN or an
authenticated reverse proxy. The plugin intentionally requires a bearer token
for `/api` and `/mcp`.
