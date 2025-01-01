# Development Docker image

This directory [specifies a Docker image](Dockerfile) in which all
development tasks can be done. This is then used in two ways:

1. On the command line. The [`dev-run` script](../script/dev-run)
   provides a single regular point of entry that can be used locally
   or during CI to run any command in the repository checkout. For
   example: `./script/dev-run make protoc`.

2. As a [VSCode development
   container](https://code.visualstudio.com/docs/remote/containers).
   This can be used to launch a shell inside the Docker container and
   run any desired commands from there.

## Testing codespace changes

If you'd like to test some changes you've made to the Codespace e.g. changes to the Dockerfile, you can do the following:

- Make your code changes and publish them on a branch called `codespace-prebuild-test`.
- [Monitor action that is automatically triggered here](https://github.com/github/turboscan/actions/workflows/dynamic/codespaces/create_codespaces_prebuilds?query=branch%3Acodespace-prebuild-test).

You can see Codespace prebuild settings at https://github.com/github/turboscan/settings/codespaces.

If you would like to point your codespace-compose to one of these builds, update the `branch` property in the turboscan codespace in `codespace-compose.yml` from `main` to `codespace-prebuild-test` and create a new codespace.

Note that you can use a different branch if you want, you just need to make sure to set up a prebuild on https://github.com/github/turboscan/settings/codespaces. Please clean up after you're done!
