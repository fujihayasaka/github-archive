# Debugging

## Table of Contents

- [Details](#details)
  - [Debugging with tests](#debugging-with-tests)
- [References](#references)

## Details

### General Debugging

1. Start billing-platform in debug mode:
    ```
    ./script/server -d
    ```

2. Once started, you can use the VSCode `Run and Debug` dropdown to select one of the "Attach..." options to attach a debugger to one or multiple of the billing-platform services running in Docker containers.

3. Set breakpoints & debug.

This can be used both when debugging in a standalone billing-platform codespace or when [running billing-platform in a Dotcom codespace](../../tutorials/run-billing-platform-in-dotcom-codespaces.md).

> [!NOTE]
> This debugging method uses [Delve servers](https://github.com/go-delve/delve/blob/master/Documentation/faq.md#-how-do-i-use-delve-with-docker) to allow VSCode to attach to and debug the applications running inside each Docker container. There is a quirk with this approach in that VSCode informs the Delve server of when breakpoints are set/removed but when the VSCode debugger disconnects from the server it does not clean up its breakpoints and the server may still trip them and get stuck even when you are not debugging. To avoid this, disable breakpoints in VSCode before disconnecting if you need to disconnect/reconnect for any reason. If the service does get stuck, simply restarting its docker container will clear all the breakpoints (i.e. `docker restart <container_name>`).

### Debugging with tests

When debugging issues in billing platform, one of the first things you can try is writing an integration test case for the scenario if one doesn't already exist. You can then follow [the docs](https://github.com/github/billing-platform/blob/main/docs/reference/project/testing.md#using-the-debugger) on using the VSCode debugger with the integration tests to help you understand the issue. If a test case already exists and it's passing when you would expect it to be failing, it can be helpful to check the stubs and make sure they are accurately mocking the scenario.

## References

- [Playbooks for responding to billing platform alerts in the gitcoin repo](https://github.com/github/gitcoin/tree/main/docs/playbook/alerts/billing-platform)
