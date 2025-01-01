## swarm

Swarm-go is a very rough Go prototype of the existing Octoshift Swarm implementation.
The thought behind this is how we could shift part of the work that is currently done
by the Octoshift Swarm to a Go implementation that uses way less Redis resources
by using Kafka and Azure Blob Store.

A Swarm is a collection of jobs that may run concurrently across a set of multiple
workers and whose overall progress is tracked by the Swarm itself. The status
of the Swarm is determined by the status of its jobs and can be queried at any time.

## Dependencies

It depends on the following external services:

- `Redis` - for storing the state of the Swarm and its jobs
- `Kafka` - to fan out jobs to workers
- `Azure Blob Store` - to store job payloads that are too large to fit in Kafka

### Worker

The worker is responsible for listening for jobs to run and reporting back to the Swarm state.

You can run as many workers as you want from multiple instances. Workers read jobs from Kafka, in
batches and run them concurrently.

## TODO

- [ ] Decide whether this might be useful at all
- [ ] Decide whether we want to use Redis for KV (it's a good fit but we could use something else)
- [ ] Make sure we can actually use this to fan out jobs from Octoshift (semantics are correct, polling is fine, corner cases, etc)
- [ ] Better error handling: right now it's very rudimentary and assumes happy paths everywhere
- [ ] Complete functionality and go from rough prototype to cover the feature set
- [x] Add CI
- [ ] Dependabot
- [x] Add linter
- [ ] Use Hydro schemas instead of direct protobuf
- [ ] Add support for suspending jobs
- [ ] Add support for retries
- [ ] Add support for timeouts
- [x] Add actual logic to the worker
- [ ] Evaluate whether Aqueduct is a better fit than raw Kafka
- [ ] Test with a real Azure Blob Store
- [ ] Metrics
- [ ] Other things I'm forgetting

## Caveats

Lots :) This is a prototype is not complete by any means.
