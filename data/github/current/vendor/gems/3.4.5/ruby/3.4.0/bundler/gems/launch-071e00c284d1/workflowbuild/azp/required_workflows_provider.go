package azp

import (
	"context"
	"fmt"
	"strings"
	"sync"

	authzpb "github.com/github/authzd/pkg/proto"
	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/spokesd"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/requiredworkflowutils"

	stypes "github.com/github/spokes-proto/gen/go/v1/types"
)

type ResolvedObject struct {
	ObjectID  string
	Path      string
	Ref       string
	CommitOID string
}

type ResolveObjectsResult struct {
	Err               error
	RepoID            int64
	ResolvedObjects   []*ResolvedObject
	UnresolvedObjects []*ResolvedObject
}

type ResolvedObjectsByRepo struct {
	RepoID          int64
	ResolvedObjects []*ResolvedObject
}

type repository struct {
	ID  types.GlobalID
	Nwo string
}

const (
	// No of goroutines that will be spawned in parallel to resolve required workflows
	concurrentWorkers = 10
)

type RequiredWorkflowsProvider interface {
	// GetRequiredWorkflowFiles gets the workflow blobs of all the Required workflows
	// enforced by the organization on to the current repository. This endpoint
	// internally does the following:
	//
	// 1) Contact authz to filter out imposer repositories where the workflow
	//    sharing policy is restricted.
	// 2) Resolve the commitIDs of the referenced required workflows with the path
	//    and ref.
	// 3) Resolve the objectIDs of the files corresponding to the commitID and the
	//    path of the file.
	// 4) Resolve the actual blobs from the objectIDs retrieved in the previous step
	//    per repository.
	GetRequiredWorkflowFiles(ctx context.Context, requiredWorkflows []*ghtwirp.RequiredWorkflow, invokingEventName string, invokingRepoID int64, invokingActorID int64) []types.ResolvedFile
}

func NewRequiredWorkflowsProvider(spokesClient spokesd.Client, authzClient authzd.Client, obs *observability.Observability) RequiredWorkflowsProvider {
	return &requiredWorkflowsProvider{
		spokesClient: spokesClient,
		authzClient:  authzClient,
		obs:          obs,
	}
}

type requiredWorkflowsProvider struct {
	spokesClient spokesd.Client
	authzClient  authzd.Client
	obs          *observability.Observability
}

func (rwp *requiredWorkflowsProvider) GetRequiredWorkflowFiles(ctx context.Context, requiredWorkflows []*ghtwirp.RequiredWorkflow, invokingEventName string, invokingRepoID int64, invokingActorID int64) []types.ResolvedFile {
	if len(requiredWorkflows) == 0 {
		return nil
	}

	filteredRequiredWorkflows, err := rwp.filterAllowedRequiredWorkflows(ctx, requiredWorkflows, invokingRepoID)
	if err != nil {
		rwp.obs.Error(ctx, errors.Wrap(err, "couldn't filter required workflows").Error(), kvp.Int64("gh.repo.id", invokingRepoID), kvp.String("gh.launch.event.name", invokingEventName))
		return nil
	}

	if len(filteredRequiredWorkflows) == 0 {
		rwp.obs.Debug(ctx, "no required workflows filtered out", kvp.Int64("gh.repo.id", invokingRepoID), kvp.String("gh.launch.event.name", invokingEventName))
		return nil
	}

	return rwp.resolveWorkflowFiles(ctx, filteredRequiredWorkflows, invokingActorID)
}

// Filters required workflows based on the Authz policies setup in the source repo
// of the required workflows.
func (rwp *requiredWorkflowsProvider) filterAllowedRequiredWorkflows(ctx context.Context, requiredWorkflows []*ghtwirp.RequiredWorkflow, callerRepoID int64) ([]*ghtwirp.RequiredWorkflow, error) {
	allowedRequiredWorkflows := make([]*ghtwirp.RequiredWorkflow, 0)
	referencedRepos := make([]*authzd.RepositoryParam, 0)

	for _, reqWorkflow := range requiredWorkflows {
		referencedRepos = append(referencedRepos, &authzd.RepositoryParam{
			ID:   uint64(reqWorkflow.RepoDatabaseID),
			Name: reqWorkflow.RepoNwo,
		})
	}

	// TODO: Filter out public referenced repositories from this call.github/c2c-actions-ace#129
	authzDecision, err := rwp.authzClient.BatchAuthorize(ctx, uint64(callerRepoID), referencedRepos)
	if err != nil {
		return allowedRequiredWorkflows, err
	}

	isRepoAccessForbidden := make(map[int64]bool, 0)
	for i, decision := range authzDecision.Decisions {
		isRepoAccessForbidden[int64(referencedRepos[i].ID)] = decision.Result == authzpb.Result_DENY
	}

	forbiddenRepoIDs := make([]string, 0)
	for _, reqWorkflow := range requiredWorkflows {
		isAccessForbidden, ok := isRepoAccessForbidden[reqWorkflow.RepoDatabaseID]
		if !ok {
			return allowedRequiredWorkflows, errors.New("could not find repo access details")
		}

		if isAccessForbidden {
			forbiddenRepoIDs = append(forbiddenRepoIDs, reqWorkflow.RepoID.String())
			continue
		}

		allowedRequiredWorkflows = append(allowedRequiredWorkflows, reqWorkflow)
	}

	if len(forbiddenRepoIDs) > 0 {
		rwp.obs.Debug(ctx,
			"filtering some required workflows because of authz policy",
			kvp.Int64("gh.launch.caller.repo.id", callerRepoID),
			kvp.String("gh.launch.forbidden_repos.ids.csv", strings.Join(forbiddenRepoIDs, ",")),
		)
	}

	return allowedRequiredWorkflows, nil
}

// resolveWorkflowFiles groups the required workflows by their source repositories,
// creates the spokesd object identifier, and makes the request to get the blobs for each repo.
func (rwp *requiredWorkflowsProvider) resolveWorkflowFiles(ctx context.Context, requiredWorkflows []*ghtwirp.RequiredWorkflow, invokingActorID int64) []types.ResolvedFile {
	identifierByRepo := make(map[int64][]*spokesd.ObjectIdentifier)
	repoIdentifier := make(map[int64]repository)
	resolvedCommitsByRepo := make(map[int64][]*spokesd.ObjectIdentifier)
	// Create a mapping of repository database IDs to global ID and NWO. Spokesd calls are grouped by repo.
	for _, reqWorkflow := range requiredWorkflows {
		_, ok := repoIdentifier[reqWorkflow.RepoDatabaseID]
		if !ok {
			repoIdentifier[reqWorkflow.RepoDatabaseID] = repository{
				ID:  reqWorkflow.RepoID,
				Nwo: reqWorkflow.RepoNwo,
			}
		}
		// Create an objectIdentifier for spokesd for each required workflow. Append the objectIdentifier to resolvedCommitsByRepo. There are three cases:
		// 1. workflow file sha is present: Use it to create the objectIdentifier and add it to the list of resolvedCommitsByRepo
		// 2. ref is a resolved commit sha: Use it as the sha to create the objectIdentifier and add it to the list of resolvedCommitsByRepo
		// 3. There is no sha and the ref is a branch name: Resolve the branch name to a commit sha and then create the objectIdentifier add it to the list of resolvedCommitsByRepo
		if reqWorkflow.WorkflowFileSha != "" {
			resolvedCommitsByRepo[reqWorkflow.RepoDatabaseID] = append(resolvedCommitsByRepo[reqWorkflow.RepoDatabaseID], &spokesd.ObjectIdentifier{
				SHA:  reqWorkflow.WorkflowFileSha,
				Ref:  reqWorkflow.Ref,
				Path: reqWorkflow.Path,
			})
			continue
		}

		if types.IsCommitSha(reqWorkflow.Ref) {
			resolvedCommitsByRepo[reqWorkflow.RepoDatabaseID] = append(resolvedCommitsByRepo[reqWorkflow.RepoDatabaseID], &spokesd.ObjectIdentifier{
				SHA:  reqWorkflow.Ref,
				Ref:  reqWorkflow.Ref,
				Path: reqWorkflow.Path,
			})
			continue
		}

		identifierByRepo[reqWorkflow.RepoDatabaseID] = append(identifierByRepo[reqWorkflow.RepoDatabaseID], &spokesd.ObjectIdentifier{
			Path: reqWorkflow.Path,
			Ref:  reqWorkflow.Ref,
		})
	}

	// Resolve refs to commit SHAs for all the required workflows that didn't have a sha or a resolved commit sha.
	var resolvedRequiredWorkflowRefs []*ResolvedObjectsByRepo
	if len(identifierByRepo) > 0 {
		resolvedRequiredWorkflowRefs = rwp.resolvedRequiredWorkflowRefs(ctx, identifierByRepo, invokingActorID)
		if len(resolvedRequiredWorkflowRefs) == 0 {
			rwp.obs.Error(ctx, "failed to resolve all given required workflow refs")
			return nil
		}
	}

	for _, resolvedRequiredWorkflowRef := range resolvedRequiredWorkflowRefs {
		for _, obj := range resolvedRequiredWorkflowRef.ResolvedObjects {
			resolvedCommitsByRepo[resolvedRequiredWorkflowRef.RepoID] = append(resolvedCommitsByRepo[resolvedRequiredWorkflowRef.RepoID], &spokesd.ObjectIdentifier{
				SHA:  obj.CommitOID,
				Ref:  obj.Ref,
				Path: obj.Path,
			})
		}
	}

	// Resolve the objectIDs into spokesd object identifiers
	resolvedRequiredWorkflowObjects := rwp.resolveRequiredWorkflowCommitSHAs(ctx, resolvedCommitsByRepo, invokingActorID)
	if len(resolvedRequiredWorkflowObjects) == 0 {
		rwp.obs.Error(ctx, "failed to resolve all given required workflow objects")
		return nil
	}

	// Get the blobs for each workflow by repo
	resolvedRequiredWorkflows := rwp.getRequiredWorkflowsBlobs(ctx, resolvedRequiredWorkflowObjects, invokingActorID, repoIdentifier)
	if len(resolvedRequiredWorkflows) == 0 {
		rwp.obs.Error(ctx, "failed to retrieve required workflow blobs")
		return nil
	}

	if len(resolvedRequiredWorkflows) != len(requiredWorkflows) {
		rwp.obs.Error(ctx, "resolved required workflow blobs does not match required workflow count",
			kvp.Int64("gh.launch.actor.id", invokingActorID),
			kvp.Int("gh.launch.required_workflow.count", len(requiredWorkflows)),
			kvp.Int("gh.launch.resolved_required_workflow.count", len(resolvedRequiredWorkflows)))

		rwp.obs.Counter(ctx, "required_workflows_provider.matching_resolved_required_workflow_blobs", statter.Tags{"status": "failure"}, 1)
	} else {
		rwp.obs.Counter(ctx, "required_workflows_provider.matching_resolved_required_workflow_blobs", statter.Tags{"status": "success"}, 1)
	}

	return resolvedRequiredWorkflows
}

func (rwp *requiredWorkflowsProvider) resolvedRequiredWorkflowRefs(ctx context.Context, refsByRepo map[int64][]*spokesd.ObjectIdentifier, invokingActorID int64) []*ResolvedObjectsByRepo {
	resolveObjectsByRefRequests := make(chan *spokesd.ResolveObjectsRequest)
	go func() {
		defer close(resolveObjectsByRefRequests)
		for repoID, objectIdentifierList := range refsByRepo {
			resolveObjectsByRefRequests <- &spokesd.ResolveObjectsRequest{
				RepositoryID:         repoID,
				ActorID:              invokingActorID,
				ObjectIdentifierList: objectIdentifierList,
				QualityOfService:     stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			}
		}
	}()

	wg := sync.WaitGroup{}
	wg.Add(concurrentWorkers)
	resolveObjectsByRefResponses := make(chan *ResolveObjectsResult)

	go func() {
		defer close(resolveObjectsByRefResponses)
		wg.Wait()
	}()

	// This loop guarantees that we spin atmost 10 goroutines to
	// perform ref resolution for a set of required workflows
	// that belong to a repository.
	for i := 0; i < concurrentWorkers; i++ {
		go func() {
			defer wg.Done()

			for resolveObjectsRequest := range resolveObjectsByRefRequests {
				resolveObjectsByRefResponses <- rwp.resolveRefsForRepository(ctx, resolveObjectsRequest)
			}
		}()
	}

	resolvedRequiredWorkflowObjects := make([]*ResolvedObjectsByRepo, 0)
	for resolveObjectByRefResponse := range resolveObjectsByRefResponses {
		// This indicates that we failed to resolve objects
		// for a repository as a whole. In such cases, we
		// continue to loop over the response channel.
		if resolveObjectByRefResponse.Err != nil {
			rwp.obs.Debug(ctx, "failed to resolve objects for repository", kvp.Int64("gh.repo.id", resolveObjectByRefResponse.RepoID))
			continue
		}

		if len(resolveObjectByRefResponse.ResolvedObjects) > 0 {
			resolvedRequiredWorkflowObjects = append(resolvedRequiredWorkflowObjects, &ResolvedObjectsByRepo{
				RepoID:          resolveObjectByRefResponse.RepoID,
				ResolvedObjects: resolveObjectByRefResponse.ResolvedObjects,
			})
		}
	}

	return resolvedRequiredWorkflowObjects
}

func (rwp *requiredWorkflowsProvider) resolveRefsForRepository(ctx context.Context, req *spokesd.ResolveObjectsRequest) *ResolveObjectsResult {
	res, err := rwp.spokesClient.ResolveObjectsByRef(ctx, req)
	if err != nil {
		return &ResolveObjectsResult{
			Err:               err,
			RepoID:            req.RepositoryID,
			ResolvedObjects:   nil,
			UnresolvedObjects: nil,
		}
	}

	resolvedObjects := make([]*ResolvedObject, 0)
	unresolvedObjects := make([]*ResolvedObject, 0)
	var kvps []kvp.Field
	for i, item := range res.GetItems() {
		// The items coming back are guaranteed to be in the same order we sent them
		// so we can simply use the index of the ObjectIdentifier in the request to
		// pull out an unique object and use it.
		object := req.ObjectIdentifierList[i]

		kvps = []kvp.Field{
			kvp.Int64("gh.repo.id", req.RepositoryID),
			kvp.String("gh.launch.commit.file_path", object.Path),
			kvp.String("gh.launch.event.ref", object.Ref),
		}

		if len(item.GetError()) > 0 {
			unresolvedObjects = append(unresolvedObjects, &ResolvedObject{
				Path: object.Path,
				Ref:  object.Ref,
			})
			rwp.obs.Debug(ctx, fmt.Sprintf("failed to resolve object with ref: %s", item.GetError()), kvps...)
			continue
		}

		if !item.GetObject().IsCommit() {
			unresolvedObjects = append(unresolvedObjects, &ResolvedObject{
				Path: object.Path,
				Ref:  object.Ref,
			})
			kvps = append(kvps, kvp.String("gh.launch.object.type", item.GetObject().Type.String()))
			rwp.obs.Debug(ctx, fmt.Sprintf("resolved object is not of type blob: %s", item.GetError()), kvps...)
			continue
		}

		resolvedObjects = append(resolvedObjects, &ResolvedObject{
			CommitOID: item.GetObject().GetOid().GetId(),
			Path:      object.Path,
			Ref:       object.Ref,
		})
	}

	return &ResolveObjectsResult{
		Err:               nil,
		RepoID:            req.RepositoryID,
		ResolvedObjects:   resolvedObjects,
		UnresolvedObjects: unresolvedObjects,
	}
}

func (rwp *requiredWorkflowsProvider) resolveRequiredWorkflowCommitSHAs(ctx context.Context, resolvedCommitsByRepo map[int64][]*spokesd.ObjectIdentifier, invokingActorID int64) []*ResolvedObjectsByRepo {
	resolveObjectsByCommitRequests := make(chan *spokesd.ResolveObjectsRequest)
	go func() {
		defer close(resolveObjectsByCommitRequests)
		for repoID, objectIdentifierList := range resolvedCommitsByRepo {
			resolveObjectsByCommitRequests <- &spokesd.ResolveObjectsRequest{
				RepositoryID:         repoID,
				ActorID:              invokingActorID,
				ObjectIdentifierList: objectIdentifierList,
				QualityOfService:     stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			}
		}
	}()

	wg := sync.WaitGroup{}
	wg.Add(concurrentWorkers)
	resolveObjectsByCommitResponses := make(chan *ResolveObjectsResult)

	go func() {
		defer close(resolveObjectsByCommitResponses)
		wg.Wait()
	}()

	// This loop guarantees that we spin atmost 10 goroutines to
	// perform object resolution for a set of required workflows
	// that belong to a repository.
	for i := 0; i < concurrentWorkers; i++ {
		go func() {
			defer wg.Done()

			for resolveObjectsRequest := range resolveObjectsByCommitRequests {
				resolveObjectsByCommitResponses <- rwp.resolveCommitsForRepository(ctx, resolveObjectsRequest)
			}
		}()
	}

	resolvedRequiredWorkflowObjects := make([]*ResolvedObjectsByRepo, 0)
	for resolveObjectsResponse := range resolveObjectsByCommitResponses {
		// This indicates that we failed to resolve objects
		// for a repository as a whole. In such cases, we
		// continue to loop over the response channel.
		if resolveObjectsResponse.Err != nil {
			rwp.obs.Debug(ctx, "failed to resolve objects for repository", kvp.Int64("gh.repo.id", resolveObjectsResponse.RepoID))
			continue
		}

		if len(resolveObjectsResponse.ResolvedObjects) > 0 {
			resolvedRequiredWorkflowObjects = append(resolvedRequiredWorkflowObjects, &ResolvedObjectsByRepo{
				RepoID:          resolveObjectsResponse.RepoID,
				ResolvedObjects: resolveObjectsResponse.ResolvedObjects,
			})
		}
	}

	return resolvedRequiredWorkflowObjects
}

func (rwp *requiredWorkflowsProvider) resolveCommitsForRepository(ctx context.Context, req *spokesd.ResolveObjectsRequest) *ResolveObjectsResult {
	res, err := rwp.spokesClient.ResolveObjectsByCommitShaAndPath(ctx, req)
	if err != nil {
		return &ResolveObjectsResult{
			Err:               err,
			RepoID:            req.RepositoryID,
			ResolvedObjects:   nil,
			UnresolvedObjects: nil,
		}
	}

	resolvedObjects := make([]*ResolvedObject, 0)
	unresolvedObjects := make([]*ResolvedObject, 0)
	var kvps []kvp.Field
	for i, item := range res.GetItems() {
		// The items coming back are guaranteed to be in the same order we sent them
		// so we can simply use the index of the ObjectIdenfier in the request to
		// pull out an unique object and use it.
		object := req.ObjectIdentifierList[i]

		kvps = []kvp.Field{
			kvp.Int64("gh.repo.id", req.RepositoryID),
			kvp.String("gh.commit.oid", object.SHA),
			kvp.String("gh.launch.commit.file_path", object.Path),
			kvp.String("gh.launch.event.ref", object.Ref),
		}

		if len(item.GetError()) > 0 {
			unresolvedObjects = append(unresolvedObjects, &ResolvedObject{
				Path: object.Path,
				Ref:  object.Ref,
			})
			rwp.obs.Debug(ctx, fmt.Sprintf("failed to resolve object: %s", item.GetError()), kvps...)
			continue
		}

		if !item.GetObject().IsBlob() {
			unresolvedObjects = append(unresolvedObjects, &ResolvedObject{
				Path: object.Path,
				Ref:  object.Ref,
			})
			kvps = append(kvps, kvp.String("gh.launch.object.type", item.GetObject().Type.String()))
			rwp.obs.Debug(ctx, fmt.Sprintf("resolved object is not of type blob: %s", item.GetError()), kvps...)
			continue
		}

		resolvedObjects = append(resolvedObjects, &ResolvedObject{
			ObjectID:  item.GetObject().GetOid().GetId(),
			CommitOID: object.SHA,
			Path:      object.Path,
			Ref:       object.Ref,
		})
	}

	return &ResolveObjectsResult{
		Err:               nil,
		RepoID:            req.RepositoryID,
		ResolvedObjects:   resolvedObjects,
		UnresolvedObjects: unresolvedObjects,
	}
}

func (rwp *requiredWorkflowsProvider) getRequiredWorkflowsBlobs(ctx context.Context, resolvedObjectsByRepo []*ResolvedObjectsByRepo, actorID int64, repoIdentifier map[int64]repository) []types.ResolvedFile {
	identifierByObjectID := make(map[string]*spokesd.ObjectIdentifier)
	batchedBlobsReqChannel := make(chan *spokesd.GetBlobContentsBatchRequest)
	mu := &sync.RWMutex{}

	go func() {
		defer close(batchedBlobsReqChannel)
		for _, resolvedObjectByRepo := range resolvedObjectsByRepo {
			objectIDs := make([]string, 0)
			for _, resolvedObject := range resolvedObjectByRepo.ResolvedObjects {
				objectIDs = append(objectIDs, resolvedObject.ObjectID)

				// We populate this map to later identify the objects from
				// the GetBlobContentsBatch call which returns a objectID
				// to blob contents map. We also acquire a write lock since
				// this is a safe way to make concurrent writes/reads to
				// maps in golang.
				mu.Lock()
				// We do this because spokesD returns the same objectID when
				// two blobs getting resolved have the same path, ref and
				// contents even though they are present in different repositories.
				identifierKey := fmt.Sprintf("%d:%s", resolvedObjectByRepo.RepoID, resolvedObject.ObjectID)
				identifierByObjectID[identifierKey] = &spokesd.ObjectIdentifier{
					Ref:  resolvedObject.Ref,
					Path: resolvedObject.Path,
					SHA:  resolvedObject.CommitOID,
				}
				mu.Unlock()
			}

			batchedBlobsReqChannel <- &spokesd.GetBlobContentsBatchRequest{
				RepositoryID:     resolvedObjectByRepo.RepoID,
				ActorID:          actorID,
				ObjectIDs:        objectIDs,
				QualityOfService: stypes.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			}
		}
	}()

	wg := sync.WaitGroup{}
	wg.Add(concurrentWorkers)
	batchedBlobResponses := make(chan *spokesd.GetBlobContentsBatchResponse)
	go func() {
		defer close(batchedBlobResponses)
		wg.Wait()
	}()

	// This loop guarantees that we spin atmost 10 goroutines to
	// retrieve batched blobs for a set of required workflows.
	for i := 0; i < concurrentWorkers; i++ {
		go func() {
			defer wg.Done()

			for batchedBlobsRequest := range batchedBlobsReqChannel {
				batchedBlobResponses <- rwp.getBatchedBlobsForRepository(ctx, batchedBlobsRequest)
			}
		}()
	}

	resolvedRequiredWorkflowFiles := make([]types.ResolvedFile, 0)
	resolvedObjectsRepoMap := make(map[int64][]*ResolvedObject)

	for _, resolvedObjectByRepo := range resolvedObjectsByRepo {
		resolvedObjectsRepoMap[resolvedObjectByRepo.RepoID] = resolvedObjectByRepo.ResolvedObjects
	}

	for batchedBlobResponse := range batchedBlobResponses {
		if batchedBlobResponse == nil {
			continue
		}

		mu.RLock()

		repoID := batchedBlobResponse.RepositoryID
		repoBlobs := resolvedObjectsRepoMap[repoID]

		for _, obj := range repoBlobs {
			path := requiredworkflowutils.ConstructRequiredWorkflowPath(
				obj.Path,
				repoID)
			content := string(batchedBlobResponse.BlobContentsByID[obj.ObjectID])
			resolvedRequiredWorkflowFiles = append(resolvedRequiredWorkflowFiles, types.ResolvedFile{
				Path:          path,
				Ref:           obj.Ref,
				Text:          content,
				SHA:           obj.CommitOID,
				IsTruncated:   false,
				RepositoryNwo: repoIdentifier[repoID].Nwo,
				RepositoryID:  repoIdentifier[repoID].ID,
			})
		}

		mu.RUnlock()
	}

	return resolvedRequiredWorkflowFiles
}

func (rwp *requiredWorkflowsProvider) getBatchedBlobsForRepository(ctx context.Context, req *spokesd.GetBlobContentsBatchRequest) *spokesd.GetBlobContentsBatchResponse {
	resp, err := rwp.spokesClient.GetBlobContentsBatch(ctx, req)
	if err != nil {
		rwp.obs.Error(ctx, errors.Wrap(err, "failed to get batched blobs for repository").Error(), kvp.Int64("gh.repo.id", req.RepositoryID))
		return nil
	}

	return resp
}
