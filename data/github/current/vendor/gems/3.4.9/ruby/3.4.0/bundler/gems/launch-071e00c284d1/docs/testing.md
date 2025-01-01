# Testing

## Automated testing

### Mocks

Mocks are generated via [mockery](https://github.com/vektra/mockery).

To regenerate one or more mocks, use [`script/mock-check`](/script/mock-check):

```shell
script/mock-check
```

Mocks are configured in [.mockery.yaml](/.mockery.yaml).

### Running individual tests

Individual test suites can be run with `-run TestSuiteName`. Individual test runs can be run with `-testify.m TestRunName`, which requires `-run`.
Some tests require the database to pass, so they should be run with `script/test` rather than `go test`. Also, most tests require the package they belong to, so all relevant files should be added to the command line.

Example running a single test suite:

```
$ script/test -v ./db/stores/deployer/... -run TestAzpResourcesRepository
[...]
=== RUN   TestAzpResourcesRepository/TestTryGetNoExistingResources
=== RUN   TestAzpResourcesRepository/TestTryGetWaitsForLock
--- PASS: TestAzpResourcesRepository (0.56s)
    --- PASS: TestAzpResourcesRepository/TestGetAzpResourcesError (0.01s)
    --- PASS: TestAzpResourcesRepository/TestGetAzpResourcesErrorTypeAssertion (0.01s)
    [...]
PASS
coverage: 18.1% of statements
ok      github.com/github/launch/db/stores/deployer     1.080s  coverage: 18.1% of statements
```

Example running a single test case:

```
$ script/test -v ./db/stores/deployer/... -run TestAzpResourcesRepository -testify.m TestGetOrCreateWaitForLockExpiry
[...]
=== RUN   TestAzpResourcesRepository
=== RUN   TestAzpResourcesRepository/TestGetOrCreateWaitForLockExpiry
--- PASS: TestAzpResourcesRepository (0.09s)
    --- PASS: TestAzpResourcesRepository/TestGetOrCreateWaitForLockExpiry (0.08s)
PASS
coverage: 10.4% of statements
ok      github.com/github/launch/db/stores/deployer     0.410s  coverage: 10.4% of statements
```

#### Database tests - "Field 'workflow_identifier' doesn't have a default value" error

This should no longer be an issue as of May 2022. If necessary, run the following:

- `mkdir -p ./tmp`
- `cp config/my.cnf.dev ./tmp`
-  `chmod 644 ./tmp/my.cnf.dev`
- `docker-compose down`
- `docker-compose up --no-start`

...then running `script/test` should bring up mysql with the correct config.

#### Debugging in vscode
See https://github.com/github/launch/blob/master/docs/local-dev.md#debugging-unit-tests
## Manual (in-browser) testing

There are several ways to test changes in Launch. Read about our
[deployment options](https://github.com/github/c2c-actions-experience/blob/master/doc/deploy-environments.md)
for more information.

## Manual testing from terminal window

There happen to be cases when there is no Dotcom code yet that supposed to interact with Launch, but you already need to test Launch, for example, its new endpoints. 
This can be achieved with [`script/twirpcurl`](https://github.com/github/launch/blob/master/script/twirpcurl) script.

Usage (Custom Hosted Runners, former Premium Runners, as an example):
```
echo '{"image_definition_id":1, "image_version":"1.0.0", "owner_id": {"global_id": "<entity_id>"}}' | script/twirpcurl largerrunners GetImageVersion
```
Trick here is to format JSON the way Dotcom would format it, but specify Launch method name to be called the way it is called in Launch code. `<entity_id>` is a global ID of Organization/Enterprise/Repository depending from which level you need to call Launch.

## Running integration tests

We leverage [`actions/canary`](https://github.com/actions/canary) for running functional and security integration tests. If you're making a security related change, you should run these tests in lab before deploying to prod. You may also need to add additional test workflows if your change would not be exercised there.

Also consider writing a similar Sauron test in [`github/sauron`](https://github.com/github/sauron)

### Steps
1. Deploy your PR to `lab` and wait for it to complete.
1. Queue a canary test suite. See https://github.com/actions/canary/blob/main/README.md#queuing-test-suites
1. Monitor the tests and investigate any failures.
1. In your PR, note the check suite you ran and link to your commit's checks (e.g. https://github.com/actions/canary/commit/6ae992ffe80238aa6902738ecfdf9706b74a6f4b/checks).
