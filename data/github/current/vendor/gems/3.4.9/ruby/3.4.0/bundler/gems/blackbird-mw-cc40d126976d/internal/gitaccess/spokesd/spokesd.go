package spokesd

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	backoff "github.com/cenkalti/backoff/v4"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	spokesBlobs "github.com/github/spokes-proto/gen/go/v1/blobs"
	spokesCommits "github.com/github/spokes-proto/gen/go/v1/commits"
	spokesExperimental "github.com/github/spokes-proto/gen/go/v1/experimental"
	spokesObjects "github.com/github/spokes-proto/gen/go/v1/objects"
	spokesRefs "github.com/github/spokes-proto/gen/go/v1/references"
	"github.com/github/spokes-proto/gen/go/v1/streaming"
	spokesTrees "github.com/github/spokes-proto/gen/go/v1/trees"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/internal/utils"
)

const (
	// Request-Timeout is a number of seconds. The default if not specified is
	// 15 seconds and the maximum that can be specified is 5 minutes.
	//
	// See: https://github.com/github/gitrpcd/blob/67ca63ac6cf2bb80ea2a124c6135c3078cd6952d/internal/http/timeout/timeout.go#L15-L16
	requestTimeoutHeaderName = "Request-Timeout"

	// Set our Request-Timeout to the maximum to allow Spokes/GitMon to slow us
	// down.
	requestTimeout = 5 * time.Minute

	// This is the hardcoded max batch size inside spokes, see https://github.com/github/spokes-proto/blob/738edd90460f202e724b8c02102981164d43ba3d/gen/go/v1/experimental/experimental_api.go#L55
	resolveBlobsBatchSize = 1000
)

type GitClient struct {
	spokesBlobsClient     spokesBlobs.BlobsAPI
	spokesCommitsAPI      spokesCommits.CommitsAPI
	spokesTreesAPI        spokesTrees.TreesAPI
	spokesObjectsAPI      spokesObjects.ObjectsAPI
	spokesRefsAPI         spokesRefs.ReferencesAPI
	spokesExperimentalAPI spokesExperimental.ExperimentalAPI

	// for spokes blob streaming
	httpClient *http.Client
	baseURL    string

	opts *ClientOpts
}

// New creates a new spokesd-powered gitaccess.Client.
func New(baseURL string, httpClient *http.Client, opts *ClientOpts) *GitClient {
	if opts == nil {
		opts = DefaultClientOpts()
	}

	// Use a Twirp client hook to add the timeout header to all requests. This
	// can be done by adding a header to the context, but we'd have to do it
	// everywhere we call a spokes API.
	//
	// NOTE: RequestPrepared runs after setting custom headers from the context,
	// so I'm adding the headers directly.
	requestTimeoutHook := twirp.WithClientHooks(&twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, req *http.Request) (context.Context, error) {
			req.Header.Set(requestTimeoutHeaderName, strconv.FormatInt(int64(requestTimeout/time.Second), 10))
			return ctx, nil
		},
	})

	return &GitClient{
		spokesBlobsClient:     spokesBlobs.NewBlobsAPIProtobufClient(baseURL, httpClient, requestTimeoutHook),
		spokesCommitsAPI:      spokesCommits.NewCommitsAPIProtobufClient(baseURL, httpClient, requestTimeoutHook),
		spokesTreesAPI:        spokesTrees.NewTreesAPIProtobufClient(baseURL, httpClient, requestTimeoutHook),
		spokesObjectsAPI:      spokesObjects.NewObjectsAPIProtobufClient(baseURL, httpClient, requestTimeoutHook),
		spokesRefsAPI:         spokesRefs.NewReferencesAPIProtobufClient(baseURL, httpClient, requestTimeoutHook),
		spokesExperimentalAPI: spokesExperimental.NewExperimentalAPIProtobufClient(baseURL, httpClient, requestTimeoutHook),
		httpClient:            httpClient,
		baseURL:               baseURL,
		opts:                  opts,
	}
}

// SetFetchConcurrency is used to change the number of concurrent requests to
// fetch blob content.
func (c *GitClient) SetFetchConcurrency(n int) *GitClient {
	c.opts.FetchConcurrency = n
	return c
}

type ClientOpts struct {
	FetchConcurrency int
	BatchSize        int
	Retries          int
}

const (
	defaultFetchConcurrency = 1
	defaultBatchSize        = 25
	defaultRetries          = 0
)

func DefaultClientOpts() *ClientOpts {
	return &ClientOpts{
		FetchConcurrency: defaultFetchConcurrency,
		BatchSize:        defaultBatchSize,
		Retries:          defaultRetries,
	}
}

// Diff takes two treeish objects and computes the diff as slice of diff entries.
func (c *GitClient) Diff(ctx context.Context, locationLimit int, base, head *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
	if head == nil {
		panic("diff called with a nil head")
	}

	if base == nil {
		base = &gitaccess.Treeish{RepoID: head.RepoID, Treeish: nil}
	}

	// If the base and head point to same commit oid, there is no diff to compute.
	if base.Treeish.GetOid() != nil && head.Treeish.GetOid() != nil {
		if base.Treeish.GetOid().Id == head.Treeish.GetOid().Id {
			statting.Counter(ctx, "gitaccess.spokesd.diff.no_diff", 1)
			return gitaccess.RepoDiff{base.RepoID: []*gitaccess.DiffEntry{}, head.RepoID: []*gitaccess.DiffEntry{}}, nil
		}
	}

	start := time.Now()
	if base.RepoID == head.RepoID {
		entries, err := c.intraRepoDiffWithRetry(ctx, locationLimit, base.RepoID, base.Treeish, head.Treeish)
		if err != nil {
			statting.DistributionMs(ctx, "gitaccess.spokesd.diff.duration", time.Since(start), stats.Tags{"status": "error"})
			return nil, errors.WithMessage(err, "spokesd: failed to compare trees within a repository")
		}
		statting.DistributionMs(ctx, "gitaccess.spokesd.diff.duration", time.Since(start), stats.Tags{"status": "success"})
		return gitaccess.RepoDiff{base.RepoID: entries}, nil
	} else {
		diff, err := c.interRepoDiffWithRetry(ctx, locationLimit, base, head)
		if err != nil {
			statting.DistributionMs(ctx, "gitaccess.spokesd.diff.duration", time.Since(start), stats.Tags{"status": "error"})
			return nil, errors.WithMessage(err, "spokesd: failed to compare trees across repositories")
		}
		statting.DistributionMs(ctx, "gitaccess.spokesd.diff.duration", time.Since(start), stats.Tags{"status": "success"})
		return diff, nil
	}
}

// list a tree as the base
func (c *GitClient) lsBaseTreeWithRetry(ctx context.Context, locationLimit int, repoID types.RepoID, treeish *spokes.Treeish) ([]*gitaccess.DiffEntry, error) {
	entries, err := c.lsTreeWithRetry(ctx, locationLimit, repoID, treeish)
	if err != nil {
		if retry.IsTwirpNotFoundError(err) {
			// Determine whether the repo was deleted, or the base or head was missing based on the error message.
			// See:
			// https://github.com/github/gitrpcd/blob/fd6b447cdd0a7072a2f5b8bb575d1c03f59c26e5/internal/pipe/pipetwirp/twirp.go#L14-L38
			// https://github.com/github/gitrpcd/blob/fd6b447cdd0a7072a2f5b8bb575d1c03f59c26e5/internal/http/gitpath/error.go#L5
			switch {
			case strings.Contains(err.Error(), fmt.Sprintf("object %s not found", treeish.GetOid().GetId())):
				return nil, WrapInvalidDiffBaseError(err, "cannot list tree with missing base object")
			default:
				// NOTE: other not_found errors imply an error finding the repo
				// or network, and usually mean the repo was deleted during the
				// operation. Since this is the base commit, we'll return
				// InvalidDiffBaseError so a new base can be selected.
				return nil, WrapInvalidDiffBaseError(err, "not found error listing base tree")
			}
		}
		return nil, err
	}

	return entries, nil
}

// list a tree as the head
func (c *GitClient) lsHeadTreeWithRetry(ctx context.Context, locationLimit int, repoID types.RepoID, treeish *spokes.Treeish) ([]*gitaccess.DiffEntry, error) {
	entries, err := c.lsTreeWithRetry(ctx, locationLimit, repoID, treeish)
	if err != nil {
		if retry.IsTwirpNotFoundError(err) {
			// Determine whether the repo was deleted, or the base or head was missing based on the error message.
			// See:
			// https://github.com/github/gitrpcd/blob/fd6b447cdd0a7072a2f5b8bb575d1c03f59c26e5/internal/pipe/pipetwirp/twirp.go#L14-L38
			// https://github.com/github/gitrpcd/blob/fd6b447cdd0a7072a2f5b8bb575d1c03f59c26e5/internal/http/gitpath/error.go#L5
			switch {
			case strings.Contains(err.Error(), fmt.Sprintf("object %s not found", treeish.GetOid().GetId())):
				return nil, WrapInvalidCommit(err, "cannot list head tree with missing object")
			default:
				// NOTE: other not_found errors imply an error finding the repo
				// or network, and usually mean the repo was deleted during the
				// operation. Since this is the head commit, we'll return an
				// error indicating the repo is deleted.
				return nil, WrapRepoDeletedError(err, "cannot list head tree with deleted repo")
			}
		}
		return nil, err
	}

	return entries, nil
}

// lsTreeWithRetry lists a tree. Use lsBaseTreeWithRetry or lsHeadTreeWithRetry
// depending on if the tree is the base or head of the diff.
func (c *GitClient) lsTreeWithRetry(ctx context.Context, locationLimit int, repoID types.RepoID, treeish *spokes.Treeish) ([]*gitaccess.DiffEntry, error) {
	start := time.Now()
	var entries []*gitaccess.DiffEntry
	attempt := 0

	listOperation := func() error {
		start := time.Now()
		defer func() {
			statting.DistributionMs(ctx, "gitaccess.spokesd.diff_with_retry.list_operation.duration", time.Since(start))
		}()

		attempt++
		entries = []*gitaccess.DiffEntry{}

		page := 0
		var cursor *spokes.Cursor
		for {
			page++

			rid := requestid.GetGitHubRequestID(ctx)
			ctx := requestid.WithGitHubRequestID(ctx, fmt.Sprintf("%s;listtree;attempt=%d;page=%d", rid, attempt, page))

			res, err := c.spokesTreesAPI.ListTrees(
				ctx,
				spokesTrees.NewListTreesRequestWithTreeishSelector(
					spokes.NewRequestContext(spokes.RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
					spokes.NewRepository(uint64(repoID)),
					selectors.NewTreeishSelector(treeish),
					true, // recursive
					cursor,
				),
			)
			if err != nil {
				if attempt%100 == 99 {
					logging.Error(
						ctx,
						"listing tree repeatedly failing",
						kvp.Int("ls_tree_attempts", attempt),
						kvp.Any("duration", time.Since(start)),
						kvp.Duration("duration_ms", time.Since(start)),
						kvp.Stringer("head", treeish),
						kvp.Err(err),
					)
				}

				return retry.CheckTwirpErrResponse(err)
			}

			for _, e := range res.GetEntries() {
				oid, err := gitaccess.NewObjectIDFromSHA(e.GetObject().GetOid().GetId())
				if err != nil {
					logging.Error(ctx, "invalid oid, skipping", kvp.Err(err), kvp.Any("entry", e))
					continue
				}

				if e.GetObject().GetType() != spokes.Object_TYPE_BLOB {
					continue
				}

				if e.GetMode().IsSubmodule() {
					logging.Info(ctx, "submodule, skipping", kvp.Stringer("oid", oid))
					continue
				}

				if !utf8.Valid(e.GetPath().GetName()) {
					logging.Info(ctx, "non-UTF-8 path name for addition, skipping", kvp.Stringer("oid", oid), kvp.Any("entry", e))
					continue
				}

				entry := &gitaccess.DiffEntry{
					OID:    oid,
					Path:   string(e.GetPath().GetName()),
					Change: gitaccess.Add,
				}

				entries = append(entries, entry)

				// A locationLimit of 0 indicates no limit.
				if locationLimit > 0 && len(entries) > locationLimit {
					logging.Error(ctx, "location limit exceeded", kvp.Int("limit", locationLimit))
					return LocationLimitExceededError
				}
			}

			if res.NextCursor == nil {
				break
			}

			cursor = res.NextCursor
		}

		return nil
	}

	err := backoff.Retry(listOperation, retry.DefaultBackOff(ctx, uint64(c.opts.Retries)))
	if err != nil {
		logging.Error(
			ctx,
			"listing tree failed",
			kvp.Int("ls_tree_attempts", attempt),
			kvp.Any("duration", time.Since(start)),
			kvp.Duration("duration_ms", time.Since(start)),
			kvp.Stringer("head", treeish),
			kvp.Err(err),
		)
		return nil, err
	}

	statting.Distribution(ctx, "gitaccess.spokesd.ls_tree_with_retry.entries", float64(len(entries)))
	logging.Info(
		ctx,
		"listing tree succeeded",
		kvp.Int("ls_tree_attempts", attempt),
		kvp.Int("tree_entries", len(entries)),
		kvp.Duration("ls_tree_duration", time.Since(start)),
	)
	return entries, nil
}

func (c *GitClient) compareTreesWithRetry(ctx context.Context, repoID types.RepoID, base, head *spokes.Treeish) ([]*gitaccess.DiffEntry, error) {
	start := time.Now()
	var entries []*gitaccess.DiffEntry
	attempt := 0

	diffOperation := func() error {
		start := time.Now()
		defer func() {
			statting.DistributionMs(ctx, "gitaccess.spokesd.diff_with_retry.operation.duration", time.Since(start))
		}()

		attempt++
		entries = []*gitaccess.DiffEntry{}

		page := 0
		var cursor *spokes.Cursor
		for {
			page++

			rid := requestid.GetGitHubRequestID(ctx)
			ctx := requestid.WithGitHubRequestID(ctx, fmt.Sprintf("%s;comparetrees;attempt=%d;page=%d", rid, attempt, page))

			res, err := c.spokesTreesAPI.CompareTrees(
				ctx,
				spokesTrees.NewCompareTreesRequestWithRangeSelector(
					spokes.NewRequestContext(spokes.RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
					spokes.NewRepository(uint64(repoID)),
					selectors.NewRangeSelector(base, head),
					true,  // recursive
					false, // includeRenames
					cursor,
				),
			)
			if err != nil {
				if isMemoryLimitError(err) {
					return backoff.Permanent(WrapGitSystemError(err, "diff too large"))
				}

				if retry.IsTwirpNotFoundError(err) {
					// Determine whether the repo was deleted, or the base or head was missing based on the error message.
					// See:
					// https://github.com/github/gitrpcd/blob/fd6b447cdd0a7072a2f5b8bb575d1c03f59c26e5/internal/pipe/pipetwirp/twirp.go#L14-L38
					// https://github.com/github/gitrpcd/blob/fd6b447cdd0a7072a2f5b8bb575d1c03f59c26e5/internal/http/gitpath/error.go#L5
					switch {
					case strings.Contains(err.Error(), fmt.Sprintf("object %s not found", base.GetOid().GetId())):
						return backoff.Permanent(WrapInvalidDiffBaseError(err, "cannot diff tree with missing base object"))
					case strings.Contains(err.Error(), fmt.Sprintf("object %s not found", head.GetOid().GetId())):
						return backoff.Permanent(WrapInvalidCommit(err, "cannot diff tree with missing head object"))
					default:
						// NOTE: other not_found errors imply an error finding
						// the repo or network, and usually mean the repo was
						// deleted during the operation.
						return backoff.Permanent(WrapRepoDeletedError(err, "not found error diffing tree"))
					}
				}

				return retry.CheckTwirpErrResponse(err)
			}

			for _, e := range res.GetEntries() {
				sourceEntry := toDiffEntry(ctx, e.GetSourceOid(), e.GetSource(), e.GetSourceMode(), gitaccess.Delete)
				destEntry := toDiffEntry(ctx, e.GetDestinationOid(), e.GetDestination(), e.GetDestinationMode(), gitaccess.Add)

				if isNoopDiff(sourceEntry, destEntry) {
					// These are valid, but don't represent a diff in Blackbird terms. Skip them.
					continue
				}

				if sourceEntry != nil {
					entries = append(entries, sourceEntry)
				}

				if destEntry != nil {
					entries = append(entries, destEntry)
				}
			}

			if res.NextCursor == nil {
				break
			}

			cursor = res.NextCursor
		}

		return nil
	}

	err := backoff.Retry(diffOperation, retry.DefaultBackOff(ctx, uint64(c.opts.Retries)))
	if err != nil {
		logging.Error(
			ctx,
			"comparing trees failed",
			kvp.Int("compare_trees_attempts", attempt),
			kvp.Any("duration", time.Since(start)),
			kvp.Duration("duration_ms", time.Since(start)),
			kvp.Stringer("base", base),
			kvp.Stringer("head", head),
			kvp.Err(err),
		)
		return nil, err
	}

	return entries, nil
}

// Takes either the source or destination half of a spokes.DiffEntry and returns
// the appropriate internal DiffEntry representation *gitaccess.DiffEntry
// or nil if the entry should be skipped.
//
// Note that in a spokes.DiffEntry, the objectID will be nil on the source for
// STATUS_ADDITION and nil on the destination for STATUS_DELETION. No entry will
// be returned in either of these cases.
func toDiffEntry(ctx context.Context, objectID *spokes.ObjectID, path *spokes.Path, mode *spokes.Mode, change gitaccess.ChangeType) *gitaccess.DiffEntry {
	if objectID == nil {
		return nil
	}

	ctx = logging.With(ctx, kvp.String("change", change.String()), kvp.String("oid", objectID.GetId()), kvp.String("path", string(path.GetName())))
	oid, err := gitaccess.NewObjectIDFromSHA(objectID.GetId())
	if err != nil {
		logging.Error(ctx, "skipping invalid blob oid", kvp.Err(err))
		return nil
	}

	if mode.IsSubmodule() {
		logging.Info(ctx, "skipping submodule")
		return nil
	}

	if !utf8.Valid(path.GetName()) {
		logging.Info(ctx, "skipping non-UTF-8 path name")
		return nil
	}

	return &gitaccess.DiffEntry{Path: string(path.GetName()), OID: oid, Change: change}
}

func (c *GitClient) intraRepoDiffWithRetry(ctx context.Context, locationLimit int, repoID types.RepoID, base, head *spokes.Treeish) ([]*gitaccess.DiffEntry, error) {
	if base == nil {
		return c.lsHeadTreeWithRetry(ctx, locationLimit, repoID, head)
	}

	return c.compareTreesWithRetry(ctx, repoID, base, head)
}

// Request the trees from base and head and return the differences in the
// context of head.
//
// Only additions/deletions are considered changes (for example, a different
// mode will not be included.)
//
// The algorithm used is:
//
// 1. Request all tree entries for base
// 2. Request all tree entries for head
// 3. For every entry in head, check and see if the path exists in base
//   - if it exists and is the same OID, remove the entry from the results
//   - if it exists but is a different OID, add a Addition and leave the base entry
//   - if it does not exist, add an Addition for that entry
//
// 4. For every path left in base, add a deletion
func (c *GitClient) interRepoDiffWithRetry(ctx context.Context, locationLimit int, base, head *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
	start := time.Now()

	baseEntries, err := c.lsBaseTreeWithRetry(ctx, locationLimit, base.RepoID, base.Treeish)
	if err != nil {
		statting.DistributionMs(ctx, "gitaccess.spokesd.inter_repo_diff_with_retry.duration", time.Since(start), stats.Tags{"status": "error"})
		return nil, err
	}

	headEntries, err := c.lsHeadTreeWithRetry(ctx, locationLimit, head.RepoID, head.Treeish)
	if err != nil {
		statting.DistributionMs(ctx, "gitaccess.spokesd.inter_repo_diff_with_retry.duration", time.Since(start), stats.Tags{"status": "error"})
		return nil, err
	}

	// Diff the two trees. This is based on the Cistern implementation:
	// https://github.com/github/cistern/blob/65793e27735d1417e43569549c985144b8b5840b/gitaccess/trees/trees.go#L24-L83
	baseMap := map[string]gitaccess.ObjectID{}
	for _, entry := range baseEntries {
		baseMap[entry.Path] = entry.OID
	}

	headDiff := []*gitaccess.DiffEntry{}
	for _, entry := range headEntries {
		baseOID, present := baseMap[entry.Path]

		if present {
			if baseOID.Equal(entry.OID) {
				// No modification at this path: remove from consideration
				delete(baseMap, entry.Path)
			} else {
				// modification at this path: add to diff
				headDiff = append(headDiff, entry)
			}
		} else {
			// New content at this path: add to diff
			headDiff = append(headDiff, entry)
		}
	}

	// Any path left in base was deleted in head: add to diff
	baseDiff := []*gitaccess.DiffEntry{}
	for path, oid := range baseMap {
		baseDiff = append(baseDiff, &gitaccess.DiffEntry{
			Path:   path,
			OID:    oid,
			Change: gitaccess.Delete,
		})
	}

	statting.DistributionMs(ctx, "gitaccess.spokesd.inter_repo_diff_with_retry.duration", time.Since(start), stats.Tags{"status": "success"})
	return gitaccess.RepoDiff{base.RepoID: baseDiff, head.RepoID: headDiff}, nil
}

type blobEntryBatch struct {
	batchID int
	repoID  types.RepoID
	// key: blob_oid
	blobs map[gitaccess.ObjectID]*gitaccess.BlobContentChange
}

func (c *GitClient) GetBlobsForDiff(ctx context.Context, cancel context.CancelFunc, diff gitaccess.RepoDiff, f func(*gitaccess.BlobContentChange)) error {
	// Batch up so we can fetch concurrently
	batches := make(chan blobEntryBatch)
	go func() {
		defer utils.PanicLogger(ctx)
		defer close(batches)

		batchID := 0
		for repoID, diffEntries := range diff {
			blobs := make(map[gitaccess.ObjectID]*gitaccess.BlobContentChange, c.opts.BatchSize)
			for _, e := range diffEntries {
				// NB: Important to download both adds and deletes as the later isGenerated checks require content.
				loc := &gitaccess.BlobLocationEntry{Change: e.Change, Path: e.Path}
				entry, ok := blobs[e.OID]
				if ok {
					entry.BlobLocations = append(entry.BlobLocations, loc)
				} else {
					blobs[e.OID] = &gitaccess.BlobContentChange{
						ObjectID:      e.OID,
						BlobLocations: []*gitaccess.BlobLocationEntry{loc},
					}
				}

				if len(blobs) >= c.opts.BatchSize {
					batchID++
					batches <- blobEntryBatch{batchID, repoID, blobs}
					blobs = make(map[gitaccess.ObjectID]*gitaccess.BlobContentChange, c.opts.BatchSize)
				}
			}

			// final, partial batch
			if len(blobs) > 0 {
				batchID++
				batches <- blobEntryBatch{batchID, repoID, blobs}
			}
		}
	}()

	// The collection goroutine aggregates errors from fetch routines and returns the
	// first error (if any) by writing to the done channel.
	done := make(chan error)
	errs := make(chan error)
	go func() {
		defer utils.PanicLogger(ctx)

		// Drain errs channel to collect returns
		var anyErr error
		for err := range errs {
			if err != nil {
				if anyErr == nil { // capture first error
					anyErr = err
					cancel() // abort any further work immediately
				}
			}
		}
		done <- anyErr
	}()

	// Spawn multiple goroutines to fetch batches of blobs concurrently
	wg := &sync.WaitGroup{}
	for i := 0; i < c.opts.FetchConcurrency; i++ {
		wg.Add(1)
		go func() {
			defer utils.PanicLogger(ctx)
			defer wg.Done()

			for batch := range batches {
				start := time.Now()
				oids := make([]*spokes.ObjectID, 0, c.opts.BatchSize)
				for sha := range batch.blobs {
					oids = append(oids, spokes.NewObjectID(sha.String()))
				}

				rid := requestid.GetGitHubRequestID(ctx)
				ctx := requestid.WithGitHubRequestID(ctx, fmt.Sprintf("%s;getblobs;batch=%d", rid, batch.batchID))

				err := c.GetBlobs(ctx, batch.repoID, oids, func(blob *gitaccess.BlobEntry) {
					entry := batch.blobs[blob.OID]
					entry.Content = blob.Content
					f(entry)
				})
				switch {
				case errors.Is(err, context.Canceled):
					// don't log or stat these, but write errs in case the root failure
					// was due to something like a deployment context cancelled.
					errs <- err
				case err != nil:
					statting.Counter(ctx, "gitaccess.spokesd.batch_blobs_request.error", 1)
					logging.Error(ctx, "failed to get blob contents for batch of oids", kvp.Err(err))
					errs <- err
				default:
					statting.DistributionMs(ctx, "gitaccess.spokesd.batch_blobs_request.duration", time.Since(start))
				}
			}
		}()
	}

	wg.Wait()   // wait for all workers to finish
	close(errs) // signal the error collector routine

	return <-done
}

// GetDefaultRef returns the tip of the default branch, or nil if no default branch was found.
func (c *GitClient) GetDefaultRef(ctx context.Context, repoID types.RepoID) (*gitaccess.RefTip, error) {
	start := time.Now()

	rid := requestid.GetGitHubRequestID(ctx)
	ctx = requestid.WithGitHubRequestID(ctx, fmt.Sprintf("%s;defaultref", rid))

	ref, err := c.getDefaultBranch(ctx, repoID)
	if err != nil {
		return nil, err
	}

	if ref == nil {
		return nil, nil
	}

	oid, err := c.getHeadOID(ctx, repoID)
	if err != nil {
		return nil, err
	}

	if oid == gitaccess.NullObjectID {
		return nil, nil
	}

	refTip, err := gitaccess.NewRefTip(ref.GetName(), oid)
	if err != nil {
		statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.duration", time.Since(start), stats.Tags{"status": "error"})
		logging.Error(ctx, "error getting default ref", kvp.Any("duration", time.Since(start)), kvp.Duration("duration_ms", time.Since(start)), kvp.Err(err))
		return nil, WrapInvalidRefError(err, "spokesd: invalid or unsupported ref name")
	}

	statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.duration", time.Since(start), stats.Tags{"status": "success"})

	return refTip, nil
}

func (c *GitClient) getDefaultBranch(ctx context.Context, repoID types.RepoID) (*spokes.Reference, error) {
	start := time.Now()

	rid := requestid.GetGitHubRequestID(ctx)
	ctx = requestid.WithGitHubRequestID(ctx, fmt.Sprintf("%s;defaultref;getdefaultbranch", rid))

	res, err := c.spokesRefsAPI.GetDefaultBranch(
		ctx,
		&spokesRefs.GetDefaultBranchRequest{
			RequestContext: spokes.NewRequestContext(spokes.RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
			Repository:     spokes.NewRepository(uint64(repoID)),
		},
	)
	if err != nil {
		if retry.IsTwirpNotFoundError(err) {
			statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_default_branch.duration", time.Since(start), stats.Tags{"status": "not-found"})
			logging.Error(ctx, "not found error getting default ref", kvp.Err(err))
			return nil, nil
		}

		if isSymbolicRefError(err) {
			statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_default_branch.duration", time.Since(start), stats.Tags{"status": "symbolic-ref"})
			logging.Error(ctx, "internal error getting default ref", kvp.Err(err))
			return nil, nil
		}

		if isGitmonTooManyProcessesError(err) {
			statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_default_branch.duration", time.Since(start), stats.Tags{"status": "too-many-processes"})
			logging.Error(ctx, "gitmon too-many-processes error getting default ref", kvp.Err(err))
			return nil, WrapGitmonTooManyProcessesError(err, "error getting default ref")
		}

		statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_default_branch.duration", time.Since(start), stats.Tags{"status": "error"})
		logging.Error(ctx, "unclassified error getting default ref", kvp.Err(err))
		return nil, err
	}

	statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_default_branch.duration", time.Since(start), stats.Tags{"status": "success"})
	return res.Reference, nil
}

func (c *GitClient) getHeadOID(ctx context.Context, repoID types.RepoID) (gitaccess.ObjectID, error) {
	start := time.Now()

	rid := requestid.GetGitHubRequestID(ctx)
	ctx = requestid.WithGitHubRequestID(ctx, fmt.Sprintf("%s;defaultref;getheadoid", rid))

	req := spokesObjects.NewResolveObjectRequest(
		spokes.NewRequestContext(spokes.RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
		spokes.NewRepository(uint64(repoID)),
		spokes.NewRevision(spokes.DefaultBranch().Name),
	)
	res, err := c.spokesObjectsAPI.ResolveObject(ctx, req)
	if err != nil {
		if retry.IsTwirpNotFoundError(err) {
			statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_head_oid.duration", time.Since(start), stats.Tags{"status": "not-found"})
			logging.Error(ctx, "not found error resolving head OID", kvp.Err(err))
			return gitaccess.NullObjectID, nil
		}

		if isGitmonTooManyProcessesError(err) {
			statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_head_oid.duration", time.Since(start), stats.Tags{"status": "too-many-processes"})
			logging.Error(ctx, "gitmon too-many-processes error resolving head OID", kvp.Err(err))
			return gitaccess.NullObjectID, WrapGitmonTooManyProcessesError(err, "error resolving head OID")
		}

		statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_head_oid.duration", time.Since(start), stats.Tags{"status": "error"})
		return gitaccess.NullObjectID, err
	}

	statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_head_oid.duration", time.Since(start), stats.Tags{"status": "success"})

	oid, err := gitaccess.NewObjectIDFromSHA(res.GetOid().GetId())
	if err != nil {
		statting.DistributionMs(ctx, "gitaccess.spokesd.get_default_ref.get_head_oid.duration", time.Since(start), stats.Tags{"status": "error"})
		logging.Error(ctx, "error resolving head OID: invalid OID", kvp.Any("duration", time.Since(start)), kvp.Duration("duration_ms", time.Since(start)), kvp.Err(err))

		return gitaccess.NullObjectID, WrapInvalidRefError(err, "spokesd: unable to resolve default ref to a commit oid")
	}

	return oid, nil
}

// GetTreeOIDForCommit peels a commit oid to a tree oid.
func (c *GitClient) GetTreeOIDForCommit(ctx context.Context, repoID types.RepoID, commitOID gitaccess.ObjectID) (gitaccess.ObjectID, error) {
	start := time.Now()
	oid, err := c.getTreeOIDForCommitWithRetries(ctx, repoID, commitOID)
	if err != nil {
		logging.Error(ctx, "error getting tree OID for commit", kvp.Any("duration", time.Since(start)), kvp.Duration("duration_ms", time.Since(start)), kvp.Err(err))
		statting.DistributionMs(ctx, "gitaccess.spokesd.get_tree_oid_for_commit.duration", time.Since(start), stats.Tags{"status": "error"})
		return gitaccess.NullObjectID, errors.WithMessage(err, "spokesd: failed to get tree OID for commit")
	}

	statting.DistributionMs(ctx, "gitaccess.spokesd.get_tree_oid_for_commit.duration", time.Since(start), stats.Tags{"status": "success"})

	return oid, nil
}

func (c *GitClient) getTreeOIDForCommitWithRetries(ctx context.Context, repoID types.RepoID, commitOID gitaccess.ObjectID) (gitaccess.ObjectID, error) {
	var oid gitaccess.ObjectID
	attempt := 0
	operation := func() error {
		start := time.Now()
		defer func() {
			statting.DistributionMs(ctx, "gitaccess.spokesd.get_tree_oid_for_commit_with_retries.operation.duration", time.Since(start))
		}()

		attempt++

		rid := requestid.GetGitHubRequestID(ctx)
		ctx := requestid.WithGitHubRequestID(ctx, fmt.Sprintf("%s;treeoid;attempt=%d", rid, attempt))

		res, err := c.spokesCommitsAPI.ListCommits(
			ctx,
			spokesCommits.NewListCommitsRequestWithObjectIDSelector(
				spokes.NewRequestContext(spokes.RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
				spokes.NewRepository(uint64(repoID)),
				selectors.NewObjectIDSelector(spokes.NewObjectID(commitOID.String())),
				nil, //cursor
			),
		)

		if err != nil {
			return retry.CheckTwirpErrResponse(err)
		}

		// This is terminally broken and should not be retried
		if len(res.Commits) != 1 {
			return backoff.Permanent(InvalidCommit("expected one and only one commit for %s but got %d", commitOID.String(), len(res.Commits)))
		}

		oid, err = gitaccess.NewObjectIDFromSHA(res.Commits[0].GetCommitContent().GetTree().GetId())
		if err != nil {
			// This is unrecoverable and should not be retried
			return backoff.Permanent(WrapInvalidCommit(err, "invalid git tree oid for commit"))
		}

		return nil
	}

	err := backoff.Retry(operation, retry.DefaultBackOff(ctx, uint64(c.opts.Retries)))
	if err != nil {
		logging.Error(ctx, "getting tree ID for commit failed", kvp.Int("get_tree_oid_attempts", attempt), kvp.Stringer("commit_oid", commitOID), kvp.Err(err))
		return gitaccess.NullObjectID, err
	}

	return oid, nil
}

func (c *GitClient) GetBlobs(ctx context.Context, repoID types.RepoID, oids []*spokes.ObjectID, f func(*gitaccess.BlobEntry)) error {
	start := time.Now()
	resp, err := c.getBlobsWithRetries(ctx, repoID, oids)
	if err != nil {
		logging.Error(ctx, "error fetching a batch of blobs", kvp.Any("duration", time.Since(start)), kvp.Duration("duration_ms", time.Since(start)), kvp.Err(err))
		statting.DistributionMs(ctx, "gitaccess.spokesd.get_blobs.duration", time.Since(start), stats.Tags{"status": "error"})
		return errors.WithMessage(err, "spokesd: error fetching batch of blobs")
	}

	defer func() {
		cerr := resp.Body.Close()
		if err == nil && cerr != nil {
			logging.Error(ctx, "failed to close response body", kvp.Err(cerr))
		}
	}()

	tar, err := streaming.GetBatchBlobsTarReader(resp)
	if err != nil {
		return errors.WithMessage(err, "reading tar response failed")
	}

	for {
		header, err := tar.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return errors.WithMessage(err, "reading tar entry header failed")
		}

		content, err := io.ReadAll(tar)
		if err != nil {
			return errors.WithMessage(err, "reading entry failed")
		}
		statting.Counter(ctx, "gitaccess.spokesd.batch_blobs_request.blob_size", int64(len(content)))

		blobOID, err := gitaccess.NewObjectIDFromSHA(header.Name)
		if err != nil {
			return errors.WithMessage(err, "invalid blob oid in tar header")
		}

		f(&gitaccess.BlobEntry{OID: blobOID, Content: content})
	}

	statting.DistributionMs(ctx, "gitaccess.spokesd.get_blobs.duration", time.Since(start), stats.Tags{"status": "success"})
	return nil
}

//
// Wrap the generated proto/twirp API with backoff and retries.
//

// getBlobsWithRetries wraps the streaming/GetBlobs http call with retries.
func (c *GitClient) getBlobsWithRetries(ctx context.Context, repoID types.RepoID, oids []*spokes.ObjectID) (resp *http.Response, err error) {
	start := time.Now()
	req := streaming.NewBatchBlobsRequest(
		spokes.NewRequestContext(spokes.RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
		spokes.NewRepository(uint64(repoID)),
		oids,
		streaming.WithUTF8Only(),
		streaming.WithPlainTextOnly(),
		streaming.WithMaxSize(gitaccess.MaxBlobSize),
		streaming.WithMinSize(gitaccess.MinBlobSize),
	)
	httpReq, err := streaming.NewBatchBlobsHTTPRequest(req, c.baseURL)
	if err != nil {
		return nil, err
	}

	attempt := 0
	operation := func() error {
		opStart := time.Now()
		defer func() {
			statting.DistributionMs(ctx, "gitaccess.spokesd.get_blobs_with_retries.operation.duration", time.Since(opStart))
		}()

		attempt++
		rid := requestid.GetGitHubRequestID(ctx)
		ctx := requestid.WithGitHubRequestID(ctx, fmt.Sprintf("%s;getblobs;attempt=%d", rid, attempt))
		httpReq = httpReq.WithContext(ctx)
		resp, err = c.httpClient.Do(httpReq)
		return retry.CheckHTTPResponse(resp, err)
	}

	err = backoff.Retry(operation, retry.DefaultBackOff(ctx, uint64(c.opts.Retries)))
	if err != nil {
		logging.Error(
			ctx,
			"get blobs failed",
			kvp.Int("num_oids", len(oids)),
			kvp.Any("duration", time.Since(start)),
			kvp.Duration("duration_ms", time.Since(start)),
			kvp.Int("get_blobs_attempts", attempt),
			kvp.Err(err),
		)
	}
	return resp, err
}

func (c *GitClient) ResolveBlobs(ctx context.Context, blobs gitaccess.RepoBlobsMap) error {
	if len(blobs) == 0 {
		return nil
	}

	numRepos := 0
	numBlobs := 0
	repoBatch := make([]*spokesExperimental.ObjectSelectorsByRepo, 0, len(blobs))
	for repoID, oids := range blobs {
		sels := make([]*selectors.ObjectSelector, 0, len(oids))
		for oid := range oids {
			sels = append(sels, selectors.NewObjectSelectorByObjectID(spokes.NewObjectID(oid.String())))
		}
		numRepos++
		numBlobs += len(sels)

		for i := 0; i <= len(sels)/resolveBlobsBatchSize; i++ {
			start := i * resolveBlobsBatchSize
			end := (i + 1) * resolveBlobsBatchSize
			if end > len(sels) {
				end = len(sels)
			}
			thisBatchSelectors := sels[start:end]

			if len(thisBatchSelectors) > 0 {
				repoBatch = append(repoBatch, spokesExperimental.NewObjectSelectorsByRepo(spokes.NewRepository(uint64(repoID)), thisBatchSelectors...))
			}
		}
	}

	logging.Info(ctx, "resolving blobs", kvp.Int("num_blobs_oids_to_resolve", numBlobs), kvp.Int("num_repos", numRepos))
	res, err := c.resolveBlobsWithRetries(
		ctx,
		spokesExperimental.NewResolveObjectsRequest(
			spokes.NewRequestContext(spokes.RequestContext_QUALITY_OF_SERVICE_NO_DELAY),
			repoBatch...),
	)
	if err != nil {
		return err
	}

	for _, r := range res.ResolvedBatches {
		repoID := types.RepoID(r.Repository.Id)
		for _, item := range r.GetItems() {
			if len(item.GetError()) > 0 {
				logging.Error(ctx, "resolved object has an error", kvp.String("error", item.GetError()))
				continue
			}
			if !item.GetObject().IsBlob() {
				logging.Error(ctx, "resolved object is not a blob", kvp.Stringer("object_type", item.GetObject().Type))
				continue
			}
			oid, err := gitaccess.NewObjectIDFromSHA(item.GetObject().GetOid().Id)
			if err != nil {
				logging.Error(ctx, "resolved object has an invalid oid", kvp.Err(err), kvp.String("item_oid", item.GetObject().GetOid().Id))
				continue
			}
			delete(blobs[repoID], oid)
		}
		if len(blobs[repoID]) == 0 {
			delete(blobs, repoID)
		}
	}

	return nil
}

func (c *GitClient) resolveBlobsWithRetries(ctx context.Context, req *spokesExperimental.ResolveObjectsRequest) (*spokesExperimental.ResolveObjectsResponse, error) {
	attempt := 0
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		// 75 milliseconds pulled out of thin air
		if duration > time.Millisecond*75 {
			logging.Info(
				ctx,
				"slow blob resolution",
				kvp.Int("batch_size", len(req.ObjectSelectorsByRepo)),
				kvp.Duration("duration_ms", duration),
				kvp.Int("resolve_blob_attempts", attempt),
			)
		}
	}()

	var response *spokesExperimental.ResolveObjectsResponse
	op := func() error {
		attempt++

		var err error
		response, err = c.spokesExperimentalAPI.ResolveObjects(ctx, req)
		if err != nil {
			if retry.IsTwirpNotFoundError(err) {
				return nil
			}
			logging.Error(ctx, "error resolving blobs", kvp.Err(err), kvp.Int("resolve_blob_attempts", attempt))
			return retry.CheckTwirpErrResponse(err)
		}

		return err
	}

	err := backoff.Retry(op, retry.DefaultBackOff(ctx, uint64(c.opts.Retries)))
	if err != nil {
		logging.Error(ctx, "could not resolve objects", kvp.Int("resolve_blob_attempts", attempt), kvp.Err(err))
		return nil, err
	}

	return response, nil
}

// isMemoryLimitError checks for internal errors from gitrpcd that are returned when git operations hit a memory limit.
// Example: twirp error internal: git-diff-tree with memory limit: exit status 128
func isMemoryLimitError(err error) bool {
	if twerr, ok := err.(twirp.Error); ok {
		if twerr.Code() == twirp.Internal && strings.Contains(twerr.Error(), "with memory limit") {
			return true
		}
	}

	return false
}

// isSymbolicRefError checks for internal errors from gitrpcd that are returned
// when a symbolic ref cannot be found. This indicates an invalid repository and
// at this time, gitrpcd returns a 500 error.
//
// See: https://github.com/github/gitrpcd/issues/1025
func isSymbolicRefError(err error) bool {
	if twerr, ok := err.(twirp.Error); ok {
		if twerr.Code() == twirp.Internal && strings.Contains(twerr.Error(), "git-symbolic-ref: exit status 128") {
			return true
		}
	}

	return false
}

// isGitmonTooManyProcessesError checks for resource exhausted
// "too-many-processes" errors returned from gitmon. We ask Spokes API to wait
// until Gitmon has capacity for us, but if there are too many Git processes on
// the host, it will fail fast despite that setting.
//
// See: https://github.com/github/blackbird/issues/7396
func isGitmonTooManyProcessesError(err error) bool {
	if twerr, ok := err.(twirp.Error); ok {
		if twerr.Code() == twirp.ResourceExhausted && strings.Contains(twerr.Error(), "gitmon refuses to schedule us: too-many-processes") {
			return true
		}
	}

	return false
}

// isNoopDiff returns true if entryA and entryB point to the same content at the
// same path. This can happen, for example, with Git mode changes. From
// blackbird's point of view, there is nothing to change in the index.
func isNoopDiff(entryA *gitaccess.DiffEntry, entryB *gitaccess.DiffEntry) bool {
	if entryA == nil || entryB == nil {
		return false
	}

	return entryA.OID == entryB.OID && entryA.Path == entryB.Path && entryA.Change != entryB.Change
}

// NOTE: makes sure the blackbird.GitClient implements gitaccess.Client.
var _ gitaccess.Client = &GitClient{}
