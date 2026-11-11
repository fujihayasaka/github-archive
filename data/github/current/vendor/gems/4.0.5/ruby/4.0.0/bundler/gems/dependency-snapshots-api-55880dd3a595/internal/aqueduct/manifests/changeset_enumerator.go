package manifests

import (
	"context"
	"fmt"
	"sort"
	"time"
	"unicode/utf8"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	jobs_proto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/trace"
	"github.com/github/go-stats"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/pkg/errors"
)

type ChangesetEnumerator interface {
	// this supports push changeset processing for manifest ETL
	Process(ctx context.Context, payload *jobs_proto.ManifestChangesetJob) (RelatedManifests, error)
}

// meets ChangesetEnumerator contract
var _ ChangesetEnumerator = changesetEnumImpl{}

type changesetEnumImpl struct {
	cfg     *config.Config
	tracer  *trace.Tracer
	statter stats.Client
	client  gitaccess.Client
}

const enumeratorTracerName = "aqueduct.manifests.ChangesetEnumerator"

var (
	emptyRM = RelatedManifests{}
	emptyMC = ManifestChange{}
)

func NewChangesetEnumerator(cfg *config.Config, t *trace.Tracer, s stats.Client, spc gitaccess.Client) changesetEnumImpl {
	return changesetEnumImpl{
		cfg:     cfg,
		client:  spc,
		tracer:  t,
		statter: s,
	}
}

func (m changesetEnumImpl) Process(ctx context.Context, payload *jobs_proto.ManifestChangesetJob) (RelatedManifests, error) {
	// make sure the event payload is well-formed and we can proceed
	if err := m.validatePayload(ctx, payload); err != nil {
		return emptyRM, err
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, enumeratorTracerName, "Process")
	defer ender()

	start := time.Now()
	defer func() {
		m.statter.DistributionMs("manifest.etl.changeset_enumerator.elapsed_ms", nil, time.Since(start))
	}()

	// obtain Git tree and diff entries representing the whole push changeset
	entries, err := m.client.CompareTrees(ctx,
		uint64(payload.GetRepositoryId()),
		payload.GetBeforeOid(),
		payload.GetAfterOid())
	if err != nil {
		// Tree comparison errors are non-fatal - we log and emit metrics but
		// continue with empty entries. This allows the job to complete gracefully
		// when Git operations fail transiently.
		m.statter.Counter("manifest.etl.changeset_enumerator.process.error", stats.Tags{"reason": "comparing_trees"}, 1)
		contextlogger.Error(ctx, "failed to compare trees",
			kvp.String("exception.message", err.Error()),
			semconv.RepoID(payload.GetRepositoryId()),
			semconv.MessagingMessageID(payload.GetEventId()),
			semconv.RequestID(payload.GetRequestId()))
		entries = nil
	}

	// filter all supported manifest types from the push changeset
	// then group by related changes to be submitted for ingest
	// or deletion processing together
	return m.filterDiffEntries(ctx, entries)
}

// filter and group manifests found in push changeset, report results
func (m changesetEnumImpl) filterDiffEntries(ctx context.Context, entries []*types.DiffEntry) (RelatedManifests, error) {
	var totalBlobs int64

	grouper := newManifestGrouper(m.cfg.ManifestETLMaxChanges)
	for _, entry := range entries {
		if entry == nil {
			continue
		}
		totalBlobs += 1

		mc, found := m.manifestFromDiff(ctx, entry)
		if found {
			if err := grouper.Store(mc); err != nil {
				return RelatedManifests{}, err
			}
		}
	}
	m.statter.Counter("manifest.etl.changeset_enumerator.manifests.total_blobs", nil, totalBlobs)

	adds, mods, dels := grouper.Report()
	m.statter.Counter("manifest.etl.changeset_enumerator.manifests.collected", stats.Tags{"change": "added"}, adds)
	m.statter.Counter("manifest.etl.changeset_enumerator.manifests.collected", stats.Tags{"change": "modified"}, mods)
	m.statter.Counter("manifest.etl.changeset_enumerator.manifests.collected", stats.Tags{"change": "deleted"}, dels)
	contextlogger.Info(ctx, "manifests successfully collected from push changeset",
		kvp.Int64("gh.dgp.etl.changeset_enumerator.manifests.added", adds),
		kvp.Int64("gh.dgp.etl.changeset_enumerator.manifests.modified", mods),
		kvp.Int64("gh.dgp.etl.changeset_enumerator.manifests.deleted", dels),
		kvp.Int64("gh.dgp.etl.changeset_enumerator.manifests.total_blobs", totalBlobs))

	return grouper.ToRelatedManifests(), nil
}

func (m changesetEnumImpl) manifestFromDiff(ctx context.Context, entry *types.DiffEntry) (ManifestChange, bool) {
	var rawPath []byte
	var blobOID string
	change := ChangeUnknown

	// the CompareTrees call sets the "includeRenames" flag to false, so
	// complex event types get expanded into a pair of ADDED and DELETED
	switch entry.GetStatus() {
	case types.DiffEntry_STATUS_ADDITION:
		change = ChangeAdded
		rawPath = entry.GetDestination().GetName()
		blobOID = entry.GetDestinationOid().GetId()

	case types.DiffEntry_STATUS_MODIFICATION:
		change = ChangeModified
		rawPath = entry.GetDestination().GetName()
		blobOID = entry.GetDestinationOid().GetId()

	case types.DiffEntry_STATUS_DELETION:
		change = ChangeDeleted
		rawPath = entry.GetSource().GetName()
		blobOID = entry.GetSourceOid().GetId()

	case types.DiffEntry_STATUS_TYPE:
		// DGP doesn't care about file perms changes
		return emptyMC, false

	default:
		// with the CompareTrees request config we use, this should never happen
		tags := stats.Tags{"reason": "invalid_diff_status"}
		m.statter.Counter("manifest.etl.changeset_enumerator.filter.dropped", tags, 1)
		contextlogger.Error(ctx, "unexpected DiffEntry status",
			kvp.String("gh.dgp.changeset_enumerator.diff_entry.status", entry.GetStatus().String()))
		return emptyMC, false
	}

	// no, this doesn't panic on non UTF-8 inputs
	filePath := string(rawPath)

	// since we fetch and parse by blob contents, this isn't fatal...but
	// unlikely we'd want to keep them? for a manifest, it doesn't bode well
	if !utf8.Valid(rawPath) {
		contextlogger.Warn(ctx, "DiffEntry with non UTF-8 file path",
			kvp.String("gh.dgp.changeset_enumerator.manifest.change_type", change.String()),
			kvp.String("gh.dgp.changeset_enumerator.manifest.filepath", filePath))
		tags := stats.Tags{"reason": "non_utf8_path"}
		m.statter.Counter("manifest.etl.changeset_enumerator.filter.dropped", tags, 1)

		return emptyMC, false // ditch this if we want to log + keep these strange asciifests
	}

	if info, found := ClassifyManifest(filePath); found {
		if info.IsVendored {
			tags := stats.Tags{"reason": "vendored"}
			m.statter.Counter("manifest.etl.changeset_enumerator.filter.dropped", tags, 1)
			return emptyMC, false
		}

		m.statter.Counter("manifest.etl.changeset_enumerator.filter.matched",
			stats.Tags{
				"manifest_type": info.FileType.String(),
				"ecosystem":     info.Ecosystem.String(),
				"change":        change.String(),
			}, 1)

		return NewManifestChange(info, blobOID, change), true
	}

	m.statter.Counter("manifest.etl.changeset_enumerator.filter.dropped", stats.Tags{"reason": "ineligible"}, 1)
	return emptyMC, false
}

// validate push changeset processing job payload
func (m changesetEnumImpl) validatePayload(ctx context.Context, payload *jobs_proto.ManifestChangesetJob) error {
	if payload.GetRepositoryId() == 0 {
		tags := stats.Tags{"reason": "missing_repo"}
		m.statter.Counter("manifest.etl.changeset_enumerator.process.error", tags, 1)
		contextlogger.Error(ctx, "event missing repository ID",
			semconv.RepoID(payload.GetRepositoryId()),
			semconv.MessagingMessageID(payload.GetEventId()),
			semconv.RequestID(payload.GetRequestId()))
		return errors.New("in ChangesetEnumerator.Process: missing repo ID in ManifestChangesetJob")
	}

	if len(payload.GetBeforeOid()) == 0 || len(payload.GetAfterOid()) == 0 {
		tags := stats.Tags{"reason": "missing_oids"}
		m.statter.Counter("manifest.etl.changeset_enumerator.process.error", tags, 1)
		contextlogger.Error(ctx, "event missing before or after commit OID",
			semconv.RepoID(payload.GetRepositoryId()),
			semconv.MessagingMessageID(payload.GetEventId()),
			semconv.RequestID(payload.GetRequestId()))
		return errors.New("in ChangesetEnumerator.Process: missing commit OIDs for repo")
	}

	return nil
}

func NewManifestChange(info Info, oid string, change ChangeType) ManifestChange {
	return ManifestChange{
		FileInfo: info,
		BlobOID:  oid,
		Type:     change,
	}
}

// container for bucketing files identified as supported manifest types
// into related groups that should be ingested or deleted together
type manifestGrouper struct {
	addedModified map[string]map[ecosystems.Ecosystem][]ManifestChange
	deleted       []ManifestChange

	// how many manifests should be captured per push or repo repair operation?
	// NOTE! does *not* currently apply to deleted manifests
	maxManifestsCap int64

	// captured manifest counts
	addCount int64
	modCount int64
	delCount int64
}

// initialize a new grouper and supply a cap for max added/modified
// manifests to capture for this ingest operation
func newManifestGrouper(maxManifestsCap int64) *manifestGrouper {
	return &manifestGrouper{
		addedModified:   map[string]map[ecosystems.Ecosystem][]ManifestChange{},
		deleted:         []ManifestChange{},
		maxManifestsCap: maxManifestsCap,
	}
}

// bucket a manifest change into a group with related changes
func (gm *manifestGrouper) Store(mc ManifestChange) error {
	switch mc.Type {
	case ChangeAdded, ChangeModified:
		path := mc.FileInfo.Path
		eco := mc.FileInfo.Ecosystem

		if mc.Type == ChangeAdded {
			gm.addCount += 1
		} else {
			gm.modCount += 1
		}

		ecoBuckets, found := gm.addedModified[path]
		if !found {
			ecoBuckets = map[ecosystems.Ecosystem][]ManifestChange{}
		}

		// store manifest under eco sub-bucket to be grouped in single ingest job
		ecoBuckets[eco] = append(ecoBuckets[eco], mc)
		// (re)place the eco-scoped bucket under the path-scoped bucket
		gm.addedModified[path] = ecoBuckets

	case ChangeDeleted:
		gm.delCount += 1
		// no frills here - each deleted manifest can get its own delete job
		gm.deleted = append(gm.deleted, mc)

	default:
		return fmt.Errorf("Unexpected ManifestChange ChangeType: %s", mc.Type.String())
	}

	return nil
}

// return the results in a convenient shape for downstream submission as ingest and deletion jobs
func (gm *manifestGrouper) ToRelatedManifests() RelatedManifests {
	// added and modified grouped manifests should be sorted by
	// path length to attempt to avoid skew when there are more
	// manifests in the push (or the parent repo!) than the max
	// manifests cap. This mirrors the legacy approach and yes,
	// its pretty terrible. Let's reconsider it when there's time :)
	paths := make([]string, 0, len(gm.addedModified))
	for path := range gm.addedModified {
		paths = append(paths, path)
	}
	sort.Slice(paths, func(i, j int) bool { return len(paths[i]) < len(paths[j]) })

	var numManifests int64
	adds := [][]ManifestChange{}

ManifestLoop:
	for _, path := range paths {
		relatedByPath := gm.addedModified[path]
		for _, relatedChanges := range relatedByPath {
			adds = append(adds, relatedChanges)
			numManifests += int64(len(relatedChanges))
			if numManifests >= gm.maxManifestsCap {
				break ManifestLoop
			}
		}
	}

	return RelatedManifests{
		ToUpdate: adds,
		ToDelete: gm.deleted,
	}
}

func (gm *manifestGrouper) Report() (int64, int64, int64) {
	return gm.addCount, gm.modCount, gm.delCount
}
