package storage

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"sort"
	"time"

	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/Masterminds/semver"
	"github.com/github/dependency-snapshots-api/internal/graph"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/go-stats"
	_ "github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/package-url/packageurl-go"
)

// This model (and related JSON structs) is targeting DB persistence for data created by
//
//	https://github.com/github/dependency-graph-api/tree/master/app/models/snapshots
//
// Unless otherwise documented, assume that the domain described by proto/snapshots.proto is a
//
//	starting point for understanding these types.
//
// See getSnapshotByIDSQLQuery for a query that match up with this struct.
type snapshotModel struct {
	ID             uint64         `db:"id"`
	RepositoryID   uint64         `db:"repository_id"`
	SnapshotBlobID uint64         `db:"snapshot_blob_id"`
	SHA            string         `db:"sha"`
	Internal       bool           `db:"internal"`
	Ref            string         `db:"branch_ref"`
	CreatedAt      time.Time      `db:"created_at"`
	MetadataJSON   string         `db:"metadata"`
	BlobJSON       string         `db:"blob"`
	BlobURL        sql.NullString `db:"blob_url"`
}

// This represents the JSON object that is stored in the DB in the
// `ds_snapshot_blobs` table.
type snapshotBlobJSON struct {
	Version uint64    `json:"version"`
	Job     jobJSON   `json:"job"`
	SHA     string    `json:"sha"`
	Ref     string    `json:"ref"`
	Scanned time.Time `json:"scanned"`
	// Optional keys
	Manifests map[string]manifestJSON `json:"manifests"`
	Detector  detectorJSON            `json:"detector"`
	Metadata  metadata                `json:"metadata"`
}

// Enforced at boundary: scalar values only
type metadata = map[string]interface{}

type detectorJSON struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	// Optional
	URL string `json:"url"`
}

type jobJSON struct {
	Correlator string `json:"correlator"`
	ID         string `json:"id"`
	HTMLUrl    string `json:"html_url"`
}

func (j *jobJSON) UnmarshalJSON(data []byte) error {
	type Alias jobJSON
	aux := &struct {
		Name string `json:"name"`
		*Alias
	}{
		Alias: (*Alias)(j),
	}

	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}

	if aux.Correlator == "" {
		j.Correlator = aux.Name
	}
	return nil
}

// manifestJSON is the type of the JSON value for a manifest path key
type manifestJSON struct {
	Name string `json:"name"`
	// Everything other than `Name` is optional
	File     fileJSON `json:"file"`
	Metadata metadata `json:"metadata"`
	// Dependencies stored by arbitrary key
	Resolved    map[string]resolvedNodeJSON `json:"resolved"`
	SnapshotIDs []uint64                    `json:"snapshot_ids"`
}

type fileJSON struct {
	// Optional
	SourceLocation string `json:"source_location"`
}

// These are dependencies, but also nodes in the graph. In the full schema they
// show up as values where the keys are arbitrary names.
type resolvedNodeJSON struct {
	// All of these are optional
	PackageURL   string   `json:"package_url"`
	Metadata     metadata `json:"metadata"`
	Relationship string   `json:"relationship"`
	Scope        string   `json:"scope"`
	Dependencies []string `json:"dependencies"`
}

func (d *resolvedNodeJSON) UnmarshalJSON(data []byte) error {
	type Alias resolvedNodeJSON
	aux := &struct {
		DeprecatedPurl string `json:"purl"`
		*Alias
	}{
		Alias: (*Alias)(d),
	}

	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}

	if aux.DeprecatedPurl != "" {
		d.PackageURL = aux.DeprecatedPurl
		aux.DeprecatedPurl = ""
	}
	return nil
}

// Parameters: (repository_id int, snapshot_id int)
const getSnapshotByIDSQLQuery = `
	SELECT s.id,
		   s.repository_id,
		   s.snapshot_blob_id,
		   s.sha,
		   s.internal,
		   s.branch_ref,
		   s.created_at,
		   s.metadata,
		   sb.blob,
		   sb.blob_url
	FROM   ds_snapshots s
		   JOIN ds_snapshot_blobs sb
			 ON s.snapshot_blob_id = sb.id
			 AND s.repository_id = sb.repository_id
	WHERE  s.repository_id = ? and s.id = ?
	LIMIT  1 `

// Parameters: (repository_id int, sha string)
const getSnapshotIDsBySHASQLQuery = `
	SELECT id
	FROM   ds_snapshots
	WHERE  repository_id = ? AND sha = ?
	AND   internal = false
`

func (r *MySQLSnapshotsAdapter) QuerySnapshots(ctx context.Context, repositoryID uint64, query interfaces.SnapshotsQuery) ([]*interfaces.Snapshot, error) {
	if len(query.SHA) == 0 {
		return nil, errors.New("must specify SHA")
	}

	// first get the snapshot IDs
	matchingSnapshotIDs := []struct {
		ID uint64 `db:"id"`
	}{}

	err := QueryRows(ctx, r.DB, &matchingSnapshotIDs, "QuerySnapshots", getSnapshotIDsBySHASQLQuery, repositoryID, query.SHA)
	if err != nil {
		return nil, errors.Wrap(err, "failed to execute getSnapshotIDsBySHASQLQuery")
	}

	// then get the snapshots
	snapshots := make([]*interfaces.Snapshot, 0)
	for _, match := range matchingSnapshotIDs {
		snapshot, err := r.SnapshotByID(ctx, repositoryID, match.ID)
		if err != nil {
			return nil, errors.Wrap(err, "failed to get snapshot by ID")
		}
		snapshots = append(snapshots, snapshot)
	}

	return filterSuperseded(snapshots), nil
}

func (r *MySQLSnapshotsAdapter) SnapshotByID(ctx context.Context, repositoryID uint64, snapshotID uint64) (*interfaces.Snapshot, error) {
	snapshot := new(snapshotModel)

	ok, err := QueryRow(ctx, r.DB, snapshot, "SnapshotByID", getSnapshotByIDSQLQuery, repositoryID, snapshotID)
	if err != nil {
		return nil, errors.Wrap(err, "failed to execute getSnapshotByIDSQLQuery")
	}
	if !ok || err != nil {
		return nil, err
	}

	blobJSON, err := r.fetchJSONFromBlobStorageIfExists(ctx, repositoryID, snapshot.BlobURL, r.ShouldStoreBlobsInAzure)
	if err != nil {
		return nil, errors.Wrap(err, "snapshot JSON could not be loaded from blob storage")
	} else if len(blobJSON) != 0 {
		snapshot.BlobJSON = string(blobJSON)
	}

	return convertDependencyGraphDBSnapshotToInterfacesSnapshot(snapshot)
}

// fetchJSONFromBlobStorageIfExists fetches json from blob storage, if it can be found and if blob storage is configured.
// this method can return an empty byte array and no error in cases where nothing is found but blob storage is not configured
// (or the snapshot does not have a blob URL). As we migrate data in production, this method could start to return an error instead
// of an empty result.
// When GHES support is added, this method will likely need to support a config flag to know if an error or empty response is valid.
func (r *MySQLSnapshotsAdapter) fetchJSONFromBlobStorageIfExists(ctx context.Context, repositoryID uint64, blobURL sql.NullString, useBlobStoreForRead bool) ([]byte, error) {
	// it's an unusual case when r.blobs == nil but we have a blobURL.
	// in practice, it should only happen if we were to rollback blob enablement while this code was still around,
	// and it also happens in tests (since we alternate between which mode we run in).
	if blobURL.Valid && r.BlobClient != nil && useBlobStoreForRead {
		contents, err := r.BlobClient.GetBlob(ctx, blobURL.String)
		if err != nil {
			return []byte{}, errors.Wrap(err, "blob contents could not be fetched for blob")
		}
		return contents, nil
	}

	// Once all DB snapshots have been updated to have blobURLs, we can enforce an
	// error condition here.
	return []byte{}, nil
}

type canonicalSnapshotRow struct {
	ID           uint64         `db:"id"`
	SnapshotID   uint64         `db:"snapshot_id"`
	RepositoryID uint64         `db:"repository_id"`
	Blob         []byte         `db:"blob"`
	BlobURL      sql.NullString `db:"blob_url"`
	SHA          string         `db:"sha"`
	ScannedAt    time.Time      `db:"scanned_at"`
	UpdatedStamp time.Time      `db:"updated_stamp"`
	StaleSince   sql.NullTime   `db:"stale_since"`
}

// Parameters: (repository_id int, include_internal bool)
// note that include_internal should be either 0 or 1.
const getCanonicalSnapshotsForRepositorySQLQuery = `
	select cs.id,
	       s.id as snapshot_id,
		   s.repository_id,
		   sb.blob,
		   sb.blob_url,
		   s.sha,
		   s.scanned_at,
		   cs.updated_stamp,
		   cs.stale_since
	from   ds_canonical_snapshots cs
		   join ds_snapshots s on cs.snapshot_id = s.id and cs.repository_id = s.repository_id
		   join ds_snapshot_blobs sb on s.snapshot_blob_id = sb.id and sb.repository_id = s.repository_id
	where  cs.repository_id = ?
	  and  s.internal <= ?
`

func (r *MySQLSnapshotsAdapter) CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode interfaces.SnapshotQueryMode) ([]*interfaces.Snapshot, error) {
	return r.canonicalSnapshotsForRepository(ctx, r.DB, repositoryID, mode)
}

func (r *MySQLSnapshotsAdapter) canonicalSnapshotsForRepository(ctx context.Context, queryable Queryable, repositoryID uint64, mode interfaces.SnapshotQueryMode) ([]*interfaces.Snapshot, error) {
	results := []*canonicalSnapshotRow{}

	rowHandler := func(rows *sqlx.Rows) error {
		var result canonicalSnapshotRow
		err := rows.StructScan(&result)
		if err != nil {
			return err
		}
		results = append(results, &result)
		return nil
	}

	err := ExecuteQueryAndReadRows(ctx, r.DB, rowHandler, "CanonicalSnapshotsForRepository", getCanonicalSnapshotsForRepositorySQLQuery, repositoryID, mode)
	if err != nil {
		return nil, errors.Wrap(err, "failed to execute getCanonicalSnapshotsForRepositorySQLQuery")
	}

	// fetch blobs in parallel
	if r.ShouldStoreBlobsInAzure {
		group, groupCtx := errgroup.WithContext(ctx)
		group.SetLimit(50) // protect against runaway goroutine creation and resource exhaustion
		for _, result := range results {
			result := result
			group.Go(func() error {
				blobJSON, err := r.fetchJSONFromBlobStorageIfExists(groupCtx, repositoryID, result.BlobURL, r.ShouldStoreBlobsInAzure)
				if err != nil {
					return errors.Wrap(err, "blob JSON could not be loaded from blob storage")
				} else if len(blobJSON) > 0 {
					result.Blob = blobJSON
				}
				return nil
			})
		}

		err := group.Wait()
		if err != nil {
			return nil, err
		}
	}

	var measureTxPathsEnabled bool
	// TODO: uncomment if/when we decide to expose transitive paths. See https://github.com/github/dependency-graph/issues/2321
	// if r.Features != nil {
	// 	measureTxPathsEnabled, err = r.Features.
	// 		IsFeatureFlagEnabledForRepository(ctx, "dependency_snapshots_transitive_paths", repositoryID)
	// 	if err != nil {
	// 		r.Statter.Counter("tx_paths.error", stats.Tags{"stage": "pre", "error_type": "feature_flag"}, 1)
	// 		measureTxPathsEnabled = false
	// 	}
	// }

	snapshots := make([]*interfaces.Snapshot, len(results))
	for i, result := range results {
		snapshot := new(interfaces.Snapshot)

		err = json.Unmarshal(result.Blob, snapshot)
		if err != nil {
			return nil, errors.Wrapf(err, "could not unmarshal snapshot blob for snapshot with ID: %d", result.SnapshotID)
		}

		snapshot.ID = result.SnapshotID
		snapshot.RepositoryID = result.RepositoryID
		snapshots[i] = snapshot

		if measureTxPathsEnabled {
			// TODO: capture the extracted paths, once we know it's feasible to ship this!
			r.extractMeasureTransitivePaths(snapshot)
		}
	}

	return snapshots, nil
}

func (r *MySQLSnapshotsAdapter) extractMeasureTransitivePaths(snapshot *interfaces.Snapshot) {
	if r.Statter == nil {
		return
	}

	for _, manifest := range snapshot.Manifests {
		manifestStart := time.Now()

		var finder graph.Pathfinder
		var err error
		finder, err = graph.New(manifest)
		if err != nil {
			r.Statter.Counter("tx_paths.error", stats.Tags{"stage": "init", "error_type": fmt.Sprintf("%t", err)}, 1)
			continue
		}

		r.Statter.Distribution("tx_paths.dependencies_per_manifest", stats.Tags{}, float64(len(manifest.Resolved)))
		for depName := range manifest.Resolved {
			dependencyStart := time.Now()
			_, err = finder.PathsFrom(depName)
			if err != nil {
				r.Statter.Counter("tx_paths.error", stats.Tags{"stage": "paths_from", "error_type": fmt.Sprintf("%t", err)}, 1)
				continue
			}
			elapsed := float64(time.Since(dependencyStart).Milliseconds())
			r.Statter.Distribution("tx_paths.dependency.elapsed", stats.Tags{}, elapsed)
		}
		elapsed := float64(time.Since(manifestStart).Milliseconds())
		r.Statter.Distribution("tx_paths.manifest.elapsed", stats.Tags{}, elapsed)
	}
}

// Parameters: (repository_id int, include_internal bool)
// note that include_internal should be either 0 or 1.
const getCanonicalSnapshotIDsForRepositorySQLQuery = `
	select s.id as snapshot_id
	from   ds_canonical_snapshots cs
		   join ds_snapshots s on cs.snapshot_id = s.id and cs.repository_id = s.repository_id
		   join ds_snapshot_blobs sb on s.snapshot_blob_id = sb.id and sb.repository_id = s.repository_id
	where  cs.repository_id = ?
	order by snapshot_id asc
`

type snapshotIDRow struct {
	SnapshotID uint64 `db:"snapshot_id"`
}

func (r *MySQLSnapshotsAdapter) canonicalSnapshotIDsForRepository(ctx context.Context, queryable Queryable, repositoryID uint64) ([]uint64, error) {
	results := []*snapshotIDRow{}

	rowHandler := func(rows *sqlx.Rows) error {
		var result snapshotIDRow
		err := rows.StructScan(&result)
		if err != nil {
			return err
		}
		results = append(results, &result)
		return nil
	}

	err := ExecuteQueryAndReadRows(ctx, r.DB, rowHandler, "CanonicalSnapshotIDsForRepository", getCanonicalSnapshotIDsForRepositorySQLQuery, repositoryID)
	if err != nil {
		return nil, errors.Wrap(err, "failed to execute getCanonicalSnapshotsForRepositorySQLQuery")
	}

	ids := make([]uint64, len(results))
	for i, result := range results {
		ids[i] = result.SnapshotID
	}

	return ids, nil
}

func (r *MySQLSnapshotsAdapter) HasManifests(ctx context.Context, repositoryID uint64) (bool, error) {
	hasManifestsSQLQuery := `
	 	select 1 as one
		from ds_canonical_snapshots
		join ds_snapshots on ds_canonical_snapshots.snapshot_id = ds_snapshots.id
		where ds_canonical_snapshots.repository_id = ?
		and ds_snapshots.internal = 0
		limit 1
	`
	dest := struct {
		One int `db:"one"`
	}{}

	ok, err := QueryRow(ctx, r.DB, &dest, "HasManifests", hasManifestsSQLQuery, repositoryID)
	if err != nil {
		return false, errors.Wrap(err, "failed to execute HasManifestsSQLQuery")
	}

	return ok, nil
}

type matchingDependencyWithVersion struct {
	RepositoryID      uint64 `db:"repository_id"`
	DependencyVersion string `db:"dependency_version"`
}

// Parameters: (packageName string)
const getAllMatchingDependenciesQuery = `
	SELECT repository_id, dependency_version
	FROM   ds_repository_dependencies_staged
	WHERE  staged = 0 AND dependency_locator = ?`

func (r *MySQLSnapshotsAdapter) allMatchingDependenciesWithVersions(ctx context.Context, queryPurl string) ([]matchingDependencyWithVersion, error) {
	purl, err := packageurl.FromString(queryPurl)
	if err != nil {
		return nil, errors.Wrap(err, "unable to parse purl")
	}

	results := make([]matchingDependencyWithVersion, 0)
	rowHandler := func(rows *sqlx.Rows) error {
		var result matchingDependencyWithVersion
		err := rows.StructScan(&result)
		if err != nil {
			return err
		}

		results = append(results, result)
		return nil
	}

	dependencyLocator := getDependencyLocatorPURL(purl)
	err = ExecuteQueryAndReadRows(ctx, r.DB, rowHandler, "AllMatchingDependencies", getAllMatchingDependenciesQuery, dependencyLocator.String())
	if err != nil {
		return nil, errors.Wrap(err, "failed to execute getAllMatchingDependenciesQuery")
	}

	return results, nil
}

// SearchForRepositoriesContainingDependency returns the same data as SearchCanonicalSnapshots, but with a specific performance optimization.
// It's expected that if this optimization is chosen, we will delete the old SearchCanonicalSnapshots method and prefer this implementation.
func (r *MySQLSnapshotsAdapter) SearchForRepositoriesContainingDependency(ctx context.Context, queryPurl string, versionConstraint string) ([]uint64, error) {
	matchingDependencies, err := r.allMatchingDependenciesWithVersions(ctx, queryPurl)
	if err != nil {
		return nil, errors.Wrap(err, "unable to get all matching dependencies containing package")
	}

	constraintMatch, err := newConstraintPredicate(versionConstraint)
	if err != nil {
		return nil, errors.Wrap(err, "unable to create version range predicate")
	}

	containedByRepositoryIDs := make([]uint64, 0)
	for _, dependency := range matchingDependencies {
		if constraintMatch(dependency.DependencyVersion) {
			containedByRepositoryIDs = append(containedByRepositoryIDs, dependency.RepositoryID)
		}
	}

	return containedByRepositoryIDs, nil
}

func convertDependencyGraphDBSnapshotToInterfacesSnapshot(snapshot *snapshotModel) (*interfaces.Snapshot, error) {
	metadata, err := unmarshalMetadata(snapshot)
	if err != nil {
		return nil, errors.Wrap(err, "unmarshalling metadata")
	}

	blob, err := unmarshalSnapshotBlob(snapshot)
	if err != nil {
		return nil, errors.Wrap(err, "unmarshalling manifests")
	}

	return &interfaces.Snapshot{
		Version:      blob.Version,
		Job:          interfaces.Job{Correlator: blob.Job.Correlator, ID: blob.Job.ID, HTMLUrl: blob.Job.HTMLUrl},
		SHA:          snapshot.SHA,
		Internal:     snapshot.Internal,
		Ref:          blob.Ref,
		Detector:     &interfaces.DetectorMetadata{Name: blob.Detector.Name, Version: blob.Detector.Version, URL: blob.Detector.URL},
		Metadata:     *metadata,
		Manifests:    convertDBManifestsToInterfaceManifests(blob.Manifests),
		Scanned:      blob.Scanned,
		ID:           snapshot.ID,
		RepositoryID: snapshot.RepositoryID,
	}, nil
}

func convertDBManifestsToInterfaceManifests(manifests map[string]manifestJSON) interfaces.Manifests {
	result := interfaces.Manifests{}

	for path, manifest := range manifests {
		depGraph := interfaces.DependencyGraph{}
		// iterate through the resolved nodes and add them to depGraph
		for name, resolvedNode := range manifest.Resolved {
			depGraph[name] = &interfaces.DependencyNode{
				PackageURL:   resolvedNode.PackageURL,
				Metadata:     resolvedNode.Metadata,
				Relationship: interfaces.DependencyRelationshipValues[resolvedNode.Relationship],
				Scope:        interfaces.DependencyScopeValues[resolvedNode.Scope],
				Dependencies: resolvedNode.Dependencies,
			}
		}
		convertedManifest := interfaces.Manifest{
			Name:     manifest.Name,
			File:     interfaces.FileInfo{SourceLocation: manifest.File.SourceLocation},
			Metadata: manifest.Metadata,
			Resolved: depGraph,
		}
		result[path] = &convertedManifest
	}

	return result
}

func unmarshalSnapshotBlob(snapshot *snapshotModel) (*snapshotBlobJSON, error) {
	var blob snapshotBlobJSON
	if len(snapshot.BlobJSON) == 0 {
		return nil, errors.Errorf("snapshot blob is empty")
	}
	err := json.Unmarshal([]byte(snapshot.BlobJSON), &blob)
	if err != nil {
		return nil, errors.Wrapf(err, "unmarshalling snapshot blob")
	}

	return &blob, nil
}

// Returns a map of no more than 8 k-v pairs, where all values are scalars.
func unmarshalMetadata(snapshot *snapshotModel) (*metadata, error) {
	sanitizedMetadata := metadata{}
	metadata := metadata{}
	if len(snapshot.MetadataJSON) == 0 {
		return &sanitizedMetadata, nil
	}
	err := json.Unmarshal([]byte(snapshot.MetadataJSON), &metadata)
	if err != nil {
		return nil, errors.Wrap(err, "unmarshalling metadata json")
	} else {
		i := 0
		for k, v := range metadata {
			// maximum metadata size is 8 k-v pairs
			if i >= 8 {
				break
			}
			// Non-scalar values should fail validation long before they're stored here,
			// but make sure to exclude them from snapshots otherwise.
			if isJSONScalar(v) {
				sanitizedMetadata[k] = v
				i += 1
			}
		}
	}

	return &sanitizedMetadata, nil
}

// Returns true if `x` is a scalar value, assuming that `x` is deserialized from JSON.
func isJSONScalar(x interface{}) bool {
	switch x.(type) {
	case string:
		return true
	case float64:
		return true
	case bool:
		return true
	case nil:
		return true
	default:
		return false
	}
}

// newConstraintPredicate returns a predicate that can be used to check if a
// semver version matches a semver constraint.
// constraintStr is a semver range, e.g. ">= 2.3.0 < 3.0.0"
// versionStr is a semver version, e.g. "2.3.4"
func newConstraintPredicate(constraintStr string) (func(string) bool, error) {
	constraint, err := semver.NewConstraint(constraintStr)
	if err != nil {
		return nil, errors.Wrap(err, "invalid constraint string")
	}

	return func(versionStr string) bool {
		version, err := semver.NewVersion(versionStr)
		if err != nil {
			return false
		}
		return constraint.Check(version)
	}, nil
}

// filterSuperseded returns a new slice of snapshots, containing only the most recent
// snapshot for each (detector, correlator) pair.
func filterSuperseded(snapshots []*interfaces.Snapshot) []*interfaces.Snapshot {
	filtered := []*interfaces.Snapshot{}

	// sort snapshots by timestamp (newest first)
	sort.Slice(snapshots, func(i, j int) bool {
		return snapshots[i].Scanned.After(snapshots[j].Scanned)
	})

	// i.e., map[detector]correlator
	// keep track of which (detector, correlator) pairs we've seen so that we keep just one
	// snapshot for each combination
	seen := map[string]string{}

	for _, snap := range snapshots {
		if seen[snap.Detector.Name] == snap.Job.Correlator {
			continue
		}
		seen[snap.Detector.Name] = snap.Job.Correlator
		filtered = append(filtered, snap)
	}

	return filtered
}
