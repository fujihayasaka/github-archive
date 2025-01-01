package aqueduct

import (
	"context"
	"time"
)

// JobPerformer provides a minimal interface for enqueuing jobs
type JobPerformer interface {
	PerformLater(ctx context.Context, j EnqueableJob) (string, error)
	PerformLaterAt(ctx context.Context, j EnqueableJob, at time.Time) (string, error)
}
