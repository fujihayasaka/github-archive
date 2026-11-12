package jobutils

import (
	"context"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
)

// UpdateRequestContextJob updates the request context with the given job.
//
// Deprecated: this is a temporary static method to allow the functionality to
// move to the jobservice, and be removed from jobutils. New callers should use
// the jobservice to manage the job, which will manage the session and populate
// the context internally.
func UpdateRequestContextJob(ctx context.Context, obsv observability.Exporters, job *jobs.Job) {
	jobservice.UpdateRequestContextJob(ctx, obsv, job) //nolint:staticcheck // temporary while requirement is removed from callers
}

// UpdateRequestContextSession is a helper to update the session in the request context.
//
// Deprecated: this is a temporary static method to allow the functionality to
// move to the jobservice, and be removed from jobutils. New callers should use
// the jobservice to manage the job, which will manage the session and populate
// the context internally.
func UpdateRequestContextSession(ctx context.Context, obsv observability.Exporters, update capi.SessionUpdate) {
	jobservice.UpdateRequestContextSession(ctx, obsv, update) //nolint:staticcheck // temporary while requirement is removed from callers
}
