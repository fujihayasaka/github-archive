package selfhostedrunners

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
)

func (s *service) getOwnerGlobalIDFromListRequest(ctx context.Context, req *ListRunnersRequest) types.GlobalID {
	// ListRunnersRequest.RepositoryId is legacy, the global id can represent a repo, org, or enterprise
	// Should be renamed as OwnerGlobalID
	return types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
}

// ListRunnersV2 returns a list of runners
func (s *service) ListRunnersV2(ctx context.Context, req *ListRunnersRequest) (*ListRunnersResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "listrunnersv2")

	oid := s.getOwnerGlobalIDFromListRequest(ctx, req)
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.launch.owner.global_id", oid.String()),
		kvp.Int64("gh.launch.page", req.GetPage()),
		kvp.Int64("gh.launch.per_page", req.GetPerPage()))

	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for ListRunnersV2 lookup")
			return &ListRunnersResponse{Runners: make([]*Runner, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	includeAssignedRequest := req.GetIncludeAssignedRequest()

	azpRunners, total, err := arc.ListRunnersV2(ctx, req.GetPage(), req.GetPerPage(), includeAssignedRequest, req.GetPoolId(), req.GetName(), req.GetExcludeElasticRunners())
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	var rs []*Runner
	if !includeAssignedRequest {
		rs = MapDetailedAzpRunners(azpRunners)
		return &ListRunnersResponse{Runners: rs, TotalRunners: total}, nil
	}

	mapRunnersWithJobs := make(map[string]*Runner)
	var externalJobIDs []string

	for _, azpRunner := range azpRunners {
		r := ConvertDetailedRunnerFromAzp(azpRunner)
		if azpRunner.AssignedRequest != nil {
			externalJobID := azpRunner.GetExternalJobID()
			externalJobIDs = append(externalJobIDs, externalJobID)
			mapRunnersWithJobs[externalJobID] = r
		} else {
			rs = append(rs, r)
		}
	}

	mapCheckRunIds, err := s.jobsRepository.GetWorkflowJobsFromJobIds(ctx, externalJobIDs)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	for k, r := range mapRunnersWithJobs {
		if checkRunID, ok := mapCheckRunIds[k]; ok {
			r.AssignedRequest.CheckRunId = checkRunID
		}
		rs = append(rs, r)
	}

	return &ListRunnersResponse{Runners: rs, TotalRunners: total}, nil
}
