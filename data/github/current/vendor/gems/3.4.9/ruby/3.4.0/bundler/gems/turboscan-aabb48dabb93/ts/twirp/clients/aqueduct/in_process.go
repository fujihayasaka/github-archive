package aqueduct

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/indexer"
)

// InProcessJob is a mock implementation of jobs that can be used for testing.
// It executes the job directly by calling Perform, and does not enqueue it.
type InProcessJob struct {
	TSServices *TSServices
}

func (i InProcessJob) PerformLater(ctx context.Context, j EnqueableJob) (string, error) {
	return "", j.Perform(ctx, i.TSServices)
}

func (i InProcessJob) PerformLaterAt(ctx context.Context, j EnqueableJob, at time.Time) (string, error) {
	return "", j.Perform(ctx, i.TSServices)
}

// DefaultInProcessJob returns simple version of InProcessJob, this only contains
// a few services and no logging or stats.
func DefaultInProcessJob(indexer *indexer.Service) InProcessJob {
	serv := &TSServices{
		Indexer: indexer,
	}
	jobs := InProcessJob{
		TSServices: serv,
	}
	jobs.TSServices.Aqueduct = jobs
	return jobs
}
