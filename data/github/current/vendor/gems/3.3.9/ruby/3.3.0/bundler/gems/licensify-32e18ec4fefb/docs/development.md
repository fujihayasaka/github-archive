# Development
## Getting Started
Run these scripts in your codespace to pull down your connection string:
```bash
./script/azure-login
./script/set-remote
```

You should see an account endpoint in the printing `DB_CONNECTION_STR` variable.

## Running tests

```bash
# Runs go tests (excluding integration tests)
make go-test

# Runs ruby gem tests
make ruby-test

# Runs both go-test and ruby-test
make test

# Runs tests tagged with `integration`; option to filter by test name
make integration-test
make integration-test TEST_NAME=TestName
make integration-test TEST_NAME=^TestName$
```

## Starting the API
Before starting the API you must make the binary, then you can start the API using the API script:
```bash
make

./script/api
```

Here's an example request to test out one of the twirp APIs:
```bash
curl --request POST \
--url http://localhost:12345/twirp/licensify.services.v1.CustomerLicenseService/GetLicenseeIds \
--header 'Content-Type: application/json' \
--data '{
  "customerId": 1,
  "product": "PRODUCT_SDLC",
  "enablementReasons": [
    "ENABLEMENT_REASON_ORG_MEMBERSHIP",
    "ENABLEMENT_REASON_REPOSITORY_COLLABORATOR"
  ]
}'
```

## Testing Hydro Messages

Read more about the [test producer](./test_producer.md).

## Testing Aqueduct Messages
1. Start up aqueduct-lite: `./script/bootstrap`
2. Start the queue worker(s):
  * Standard priority queue worker: `./script/queue-worker`
  * Low priority queue worker: `AQUEDUCT_WORKER_TYPE=low-priority script/queue-worker`
3. Publish a message: `./script/publish-aqueduct-message`

## Tracing
To enable tracing in development, copy the following env variables to `dev.env`
```
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://127.0.0.1:4318/v1/traces"
export OTEL_SERVICE_NAME="licensify-dev"
```
Then run `./script/dev-tracing` to start collecting tracers and go to `localhost:16686` to view the UI. You may need to restart the licensify server.

## Updating licensify protobufs
1. Update the protos in the `./proto` directory
1. `./script/protoc`
1. Bump the gem version in `./ruby/lib/licensify/version.rb`

## Updating the monolith-twirp protobufs
1. Update the protos in the `./monolith-twirp-proto` directory
1. `./script/protoc`

## Updating hydro schemas
1. `go get github.com/github/hydro-schemas-go`

## Vendor new monolith-twirp gem
1. Follow [this guide](https://github.com/github/monolith-twirp/blob/master/docs/implementation.md)

## Testing monolith-twirp API
Here's an example request to test out one of our monolith-twirp APIs in a codespace:
```
hmac_key="thehmac"

# build signature from the HMAC key
ts=$(date +%s)
signature=$ts.$(echo -n $ts | openssl sha256 -hmac ${hmac_key} | sed 's/^.* //')

curl --request POST \
  --url https://api.github.localhost/internal/twirp/licensing.customers.v1.UsersAPI/GetUsers \
  --header "Request-HMAC: $signature" \
  --header "Content-Type: application/json" \
  --data '{"entityType": 1, "entityId": 123, "pageToken": ""}' \
  --write-out '\n'
```
(The `licensing` HMAC key can be found [here](https://github.com/github/github/blob/c52f3a419cb78c08f133d52c9f013b4d1fc92ef2/lib/github/config/environments/development.rb#L275).)
