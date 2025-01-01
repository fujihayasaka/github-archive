# Development

## Dev environments

There are two dev environments for IMS:
- IMS Codespace
    - Use this environment if you don't depend on other services (dotcom, Runner, etc)
    - It is light-weight codespace which deploys IMS and its direct dependencies (MySQL, Aqueduct, Redis, etc)
    - IMS lives in `/workspaces/hosted-compute-ims` in IMS codespace.
- gh/gh codespace
    - Use this environment if you need to develop a feature which requires integration or testing IMS with dotcom and Runner service.
    - IMS is deployed as a part of larger-runners scenario in gh/gh codespace.
    - IMS lives in `/workspaces/actions/hosted-compute-ims` in gh/gh codespace.
    - By default, IMS is not integrated with Runner service. Check [Testing with Runner](#testing-with-runner) section to see how to enable integration.

In both environments, IMS is deployed to minikube and works identically.

## Running IMS application

This command deployes IMS and all its dependencies to Minikube:
```console
script/server
```

`script/server` supports two additional modes:
- `script/server --dev` - Runs IMS application in development mode. When dev mode enabled, Skaffold monitors source code changes and automatically rebuild / redeploy application on any change.
- `script/server --debug` - Runs IMS application in debug mode. When debug mode enabled, Skaffold forwards ports for debugging and you can use `Attach twirp` and `Attach worker` VSCode debug targets to connect debugger.

## Viewing logs

Use kubernetes extension in VSCode to view the live logs of IMS application and its dependencies:

<img width="565" alt="image" src="https://github.com/user-attachments/assets/a175bfc0-ba1f-42ba-8270-914666f96f92">

Alternatively, you can use `script/helpers/kube-save-logs` script which will grab logs from all minikube pods and save under `logs` directory.

## Cron jobs

Cronjobs are suspend in development environment by default. You can use `script/start-cronjob <job_name>` to trigger a specific job.  
For example, `script/start-cronjob replication`. Logs of job execution can be in `logs` directory.

## Making calls to IMS API

### Using twirpcurl to make API calls

`script/twirpcurl` is a wrapper around curl which simplifies making requests to the twirp API.

Example of testing flow using `script/twirpcurl`:
```bash
# validating that service is available
script/twirpcurl ping
# creating image definition
echo '{ "name": "myImage3", "os_type": "Linux", "architecture": "X64" }' | script/twirpcurl admin CreateCuratedImageDefinition
# validating image definition
echo '{ "image_definition_id": 3 }' | script/twirpcurl images GetCuratedImageDefinition
# provision image version
echo '{ "image_definition_id": 3, "version": "1.0.0", "source_vhd_url": "http://myvhdurl" }' | script/twirpcurl admin CreateCuratedImageVersion
# monitor image version provision status
echo '{ "image_definition_id": 3, "version": "1.0.0" }' | script/twirpcurl images GetCuratedImageVersion
# get image reference
echo '{ "image_key": { "source": "Curated", "id": 1, "version": "1.0.0" } }' | script/twirpcurl internal GetImageDetails
```

See [Twirp Queries](/docs/twirp-queries.md) for more examples.

### Using dev-client to validate basic scenarios

Also, there is a dev-client which simplies running base dev scenarios:
```console
$ script/dev-client --help
Usage: script/dev-client [--scenario] [--image] [--only-build]
    --only-build                    Only build the dev-client without running it
    --scenario                      The scenario to run. Default: health
    --image                         The image to use for the scenario. Default: "centos"

    Available scenarios:
    - health                       Check that API is up and running
    - curated                      Create a new curated image definition, new curated image version and start image version uploading
    - customer                     Create a new customer image definition, new customer image version and start image version uploading
    - custom                       Run custom dev scenario. It is empty by default and can be implemented by developer in tools/dev-client/custom.go

    Available images: centos, ubuntu, windows, etc
    Run the following command to get actual list of available images:
        az storage blob list --account-name hostedcomputeimsimages --container-name images --output table

Examples:
    script/dev-client health
    script/dev-client curated
    script/dev-client customer
    script/dev-client custom
    script/dev-client curated --image windows
    script/dev-client customer --image ubuntu
```

## Database

See [Database - Local Development](/docs/database.md#development-environment) for more details.

## Feature flags

See [Feature flags in local environment](./feature-flags.md#feature-flags-in-local-environment) for more details.

## Mock files

IMS uses [go.uber.org/mock](https://https://pkg.go.dev/go.uber.org/mock@v0.4.0) for working with mocks.
All generated mock files are located under `gen/mocks` folder.

To regenerate all mock files, run the following command:
```console
make generate
```

If you need to generate mocks for new interface, add go-generate statement to file with interface and run `make generate`.  
Example of go-generate statement: https://github.com/github/hosted-compute-ims/blob/3cc63778c5f72c64ee878e758fd6df95b711c7e7/internal/azure/azure.go#L24

### Protobufs

Protobuf definitions are located in `proto/service`.

Generated protobuf files are located under `gen/twirp`

To regenerate protobuf files, run the following command:
```console
script/buf
```

## Unit tests 

Run all tests:
```console
script/test
```

Unit tests can be debugged using integrated VSCode functionality:
<img width="712" alt="image" src="https://github.com/github/hosted-compute-ims/assets/16715858/14d028c3-8961-48e8-95e5-379bae18b85f">

## E2E tests

General suggestions for E2E implementation:
1. For long-running E2E test scenarios, consider creating TestSuite for every test. go-test runs test suites in parallel but tests within test suite are run in order.
2. E2E test suite should inherit from [BaseE2ETestSuite](../internal/e2e/base_e2e_test.go). This way all resources will be configured automatically.
3. Since tests can be run in parallel, we need to ensure that test doesn't access resources created by another test. There is `BaseE2ETestSuite.uniquePrefix`. It is a prefix which will be unique for every test suite. We recommend adding this prefix in the following cases:
    - curated image definition name: `imageDefName = fmt.Sprintf("%s-curated-def-1", s.uniquePrefix)`. Later, you can use `BaseE2ETestSuite.filterTestCuratedImageDefinitions` to get image definitions which belong to your test suite.
    - ownerId: `testOwner1 = fmt.Sprintf("%s_U1", s.uniquePrefix)`
3. Image version provision:
    - If you need to create an image version during E2E test, consider using `BaseE2ETestSuite.sourceVhdUrlForQuickFail` to speed up test running. The real provision of image version takes 5-10 minutes. The most of use-cases don't really require image version to be in "Ready" state. Using `BaseE2ETestSuite.sourceVhdUrlForQuickFail` will cause provision process to fail within a couple of seconds and image version will have `ProvisionFailed`. It might be enough for your use-case.
    - Use `BaseE2ETestSuite.waitForAdminImageVersionProvisionFailed` and `BaseE2ETestSuite.waitForAdminImageVersionDeletion` helper methods if necessary.

### Running E2E tests

IMS has 3 modes for running E2E tests:
- `script/test-e2e --short` -> This mode runs all E2E tests except long-running image uploading test suites
    - Execution of E2E tests in short mode takes 2-3 minutes
    - E2E tests in short mode are run in PR CI after all other checks. These tests use a local instance of IMS deployed in docker (similar to running tests locally)
- `script/test-e2e --full` -> This mode runs all E2E tests including image uploading test suites.
    - Execution of E2E tests in full mode takes ~25 minutes
    -  E2E tests in full mode are run during PR deployment after deployment changes to Lab environment. These tests are run against real [Lab environment](./infrastructure/environments.md#lab)
- `script/test-e2e --suite AuthE2ETestSuite` -> This mode runs the single test suite with e2e tests.

See `script/test-e2e --help` for more details on parameters.

### Debugging e2e tests

There are two types of debugging e2e-tests:
- Debug of application (`twirp` or `worker`)
    - Run `script/test-e2e --debug-app`
    - Wait for resource stabilizing
    - Connect to debugger using `Attach twirp` and `Attach worker` VSCode debug targets
    - Click "Enter" to start test execution
- Debug of test suites
    - Run `script/test-e2e --debug-tests`
    - Wait for resource stabilizing
    - Start debugging using `Attach tests` VSCode debug target

Both types of debugging can be used with `--short`, `--full` or `--suite` modes.

## Testing with Runner

In a [Runner codespace](https://github.com/github/actions-larger-runners/blob/f0d131abcc0c8b484edadf220d3f68af46191807/docs/dev-workflow.md#tldr) do the following to configure Runner to use IMS, open three bash shells prompts.

Start IMS. This may require you to jit into test resources. It will prompt if required.

```
cd /workspaces/actions/hosted-compute-ims
script/server
```

Configure an image. Version shouldn't matter since curated images in Runner require 'latest' and IMS will automatically pick this (the only image version) as the latest.

```
cd /workspaces/actions/hosted-compute-ims
script/dev-client curated --image ubuntu
```

Configure Runner to consume IMS. [Deploy Runner](https://github.com/github/actions-larger-runners/blob/f0d131abcc0c8b484edadf220d3f68af46191807/docs/dev-workflow.md#runner-1) if you haven't already prior to these steps.

```
skyrise
lr runner

Set-FeatureFlag -FeatureName 'GitHub.Actions.Runner.Server.ImageManagementService.Curated' -State On -AllowUnregisteredFeature
Set-ServiceRegistryValue -RegistryPath '/Service/Runner/Settings/ImsCuratedImage/Ubuntu24' -Value 1
```

The CreateCuratedImageDefinition call will return an image definition id, which is what we're setting in the ```/Service/Runner/Settings/ImsCuratedImage/Ubuntu24``` path. It starts at 1, so it'll be 1 unless you create multiple images. This tells Runner what image id to call IMS with, so that needs to be correct. The registry keys need to be at the deployment level, but the feature flag could be set at the host level to scope to a particular host. Note: the feature flag will attempt to use IMS for all curated images, so if there are multiple curated image pools, they will all attempt to get images from IMS instead of locally.

