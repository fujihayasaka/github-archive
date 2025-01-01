package jobs

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

type SuggestedFixAlertGenerateLowPriorityJob SuggestedFixAlertGenerate

var _ aqueduct.EnqueableJob = (*SuggestedFixAlertGenerateLowPriorityJob)(nil)

func (p SuggestedFixAlertGenerateLowPriorityJob) Name() string {
	return "SuggestedFixAlertGenerateLowPriority"
}

func (p SuggestedFixAlertGenerateLowPriorityJob) Queue() string {
	return "turboscan-suggested-fix-generate-low-priority"
}

func (p SuggestedFixAlertGenerateLowPriorityJob) GetRepositoryID() *ts.RepositoryEID {
	return &p.RepoID
}

func (p SuggestedFixAlertGenerateLowPriorityJob) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.SuggestedFixAlertGenerateJobRetryBackoffFunc
}

func (p SuggestedFixAlertGenerateLowPriorityJob) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	return PerformSuggestedFixAlertGenerate(ctx, s, SuggestedFixAlertGenerate(p), ts.ThrottlerWorkload_LOW)
}
