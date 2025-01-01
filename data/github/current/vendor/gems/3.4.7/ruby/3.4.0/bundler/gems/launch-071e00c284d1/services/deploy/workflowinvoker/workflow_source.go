package workflowinvoker

import (
	"context"
	"encoding/hex"
	"fmt"
	"strconv"

	"github.com/google/uuid"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/go-kvp"
	"github.com/github/go-log"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	ghclient "github.com/github/launch/clients/github"
	spokesd "github.com/github/launch/clients/spokesd"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/model"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	ghactions "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/types"
	launcherror "github.com/github/launch/types/errors"
	terrors "github.com/github/launch/types/errors"

	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowparser"

	blobs "github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	sTypes "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

const (
	// common error message to cover all the not found case
	// this message hides the internal error message
	workflowNotFoundErrorMessage = "workflow was not found."
)

type CallerRepo struct {
	NWO        types.RepositoryFullName
	RepoID     types.GlobalID
	DatabaseID uint64
	Ref        string
	SHA        string
}

type RepositoryMetadataResolver interface {
	// It is acceptable to pass NilGlobalID for ownerID.  Implementors of this interface should be able to compensate for the omission.
	GetRepoMetadataFromGlobalID(ctx context.Context, ownerID, repoID types.GlobalID) (*workflowparser.RepositoryMetadata, error)
}

type repositoryMetadataResolver struct {
	azpResourcesRepo deployer.AzpResourcesRepository
	ghClientFactory  github.Factory
	callerPlanOwner  types.GlobalID

	log log.FieldLogger
}

func NewRepositoryMetadataResolver(ghClientFactory github.Factory, azpResourcesRepo deployer.AzpResourcesRepository, callerPlanOwner types.GlobalID, log log.FieldLogger) RepositoryMetadataResolver {
	return &repositoryMetadataResolver{
		azpResourcesRepo: azpResourcesRepo,
		ghClientFactory:  ghClientFactory,
		callerPlanOwner:  callerPlanOwner,
		log:              log,
	}
}

func (rir *repositoryMetadataResolver) GetRepoMetadataFromGlobalID(ctx context.Context, ownerID types.GlobalID, repoID types.GlobalID) (*workflowparser.RepositoryMetadata, error) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.repo.owner.global_id", ownerID.String()),
		attribute.String("gh.repo.global_id", repoID.String()),
		attribute.String("gh.launch.calling_plan.owner", rir.callerPlanOwner.String()),
	))
	defer span.End()

	kvs := append(ctxstash.From(ctx).Fields(),
		kvp.String("gh.repo.owner.global_id", ownerID.String()),
		kvp.String("gh.repo.global_id", repoID.String()),
		kvp.String("gh.launch.calling_plan.owner", rir.callerPlanOwner.String()),
	)
	ll := rir.log.With(kvs...)

	// Leverage NewClientForRepositoryOwner as a way to maximize our chances of reusing an existing token.
	// That's more important than adhering to least privilege in this tightly-scoped (fleeting client instance) scenario.
	ghRepoClient, err := rir.ghClientFactory.NewClientForRepositoryOwner(ctx, repoID, ownerID)
	if err != nil {
		errMsg := "error creating github client from GlobalID(s)"
		err = errors.Wrap(err, errMsg)
		ll.Error(errMsg, kvp.Err(err))
		return nil, err
	}
	ll.Info("resolving repository info from repoID")
	info, err := ghRepoClient.RepositoryInfoFromID(ctx, repoID)
	if err != nil {
		errMsg := "error getting repository info"
		err = errors.Wrap(err, errMsg)
		ll.Error(errMsg, kvp.Err(err))
		return nil, err
	}
	return rir.getRepoMetadataFromAZPResourceRepo(ctx, ll, info)
}

func (rir *repositoryMetadataResolver) getRepoMetadataFromAZPResourceRepo(ctx context.Context, ll log.FieldLogger, info *github.BasicRepositoryInfo) (*workflowparser.RepositoryMetadata, error) {
	ll.Info("resolving azp resource info from repository ID")
	res, err := rir.azpResourcesRepo.TryGet(ctx, info.ID)
	if err != nil {
		// if we get a GetAzpResourcesError then for the
		// centrally-managed-workflow private beta default to a null
		// TenantID (UUID)
		//
		// We will address this more thoroughly as part of enabling restriction
		// of callable workflows to specific runner groups in
		// github/c2c-actions#3123
		var azpResourceErr *deployer.GetAzpResourcesError
		if errors.As(err, &azpResourceErr) {
			res = &azptypes.BackingResources{
				CreationResult: azptypes.CreationResult{
					TenantID: "00000000-0000-0000-0000-000000000000",
				},
			}
		} else {
			return nil, errors.Wrap(err, "error getting repository azp resource")
		}
	}

	// We trust any workflow that comes from a repository that has the same ActionsPlanOwner as
	// the repo that the calling workflow has. This is equivalent to checking whether the repo is
	// in the same enterprise (if on an enterprise plan), the same org (if a non-enterprise org),
	// or the same user.
	trusted := info.PlanOwner.ID.IsEquivalent(rir.callerPlanOwner)
	return &workflowparser.RepositoryMetadata{
		TenantID: res.TenantID,
		RepositoryNWO: types.RepositoryFullName{
			Owner: info.Owner.Name,
			Name:  info.Name,
		},
		RepositoryID:         info.ID,
		RepositoryDatabaseID: info.DatabaseID,
		IsTrusted:            trusted,
		PlanOwnerID:          info.PlanOwner.ID,
	}, nil
}

// WorkflowSourceFactory is a factory for creating WorkflowSource instances.
// Specify an existing check suite ID and previous plan ID to resolve reusable workflow refs (if any)
// to commit SHAs, using the previous run attempt info.
type WorkflowSourceFactory interface {
	Build(ctx context.Context, repositoryMetadataResolver RepositoryMetadataResolver, callerRepo *CallerRepo, invokingEvent *InvokingEvent, existingCheckSuiteID types.GlobalID, previousPlanID uuid.UUID) workflowparser.WorkflowSource
}

type NullWorkflowSourceFactory struct{}

func (NullWorkflowSourceFactory) Build(_ context.Context, _ RepositoryMetadataResolver, _ *CallerRepo, _ *InvokingEvent, _ types.GlobalID, _ uuid.UUID) workflowparser.WorkflowSource {
	return workflowparser.NullWorkflowSource{}
}

type spokesdWorkflowSourceFactory struct {
	authzclient   authzd.Client
	spokesdclient spokesd.Client
	ghTwirpClient ghtwirp.Client
	log           log.FieldLogger
	obs           *observability.Observability
}

func SpokesdWorkflowSourceFactory(authzclient authzd.Client, spokesdclient spokesd.Client, ghTwirpClient ghtwirp.Client, log log.FieldLogger, obs *observability.Observability) WorkflowSourceFactory {
	return &spokesdWorkflowSourceFactory{authzclient: authzclient, spokesdclient: spokesdclient, ghTwirpClient: ghTwirpClient, log: log, obs: obs}
}

func (swsf *spokesdWorkflowSourceFactory) Build(_ context.Context, repoRes RepositoryMetadataResolver, callerRepo *CallerRepo, event *InvokingEvent, existingCheckSuiteID types.GlobalID, previousPlanID uuid.UUID) workflowparser.WorkflowSource {
	return &spokesdWorkflowSource{
		authzclient:          swsf.authzclient,
		spokesdclient:        swsf.spokesdclient,
		ghTwirpClient:        swsf.ghTwirpClient,
		initialCallerRepo:    callerRepo,
		callerRepo:           callerRepo,
		event:                event,
		repoMetadataResolver: repoRes,
		existingCheckSuiteID: existingCheckSuiteID,
		previousPlanID:       previousPlanID,
		log:                  swsf.log,
		obs:                  swsf.obs,
	}
}

type spokesdWorkflowSource struct {
	authzclient   authzd.Client
	spokesdclient spokesd.Client
	ghTwirpClient ghtwirp.Client
	// initialCallerRepo is the caller repository where the workflow run is being executed
	// callerRepo is the direct caller of the called workflow
	// in the nested workflow scenario, as the reusable workflows are nested, the initial caller and (direct) caller can be different.
	// for example, in the chain of A->B->C, A is the initial caller of C and B is the direct caller of C.
	initialCallerRepo    *CallerRepo
	callerRepo           *CallerRepo
	event                *InvokingEvent
	repoMetadataResolver RepositoryMetadataResolver

	// ExistingCheckSuiteID is used to resolve workflow refs to the same commit SHAs, across partial re-run attempts.
	existingCheckSuiteID types.GlobalID

	// PreviousPlanID is used to resolve workflow refs to the same commit SHAs, across partial re-run attempts.
	previousPlanID uuid.UUID

	// PreviousReferencedWorkflows is used to resolve workflow refs to the same commit SHAs, across partial re-run attempts.
	// Workflow refs using branches/tags syntax should match the original attempt.
	//
	// The lookup key matches the "path" field.
	//
	// Example workflow ref using branch/tag syntax, e.g. "contoso/templates/.github/workflows/deploy.yml@v1"
	//   {
	//     "path": "contoso/templates/.github/workflows/deploy.yml@v1",
	//     "sha": "1234567890123456789012345678901234567890",
	//     "ref": "refs/heads/v1"
	//   }
	//
	// Example workflow ref using local-syntax, e.g. "./.github/workflows/deploy.yml"
	//   {
	//     "path": "contoso/my-app/.github/workflows/deploy.yml@1234567890123456789012345678901234567890",
	//     "sha": "1234567890123456789012345678901234567890",
	//     "ref": "refs/heads/main"
	//   }
	//
	// Example workflow ref using SHA syntax, e.g. "contoso/templates/.github/workflows/deploy.yml@1234567890123456789012345678901234567890"
	//   {
	//     "path": "contoso/templates/.github/workflows/deploy.yml@1234567890123456789012345678901234567890",
	//     "sha": "1234567890123456789012345678901234567890"
	//   }
	previousReferencedWorkflows map[string]workflowparser.ReferencedWorkflow

	log log.FieldLogger
	obs *observability.Observability
}

func (sws *spokesdWorkflowSource) SetCallerRepo(repoID types.GlobalID, nwo types.RepositoryFullName, callerRef string, callerSHA string) {
	sws.callerRepo = &CallerRepo{
		NWO:    nwo,
		RepoID: repoID,
		Ref:    callerRef,
		SHA:    callerSHA,
	}
}

func (sws *spokesdWorkflowSource) LoadPreviousRunAttemptInfo(ctx context.Context) error {
	if sws.previousReferencedWorkflows == nil && sws.existingCheckSuiteID != types.NilGlobalID {
		sws.obs.Log(ctx, "Getting previous attempt workflow run execution")
		response, err := sws.ghTwirpClient.GetWorkflowRunExecution(ctx, sws.existingCheckSuiteID, sws.previousPlanID)
		if err != nil {
			sws.obs.Error(ctx, "Failed to get previous workflow run execution", kvp.Err(err))
			return err
		}

		rws := make(map[string]workflowparser.ReferencedWorkflow)
		for _, referencedWorkflow := range response.ReferencedWorkflows {
			rws[referencedWorkflow.Path] = referencedWorkflow
		}
		sws.previousReferencedWorkflows = rws
	}

	return nil
}

func (sws *spokesdWorkflowSource) Clone() workflowparser.WorkflowSource {
	clonedWfs := *sws
	return &clonedWfs
}

func looksLikeCommitSHA(ref string) bool {
	if len(ref) != 40 {
		return false
	}

	// decode the ref
	_, err := hex.DecodeString(ref)

	return err == nil
}
func (sws *spokesdWorkflowSource) GetCallerRepoMetadata(ctx context.Context) (*workflowparser.RepositoryMetadata, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	kvs := append(ctxstash.From(ctx).Fields(),
		kvp.Uint64("gh.launch.initial_caller.id", sws.initialCallerRepo.DatabaseID),
	)

	ll := sws.log.With(kvs...)

	return sws.getRepoMetadata(ctx, ll, sws.callerRepo)
}

func (sws *spokesdWorkflowSource) GetWorkflowFile(ctx context.Context, wfRef model.WorkflowRef, callerRepoMetadata *workflowparser.RepositoryMetadata, actorID int64) (*types.ResolvedFile, *workflowparser.RepositoryMetadata, bool, error) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.launch.called_owner", wfRef.Owner),
		attribute.String("gh.launch.called_repo", wfRef.Repo),
		attribute.String("gh.launch.called_path", wfRef.Path),
		attribute.String("gh.launch.called_repo.version", wfRef.Version.String()),
		attribute.String("gh.launch.initial_caller.id", strconv.FormatUint(sws.initialCallerRepo.DatabaseID, 10)),
	))
	defer span.End()

	kvs := append(ctxstash.From(ctx).Fields(),
		kvp.String("gh.launch.called_owner", wfRef.Owner),
		kvp.String("gh.launch.called_repo", wfRef.Repo),
		kvp.String("gh.launch.called_path", wfRef.Path),
		kvp.String("gh.launch.called_repo.version", wfRef.Version.String()),
		kvp.Uint64("gh.launch.initial_caller.id", sws.initialCallerRepo.DatabaseID),
	)

	ll := sws.log.With(kvs...)

	if sws.callerRepo.RepoID.IsZeroValue() {
		ll.Error("CallerRepo.RepoID was not initialized",
			kvp.String("gh.launch.caller.repo.global_id", callerRepoMetadata.RepositoryID.String()))
		sws.callerRepo.RepoID = callerRepoMetadata.RepositoryID
	}
	if sws.callerRepo.NWO.IsBlank() {
		ll.Error("CallerRepo.NWO was not initialized",
			kvp.String("gh.launch.caller.owner", callerRepoMetadata.RepositoryNWO.Owner),
			kvp.String("gh.launch.caller.repo.name", callerRepoMetadata.RepositoryNWO.Name))
		sws.callerRepo.NWO = callerRepoMetadata.RepositoryNWO
	}
	ll = ll.With(
		kvp.String("gh.launch.caller.repo.global_id", sws.callerRepo.RepoID.String()),
		kvp.String("gh.launch.caller.owner", sws.callerRepo.NWO.Owner),
		kvp.String("gh.launch.caller.repo.name", sws.callerRepo.NWO.Name),
	)

	// localRef is the ref for file metadata (e.g. refs/heads/main)
	var localRef string
	var calledRepoMetadata *workflowparser.RepositoryMetadata

	// if the caller repo is the same as the called repo
	if sws.calledInSameRepo(wfRef) {
		if wfRef.IsDotNWO() {
			wfRef.Owner = sws.callerRepo.NWO.Owner
			wfRef.Repo = sws.callerRepo.NWO.Name

			if wfRef.Version.String() == "" {
				wfRef.Version.GitRef = &sws.callerRepo.SHA
				localRef = sws.callerRepo.Ref
			}
		}

		ll.Info("using local workflow")
		calledRepoMetadata = callerRepoMetadata
	} else {
		ll.Info("retrieving called repo's metadata")
		var (
			err        error
			permission bool
		)

		calledRepo, err := sws.findRepositoryByName(ctx, wfRef.GetNWO())
		if err != nil {
			// Did we receive a NotFoundError?
			_, isNotFoundError := err.(*terrors.NotFoundError)
			if isNotFoundError {
				// When called repo doesn't exist, treat this as "workflow not found"
				ll.Info("Could not find called repo.  Analogous to 'workflow not found'.", kvp.Err(err))
				return nil, nil, false, nil
			}
			ll.Error("error while fetching repo ownership info", kvp.Err(err))
			return nil, nil, false, terrors.NewInternalError(errors.Wrap(err, "error while fetching repo ownership info"))
		}
		calledRepoMetadata, err = sws.repoMetadataResolver.GetRepoMetadataFromGlobalID(ctx, types.NilGlobalID, types.NewGlobalID(ctx, calledRepo.GlobalRelayId))
		if err != nil {
			ll.Error("error while fetching repo metadata", kvp.Err(err))
			return nil, nil, false, terrors.NewInternalError(errors.Wrap(err, "error while fetching repo metadata"))
		}

		// validate actor permission
		if sws.initialCallerRepo.DatabaseID == 0 {
			return nil, nil, false, terrors.NewInternalError(errors.New("initial caller id should not be empty"))
		}

		skipRedirect := sws.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, ghclient.ExcludeCalledWorkflowsFromRedirectedRepositoriesFlag, calledRepoMetadata.RepositoryID)
		if !calledRepoMetadata.RepositoryNWO.IsEqual(wfRef.GetNWO()) {
			ll.Info("called repo metadata and referenced workflow don't match", kvp.Any("gh.launch.called_repo.metadata.nwo", calledRepoMetadata.RepositoryNWO), kvp.Any("gh.launch.workflow_ref.nwo", wfRef.GetNWO()))
			if skipRedirect {
				return nil, nil, false, terrors.NewNotFoundError(errors.New("reference to workflow cannot use redirected repository name"))
			}
		}

		ll.Info("verifying if the initial caller has access to called repository", kvp.Uint64("gh.launch.called_repo.id", calledRepoMetadata.RepositoryDatabaseID))
		permission, err = sws.authzclient.Authorize(ctx, sws.initialCallerRepo.DatabaseID, calledRepoMetadata.RepositoryDatabaseID)
		if err != nil {
			if launcherror.IsNotFoundError(err) {
				ll.Info("request to validating actor permission returned not found error")
				return nil, nil, false, terrors.NewNotFoundError(errors.New(workflowNotFoundErrorMessage))
			}
			return nil, nil, false, terrors.NewInternalError(errors.Wrap(err, "validating actor permission"))
		}
		if !permission {
			ll.Info("access denied: initial caller doesn't have permission to access the called repository")
			// Hiding explicitly information about the called repository from the user because it could be
			// used to determine if an private/internal repository exists or not.
			// Using same error message as for workflowfile not found which will be triggered by not returning an error here.
			sws.obs.Counter(ctx, metrickeys.CallerWorkflowAuthzdAccess, statter.Tags{"result": "denied"}, 1)
			return nil, nil, false, nil
		}
		sws.obs.Counter(ctx, metrickeys.CallerWorkflowAuthzdAccess, statter.Tags{"result": "accepted"}, 1)
	}

	if wfRef.Version.GitRef == nil {
		return nil, nil, false, terrors.NewNotFoundError(errors.New("workflow version not provided"))
	}
	calledRepo := sTypes.NewRepository(calledRepoMetadata.RepositoryDatabaseID)

	// Fetch when its not local ref, because local ref always have caller commit SHA
	if localRef == "" {
		resolvedFile, ok, isRefResolved, err := sws.getWorkflowFileUsingGitRef(ctx, ll, wfRef, calledRepo, actorID)
		if err != nil {
			return nil, nil, false, err
		}
		if ok && resolvedFile != nil {
			return resolvedFile, calledRepoMetadata, true, nil
		}

		if !looksLikeCommitSHA(*wfRef.Version.GitRef) {
			var msg string
			if isRefResolved {
				ll.Info("workflow file not found with given ref in the called repo and the ref doesn't look like a commit SHA either")
				msg = workflowNotFoundErrorMessage
			} else {
				ll.Info("given ref could not be resolved in the called repo and the ref doesn't look like a commit SHA either")
				msg = "reference to workflow should be either a valid branch, tag, or commit"
			}

			return nil, nil, false, terrors.NewNotFoundError(errors.New(msg))
		}
	}

	ll.Info("workflow version looks like a commit SHA")
	resolvedFile, ok, err := sws.getWorkflowFileUsingCommitSHA(ctx, ll, wfRef, calledRepo, localRef, actorID)
	if err != nil {
		return nil, nil, false, err
	}
	if ok && resolvedFile != nil {
		return resolvedFile, calledRepoMetadata, true, nil
	}
	return nil, nil, false, nil
}

func (sws *spokesdWorkflowSource) resolveSHAFromRef(ctx context.Context, repo *sTypes.Repository, ref string, actorID int64) (string, error) {

	objReq := objects.NewResolveObjectRequest(
		newSpokesdRequestContext(sTypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST, actorID),
		repo,
		sTypes.NewRevision([]byte(ref)),
	)

	objRes, err := sws.spokesdclient.ResolveObject(ctx, objReq)
	if err != nil {
		return "", err
	}

	return objRes.Oid.Id, nil
}

type blob struct {
	Contents  string
	Size      uint64
	Truncated bool
}

func (sws *spokesdWorkflowSource) getWorkflowBySHA(ctx context.Context, repo *sTypes.Repository, sha string, path string, actorID int64) (blob, error) {

	blobReq := blobs.NewGetBlobContentsRequestByObjectIDPath(
		newSpokesdRequestContext(sTypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST, actorID),
		repo,
		sTypes.NewObjectID(sha),
		sTypes.NewPath([]byte(path)),
	)

	blobRes, err := sws.spokesdclient.GetBlobContents(ctx, blobReq)
	if err != nil {
		return blob{}, err
	}

	return blob{
		Contents:  string(blobRes.Contents),
		Size:      blobRes.Size,
		Truncated: blobRes.Truncated,
	}, nil
}

func (sws *spokesdWorkflowSource) getWorkflowFileUsingGitRef(ctx context.Context, ll log.FieldLogger, wfRef model.WorkflowRef, calledRepo *sTypes.Repository, actorID int64) (file *types.ResolvedFile, fileFound, refResolved bool, err error) {
	// Referenced workflow info from previous run attempt
	var previous *workflowparser.ReferencedWorkflow

	// Previous run attempt?
	if sws.existingCheckSuiteID != types.NilGlobalID {
		prev, ok := sws.previousReferencedWorkflows[wfRef.String()]
		if !ok {
			// Referenced workflow info not found
			err = errors.New("workflow ref not found in previous attempt referenced workflows")
			ll.Error(err.Error(), kvp.Err(err))
			return nil, false, false, err
		}

		ll.Info("resolved referenced workflow info from previous run attempt")
		previous = &prev
	}

	isRefResolved := false
	// the order should match what `git rev-parse` does, but
	// we only consider tags and branches:
	// -> https://git-scm.com/docs/git-rev-parse#_specifying_revisions
	refPrefix := []string{"refs/tags/", "refs/heads/"}
	for _, prefix := range refPrefix {
		ref := prefix + wfRef.Version.String()
		ll := ll.With(kvp.String("gh.launch.called_repo.ref", ref))
		var sha string
		if previous != nil && previous.Ref != ref {
			ll.Info("ref doesn't match previous attempt; skipping")
			continue
		} else if previous != nil {
			ll.Info("reusing sha from previous attempt")
			sha = previous.Sha
		} else {
			// Resolve the sha. This should come before fetching the file
			// so that we avoid race condition where sha changes
			// between fetching the file and resolving sha
			ll.Info("looking if called version refers to a ref")
			sha, err = sws.resolveSHAFromRef(ctx, calledRepo, ref, actorID)
			if err != nil {
				if launcherror.IsNotFoundError(err) {
					ll.Info("doesn't seem to be a ref of this type")
					continue
				}
				return nil, false, isRefResolved, terrors.NewInternalError(errors.Wrap(err, "resolving ref to sha"))
			}
		}

		ll = ll.With(kvp.String("gh.launch.called_repo.sha", sha))
		isRefResolved = true

		ll.Info("a ref with this name exists on the called repo, attempting to fetch a file at path for the ref's SHA")
		blob, err := sws.getWorkflowBySHA(ctx, calledRepo, sha, wfRef.Path, actorID)
		if err != nil {
			if launcherror.IsNotFoundError(err) {
				ll.Info("no file exists at this path for this ref's SHA")
				continue
			}
			return nil, false, isRefResolved, terrors.NewInternalError(errors.Wrap(err, "getting blob contents"))
		}

		ll.Info("workflow file found and retrieved")
		return &types.ResolvedFile{
			Path:          wfRef.String(),
			Text:          blob.Contents,
			Ref:           ref,
			SHA:           sha,
			IsTruncated:   blob.Truncated,
			RepositoryNwo: wfRef.GetNWO().String(),
		}, true, isRefResolved, nil
	}

	return nil, false, isRefResolved, nil
}

func (sws *spokesdWorkflowSource) getWorkflowFileUsingCommitSHA(ctx context.Context, ll log.FieldLogger, wfRef model.WorkflowRef, calledRepo *sTypes.Repository, localRef string, actorID int64) (*types.ResolvedFile, bool, error) {
	ll.Info("looking if it's actually a reachable commit")
	// check if the commit is reachable from the repo (i.e. not forked one)
	usingLocalRef := localRef != ""
	ok, err := sws.checkCommitReachability(ctx, calledRepo, *wfRef.Version.GitRef, usingLocalRef, actorID)
	if err != nil {
		if launcherror.IsNotFoundError(err) {
			ll.Info("checking commit reachability returned not found error")
			return nil, false, terrors.NewNotFoundError(errors.New(workflowNotFoundErrorMessage))
		}

		return nil, false, terrors.NewInternalError(errors.Wrap(err, "validating commit"))
	}
	if !ok {
		return nil, false, nil
	}

	ll = ll.With(kvp.Any("gh.launch.called_repo.sha", *wfRef.Version.GitRef))
	ll.Info("attempting to fetch a file at path for the commit SHA")
	blob, err := sws.getWorkflowBySHA(ctx, calledRepo, *wfRef.Version.GitRef, wfRef.Path, actorID)
	if err != nil {
		if launcherror.IsNotFoundError(err) {
			ll.Info("workflow was not found in the given commit SHA")
			return nil, false, terrors.NewNotFoundError(errors.New(workflowNotFoundErrorMessage))
		}

		return nil, false, terrors.NewInternalError(errors.Wrap(err, "getting blob contents"))
	}

	ll.Info("workflow file found and retrieved")
	return &types.ResolvedFile{
		Path:          wfRef.String(),
		Text:          blob.Contents,
		Ref:           localRef,
		SHA:           *wfRef.Version.GitRef,
		IsTruncated:   blob.Truncated,
		RepositoryNwo: wfRef.GetNWO().String(),
	}, true, nil
}

func (sws *spokesdWorkflowSource) checkCommitReachability(ctx context.Context, repo *sTypes.Repository, ref string, usingLocalRef bool, actorID int64) (bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	kvs := append(ctxstash.From(ctx).Fields(),
		kvp.String("gh.launch.called_repo.sha", ref),
	)
	ll := sws.log.With(kvs...)

	if usingLocalRef && sws.isUsingMergeCommit() {
		ll.Info("skipping commit reachability for merge commit due to local reference for PR event")
		return true, nil
	}

	commitsReq := commits.NewCheckCommitReachabilityRequestWithObjectIDSelector(
		newSpokesdRequestContext(sTypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST, actorID),
		repo,
		selectors.NewObjectIDSelector(sTypes.NewObjectID(ref)),
		nil,
	)
	commitsRes, err := sws.spokesdclient.CheckCommitReachability(ctx, commitsReq)
	if err != nil {
		return false, errors.Wrap(err, "checking commit reachability")
	}

	if len(commitsRes.Commits) != 1 {
		// when the ref is not reachable from the repo (ex. forked PR)
		ll.Info(fmt.Sprintf("ref should resolve to exactly one commit, resolved %d", len(commitsRes.Commits)))
		return false, nil
	}

	if commitsRes.Commits[0].Id != ref {
		ll.Info(fmt.Sprintf(
			"resolved commit does not match with ref, want %q got %q",
			ref, commitsRes.Commits[0].Id))
		return false, nil
	}

	ll.Info("commit is reachable in the called repo")
	return true, nil
}

func (sws *spokesdWorkflowSource) calledInSameRepo(wfRef model.WorkflowRef) bool {
	calledNWO := wfRef.GetNWO()
	return calledNWO.IsDotRepo() || calledNWO.IsEqual(sws.callerRepo.NWO)
}

func (sws *spokesdWorkflowSource) isUsingMergeCommit() bool {
	if sws.event == nil {
		return false
	}

	switch sws.event.Name {
	case flowevents.PullRequest, flowevents.PullRequestReview, flowevents.PullRequestReviewComment, flowevents.MergeGroup:
		return true
	default:
		return false
	}
}

func (sws *spokesdWorkflowSource) findRepositoryByName(ctx context.Context, nwo types.RepositoryFullName) (*ghactions.Repository, error) {
	kvs := []kvp.Field{kvp.String("gh.repo.name_with_owner", nwo.String())}
	ctx = ctxstash.WithFields(ctx, kvs...)
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ll := sws.log.With(kvs...)
	ll.Info("fetching repo info")
	repos, err := sws.ghTwirpClient.FindRepositoriesByName(ctx, []string{nwo.String()})
	if err != nil {
		ll.Error("error fetching repository info by NWO", kvp.Err(err))
		return nil, err
	}

	// If you ask FindRepositoriesByName to find n repos and it finds fewer than n,
	// it signals the shortfall via RepositoriesInfo::RepositoriesNotFoundErrorMessage (essentially, a 'soft' error)
	// In our case, n=1, so treat the shortfall as an outright failure.
	if len(repos.RepositoriesNotFoundErrorMessage) > 0 {
		err = terrors.NewNotFoundError(errors.New(repos.RepositoriesNotFoundErrorMessage))
		ll.Error("twirp API reported 'repo not found'", kvp.Err(err))
		return nil, err
	}

	if len(repos.Repositories) == 0 {
		err = errors.New("twirp FindRepositoriesByName returned an empty array")
		ll.Error(err.Error(), kvp.Err(err))
		return nil, err
	}

	if len(repos.Repositories) > 1 {
		msg := "twirp API returned several matches.  Ignoring all but the zeroeth match."
		ll.Info(msg, kvp.Int("gh.launch.matching_repos.count", len(repos.Repositories)))
	}

	return repos.Repositories[0], nil
}

func (sws *spokesdWorkflowSource) getRepoMetadata(ctx context.Context, ll log.FieldLogger, repo *CallerRepo) (*workflowparser.RepositoryMetadata, error) {

	repoMetadata, err := sws.repoMetadataResolver.GetRepoMetadataFromGlobalID(ctx, types.NilGlobalID, repo.RepoID)
	if err != nil {
		errMsg := "error resolving repository metadata from repo GlobalID"
		ll.Error(errMsg, kvp.Err(err))
		return nil, errors.Wrap(err, errMsg)
	}
	return repoMetadata, nil
}

func newSpokesdRequestContext(qos sTypes.RequestContext_QualityOfService, actorID int64) *sTypes.RequestContext {
	return sTypes.NewRequestContext(qos, sTypes.WithUserID(uint64(actorID)))
}
