## Local Development without a Codespace

Developing in a codespace is the recommended way to develop this service, because it requires no setup.

However, if you strongly prefer to develop locally, you can follow these steps:

1. Install dependencies:
    * Follow Codespace [Dockerfile](../.devcontainer/Dockerfile)
    * Follow `features` section in [devcontainer.json](../.devcontainer/devcontainer.json)

2. Setup [goproxy](https://github.com/github/goproxy/blob/main/doc/user.md#set-up)

3. Authenticate with docker registry

    ```console
    docker login ghcr.io -u <username>
    ```

    **NOTE: You must use a personal access token (PAT) for your password with SSO access to GitHub organization resources.**

3. Clone this repository

4. Bootstrap

    ```console
    script/bootstrap
    ```
5. Set `$GITHUB_USER` environment variable to make sure that the service will create a separate set of resources for your development environment (see [Azure Resources Layout - Development environment](./azure-resources-layout.md#development-environment) for more details)

    ```console
    export GITHUB_USER=maxim-lobanov
    ```

5. Start the server

    ```console
    script/server
    ```
