package healthcheck

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"strings"
	"time"

	dsaclient "github.com/github/blackbird/crates/client/pkg/blackbird"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/linguist/pkg/linguist"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/google/uuid"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/types"
)

type CompletenessSummary struct {
	Missing          []string
	NumTrailingZeros int
	VerifiedSummary
}

// Returns true if this repo is considered complete, meaning that there are no missing or extra
// paths in the blackbird index.
func (c *CompletenessSummary) IsOK() bool {
	return len(c.Missing) == 0 && len(c.Extra) == 0
}

type VerifiedSummary struct {
	Verified int
	Extra    []string
}

// Runs completeness checks on the given corpus by selecting repositories in a
// hash interval and comparing the documents in blackbird's index with the blobs
// in the repo according to spokes.
func (p *Prober) runCompletenessChecks(ctx context.Context, corpus routing.Corpus) error {
	cluster, err := p.ComputeHealthSummary(ctx, corpus)
	if err != nil {
		return fmt.Errorf("failed to compute health summary: %w", err)
	}

	ctx = logging.With(ctx, kvp.String("corpus", corpus.String()), kvp.String("epoch_mode", cluster.Status.EpochMode.String()))
	ctx = statting.WithTags(ctx, stats.Tags{"corpus": corpus.String(), "epoch_mode": cluster.Status.EpochMode.String()})

	index, err := blackbird.GetClusterWithoutBlobResolution(ctx, p.searchClusters, p.store, p.pager, corpus)
	if err != nil {
		return err
	}

	const desired = 10
	hash := rand.Uint64()
	res, err := index.SnapshotsInHashInterval(ctx, hash, desired)
	if err != nil {
		return fmt.Errorf("failed to get snapshots in interval: %w", err)
	}

	numProbed := 0
	numProbedOK := 0
	for _, snapshot := range res.Snapshots {
		if len(snapshot.Entries) != 1 {
			panic(fmt.Sprintf("each snapshot should have 1 entry, got: %+v", snapshot.Entries))
		}
		entry := snapshot.Entries[0]
		s, err := p.runCompletenessCheckForSnapshot(ctx, index, entry)
		if err != nil {
			return err
		}

		numProbed++
		if s.IsOK() {
			numProbedOK++
		}
	}

	// Report prober status to DSA
	if err := p.searchClusters.ReportProberStatus(ctx, corpus, dsaclient.ProberStatus{
		StartTs:              time.Now().UnixMilli(),
		ServingTs:            cluster.Status.ServingTs.UnixMilli(),
		ServingLagMs:         float32(cluster.ServingLag.Milliseconds()),
		IngestLagMs:          float32(cluster.IngestLag.Milliseconds()),
		NumUnavailableShards: float32(cluster.Status.NumUnavailableShards),
		// TODO(rewinfrey): Send number of failed hosts.
		// NumFailedHosts:       float32(cluster.Status.NumFailedHosts),
		NumReposProbed:   float32(numProbed),
		NumReposProbedOK: float32(numProbedOK),
		NumReposIndexed:  float32(cluster.Status.MaxReposIndexed),
	}); err != nil {
		logging.Error(ctx, "failed to report prober status", kvp.Err(err))
	}

	return nil
}

func (p *Prober) runCompletenessCheckForSnapshot(ctx context.Context, cluster *blackbird.Cluster, entry *snapshotpb.SnapshotEntry) (*CompletenessSummary, error) {
	ctx = logging.With(ctx, kvp.Bool("is_public", entry.IsRepoPublic), kvp.String("nwo", entry.Nwo))

	if entry.PermanentError != "" {
		logging.Info(ctx, "skipping snapshot with permanent error", kvp.String("permanent_error", entry.PermanentError))
		return &CompletenessSummary{}, nil
	}

	repoID := types.RepoID(entry.RepoId)
	headOID := gitaccess.NewObjectIDFromBytes(entry.CommitSha)

	if headOID.IsNull() {
		versions := make([]string, 0, len(entry.Versions))
		for _, version := range entry.Versions {
			versions = append(versions, fmt.Sprintf("SnapshotEntryVersion{offset=%d, state=%s}", version.OffsetId, version.State.String()))
		}

		logging.Info(
			ctx,
			"skipping snapshot with null commit sha",
			kvp.Uint("repo_id", uint(repoID)),
			kvp.Int("epoch", int(cluster.EpochID())),
			kvp.Uint64("entry_id", entry.EntryId),
			kvp.Uint64("commit_seq_no", entry.CommitSeqNo),
			kvp.String("permanent_error", entry.PermanentError),
			kvp.String("snapshot_versions", strings.Join(versions, ", ")),
		)
		return &CompletenessSummary{}, nil
	}

	prober := CompletenessProber{cluster, repoID, headOID, p}
	return prober.Check(ctx, false)
}

// A specialized completeness prober for a single repo at a specific head
// commit.
type CompletenessProber struct {
	index   *blackbird.Cluster
	repoID  types.RepoID
	headOID gitaccess.ObjectID

	*Prober
}

func NewCompletenessProber(index *blackbird.Cluster, repoID types.RepoID, headOID gitaccess.ObjectID, prober *Prober) *CompletenessProber {
	return &CompletenessProber{index, repoID, headOID, prober}
}

// Run the completeness prober for the given corpus, repo, commit.
func (p *CompletenessProber) Check(ctx context.Context, verbose bool) (*CompletenessSummary, error) {
	rid := uuid.New().String()
	ctx = requestid.WithGitHubRequestID(ctx, rid)
	ctx = logging.With(ctx,
		kvp.String("corpus", p.index.CorpusName()),
		kvp.String("prober", "completeness"),
		kvp.String("prober_id", rid),
		kvp.Int("repo_id", int(p.repoID)),
		kvp.String("head_oid", p.headOID.String()),
		kvp.Int("epoch", int(p.index.EpochID())),
		kvp.String("epoch_mode", p.index.EpochMode().String()),
		kvp.Int64("serving_ts", p.index.ServingTs().UnixMilli()),
		kvp.Int64("serving_offset", int64(p.index.ServingOffset())),
	)
	ctx = statting.WithTags(ctx, stats.Tags{"corpus": p.index.CorpusName(), "epoch_mode": p.index.EpochMode().String(), "prober": "completeness"})

	// Required to match ingest settings.
	ctx = experiments.WithCluster(ctx,
		&experiments.ClusterEnv{
			EpochID:     p.index.EpochID(),
			ClusterName: p.index.ClusterName(),
			CorpusName:  p.index.CorpusName(),
		})

	// Query spokes/git
	head := spokes.NewTreeishWithObjectID(spokes.NewObjectID(p.headOID.String()))
	diffEntries, err := p.gitClient.Diff(ctx, 0, nil, &gitaccess.Treeish{RepoID: p.repoID, Treeish: head})
	if err != nil {
		return nil, err
	}

	// build contentTracker from diff and create query
	contentTracker := p.contentTrackerFromDiff(ctx, diffEntries, verbose)
	q, numTrailingZeros, err := contentTracker.downsampleQuery(ctx, p.repoID)
	if err != nil {
		return nil, err
	}

	// Query blackbird
	res, err := p.queryBlackbird(ctx, q, verbose)
	if err != nil {
		return nil, err
	}

	// Verify blackbird documents against spokes' git data.
	summary, err := p.filterOutMatchingGitData(ctx, res, contentTracker)
	if err != nil {
		return nil, err
	}

	// Double check anything left in our set of expected paths. It's possible
	// these paths are generated or otherwise intentionally excluded, but we have
	// to download blob content to check.
	if err := p.filterOutGeneratedPaths(ctx, contentTracker, verbose); err != nil {
		return nil, err
	}

	// Anything left in the content tracker at this point is considered content missing from the index
	missing := []string{}
	for _, docPath := range contentTracker.docPaths() {
		missing = append(missing, docPath.String())
		logging.Error(ctx, "completeness prober missing expected path in blackbird results (file found in git repo)",
			kvp.String("doc_sha", docPath.docSHA.String()),
			kvp.String("blob_sha", docPath.blobSHA.String()),
			kvp.String("path", docPath.path))
	}

	statting.Counter(ctx, "prober.completeness.verified_repos", 1)
	statting.Counter(ctx, "prober.completeness.missing_documents", int64(contentTracker.numPaths()))
	statting.Counter(ctx, "prober.completeness.verified_documents", int64(summary.Verified))
	statting.Counter(ctx, "prober.completeness.excess_documents", int64(len(summary.Extra)))

	logging.Info(ctx, "completeness probe done", kvp.Int("verified", summary.Verified), kvp.Int("missing", contentTracker.numPaths()), kvp.Int("excess", len(summary.Extra)))
	return &CompletenessSummary{missing, numTrailingZeros, *summary}, nil
}

func (p *CompletenessProber) contentTrackerFromDiff(ctx context.Context, diff gitaccess.RepoDiff, verbose bool) *contentTracker {
	contentTracker := newContentTracker(p.index.EpochMode())

	for _, diffEntries := range diff {
		for _, entry := range diffEntries {
			isIndexable, reason, err := linguist.IsIndexable(entry.Path, nil /* NB: can only check path here */, uint32(p.index.EpochID()))
			if err != nil {
				logging.Error(ctx, "isIndexable failed", kvp.Err(err), kvp.String("path", entry.Path))
				continue
			}

			if !isIndexable {
				if verbose {
					logging.Info(ctx, "prober skipping check of path due to path exclusion", kvp.String("path", entry.Path), kvp.String("skip_reason", reason))
				}
				continue
			}
			contentTracker.add(entry.OID, entry.Path)
		}
	}
	logging.Info(ctx, "determined expected documents", kvp.Int("num_docs", contentTracker.numDocs()))

	return contentTracker
}

// Queries blackbird for the given diff. Will downsample the diff if necessary
// to keep probers fast (don't want to search and iterate over too many blobs).
//
// Returns the blackbird query response or an error.
func (p *CompletenessProber) queryBlackbird(ctx context.Context, q *parser.Query, verbose bool) (*pb.QueryResponse, error) {
	ctx = logging.With(ctx, kvp.String("q", parser.Serialize(q)))
	res, err := p.search(ctx, q)
	if err != nil {
		return nil, err
	}

	logging.Info(ctx, "performed search", kvp.Int("num_docs", len(res.Documents)))
	return res, nil
}

// NOTE: Blackbird has a hard-coded max location limit. If it changes, this will need to change.
// See:
// https://github.com/github/blackbird/blob/6822601c3c03fb8bc3ddb9d7314cb4aad6839b70/crates/query/src/limits.rs#L61
// https://github.com/github/blackbird/blob/6822601c3c03fb8bc3ddb9d7314cb4aad6839b70/crates/query/src/stream.rs#L122-L124
const blackbirdLocationLimit = 1000

// Filters items out of the expectedPaths map if they are also found in the
// blackbird query response.
func (p *CompletenessProber) filterOutMatchingGitData(ctx context.Context, res *pb.QueryResponse, contentTracker *contentTracker) (*VerifiedSummary, error) {
	extraPaths := []string{}
	matchedPaths := 0

	for _, doc := range res.Documents {
		docSHA := gitaccess.NewObjectIDFromBytes(doc.DocSha)
		blobSHA := gitaccess.NewObjectIDFromBytes(doc.BlobSha)
		numPathsForDocSHA := contentTracker.numPathsForDocSHA(docSHA)

		for _, loc := range doc.Locations {
			commitOID := gitaccess.NewObjectIDFromBytes(loc.CommitSha)
			if !p.headOID.Equal(commitOID) {
				logging.Error(
					ctx,
					"document location commit_sha does not match repo head",
					kvp.String("loc_commit_sha", commitOID.String()),
					kvp.String("head_oid", p.headOID.String()),
					kvp.String("doc_sha", docSHA.String()),
					kvp.String("blob_sha", blobSHA.String()),
					kvp.String("path", loc.Path),
				)
				return nil, errors.New("document location does not match head commit oid")
			}

			foundPath := contentTracker.pathExists(loc.Path)

			if ok := contentTracker.removePathForDocSHA(docSHA, loc.Path); ok {
				matchedPaths++
				continue
			}

			// This is a mismatch
			extraPaths = append(extraPaths, docPath{docSHA: docSHA, blobSHA: blobSHA, path: loc.Path}.String())
			logging.Error(ctx, "completeness prober got unexpected path from blackbird (file not found in git repo)",
				append(
					locationKVPs(loc),
					kvp.String("commit_sha", commitOID.String()),
					kvp.String("doc_sha", docSHA.String()),
					kvp.String("blob_sha", blobSHA.String()),
					kvp.String("path", loc.Path),
					kvp.Bool("found_path", foundPath),
				)...,
			)
		}

		// Blackbird applies a limit on the number of locations returned. If we
		// hit the limit, exclude all remaining paths for that OID from
		// verification.
		if len(doc.Locations) >= blackbirdLocationLimit {
			logging.Info(
				ctx,
				"document hit location limit, excluding all remaining paths from verification",
				kvp.String("doc_sha", docSHA.String()),
				kvp.String("blob_sha", blobSHA.String()),
				kvp.Int("num_locations", len(doc.Locations)),
				kvp.Int("num_paths_for_doc_sha", numPathsForDocSHA),
				kvp.Int("num_paths_for_doc_sha_not_verified", contentTracker.numPathsForDocSHA(docSHA)),
			)

			contentTracker.removeDocSHA(docSHA)
		}
	}

	return &VerifiedSummary{
		Verified: matchedPaths,
		Extra:    extraPaths,
	}, nil
}

// Filters items out of the expectedPaths map if they detected to be generated
// content. In order to do this, blob content must be downloaded from spokes.
// Returns the number of blobs that were downloaded and/or an error. Mutates
// the expected oidPathMap, deleting entries that are detected as generated.
func (p *CompletenessProber) filterOutGeneratedPaths(ctx context.Context, contentTracker *contentTracker, verbose bool) error {
	requestedBlobSHAs := contentTracker.blobSHAs()
	spokesOIDs := make([]*spokes.ObjectID, 0, len(requestedBlobSHAs))
	for blobSHA := range requestedBlobSHAs {
		spokesOIDs = append(spokesOIDs, spokes.NewObjectID(blobSHA.String()))
	}

	const batchSize = 25
	start := 0
	end := batchSize
	downloaded := 0
	for {
		if start >= len(spokesOIDs) {
			break
		}
		if end > len(spokesOIDs) {
			end = len(spokesOIDs)
		}

		// NB: GetBlobs can return fewer blobs than requested oids. Blobs not
		// returned were filtered out by the underlying spokes method
		// (streaming.NewBatchBlobsHTTPRequest) which takes a list of filters
		// (utf8-only, plaintext-only, etc) and only returns content for blobs that
		// pass those filters. This means that if we ask for a blobOID and then
		// don't get back content, that blob is not suitable for indexing.
		if err := p.gitClient.GetBlobs(ctx, p.repoID, spokesOIDs[start:end], func(blob *gitaccess.BlobEntry) {
			downloaded++
			delete(requestedBlobSHAs, blob.OID)
			paths := contentTracker.pathsForBlobSHA(blob.OID)
			if len(paths) == 0 {
				panic(fmt.Sprintf("invariant violated: No paths for blob %s", blob.OID))
			}

			for _, path := range paths {
				isIndexable, reason, err := linguist.IsIndexable(path, blob.Content, uint32(p.index.EpochID()))
				if err != nil {
					logging.Error(ctx, "isIndexable failed", kvp.Err(err), kvp.String("path", path))
					continue
				}

				if !isIndexable {
					if verbose {
						logging.Info(ctx, "prober skipping check of path due to content exclusion", kvp.String("path", path), kvp.String("skip_reason", reason))
					}

					contentTracker.removePathForBlobSHA(blob.OID, path)
				}
			}
		}); err != nil {
			return err
		}
		start = end
		end += batchSize
	}

	// Any requested OID that did not get returned with content by GetBlobs are files
	// we intentionally excluded from indexing (e.g. binary content). We can
	// safely remove these from the expectedPaths set.
	filtered := 0
	for blobSHA := range requestedBlobSHAs {
		filtered++
		paths := contentTracker.pathsForBlobSHA(blobSHA)
		if verbose {
			logging.Info(
				ctx,
				"will not expect paths from content filtered by GetBlobs as it's not suitable for indexing",
				kvp.String("blob_oid", blobSHA.String()),
				kvp.String("paths", strings.Join(paths, ",")),
			)
		}

		for _, path := range paths {
			contentTracker.removePathForBlobSHA(blobSHA, path)
		}
	}

	statting.Counter(ctx, "prober.completeness.blobs_requested", int64(len(spokesOIDs)))
	statting.Counter(ctx, "prober.completeness.blobs_filtered", int64(filtered))
	statting.Counter(ctx, "prober.completeness.blobs_downloaded", int64(downloaded))

	return nil
}

// Perform a prober specific search with custom blackbird query limits and query
// content settings.
func (p *CompletenessProber) search(ctx context.Context, q *parser.Query) (*pb.QueryResponse, error) {
	ctx, cancel := context.WithTimeout(ctx, proberRequestTimeout)
	defer cancel()

	const bigLimit = 10000
	queryCtx := search.BuildQueryContext(
		&models.Actor{AccessiblePrivateRepoIDs: types.RepoIDSet{p.repoID: true}},
		search.QueryLimits{
			RequestedDocs:  bigLimit,
			RequestedLocs:  blackbirdLocationLimit,
			LocationsLimit: blackbirdLocationLimit,
			TermMatchLimit: 0, // NB: No need for any term matches
			ToRetrieve:     bigLimit,
			ToScore:        bigLimit,
			ToReturn:       bigLimit,
			WithContent:    0, // NB: Set to 0 to tell blackbird not to bother sending any content
		},
		3, /* retries */
		search.ProbersUnavailableShardsPercent,
		proberRPCTimeout,
		search.QueryTypeCompleteness,
		search.QuerySourceProber,
		parser.GetScopeRepoIDs(q),
		nil, /* snippetOptions */
		nil, /* paginationOptions */
		parser.Serialize(q),
		false, /* returnEnclosingSymbols */
	)

	rid := uuid.New().String()
	ctx = logging.With(requestid.WithGitHubRequestID(ctx, rid), kvp.String("request_id", rid))
	res, err := p.index.Search(ctx, parser.ConvertToProto(q), queryCtx)
	if err == nil {
		for _, e := range res.QueryErrors {
			logging.Error(ctx, "query error", kvp.String("query_error", e.Message), kvp.String("query_error_type", e.Type.String()))
			return nil, errors.New(e.Message)
		}
	}
	return res, err
}

func locationKVPs(loc *pb.Location) []kvp.Field {
	return []kvp.Field{
		kvp.String("loc_path", loc.Path),
		kvp.Int("loc_repo_id", int(loc.RepoId)),
		kvp.Int("loc_owner_id", int(loc.OwnerId)),
		kvp.String("loc_commit_sha", gitaccess.NewObjectIDFromBytes(loc.CommitSha).String()),
		kvp.String("loc_ref_name", loc.RefName),
		kvp.Int("loc_repo_score", int(loc.RepoScore)),
		kvp.Bool("loc_is_repo_public", loc.IsRepoPublic),
		kvp.String("loc_repo_nwo", loc.RepoNwo),
		kvp.Int("loc_network_id", int(loc.NetworkId)),
	}
}
