package spokes

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"regexp"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/gitaccess/facade"

	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/references"
	"github.com/github/spokes-proto/gen/go/v1/trees"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"

	"github.com/pkg/errors"
)

// internal: Spokes-backed gitaccess.Client implementation
type spokesClient struct {
	URL           string
	commitsClient commits.CommitsAPI
	blobsClient   blobs.BlobsAPI
	objectsClient objects.ObjectsAPI
	treesClient   trees.TreesAPI
	refsClient    references.ReferencesAPI
}

// internal: trim a fully qualified ref down to a branch name (ref name)
var prefixPattern = regexp.MustCompile(`^refs/(heads|tags|remotes|notes)/`)

// compile-time check against gitaccess.Client contract
var _ = gitaccess.Client(&spokesClient{})

// NewClient - returns a Spokes-backed implementation of gitaccess.Client
func NewClient(spokesURL string, httpClient *http.Client, devStandalone bool) (gitaccess.Client, error) {
	if len(spokesURL) == 0 {
		return nil, errors.New("required argument: Spokes API service URL")
	}

	if httpClient == nil {
		return nil, errors.New("required argument: well-formed HTTP client")
	}

	// cache Twirp client wrappers for use in high level gitaccess APIs
	blobsClient := blobs.NewBlobsAPIProtobufClient(spokesURL, httpClient)
	treesClient := trees.NewTreesAPIProtobufClient(spokesURL, httpClient)
	commitsClient := commits.NewCommitsAPIProtobufClient(spokesURL, httpClient)
	objectsClient := objects.NewObjectsAPIProtobufClient(spokesURL, httpClient)
	refsClient := references.NewReferencesAPIProtobufClient(spokesURL, httpClient)

	productionSpokesClient := &spokesClient{
		URL:           spokesURL,
		blobsClient:   blobsClient,
		commitsClient: commitsClient,
		objectsClient: objectsClient,
		treesClient:   treesClient,
		refsClient:    refsClient,
	}

	// This little hack is made anticipating the facade will be removed after perf testing is completed.
	if os.Getenv("DEPENDENCY_SNAPSHOTS_DB") == "dependency_snapshots_test" {
		return productionSpokesClient, nil
	}

	spokesClientFacade := facade.NewFacade(productionSpokesClient, devStandalone)
	return spokesClientFacade, nil
}

// GetDefaultBranch - given a GitHub repository ID, obtain the default branch
// name, usable as an input (Git revision) to GetRecentCommits or GetHEADCommit.
func (sc *spokesClient) GetDefaultBranch(ctx context.Context, repoID uint64) (string, error) {
	if repoID == 0 {
		return "", errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "GetDefaultBranch")
	defer ender()

	req := &references.GetDefaultBranchRequest{
		Repository: types.NewRepository(repoID),
	}

	resp, err := sc.refsClient.GetDefaultBranch(ctx, req)
	if err != nil {
		return "", errors.Wrap(err, "Spokes: error resolving repository default branch")
	}
	if len(resp.GetReference().GetName()) == 0 {
		return "", errors.New("Spokes: returned ref name is unpopulated")
	}

	// IMPORTANT: known GitHub issue - Git branch names and refs are not limited to UTF-8
	// charset but Ruby, Go, and most services expect well-formed UTF-8. This translation
	// step might be best skipped on the DS-API side if it becomes a problem for us.
	// "optionalBranchName" fields could then accept `[]byte` inputs. So far, most of the
	// company waves hands about this so it's not a large concern for us at this stage.

	// strip fully-qualified ref prefix, leaving us with branch name
	branchName := prefixPattern.ReplaceAll(resp.GetReference().GetName(), []byte(""))
	return string(branchName), nil
}

// GetHEADCommit - Obtain the latest commit SHA for the given GitHub repository ID
// and optional branch name (default branch is assumed if absent.)
func (sc *spokesClient) GetHEADCommit(ctx context.Context, repoID uint64, optionalBranchName ...string) (gitaccess.SHA, error) {
	if repoID == 0 {
		return gitaccess.SHA(""), errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "GetHEADCommit")
	defer ender()

	// TODO: support full refs instead? Lets us get latest revision at a tag point etc.
	rev := gitaccess.HEAD
	if len(optionalBranchName) > 0 {
		rev = []byte(optionalBranchName[0])
	}

	req := objects.NewResolveObjectRequest(
		types.NewRepository(repoID),
		types.NewRevision(rev),
	)

	resp, err := sc.objectsClient.ResolveObject(ctx, req)
	if err != nil {
		return gitaccess.SHA(""), errors.Wrap(err, "Spokes: error resolving HEAD commit OID")
	}

	if resp.GetOid() == nil || len(resp.GetOid().GetId()) == 0 {
		return gitaccess.SHA(""), errors.New("Spokes: commit ID resolved from HEAD is missing")
	}

	// should be well-formed, resolved "after" commit ID
	return gitaccess.SHA(resp.GetOid().GetId()), nil
}

// GetRecentCommits - given a GitHub repository ID, a valid branch on that repo,
// and a nonzero number of latest commit SHAs to fetch, obtain the commit SHAs as
// an ordered array (most recent to oldest) or error.
func (sc *spokesClient) GetRecentCommits(ctx context.Context, repoID uint64, numCommits uint, optionalBranchName ...string) ([]gitaccess.SHA, error) {
	if numCommits == 0 || numCommits > gitaccess.MaxRecentCommits {
		return nil, errors.Errorf("required: numCommits must be non-zero and no larger than %d, got: %d",
			gitaccess.MaxRecentCommits, numCommits)
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "GetRecentCommits")
	defer ender()

	// TODO: support full refs instead? Lets us get latest revision at a tag point etc.
	ref := gitaccess.HEAD
	if len(optionalBranchName) > 0 {
		ref = []byte(fmt.Sprintf("refs/heads/%s", optionalBranchName[0]))
	}
	req := commits.NewListCommitsRequestWithRevisionSelector(
		types.NewRepository(repoID),
		selectors.NewRevisionSelector(types.NewRevision(ref)),
		&types.Cursor{},
	)

	out := []gitaccess.SHA{}
PagingLoop:
	for {
		resp, err := sc.commitsClient.ListCommits(ctx, req)
		if err != nil {
			return out, errors.Wrap(err, "Spokes: error resolving recent commits")
		}
		// pick up the new Cursor in case this page isn't
		// enough to obtain numCommits for us
		req.Cursor = resp.GetNextCursor()

		// preserve array order for commits returned
		for i := 0; i < len(resp.GetCommits()); i++ {
			sha := gitaccess.SHA(resp.GetCommits()[i].GetOid().GetId())
			out = append(out, sha)
			numCommits--

			// we've fetched all the requested commits, stop paging
			if numCommits == 0 {
				break PagingLoop
			}
		}

		// we've exhausted the listable commits before reaching the
		// caller-specified limit; return what we have
		if req.Cursor == nil {
			break PagingLoop
		}
	}

	return out, nil
}

// ListTreeByRef - lists the entire tree for a repository at a given ref.
func (sc *spokesClient) ListTreeByRef(ctx context.Context, repoID uint64, ref []byte) ([]*types.TreeEntry, error) {
	if repoID == 0 {
		return nil, errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "ListTreeByRef")
	defer ender()

	selector := selectors.NewTreeishSelector(types.NewTreeishWithReference(&types.Reference{Name: ref}))
	return sc.listTree(ctx, repoID, selector, true)
}

// ListTreeByCommit - lists the entire tree for a repository at a given commit OID.
func (sc *spokesClient) ListTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	if repoID == 0 {
		return nil, errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "ListTreeByCommit")
	defer ender()

	selector := selectors.NewTreeishSelector(types.NewTreeishWithObjectID(&types.ObjectID{Id: commitOID}))
	return sc.listTree(ctx, repoID, selector, true)
}

// ListRootTreeByCommit - lists only the root-level tree entries for a repository at a given commit OID.
func (sc *spokesClient) ListRootTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	if repoID == 0 {
		return nil, errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "ListRootTreeByCommit")
	defer ender()

	selector := selectors.NewTreeishSelector(types.NewTreeishWithObjectID(&types.ObjectID{Id: commitOID}))
	return sc.listTree(ctx, repoID, selector, false)
}

// listTree - internal helper that lists tree entries with pagination support.
func (sc *spokesClient) listTree(ctx context.Context, repoID uint64, selector *selectors.TreeishSelector, recursive bool) ([]*types.TreeEntry, error) {
	request := trees.NewListTreesRequestWithTreeishSelector(
		types.NewRepository(repoID),
		selector,
		recursive,
		nil,
	)

	var entries []*types.TreeEntry
	for {
		resp, err := sc.treesClient.ListTrees(ctx, request)
		if err != nil {
			return nil, errors.Wrap(err, "Spokes: error listing tree")
		}
		entries = append(entries, resp.GetEntries()...)
		cursor := resp.GetNextCursor()
		if cursor == nil {
			break
		}
		request.Cursor = cursor
	}

	return entries, nil
}

// CompareTrees - compares two commits and returns the diff entries between them.
func (sc *spokesClient) CompareTrees(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
	if repoID == 0 {
		return nil, errors.New("Spokes: valid repository ID required")
	}
	if len(beforeCommit) == 0 || len(afterCommit) == 0 {
		return nil, errors.Errorf("Spokes: missing expected commit range for repo %d: before(%s) after(%s)", repoID, beforeCommit, afterCommit)
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "CompareTrees")
	defer ender()

	beforeOID := types.NewObjectID(beforeCommit)
	beforeTreeish := types.NewTreeishWithObjectID(beforeOID)

	afterOID := types.NewObjectID(afterCommit)
	afterTreeish := types.NewTreeishWithObjectID(afterOID)

	request := trees.NewCompareTreesRequestWithRangeSelector(
		types.NewRepository(repoID),
		selectors.NewRangeSelector(beforeTreeish, afterTreeish),
		true,  // recursive enumeration
		false, // includeNames - decompose renames as an ADD and a DELETE instead
		nil,   // initial cursor
	)

	var entries []*types.DiffEntry
	for {
		resp, err := sc.treesClient.CompareTrees(ctx, request)
		if err != nil {
			return nil, errors.Wrap(err, "Spokes: error comparing trees")
		}

		entries = append(entries, resp.GetEntries()...)
		cursor := resp.GetNextCursor()
		if cursor == nil {
			break
		}
		request.Cursor = cursor
	}

	return entries, nil
}

// GetBlobByOID - retrieves blob contents by blob OID.
func (sc *spokesClient) GetBlobByOID(ctx context.Context, repoID uint64, blobOID string) ([]byte, uint64, error) {
	if repoID == 0 {
		return nil, 0, errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "GetBlobByOID")
	defer ender()

	request := blobs.NewGetBlobContentsRequestById(
		types.NewRepository(repoID),
		&types.ObjectID{Id: blobOID},
	)

	resp, err := sc.blobsClient.GetBlobContents(ctx, request)
	if err != nil {
		return nil, 0, errors.Wrap(err, "Spokes: error getting blob by OID")
	}

	return resp.GetContents(), resp.GetSize(), nil
}

// GetBlobByPath - retrieves blob contents by path at a given ref.
func (sc *spokesClient) GetBlobByPath(ctx context.Context, repoID uint64, ref []byte, path string) ([]byte, uint64, error) {
	if repoID == 0 {
		return nil, 0, errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "GetBlobByPath")
	defer ender()

	// Resolve the ref to a commit and fetch the blob directly by commit and path,
	// avoiding a full tree enumeration.
	var revision string
	if len(ref) > 0 {
		revision = string(ref)
	} else {
		// When no ref is provided, fall back to the default revision (HEAD).
		revision = "HEAD"
	}

	commitOID, err := sc.ResolveRef(ctx, repoID, revision)
	if err != nil {
		return nil, 0, errors.Wrapf(err, "Spokes: error resolving ref '%s' for GetBlobByPath", revision)
	}

	return sc.GetBlobByPathAndCommit(ctx, repoID, commitOID.Id, path)
}

// GetBlobByPathAndCommit - retrieves blob contents by path at a given commit.
func (sc *spokesClient) GetBlobByPathAndCommit(ctx context.Context, repoID uint64, commit string, path string) ([]byte, uint64, error) {
	if repoID == 0 {
		return nil, 0, errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "GetBlobByPathAndCommit")
	defer ender()

	request := blobs.NewGetBlobContentsRequestByObjectIDPath(
		types.NewRepository(repoID),
		&types.ObjectID{Id: commit},
		&types.Path{Name: []byte(path)},
	)

	resp, err := sc.blobsClient.GetBlobContents(ctx, request)
	if err != nil {
		return nil, 0, errors.Wrap(err, "Spokes: error getting blob by path and commit")
	}

	return resp.GetContents(), resp.GetSize(), nil
}

// ResolveRef - resolves a ref to an ObjectID (commit sha).
func (sc *spokesClient) ResolveRef(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
	if repoID == 0 {
		return nil, errors.New("Spokes: valid repository ID required")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "SpokesTracer", "ResolveRef")
	defer ender()

	req := objects.NewResolveObjectRequest(
		types.NewRepository(repoID),
		types.NewRevision([]byte(ref)),
	)

	resp, err := sc.objectsClient.ResolveObject(ctx, req)
	if err != nil {
		return nil, errors.Wrapf(err, "Spokes: error resolving ref '%s'", ref)
	}

	return resp.Oid, nil
}
