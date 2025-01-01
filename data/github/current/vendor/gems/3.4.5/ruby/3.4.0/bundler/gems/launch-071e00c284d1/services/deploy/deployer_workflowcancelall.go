package deploy

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/deploy/adminevents"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
)

var (
	errorMissingRepositoryID = svcerr.NewInvalidArgumentError("RepositoryId must be supplied")
)

func (s *service) WorkflowCancelAll(ctx context.Context, req *pb.WorkflowCancelAllRequest) (*pb.WorkflowCancelAllResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx = ctxstash.WithPopulatedFields(ctx,
		kvp.String("gh.repo.owner.name", req.Owner),
		kvp.String("gh.repo.name", req.Name),
		kvp.String("gh.launch.event.type", req.EventType),
	)

	s.cfg.Log.Debug(ctx, "WorkflowCancelAll called")

	var repoGID types.GlobalID
	var repoOwnerID types.GlobalID

	if req.RepositoryId == nil {
		s.cfg.Log.Error(ctx, errorMissingRepositoryID.Error(), kvp.Err(errorMissingRepositoryID))
		return nil, tracing.RecordError(span, errorMissingRepositoryID)
	}

	repoGID, err := s.GetGlobalIDFromIdentity(ctx, req.RepositoryId, "WorkflowCancelAll")
	if err != nil {
		s.cfg.Log.Error(ctx, "error calling GetGlobalIDFromIdentity", kvp.Err(err))
		return nil, tracing.RecordError(span, err)
	}

	if repoGID.IsZeroValue() {
		errMsg := "WorkflowCancelAll req parameter must contain a valid WorkflowCancelAllRequest::RepositoryId::GlobalID"
		err = errors.New(errMsg)
		s.cfg.Log.Error(ctx, errMsg, kvp.String("gh.repo.global_id", req.RepositoryId.GlobalId), kvp.Err(err))
		return nil, tracing.RecordError(span, err)
	}

	if repoOwnerID.IsZeroValue() && req.EventType == adminevents.RepositoryTransferred {
		s.cfg.Log.Log(ctx, "detected repository transfer", kvp.String("gh.repo.global_id", repoGID.String()))
		_, repoDatabaseID, err := repoGID.Decode()
		if err != nil {
			s.cfg.Log.Error(ctx, "failed to extract databaseID from GlobalID", kvp.String("gh.repo.global_id", repoGID.String()), kvp.Err(err))
			return nil, tracing.RecordError(span, err)
		}
		repoOwners, err := s.cfg.GithubTwirpClient.GetRepositoryOwners(ctx, repoDatabaseID)
		if err != nil {
			s.cfg.Log.Error(ctx, "failed to lookup repo ownership information",
				kvp.String("gh.repo.global_id", repoGID.String()),
				kvp.Int64("gh.repo.id", repoDatabaseID),
				kvp.Err(err))
			return nil, tracing.RecordError(span, err)
		}
		repoOwnerID = repoOwners.Owner.GlobalID
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", repoGID.String()),
	)

	data := map[string]string{
		"repo_global_id": repoGID.String(),
	}

	if req.EventType == adminevents.RepositoryTransferred {
		ctx = ctxstash.WithFields(ctx,
			kvp.String("gh.repo.owner.global_id", repoOwnerID.String()),
		)
		s.cfg.Log.Debug(ctx, "reporting repo admin event (with repo owner) to cancel all workflows in the repository")
		data["repo_owner_global_id"] = repoOwnerID.String()
	} else {
		s.cfg.Log.Debug(ctx, "reporting repo admin event to cancel all workflows in the repository")
	}

	s.cfg.Log.Debug(ctx, "WorkflowCancelAll is ready to call ReportRepoAdminEvent")
	err = s.cfg.AdminEventsReporter.ReportRepoAdminEvent(ctx, repoGID, req.EventType, data)
	if err != nil {
		s.cfg.Log.Report(ctx, errors.Wrap(err, "error in cancelling all workflows"))
		return nil, tracing.RecordError(span, svcerr.NewInternalError("attempting to cancel all workflows for repository, %v", err))
	}

	s.cfg.Log.Log(ctx, "successfully reported admin event to cancel all workflows for repository")
	return &pb.WorkflowCancelAllResponse{}, nil
}

func (s *service) WorkflowCancelAllForNonOwnerRepos(ctx context.Context, req *pb.WorkflowCancelAllForNonOwnerReposRequest) (*pb.WorkflowCancelAllForNonOwnerReposResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	actorGID, err := s.GetGlobalIDFromIdentity(ctx, req.ActorGlobalId, "WorkflowCancelAllForNonOwnerRepos")
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	// query all repositories
	s.cfg.Log.Debug(ctx, "attempting to get all repositories for the actor",
		kvp.String("gh.actor.global_id", actorGID.String()),
		kvp.Int64("gh.actor.id", req.ActorId),
	)
	repositories, err := s.cfg.GithubTwirpClient.GetRepositories(ctx, req.ActorId)
	if err != nil {
		s.cfg.Log.Report(ctx, err)
		if terrors.IsNotFoundError(err) {
			return nil, tracing.RecordError(span, svcerr.NewNotFoundError("error loading repositories for actor, %v", err))
		}

		return nil, tracing.RecordError(span, svcerr.NewInternalError("error loading repositories for actor, %v", err))
	}

	excludeRepoIDs := make([]types.GlobalID, 0, len(repositories))
	for _, repo := range repositories {
		excludeRepoIDs = append(excludeRepoIDs, types.NewGlobalID(ctx, repo.GlobalRelayId))
	}

	s.cfg.Log.Debug(ctx, "attempting to cancel all workflows for actor excluding owned repos",
		kvp.String("gh.actor.global_id", actorGID.String()),
		kvp.Int64("gh.actor.id", req.ActorId),
		kvp.String("gh.launch.workflow_cancellation_reason", req.Data),
	)
	workflowCount, err := s.cfg.WorkflowCanceler.CancelAllWorkflowsForActorIDExludeRepoIDs(ctx, actorGID, excludeRepoIDs)
	if err != nil {
		// Make sure the text of the error we pass to Log.Report is consistent so that Sentry can effectively de-duplicate it.
		msg := "error attempting to cancel all workflows for actor"
		s.cfg.Log.Report(ctx, errors.New(msg), kvp.Err(err))
		return nil, tracing.RecordError(span, svcerr.NewInternalError("%v: %v", msg, err))
	}

	resp := &pb.WorkflowCancelAllForNonOwnerReposResponse{
		WorkflowCount: workflowCount,
	}
	return resp, nil
}
