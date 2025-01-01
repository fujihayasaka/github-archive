package artifactcache

import (
	context "context"
	fmt "fmt"

	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"
)

type service struct {
	log               logger.Logger
	stats             statter.Statter
	repoClientFactory azp.RepositoryClientFactory
	resourceRepo      deployer.AzpResourcesRepository
}

// New returns an instance of the ArtifactCache service
func New(log logger.Logger, statter statter.Statter, f azp.RepositoryClientFactory, resourceRepo deployer.AzpResourcesRepository) *service {
	return &service{
		log:               log,
		stats:             statter,
		repoClientFactory: f,
		resourceRepo:      resourceRepo,
	}
}

func (s *service) startLatencyCheckpoint(obs *observability.Observability) {
	obs.StartCheckpoint(observability.TwirpRequestCheckpoint)
}

func (s *service) logLatencyCheckpoint(ctx context.Context, obs *observability.Observability, action string) {
	threshold := thresholds.DefaultArtifactCache

	_, err := obs.LogDuration(ctx, observability.TwirpRequestCheckpoint, fmt.Sprintf("artifactcache_%s", action), threshold, statter.Tags{})
	if err != nil {
		obs.Report(ctx, err)
	}
}

func (s *service) getAzureRepositoryClient(ctx context.Context, rid types.GlobalID) (azp.RepositoryClient, error) {
	abr, err := s.resourceRepo.TryGet(ctx, rid)
	if err != nil {
		return nil, errors.Wrap(err, "unable to create azp resource client for repository")
	}
	return s.repoClientFactory.ClientFromResources(ctx, abr), nil
}
