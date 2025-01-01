package selfhostedrunners

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

// RegisterRunner is used to register a runner with AZP
func (s *service) GenerateJitRunnerConfig(ctx context.Context, req *GenerateJitRunnerRequest) (*GenerateJitRunnerResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "generatejitrunner")

	oid := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", oid.String()))
	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for GenerateJITRunnerConfig lookup")
			return &GenerateJitRunnerResponse{}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	settings := &azp.JITRunnerSettings{
		Name:          req.GetName(),
		RunnerGroupID: req.GetRunnerGroupId(),
		Labels:        req.GetLabels(),
		WorkFolder:    req.GetWorkFolder(),
		GithubURL:     req.GetGithubUrl(),
	}

	config, err := arc.GenerateJITRunnerConfig(ctx, settings)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	return &GenerateJitRunnerResponse{
		Runner:           ConvertDetailedRunnerFromAzp(config.Runner),
		EncodedJitConfig: config.EncodedJITConfig,
	}, nil
}
