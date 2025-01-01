package tiers

import (
	"context"

	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/types"
)

func FetchRepositoryTier(ctx context.Context, log logger.Logger, twirpClient ghtwirp.Client, repoID types.GlobalID) (types.RepositoryTier, error) {
	tier, err := twirpClient.GetTrustTier(ctx, repoID)

	if err != nil {
		err = errors.Wrap(err, "unable to fetch trust tier from dotcom, defaulting to tier 3")
		log.Report(ctx, err)
		tier = types.RepositoryTier3
	}

	return tier, err
}
