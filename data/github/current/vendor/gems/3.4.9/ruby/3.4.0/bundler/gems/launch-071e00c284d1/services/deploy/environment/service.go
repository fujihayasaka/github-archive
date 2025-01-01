package environment

import (
	"context"
	"fmt"
	"net/http"
	"net/url"

	"github.com/github/go-kvp"
	"github.com/golang/protobuf/ptypes/empty"
	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/db/stores/deployer"
	db "github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
)

type service struct {
	log                  logger.Logger
	stats                statter.Statter
	azpRepoClientFactory azp.RepositoryClientFactory
	azpResourceRepo      db.AzpResourcesRepository
	ghClientFactory      github.Factory
	buildRepo            deployer.WorkflowBuildsRepository
	ghtwirpClient        ghtwirp.Client
	isMultitenant        bool
}

func New(
	logger logger.Logger,
	statter statter.Statter,
	azpRepoClientFactory azp.RepositoryClientFactory,
	azpResourceRepo db.AzpResourcesRepository,
	ghClientFactory github.Factory,
	buildRepo deployer.WorkflowBuildsRepository,
	ghtwirpClient ghtwirp.Client,
	isMultitenant bool,
) *service {
	return &service{
		log:                  logger,
		stats:                statter,
		azpRepoClientFactory: azpRepoClientFactory,
		azpResourceRepo:      azpResourceRepo,
		ghClientFactory:      ghClientFactory,
		buildRepo:            buildRepo,
		ghtwirpClient:        ghtwirpClient,
		isMultitenant:        isMultitenant,
	}
}

func (s *service) NotifyGate(ctx context.Context, req *NotifyGateRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	obs.StartCheckpoint(observability.NotifyGateCheckpoint)
	defer logNotifyGateLatency(ctx, obs)

	repoID := types.IdentityToGlobalID(ctx, req.GetRepositoryId())
	brs, err := s.azpResourceRepo.TryGet(ctx, repoID)
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError("error getting backing resources"))
	}

	// Make certain the gate gid is in the next format. If we accidently send Actions Service a legacy gate gid,
	// we have to keep using that legacy gid for the life of the workflow run.
	legacyOrNextGateGID := req.GetGateId().GetGlobalId()
	gateID, err := s.ghtwirpClient.GetNextGlobalID(ctx, legacyOrNextGateGID)
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError("failed to fetch next global id for gate"))
	}

	// Intentionally using a strict equality check here
	if legacyOrNextGateGID != gateID.String() {
		s.logGlobalIDReplacement(ctx, "NotifyGate", legacyOrNextGateGID, gateID)
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.global_id", repoID.String()), kvp.String("gh.launch.gate.global_id", gateID.String()))

	repoClient := s.azpRepoClientFactory.ClientFromResources(ctx, brs)
	err = repoClient.UpdateGateConclusion(ctx, gateID.String(), req.GetExternalId(), req.GetExternalJobId(), req.GetToken(), req.GetIsOpen())
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError("error updating gate conclusion"))
	}

	return &empty.Empty{}, nil
}

func logNotifyGateLatency(ctx context.Context, obs *observability.Observability) {
	threshold := thresholds.NotifyGate

	_, err := obs.LogDuration(ctx, observability.NotifyGateCheckpoint, "notify_gate", threshold, statter.Tags{})
	if err != nil {
		obs.Report(ctx, err)
	}
}

// GetOrCreateEnvironment gets environment if called with a token that has write access to Actions. Otherwise it defaults to get
func (s *service) GetOrCreateEnvironment(ctx context.Context, req *GetOrCreateEnvironmentRequest) (*GetOrCreateEnvironmentResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	resp, err := s.handleGetOrCreateEnvironmentRequest(ctx, req)
	if err != nil {
		s.log.Report(ctx, err)
		span.RecordError(err)
		if terrors.IsNotFoundError(err) {
			return nil, svcerr.NewNotFoundError("Environment or repository not found")
		}
		if reqErr := terrors.GetHTTPError(err); reqErr != nil {
			if reqErr.MatchStatusCodes(http.StatusForbidden) {
				return nil, svcerr.NewNotFoundError("Could not get environment - 403 response")
			}
		}

		return nil, svcerr.NewInternalError("Could not get environment")
	}

	return resp, nil
}

func (s *service) handleGetOrCreateEnvironmentRequest(ctx context.Context, req *GetOrCreateEnvironmentRequest) (*GetOrCreateEnvironmentResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	buildState, ok, err := s.buildRepo.GetDataForTokenRequest(ctx, req.GetWorkflowID())
	if err != nil {
		return nil, errors.Wrap(err, "Error looking up token data for workflow")
	}
	if !ok {
		return nil, errors.New("No token data returned for workflow")
	}

	// GitHubTenantID will be a nil pointer for non-multi-tenant modes.
	if s.isMultitenant {

		if buildState.GitHubTenantID == nil {
			return nil, errors.New("GitHub tenant id in workflow build state must not be nil")
		}

		ctx, err = ghtenant.ContextWithTenantID(ctx, *buildState.GitHubTenantID, s.isMultitenant)
		if err != nil {
			return nil, errors.Wrap(err, "expected valid GitHub tenant id to be set in workflow build state")
		}
	}

	environmentName := req.GetEnvironmentName()

	ghClient, err := s.ghClientFactory.NewClientForRepositoryOwner(ctx, buildState.RepositoryID, types.NewGlobalID(ctx, buildState.WorkflowMetadata.RepositoryOwner.GlobalRelayID))
	if err != nil {
		s.log.Report(ctx, err)
		return nil, errors.Wrap(err, fmt.Sprintf("Could not get environment %s", environmentName))
	}

	environmentNameUnEscaped, err := url.QueryUnescape(environmentName)
	if err != nil {
		s.log.Report(ctx, err)
		return nil, errors.Wrap(err, fmt.Sprintf("Could not get environment %s as name can't be Unescaped", environmentName))
	}

	var gres *github.EnvironmentResponse
	// Only create the Environment _if_ the user has write access to Deployments. This is to prevent
	// a race condition that can occur if the postback created during job creation is delayed in the
	// postback queue. If this happen the CheckRun, which creates the Environment, may not be created
	// when Service checks for Environment pre-conditions. This won't help if the user is using gates,
	// as those depend on the Check Run to be created.
	if buildState.TokenPermissions.Deployments == tokens.WriteAccess {
		s.log.Debug(ctx, "Write deployment permissions found, creating Environment")
		gres, err = ghClient.CreateEnvironment(ctx, buildState.RepositoryID, environmentNameUnEscaped)
	} else {
		s.log.Debug(ctx, "Read deployment permissions found, will only get Environment if it already exists")
		gres, err = ghClient.GetEnvironment(ctx, buildState.RepositoryID, environmentNameUnEscaped)
	}

	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "Error creating github client"))
	}

	gates := make([]*Gate, 0, len(gres.Gates))
	for _, gate := range gres.Gates {
		var gateType string
		if gate.GateType == "TIMEOUT" {
			gateType = "wait"
			if gate.TimeoutInMinutes < 1 {
				// If an invalid timeout is specified for a wait gate, default to 15 minutes
				// see https://github.com/github/c2c-actions-service/issues/1684
				gate.TimeoutInMinutes = 15
				s.log.Debug(ctx, "Received invalid wait gate timeout:", kvp.Int("gh.launch.timeout_minutes", int(gate.TimeoutInMinutes)))
			}
		} else {
			gateType = "remote"
			if gate.TimeoutInMinutes == 0 {
				// If no timeout is specified for a remote gate, default to 30 days
				// see https://github.com/github/c2c-actions-service/issues/1647
				gate.TimeoutInMinutes = 60 * 24 * 30
			}
		}

		gates = append(gates, &Gate{
			// gate.GateID is already in the next global ID format, thanks to the header we send with graphql requests on hosted.
			Id:               types.IdentityFromGlobalID(gate.GateID),
			Type:             gateType,
			TimeoutInMinutes: gate.TimeoutInMinutes,
		})
	}

	res := GetOrCreateEnvironmentResponse{
		Id:    types.IdentityFromGlobalID(gres.EnvironmentID),
		Name:  gres.Name,
		Gates: gates,
	}

	return &res, nil
}

func (s *service) logGlobalIDReplacement(ctx context.Context, operation string, legacyOrNextGID string, nextGID types.GlobalID) {
	s.stats.Counter(ctx, "global_ids.replace_gate_legacy_gid", statter.Tags{"operation": operation}, 1)
	s.log.Debug(ctx, "Replacing gate's legacy gid with next gid",
		kvp.String("gh.launch.legacy_global_id", legacyOrNextGID),
		kvp.String("gh.launch.next_global_id", nextGID.String()))
}
