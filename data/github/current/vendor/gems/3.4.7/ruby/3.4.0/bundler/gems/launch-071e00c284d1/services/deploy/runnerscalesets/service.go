package runnerscalesets

import (
	context "context"
	fmt "fmt"

	db "github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"
)

type service struct {
	log                  logger.Logger
	stats                statter.Statter
	azpRepoClientFactory azp.RepositoryClientFactory
	azpResourceRepo      db.AzpResourcesRepository
}

func New(
	logger logger.Logger,
	statter statter.Statter,
	azpRepoClientFactory azp.RepositoryClientFactory,
	azpResourceRepo db.AzpResourcesRepository,
) *service {
	return &service{
		log:                  logger,
		stats:                statter,
		azpRepoClientFactory: azpRepoClientFactory,
		azpResourceRepo:      azpResourceRepo,
	}
}

func (s *service) startLatencyCheckpoint(obs *observability.Observability) {
	obs.StartCheckpoint(observability.TwirpRequestCheckpoint)
}

func (s *service) logLatencyCheckpoint(ctx context.Context, obs *observability.Observability, action string) {
	threshold := thresholds.DefaultRunnerScaleSets

	_, err := obs.LogDuration(ctx, observability.TwirpRequestCheckpoint, fmt.Sprintf("runnerscalesets_%s", action), threshold, statter.Tags{})
	if err != nil {
		obs.Report(ctx, err)
	}
}

func (s *service) getAzureRepositoryClient(ctx context.Context, rid types.GlobalID) (azp.RepositoryClient, error) {
	abr, err := s.azpResourceRepo.TryGet(ctx, rid)
	if err != nil {
		return nil, fmt.Errorf("unable to create azp resource client: %w", err)
	}
	return s.azpRepoClientFactory.ClientFromResources(ctx, abr), nil
}
