// Package sessions provides a collection of tests that recreate VCR recordings.
// The recordings are created in:
// ruby/spec/fixtures/vcr_cassettes
// when run with `make test` the tests will check that the cassettes would not be changed by any modifications to Turboscan
// when run with `make cassettes` the tests will commit the latest cassette changes to disk
package sessions
