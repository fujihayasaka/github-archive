package manifests

import (
	"context"
	"time"
	"unicode/utf8"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/trace"
	"github.com/github/go-stats"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/pkg/errors"
)

// RepositoryEnumerator extracts all supported manifest types from enumerated repo blob contents at
// the given repo ID and commit. If no commit is supplied, the enumerator will target the
// current HEAD of default branch.
type RepositoryEnumerator interface {
	Process(ctx context.Context, repoID uint64, commitOID string) (RelatedManifests, error)
}

// meets RepositoryEnumerator contract
var _ RepositoryEnumerator = repoEnumImpl{}

type repoEnumImpl struct {
	cfg     *config.Config
	tracer  *trace.Tracer
	statter stats.Client
	client  gitaccess.Client
}

const repoEnumeratorTracerName = "aqueduct.manifests.RepositoryEnumerator"

// NewRepositoryEnumerator creates a new RepositoryEnumerator instance.
func NewRepositoryEnumerator(cfg *config.Config, t *trace.Tracer, s stats.Client, client gitaccess.Client) RepositoryEnumerator {
	return repoEnumImpl{
		cfg:     cfg,
		client:  client,
		tracer:  t,
		statter: s,
	}
}

func (m repoEnumImpl) Process(ctx context.Context, repoID uint64, commitOID string) (RelatedManifests, error) {
	if repoID == 0 {
		tags := stats.Tags{"reason": "missing_repo"}
		m.statter.Counter("manifest.etl.repo_enumerator.process.error", tags, 1)
		return emptyRM, errors.New("in RepositoryEnumerator.Process: missing required repository ID")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, repoEnumeratorTracerName, "Process")
	defer ender()

	start := time.Now()
	defer func() {
		m.statter.DistributionMs("manifest.etl.repo_enumerator.process", nil, time.Since(start))
	}()

	// If no commit is supplied, resolve the current HEAD of the default branch.
	if len(commitOID) == 0 {
		head, err := m.client.ResolveRef(ctx, repoID, "HEAD")
		if err != nil {
			m.statter.Counter("manifest.etl.repo_enumerator.process.error", stats.Tags{"reason": "resolve_head"}, 1)
			return emptyRM, errors.Wrap(err, "in RepositoryEnumerator.Process: failed to resolve HEAD commit OID")
		}
		commitOID = head.GetId()
	}

	kvps := []kvp.Field{
		semconv.RepoID(repoID),
		kvp.String("gh.git.commit.oid", commitOID),
	}

	// if OID is present, resolve repo contents at specified commit
	entries, err := m.client.ListTreeByCommit(ctx, repoID, commitOID)
	if err != nil {
		m.statter.Counter("manifest.etl.repo_enumerator.process.error", stats.Tags{"reason": "list_tree_from_oid"}, 1)
		contextlogger.Error(ctx, "failed to list tree from OID",
			kvp.String("exception.message", err.Error()),
			kvps[0], kvps[1])
		return emptyRM, errors.Wrap(err, "in RepositoryEnumerator.Process: failed to list tree from OID")
	}

	// filter all supported manifest types from the repository
	// then group by related changes to be submitted for ingest
	// or deletion processing together
	return m.filterEntries(ctx, entries)
}

// filterEntries filters and groups related manifest entries in the repository Git tree, and reports results
func (m repoEnumImpl) filterEntries(ctx context.Context, entries []*types.TreeEntry) (RelatedManifests, error) {
	var totalBlobs int64
	totalEntries := int64(len(entries))

	grouper := newManifestGrouper(m.cfg.ManifestETLMaxChanges)
	for _, entry := range entries {
		if entry == nil || !entry.GetObject().IsBlob() {
			continue
		}
		totalBlobs += 1

		mc, found := m.manifestFromEntry(ctx, entry)
		if found {
			if err := grouper.Store(mc); err != nil {
				return RelatedManifests{}, err
			}
		}
	}
	m.statter.Counter("manifest.etl.repo_enumerator.total_blobs", nil, totalBlobs)
	m.statter.Counter("manifest.etl.repo_enumerator.total_entries", nil, totalEntries)

	adds, _, _ := grouper.Report()
	m.statter.Counter("manifest.etl.repo_enumerator.manifests.collected", stats.Tags{"change": "added"}, adds)
	contextlogger.Info(ctx, "manifests successfully collected from repository enumeration",
		kvp.Int64("gh.dsapi.etl.repo_enumerator.manifests.added", adds),
		kvp.Int64("gh.dsapi.etl.repo_enumerator.manifests.total_entries", totalEntries),
		kvp.Int64("gh.dsapi.etl.repo_enumerator.manifests.total_blobs", totalBlobs))

	return grouper.ToRelatedManifests(), nil
}

func (m repoEnumImpl) manifestFromEntry(ctx context.Context, entry *types.TreeEntry) (ManifestChange, bool) {
	rawPath := entry.GetPath().GetName()
	blobOID := entry.GetObject().GetOid().GetId()
	change := ChangeAdded

	// no, this doesn't panic on non UTF-8 inputs
	filePath := string(rawPath)

	// since we fetch and parse by blob contents, this isn't fatal...but
	// unlikely we'd want to keep them? for a manifest, it doesn't bode well
	if !utf8.Valid(rawPath) {
		contextlogger.Warn(ctx, "TreeEntry with non UTF-8 file path",
			kvp.String("gh.dsapi.repo_enumerator.manifest.filepath", filePath))
		tags := stats.Tags{"reason": "non_utf8_path"}
		m.statter.Counter("manifest.etl.repo_enumerator.filter.dropped", tags, 1)

		return emptyMC, false // ditch this if we want to log + keep these strange asciifests
	}

	if info, found := ClassifyManifest(filePath); found {
		if info.IsVendored {
			tags := stats.Tags{"reason": "vendored"}
			m.statter.Counter("manifest.etl.repo_enumerator.filter.dropped", tags, 1)
			contextlogger.Info(ctx, "Dropping vendored manifest",
				kvp.String("gh.dsapi.repo_enumerator.manifest.filepath", filePath))
			return emptyMC, false
		}

		m.statter.Counter("manifest.etl.repo_enumerator.filter.matched",
			stats.Tags{
				"manifest_type": info.FileType.String(),
				"ecosystem":     info.Ecosystem.String(),
				"change":        change.String(),
			}, 1)

		return NewManifestChange(info, blobOID, change), true
	}

	m.statter.Counter("manifest.etl.repo_enumerator.filter.dropped", stats.Tags{"reason": "ineligible"}, 1)
	return emptyMC, false
}
