// Package status handles postbacks from AZP for both Run status and Job/Step status
//
// The main ADR describing this is https://github.com/github/dreamlifter/blob/master/docs/adrs/0470-e2e.md
//
// The flow is AZP posting JSON payloads to launch-receiver (services/receiver/status) which then sends
// RPCs to here. The job of this package is to take that incoming payload and syndicate it where needed,
// which is both our local datastore as well as pushing through to CheckSuites and CheckRuns in the main
// dotcom system via GraphQL.
package status
