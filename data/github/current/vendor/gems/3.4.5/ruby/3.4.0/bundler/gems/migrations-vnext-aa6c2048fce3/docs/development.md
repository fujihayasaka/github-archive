# Development

## Project Structure

See [golang-standards/project-layout](https://github.com/golang-standards/project-layout).

## Libraries

*I need a(n) _____, what should I use?*

* Circuit breaker: https://github.com/sony/gobreaker
* HTTP Client: https://github.com/hashicorp/go-retryablehttp

## Protobufs

Protobufs in the `proto` directory can be built by running `make build-protobufs`. To build the protobufs for the Ruby client, run `script/ruby-proto`.

## Octoshift Protobufs

Copies of the Octoshift protobufs are housed within this repository. A compiled version of these protobufs are not 
available for consumption.

### CI

Two CI checks exist to make sure we don't fall behind:

1. `proto-check-latest.yaml`: This check verifies that we are using the latest version of the protobufs. The source 
   of truth is the `github/octoshift` repository.
2. `proto-gen-go-check`: This checks that the compiled versions of the protobufs that we're using are in-sync with 
   the protobuf definitions.

If either of these checks fail, the output includes instructions on how to fix the problem.

The `proto-check-latest.yaml` relies on a read-only deploy key configured in the [octoshift](https://github.ghe.
com/github/octoshift) repository. This key allows us to clone the repository from dotcom. If it ever needs to be
rotated, the `PROXIMA_OCTOSHIFT_RO_DEPLOY_KEY` must be updated to match the new key.
