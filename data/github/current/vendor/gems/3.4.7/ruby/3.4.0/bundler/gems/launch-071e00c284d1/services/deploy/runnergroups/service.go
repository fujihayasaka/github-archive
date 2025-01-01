package runnergroups

import (
	context "context"
	fmt "fmt"

	errs "github.com/pkg/errors"

	"github.com/github/launch/clients/github"
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
	ghClientFactory      github.Factory
	azpRepoClientFactory azp.RepositoryClientFactory
	azpResourceRepo      db.AzpResourcesRepository
}

// New returns an instance of the RunnerGroup service
func New(
	logger logger.Logger,
	statter statter.Statter,
	ghClientFactory github.Factory,
	azpRepoClientFactory azp.RepositoryClientFactory,
	azpResourceRepo db.AzpResourcesRepository,
) *service {
	return &service{
		log:                  logger,
		stats:                statter,
		ghClientFactory:      ghClientFactory,
		azpRepoClientFactory: azpRepoClientFactory,
		azpResourceRepo:      azpResourceRepo,
	}
}

func (s *service) getAzureRepositoryClient(ctx context.Context, rid types.GlobalID) (azp.RepositoryClient, error) {
	abr, err := s.azpResourceRepo.TryGet(ctx, rid)
	if err != nil {
		return nil, errs.Wrap(err, "unable to create azp resource client for repository")
	}
	return s.azpRepoClientFactory.ClientFromResources(ctx, abr), nil
}

func (s *service) startLatencyCheckpoint(obs *observability.Observability) {
	obs.StartCheckpoint(observability.TwirpRequestCheckpoint)
}
func (s *service) logLatencyCheckpoint(ctx context.Context, obs *observability.Observability, action string) {
	threshold := thresholds.DefaultSelfHostedRunners

	_, err := obs.LogDuration(ctx, observability.TwirpRequestCheckpoint, fmt.Sprintf("runnergroups_%s", action), threshold, statter.Tags{})
	if err != nil {
		obs.Report(ctx, err)
	}
}
