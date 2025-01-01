# Sensitive Data in Attester

This document lists attributes sent to failbot that are considered sensitive. These fields are scrubbed of their sensitive components prior to being logged or sent to Sentry.

## Sensitive Data that should be scrubbed from exception reports


* Repository names
* Release Assets
* GitHub handles (PII)
* Environment variables stored in Vault (see `.env.example` for a list of environment variables)