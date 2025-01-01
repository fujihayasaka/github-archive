package jobs

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

type SuggestedFixAlertGenerateHighPriorityJob SuggestedFixAlertGenerate

var _ aqueduct.EnqueableJob = (*SuggestedFixAlertGenerateHighPriorityJob)(nil)

func (p SuggestedFixAlertGenerateHighPriorityJob) Name() string {
	return "SuggestedFixAlertGenerateHighPriority"
}

func (p SuggestedFixAlertGenerateHighPriorityJob) Queue() string {
	return "turboscan-suggested-fix-generate-high-priority"
}

func (p SuggestedFixAlertGenerateHighPriorityJob) GetRepositoryID() *ts.RepositoryEID {
	return &p.RepoID
}

func (p SuggestedFixAlertGenerateHighPriorityJob) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.SuggestedFixAlertGenerateJobRetryBackoffFunc
}

func (p SuggestedFixAlertGenerateHighPriorityJob) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	return PerformSuggestedFixAlertGenerate(ctx, s, SuggestedFixAlertGenerate(p), ts.ThrottlerWorkload_HIGH)
}
