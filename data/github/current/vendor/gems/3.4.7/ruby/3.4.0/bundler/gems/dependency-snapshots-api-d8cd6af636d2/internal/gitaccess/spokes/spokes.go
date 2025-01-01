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
