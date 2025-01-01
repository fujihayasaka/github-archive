package jobs

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
)

type SkipDependabot struct {
	RepoID        ts.RepositoryEID
	PullRequestID uint64
}

var _ aqueduct.EnqueableJob = (*SkipDependabot)(nil)

func (r SkipDependabot) GetRepositoryID() *ts.RepositoryEID {
	return &r.RepoID
}

func (r SkipDependabot) Name() string {
	return "SkipDependabot"
}

func (r SkipDependabot) Queue() string {
	return "turboscan-skip-dependabot"
}

func (r SkipDependabot) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func (r SkipDependabot) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	fields := []kvp.Field{
		kvp.Any("gh.turboscan.pull_request_id", r.PullRequestID),
		kvp.Any("gh.aqueduct.job.name", "SkipDependabot"),
	}
	ctx = appctx.With(ctx, fields...)
	ctx = appctx.WithLogger(ctx, appctx.Logger(ctx).WithFields(fields...))
	if s == nil || s.ManagedAnalyses == nil {
		return errors.New("missing required services")
	}
	return s.ManagedAnalyses.SkipCheckForPR(ctx, r.RepoID, r.PullRequestID)
}
