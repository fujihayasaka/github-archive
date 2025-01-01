// Package test_helpers has helpers used in tests.
// At time of writing it provides an exception reporter that fails any tests.
package test_helpers

import (
	"context"
	"testing"

	"github.com/github/go-exceptions"
)

type testExporter struct {
	t *testing.T
}

func (e testExporter) Export(ctx context.Context, p []byte) error {
	e.t.Error("exception reporter was invoked with payload", string(p))
	return nil
}

// NewExceptionReporter creates a reporter that will cause any reported exception to fail the test
func NewExceptionReporter(t *testing.T) *exceptions.Reporter {
	t.Helper()

	reporter, _ := exceptions.NewReporter(
		exceptions.WithExporter(testExporter{t: t}),
		exceptions.WithApplication("testreporter"),
	)
	return reporter
}
