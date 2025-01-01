# Testing

Description of the thing

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [Philosophy](#philosophy)
  - [Running Tests](#running-tests)
  - [Using the Debugger](#using-the-debugger)
  - [E2E Testing](#e2e-testing)
  - [Code Coverage Reports](#code-coverage-reports)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Terminology

- **Integration tests**: Focus on multiple parts of the application and how they work together
- **Unit tests**: Focus on a single part of the application and how it works in isolation

## Details

### Philosophy

All APIs should have integration tests. These are included in [`testing/integration-tests`](https://github.com/github/billing-platform/tree/main/testing/integration-tests).
Shared code such as helpers should have unit tests. For example, [`lib/models/time_test.go`](https://github.com/github/billing-platform/blob/main/lib/models/time_test.go).

### Running Tests

#### Integration

Integration tests will create a new collection in CosmosDB per test. Collections
are cleaned up automatically following the test run. This allows our tests to
run in parallel, and silos data to ensure no collisions occur.

`aqueduct-lite` is used to simulate Hydro events being produced. Tests will
read events from the queue.

By default in codespaces, integration tests will run against the local Cosmos DB emulator.

Run all integration tests.
```bash
make test-integration
```

To run specific integration tests, add their name to the end of the command. When a name is *not* specified, all tests are run.
```sh
script/integration-tests test_name
```

When in a codespace, specify `-a` on the script to run against an actual Azure Cosmos DB instance.
```sh
script/integration-tests -a
```

#### Fakes

We use [Pegomock](https://github.com/petergtz/pegomock) to generate mocks of our services. Do not directly edit the files in the `testing/fakes/` directory.

To generate a mock for a new service or to update a service's mock navigate to the directory where the interface exists and then use the `script/mock` script, passing in the interface name as a parameter.

Exampe:
```
> cd lib/azure/kusto
> /workspaces/billing-platform/script/mock KustoService
```

The output will be a file like: `testing/fakes/mock_kustoservice.go`

#### Ruby Client

We have tests to verify proper integration of the Ruby client. These tests can be run with `./script/ruby-test`.

> You might get the following error when running these tests:
>
> ```
> rbenv: version `3.2.1' is not installed (set by /workspaces/billing-platform/ruby/.ruby-version)
> ```
>
> If so, you need to install the correct ruby version with: `rbenv install 3.2.1`

### Using the Debugger

A walkthrough of how to use the VS Code Debugger with billing platform integration tests is available [here](https://github.rewatch.com/video/frep3kpboknfcl6i-using-the-vs-code-debugger-with-billing-platform-integration-tests) or you can follow the steps below.

1. Launch the VSCode Debugger - this exposes a debug port from the application
2. Set your breakpoint(s) in the code
3. In your test, where the integration client is normally set up, Update the `integration.ClientOptions` fields as needed to debug the client.
In below sample test, we already started the api instance in debug mode, so we configure the test client to use that
:information_source: When you're finished debugging, make sure to update the test to use the original integration client before committing any code changes.
If you commit a test that uses the debugger integration client, it will most likely cause CI failures.

```go
import (
 "testing"
 "github.com/github/billing-platform/testing/integration"
)

func Test_MySampleTest(t *testing.T) {
    // See integration.ClientOptions for debugging options
    client, g := integration.NewTestClient(t, integration.ClientOptions{UseExistingServerAPI: true })

    // Your test case
}
```

4. In order for your breakpoints to work as expected and allow you to step into the code, you'll need to launch the appropriate processes from the VS Code Debugger. For example, if you're running tests in the [`usage_integration_test.go`](https://github.com/github/billing-platform/blob/main/testing/integration-tests/usage_integration_test.go) file, depending on the test you'll need to launch both the API and usage_ingestion before debugging the test. The processes you need to launch will vary depending on the test you're debugging.

<img width="449" alt="DebuggingScreenshot" src="https://github.com/github/billing-platform/assets/64283754/d472056e-e3e5-4b89-8da6-685824f722b3"/>

5. Click debug test for the test and step through the code once you hit your breakpoint(s).

:information_source: Especially when debugging tests related to usage ingestion or roll ups, it can be helpful to have the Azure Cosmos DB Data Explorer open so you can see at which points we are writing new line items and/or roll ups to the database as you step through the code.

:information_source: After debugging a test, you can also use the Azure Cosmos DB Data Explorer to confirm whether your test data has been cleaned up and optionally run `script/clean` to manually clean up your test data if necessary.

### E2E Testing

If you make changes to the Ruby client, it can be helpful to run a full E2E test with dotcom and billing-platform to verify that your client changes work.

Assuming you have a billing-platform branch created with changes to the client, follow these steps to vendor and test a local gem version in dotcom:

- Checkout your billing-platform changes in dotcom
- Ensure all changes to the client are committed to your branch prior to running the next step
- Run the [`vendor-gem-in-dotcom-codespace` script](https://github.com/github/billing-platform/blob/main/script/vendor-gem-in-dotcom-codespace) in `../billing-platform`
  - This will update the billing-platform-client gem in your dotcom branch with a commit hash appended version (e.g. `billing-platform-client-0.5.0.2.g8ac86cc.gem`) that can be used to test your changes
- Test the updated client changes in dotcom

### Code Coverage Reports

We have code coverage reports in place for the client RubyGem, unit tests, and integration tests.

#### Ruby Code Coverage

Ruby code coverage is generated by [SimpleCov](https://github.com/simplecov-ruby/simplecov) and is available in the `ruby/coverage` directory after a test run. On CI it is uploaded as an artifact for each `Run specs for Ruby client` job. You can access this by viewing the [summary page for the job](https://github.com/github/billing-platform/actions/runs/4501696015) and looking in the `Artifacts` section.

#### Unit & Integration Code Coverage

For go tests we use [`go coverage`](https://go.dev/testing/coverage/) to generate our coverage reports. When running either `make test` or `script/integration-tests` you will see a breakdown of coverage per package in the console output. For more detailed reports you can look in the `coverage` directory for `coverage/unit.html` and `coverage/integration.html`. On CI you can download these as artifacts on the summary page for unit and integration test jobs.

## Troubleshooting

- **Rate limiting during integration tests**: If you are seeing 429 failures while running integration tests, you may need need to decrease the `-parallel` flag value in `script/integration-tests`. Keep in mind that there is a trade off here. The lower you set the value, the longer tests will take, the higher you set it, the more likely you are to experience 429s.

## References

- [The Hub: Testing](https://thehub.github.com/epd/engineering/dev-practicals/frontend/testing/)
- [The Hub: Testing with Test Oracle](https://thehub.github.com/epd/engineering/products-and-services/dotcom/testing/testing-with-test-oracle/)
- [The Hub: Testing in Go](https://thehub.github.com/epd/engineering/dev-practicals/go/testing/)
