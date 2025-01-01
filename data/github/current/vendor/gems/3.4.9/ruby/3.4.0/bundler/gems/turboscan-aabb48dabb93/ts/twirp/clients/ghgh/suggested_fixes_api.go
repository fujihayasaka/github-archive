// Package ghgh contains Twirp clients for connecting to github/github.
package ghgh

import (
	"context"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	api "github.com/github/turboscan/ts/monolith_twirp/suggested_fixes/v1"
	"github.com/github/turboscan/ts/o11y"
)

type SuggestedFixesAPI interface {
	SuggestedFixStateChanged(ctx context.Context, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers []uint32) error
}

type suggestedFixesAPI struct {
	client api.SuggestedFixesAPI
	logger log.Logger
	stats  stats.Client
}

func NewSuggestedFixesAPI(client api.SuggestedFixesAPI, logger log.Logger, stats stats.Client) SuggestedFixesAPI {
	return &suggestedFixesAPI{
		client: client,
		logger: logger,
		stats:  stats,
	}
}

func (sf *suggestedFixesAPI) SuggestedFixStateChanged(ctx context.Context, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers []uint32) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	req := &api.SuggestedFixStateChangedRequest{
		RepositoryId:  uint64(repoID),
		PullRequestId: uint64(prID),
		AlertNumbers:  alertNumbers,
	}
	_, err := sf.client.SuggestedFixStateChanged(ctx, req)
	return err
}
