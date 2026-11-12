
# Secrets management

This document (inspired by [copilot-client](https://github.com/github/copilot-client/blob/main/secrets-management.md)) covers secrets management across the Coding Agent/Coding Agent Runtime owned codebases:
- sweagentd (this repo)
- [copilot-agent-runtime](https://github.com/github/copilot-agent-runtime/)

In general we aim to follow the guidance [here](https://thehub.github.com/security/security-operations/secrets/storing-secrets/).

## Federating Secrets

The **best practice** to federate secrets is to use `github/federate-secrets` to distribute your secrets into repos/environments/etc. To do so, there is a 2 step process, outlined below:

### Step 1. Putting your secrets into vault ci for sweagentd

In order for secrets to be federated using `github/federate-secrets`, they must be added into vault ci for sweagentd. To do so, you can follow this [guide](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/):

Example usage:

```
vault-secret --application sweagentd --key <KEY_NAME> --environment ci --prompt
```

You will need to enter your secret value and then re-enter to confirm.

### Step 2. Editing the `federation.yaml` file to federate your secrets.

Visit this [file](https://github.com/github/secrets-federation/blob/93a1dc851b25423f82d10d234e0331aa57d994fa/config/federation/sweagentd/ci/federation.yaml). Each secret can be federated to one or more targets, using the to: array. Supported target types include:

- Vault Apps:
    - Use `backend: vault` with `app`, `environment`, and `key` fields to federate secrets to other Vault-backed applications and environments.

- GitHub Repository Secrets:
    - Use `backend: repo` with `repo`, `type`, and (optionally) `environment` fields to federate secrets to GitHub repository secrets.
        - `type: actions` for GitHub Actions secrets
        - `type: dependabot` for Dependabot secrets
        - `type: codespaces` for Codespaces secrets
        - `type: environment` for Actions environment secrets (requires environment field)
You can federate the same secret to multiple destinations by listing multiple entries under `to:`.

Once your PR is merged, the secrets will be automatically federated to your desired configuration!