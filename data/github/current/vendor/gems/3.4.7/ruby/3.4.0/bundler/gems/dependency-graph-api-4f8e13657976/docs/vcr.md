## VCR Tests
Instructions for working with [VCR test fixtures](https://github.com/vcr/vcr) in DG-API and the monolith.

### Re-recording VCR tests
#### ...in DG-API
Before attempting to (re)record VCR cassettes used in DG-API test suites, check [here](https://github.com/github/dependency-graph-api/blob/d059b67bb31ba79c3843b59dd3eceda14a7876ea/spec/rails_helper.rb#L238-L253) for context about which test-env outgoing requests from DG-API are allowed to proceed, and which are short-circuited by the VCR framework.

The framework should allow calls out to Docker-supported services (Azurite, Kafka, etc.) from tests, since those backends will be available in CI. VCR can be used to locally record replayable request/response sequences for services like DS-API that are not Dockerized in DG-API and/or available to DG-API in CI. These tests should use the registered cassette file and short-circuit requests when the file is present, but allow requests when the file is deleted, triggering a re-recording.

#### ...in the monolith
DG-API server is _stubbed in the monolith test environment_ [link](https://github.com/github/github/blob/f6a9ca7565728ecaf0436ce0054b1c8e0ae2be6c/test/test_helpers/test_cases.rb#L56) and will block outgoing requests without a stub response registered [here](https://github.com/github/github/blob/f6a9ca7565728ecaf0436ce0054b1c8e0ae2be6c/test/test_helpers/fake_dependency_graph_api_server.rb#L80-L87) when this functionality is enabled. When active, this will respond with a `404` from any unregisterd/unmocked endpoints.

Steps:
- Comment out the stub registration in monolith test helpers [here](https://github.com/github/github/blob/master/test/test_helpers/github/basic_test_case.rb#L65)([permalink](https://github.com/github/github/blob/5b4464b3a089edf4180095149b62c3de499ae84a/test/test_helpers/github/basic_test_case.rb#L65))
- If recording the cassette for the first time: _ensure the new target file doesn't exist_ (such as from previous attempts)
- If re-recording an existing cassette: _delete the cassette file before each attempt_
- Use `bin/rails test path/to/test/file:<line_number>` to run one test case at a time: cassettes can be reused and shouldn't be overwritten by every dependent test
- Inspect the (re)recorded cassette file and adjust to taste
- Check the (new/modified) cassette file in
- Re-run the test case and ensure the (new) recorded contents will pass
- Commit the new change to your PR

> Note: if you're running in the codespace-compose environment, you must `unset USE_API_PATH_PREFIX` in the dotcom codespace. If you don't, you'll get 404s for all the dependency-graph-api endpoints.

### VCR + Twirp/Protobuf
Fun fact: you can hand-edit a VCR cassette file manually in situations where it's friction heavy to re-record one. If you wish to edit or replace the encoded bodies of HTTP requests, such as the data payloads of Twirp requests from the monolith to DG-API, then read on!

The Twirp payloads embedded in a cassete file are Protobuf-encoded binary data that is additionally Base64-encoded. Example: Let's say you want to edit a cassette file like [this](https://github.com/github/github/blob/master/test/fixtures/vcr_cassettes/dependency_snapshot/create_stubbed_data.yml) including the Twirp messages encoded [here](https://github.com/github/github/blob/master/test/fixtures/vcr_cassettes/dependency_snapshot/create_stubbed_data.yml#L8-L9) and [here](https://github.com/github/github/blob/master/test/fixtures/vcr_cassettes/dependency_snapshot/create_stubbed_data.yml#L22-L23). Do this:

_Setup_
- Install the [protoc tool](https://linuxcommandlibrary.com/man/protoc). Try `script/bootstrap` in the DG-API repo or use `brew install protobuf`, if missing
- Check the [endpoint in the cassette file](https://github.com/github/github/blob/master/test/fixtures/vcr_cassettes/dependency_snapshot/create_stubbed_data.yml#L5) to confirm which request and response RPC messages you'll be working with

_Decode_
- Locate the target messages in the [proto spec file](https://github.com/github/dependency-graph-api/blob/master/proto/twirp/v1/dependency_graph_api.proto#L215-L240) where the RPCs are defined
- Decode the request and response Twirp from the cassette file above:
    - `echo <BASE64_STRING_FROM_YAML> | base64 -d | protoc --decode DependencyGraphAPI.v1.CreateDependencySnapshotRequest proto/twirp/v1/dependency_graph_api.proto` Example: [gist](https://gist.ghe.io/dd4abb87453f1f7767fd334d06cdba4e)
    - `echo <BASE64_STRING_FROM_YAML> | base64 -d | protoc --decode DependencyGraphAPI.v1.CreateDependencySnapshotResponse proto/twirp/v1/dependency_graph_api.proto` Example: [gist](https://gist.ghe.io/612132bb3ba93356a68e5080dbb2b7ed)

_Edit and Encode_
- Define one "value spec" file, in the format of the examples you decoded above, for each message you want to encode
- Encode the new values you've composed using `protoc --encode` and `base64`:
    - Contents of a "value spec" file, `repsonse_rpc.example`:
        ```
        $ cat response_rpc.example
        snapshot_id: 556677
        created_at {
          seconds: 1638401907
          nanos: 268000000
        }
        ```
    - Encoding command: `cat response_rpc.example | protoc --encode DependencyGraphAPI.v1.CreateDependencySnapshotResponse proto/twirp/v1/dependency_graph_api.proto | base64`
    - Expected output: `CIX9IRILCPOOoI0GEIC25X8=`
- Rinse and repeat as needed
- Replace the encoded snippets in the cassette file


