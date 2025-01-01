package artifactsexchange

import (
	"net/http"
	strconv "strconv"
	"strings"

	"github.com/github/go-kvp"
	"github.com/golang/protobuf/ptypes/empty"
	errs "github.com/pkg/errors"
	context "golang.org/x/net/context"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

// Service is responsible for communicating with the Runtime to exchange signed
// URLs.
type Service struct {
	log                logger.Logger
	stats              statter.Statter
	repoClientFactory  azp.RepositoryClientFactory
	resourceRepo       deployer.AzpResourcesRepository
	workflowBuildsRepo deployer.WorkflowBuildsRepository
}

var resourceTypeStringMap = map[ResourceType]string{
	ResourceType_TYPE_UNKNOWN:            "unknown",
	ResourceType_TYPE_COMPLETED_LOG:      "completed_log",
	ResourceType_TYPE_STREAMING_LOG:      "streaming_log",
	ResourceType_TYPE_DOWNLOAD_ARTIFACT:  "download_artifact",
	ResourceType_TYPE_COMPLETED_STEP_LOG: "completed_step_log",
	ResourceType_TYPE_COMPLETED_RUN_LOG:  "completed_run_log",
	ResourceType_TYPE_COMPLETED_JOB_LOG:  "completed_job_log",
}

// New returns a new instance of the ArtifactsExchange service.
func New(log logger.Logger, statter statter.Statter, f azp.RepositoryClientFactory, resourceRepo deployer.AzpResourcesRepository, workflowBuildsRepo deployer.WorkflowBuildsRepository) *Service {
	return &Service{
		log:                log,
		stats:              statter,
		repoClientFactory:  f,
		resourceRepo:       resourceRepo,
		workflowBuildsRepo: workflowBuildsRepo,
	}
}

// ExchangeURL returns an authed URL for step logs in AZP.
func (s *Service) ExchangeURL(ctx context.Context, req *ExchangeURLRequest) (*ExchangeURLResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	obs.StartCheckpoint(observability.ExchangeURLCheckpoint)

	ctx = ctxstash.WithFields(
		ctx,
		kvp.String("gh.repo.global_id", req.GetRepositoryId().GetGlobalId()),
		kvp.String("gh.launch.resource_type", req.GetResourceType().String()),
		kvp.String("gh.launch.unauthenticated_url", req.GetUnauthenticatedUrl()),
	)
	mw.TagStatsWith(ctx, reqmeta.Tags{
		"status":        "unknown",
		"resource_type": getResourceTypeKey(req.GetResourceType()),
	})
	defer logExchangeURLLatency(ctx, obs, req.GetResourceType())

	if req == nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "missing_request"})
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("missing request"))
	}

	if err := req.Validate(); err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "invalid_request"})
		obs.Error(ctx, err.Error())
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError(err.Error()))
	}

	brs, err := s.resourceRepo.TryGet(ctx, types.IdentityToGlobalID(ctx, req.RepositoryId))
	if err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "get_repository"})
		obs.Report(ctx, err)
		return nil, tracing.RecordError(span, svcerr.NewInternalError("error getting backing resources"))
	}

	repoClient := s.repoClientFactory.ClientFromResources(ctx, brs)

	// TODO remove this temporary fix
	url := strings.Replace(req.UnauthenticatedUrl, "expands", "expand", 1)
	res, err := repoClient.GetAuthenticatedURL(ctx, url)
	if err != nil {
		clientError := strconv.FormatBool(isClientError(err))
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "get_authenticated_url", "client_error": clientError})
		azpErr := azperrors.GetAZPError(err)
		isRunNotFoundException := azpErr != nil && azpErr.ExceptionType == azperrors.RunNotFoundException
		if !isRunNotFoundException {
			obs.Report(ctx, err)
		}

		if azpErr != nil {
			if azpErr.StatusCode == http.StatusNotFound {
				return nil, tracing.RecordError(span, svcerr.NewNotFoundError("error fetching authenticated url"))
			}
		}

		return nil, tracing.RecordError(span, svcerr.NewInternalError("error fetching authenticated url"))
	}

	expiresAt := timestamppb.New(res.SignedContent.SignatureExpires)

	mw.TagStatsWith(ctx, reqmeta.Tags{"status": "success"})
	return &ExchangeURLResponse{
		AuthenticatedUrl: res.SignedContent.URL,
		ExpiresAt:        expiresAt,
	}, nil
}

func (s *Service) DeleteArtifact(ctx context.Context, req *DeleteArtifactRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	obs.StartCheckpoint(observability.DeleteArtifactCheckpoint)
	defer logDeleteArtifactLatency(ctx, obs)

	mw.TagStatsWith(ctx, reqmeta.Tags{
		"status": "unknown",
	})

	if req == nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "missing_request"})
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("missing request"))
	}

	repoID := types.IdentityToGlobalID(ctx, req.GetRepositoryId())
	executionID := req.GetExecutionId()
	externalBuildID := ""

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.launch.artifact_name", req.GetArtifactName()),
		kvp.String("gh.check_suite.global_id", types.IdentityToGlobalID(ctx, req.GetCheckSuiteId()).String()),
		kvp.String("gh.repo.owner.global_id", repoID.String()),
		kvp.String("gh.launch.execution_id", executionID),
	)

	if repoID == types.NilGlobalID || executionID == "" {
		if req.GetCheckSuiteId() == nil {
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "missing_check_suite_id"})
			return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("missing check suite id"))
		}

		wb, ok, err := s.workflowBuildsRepo.GetWorkflowBuildStateByCheckSuiteID(ctx, types.IdentityToGlobalID(ctx, req.GetCheckSuiteId()))
		if err != nil {
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "get_workflow_build_state"})
			obs.Report(ctx, err)
			return nil, tracing.RecordError(span, svcerr.NewInternalError("error fetching workflow build state"))
		}
		if !ok {
			err = tracing.RecordError(span, svcerr.NewNotFoundError("no build state found for check suite"))
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "get_workflow_build_state"})
			obs.Report(ctx, err)
			return nil, err
		}

		repoID = wb.RepositoryID
		externalBuildID = wb.ExternalBuildID
	}

	brs, err := s.resourceRepo.TryGet(ctx, repoID)
	if err != nil {
		if _, ok := errs.Cause(err).(*deployer.GetAzpResourcesError); ok {
			// no resources found indicate the repository was deleted (archived in azp_resources)
			// actions-service queues CleanAllArtifactsJob to delete all artifacts on RepositoryDeleted admin event so no extra calls are needed
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipping due to deleted repository"})
			return &empty.Empty{}, nil
		}

		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "get_resources"})
		obs.Report(ctx, err)
		return nil, tracing.RecordError(span, svcerr.NewInternalError("error getting backing resources"))
	}

	repoClient := s.repoClientFactory.ClientFromResources(ctx, brs)

	if externalBuildID != "" {
		err = repoClient.DeleteArtifact(ctx, externalBuildID, req.GetArtifactName())
	} else {
		err = repoClient.DeleteArtifactByPlanID(ctx, executionID, req.GetArtifactName())
	}
	if err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "delete_artifact"})
		obs.Report(ctx, err)
		return nil, tracing.RecordError(span, svcerr.NewInternalError("error deleting artifact"))
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{"status": "success"})
	return &empty.Empty{}, nil
}

func logDeleteArtifactLatency(ctx context.Context, obs *observability.Observability) {
	threshold := thresholds.DeleteArtifact

	_, err := obs.LogDuration(ctx, observability.DeleteArtifactCheckpoint, "delete_artifact", threshold, statter.Tags{})
	if err != nil {
		obs.Report(ctx, err)
	}
}

func logExchangeURLLatency(ctx context.Context, obs *observability.Observability, rt ResourceType) {
	threshold := thresholds.DefaultExchangeURL

	switch rt {
	case ResourceType_TYPE_COMPLETED_STEP_LOG:
		threshold = thresholds.ExchangeStepLogURL
	case ResourceType_TYPE_COMPLETED_JOB_LOG:
		threshold = thresholds.ExchangeJobLogURL
	}

	_, err := obs.LogDuration(ctx, observability.ExchangeURLCheckpoint, "exchange_url", threshold, statter.Tags{})
	if err != nil {
		obs.Report(ctx, err)
	}
}

func (s *Service) DeleteBuildLogs(ctx context.Context, req *DeleteBuildLogsRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	obs.StartCheckpoint(observability.DeleteBuildLogsCheckpoint)
	defer logDeleteBuildLogsLatency(ctx, obs)

	mw.TagStatsWith(ctx, reqmeta.Tags{
		"status": "unknown",
	})

	if req == nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "missing_request"})
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("missing request"))
	}

	repoID := types.IdentityToGlobalID(ctx, req.GetRepositoryId())
	executionID := req.GetExecutionId()
	externalBuildID := ""

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.check_suite.global_id", types.IdentityToGlobalID(ctx, req.GetCheckSuiteId()).String()),
		kvp.String("gh.repo.owner.global_id", repoID.String()),
		kvp.String("gh.launch.execution_id", executionID),
	)

	// track down why we're missing arguments
	s.log.Debug(ctx, "deleting build logs")

	if repoID == types.NilGlobalID || executionID == "" {
		if req.GetCheckSuiteId() == nil {
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "missing_check_suite_id"})
			return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("missing check suite id"))
		}

		wb, ok, err := s.workflowBuildsRepo.GetWorkflowBuildStateByCheckSuiteID(ctx, types.IdentityToGlobalID(ctx, req.GetCheckSuiteId()))
		if err != nil {
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "get_workflow_build_state"})
			obs.Report(ctx, err)
			return nil, tracing.RecordError(span, svcerr.NewInternalError("error fetching workflow build state"))
		}
		if !ok {
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "get_workflow_build_state"})
			return nil, tracing.RecordError(span, svcerr.NewInternalError("no workflow build state found"))
		}

		if wb.ExternalBuildID == "" {
			obs.Debug(ctx, "No external build id found, job was never queued, no logs to delete")
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipped"})
			return &empty.Empty{}, nil
		}

		repoID = wb.RepositoryID
		externalBuildID = wb.ExternalBuildID
	}

	brs, err := s.resourceRepo.TryGet(ctx, repoID)
	if err != nil {
		if _, ok := errs.Cause(err).(*deployer.GetAzpResourcesError); ok {
			// no resources found indicate the repository was deleted (archived in azp_resources)
			// actions-service queues ServiceHostSyncJob to delete all logs on RepositoryDeleted admin event so no extra calls are needed
			mw.TagStatsWith(ctx, reqmeta.Tags{"status": "skipping due to deleted repository"})
			return &empty.Empty{}, nil
		}

		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "get_resources"})
		obs.Report(ctx, err)
		return nil, tracing.RecordError(span, svcerr.NewInternalError("error getting backing resources"))
	}

	repoClient := s.repoClientFactory.ClientFromResources(ctx, brs)

	if externalBuildID != "" {
		err = repoClient.DeleteLogs(ctx, externalBuildID)
	} else {
		err = repoClient.DeleteLogsByPlanID(ctx, executionID)
	}
	if err != nil {
		mw.TagStatsWith(ctx, reqmeta.Tags{"status": "error", "error_type": "delete_build_logs"})
		obs.Report(ctx, err)
		return nil, tracing.RecordError(span, svcerr.NewInternalError("error deleting build logs"))
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{"status": "success"})
	return &empty.Empty{}, nil
}

func logDeleteBuildLogsLatency(ctx context.Context, obs *observability.Observability) {
	threshold := thresholds.DeleteBuildLogs

	_, err := obs.LogDuration(ctx, observability.DeleteBuildLogsCheckpoint, "delete_build_logs", threshold, statter.Tags{})
	if err != nil {
		obs.Report(ctx, err)
	}
}

func getResourceTypeKey(resourceType ResourceType) string {
	rt, ok := resourceTypeStringMap[resourceType]
	if !ok {
		return "unknown"
	}

	return rt
}

func isClientError(err error) bool {
	azpErr := azperrors.GetAZPError(err)
	if azpErr != nil {
		return azpErr.StatusCode >= 400 && azpErr.StatusCode <= 499
	}

	return false
}
