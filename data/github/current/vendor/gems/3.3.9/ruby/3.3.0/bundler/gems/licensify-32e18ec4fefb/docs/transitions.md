# Transitions

It may be necessary sometimes to backfill or mass update data in our CosmosDB containers. Licensify has [automated transitions](https://thehub.github.com/epd/engineering/products-and-services/internal/transitions) setup to do this.

## Usage
1. Add a new transition in `internal/transitions` that implements a `Run` method. The business logic to update the data should go here.
1. Add the transition to the switch block in `cmd/transition/main.go` with a unique name. Command line arguments can be passed to the transition by defining flags using the `flag` package.
1. Open a PR with the changes
1. After the PR is approved, go to the `#licensing-ops` slack channel and run the transition:
    ```
    .transitions run <pull-request-url> <stamp> --name=<transition-name> [args]
    ```
    ex:
    ```
    .transitions run https://github.com/github/licensify/pull/428 production --name=backfill_license_status --dry_run=false
    ```
1. The transition can be cancelled at any time with
    ```
    .transitions cancel <pull-request-url>
    ```
See [the Hub docs](https://thehub.github.com/epd/engineering/products-and-services/internal/transitions/#running-a-transition) for more on running a transition.