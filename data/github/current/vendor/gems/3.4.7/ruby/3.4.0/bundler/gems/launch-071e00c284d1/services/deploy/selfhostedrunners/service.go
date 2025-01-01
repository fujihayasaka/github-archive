package selfhostedrunners

import (
	context "context"
	fmt "fmt"

	errs "github.com/pkg/errors"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
)

type service struct {
	log                  logger.Logger
	stats                statter.Statter
	ghClientFactory      github.Factory
	azpRepoClientFactory azp.RepositoryClientFactory
	azpResourceRepo      deployer.AzpResourcesRepository
	jobsRepository       deployer.JobsRepository
	env                  launchconfig.AppEnv
	isMultiTenant        bool
	actorFFChecker       func(context.Context, string, types.GlobalID) bool
}

// New returns an instance of the SelfHostedRunner service
func New(
	logger logger.Logger,
	statter statter.Statter,
	ghClientFactory github.Factory,
	azpRepoClientFactory azp.RepositoryClientFactory,
	azpResourceRepo deployer.AzpResourcesRepository,
	jobsRepository deployer.JobsRepository,
	env launchconfig.AppEnv,
	isMultiTenant bool,
	actorFFChecker func(context.Context, string, types.GlobalID) bool,
) *service {
	return &service{
		log:                  logger,
		stats:                statter,
		ghClientFactory:      ghClientFactory,
		azpRepoClientFactory: azpRepoClientFactory,
		azpResourceRepo:      azpResourceRepo,
		jobsRepository:       jobsRepository,
		env:                  env,
		isMultiTenant:        isMultiTenant,
		actorFFChecker:       actorFFChecker,
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

	_, err := obs.LogDuration(ctx, observability.TwirpRequestCheckpoint, fmt.Sprintf("selfhostedrunners_%s", action), threshold, statter.Tags{})
	if err != nil {
		obs.Report(ctx, err)
	}
}

func (s *service) createRunnerOps(runnerID int64, labelsToAdd []int64, labelsToRemove []int64) []*azp.RunnerOp {
	var operations []*azp.RunnerOp

	if len(labelsToAdd) > 0 {
		addOperation := &azp.RunnerOp{
			Op:    "add",
			Path:  s.getLabelPath(runnerID),
			Value: labelsToAdd,
		}

		operations = append(operations, addOperation)
	}

	if len(labelsToRemove) > 0 {
		removeOperation := &azp.RunnerOp{
			Op:    "remove",
			Path:  s.getLabelPath(runnerID),
			Value: labelsToRemove,
		}

		operations = append(operations, removeOperation)
	}

	return operations
}

func (s *service) getLabelPath(runnerID int64) string {
	return fmt.Sprintf("/%v/labels", runnerID)
}
