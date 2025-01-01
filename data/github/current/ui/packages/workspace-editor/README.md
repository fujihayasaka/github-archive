# Workspace Editor

Hadron development setup guide: https://github-grid.enterprise.slack.com/canvas/C076XHZ7U59?focus_section_id=temp:C:WHH66f03fe9f2f549dab521cb760

## Upgrading `@github/codespaces-*` packages

The `@github` scope for NPM packages is in a weird state where it exists both on the public NPM feed and the private GitHub feed. Unfortunately for us, all of the Codespaces-related packages are on the private feed. If we try to upgrade, for example, the `@github/codespaces-lsp` package from version `2.0.19` to `2.0.20`, we will get a `'@github/codespaces-lsp@2.0.20' is not in this registry.` This is because the [`.npmrc`](../../../.npmrc) file is configured to use the public registry. To resolve this, you will need to do the following:
1. Generate a GitHub token with `write:packages` permissions and enable SSO for the `github` organization.
2. Add the following to the [`.npmrc`](../../../.npmrc) file:
```npmrc
@github:registry=https://npm.pkg.github.com/
//npm.pkg.github.com/:_authToken=<your token here>
always-auth=true
```
3. Run `npm i` from `/workspaces/github`
4. Remove the added lines to the [`.npmrc`](../../../.npmrc) file
