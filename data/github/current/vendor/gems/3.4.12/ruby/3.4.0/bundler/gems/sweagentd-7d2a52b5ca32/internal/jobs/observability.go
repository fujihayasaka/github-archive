package jobs

import (
	"context"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/observability"
)

// StatJobTransition records a job state transition metric.
func StatJobTransition(ctx context.Context, obsv observability.Exporters, tags stats.Tags, from, to JobStatus) {
	tags = tags.Merge(stats.Tags{
		"from": string(from),
		"to":   string(to),
	})
	obsv.Statter.Counter("jobs.state_transition", tags, 1)
}
