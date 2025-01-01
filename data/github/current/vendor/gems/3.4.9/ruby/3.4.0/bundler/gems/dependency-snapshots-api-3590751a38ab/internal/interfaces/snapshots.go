package interfaces

import (
	"context"
	"encoding/json"
	"maps"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/package-url/packageurl-go"
)

// All structs in this class are 1:1 ports of what's currently in dg-api's models/snapshots.
// Including this link for reference as we figure out if this is the correct long term model shape:
//
//	 https://github.com/github/dependency-graph-api/tree/master/app/models/snapshots
//	At this point, the models have diverged significantly and their historical relationship is just an interesting note.
//
// Unless otherwise documented, assume that the domain described by proto/snapshots.proto is a
//
//	starting point for understanding these types.
type Snapshot struct {
	Version   uint64            `json:"version"`
	Job       Job               `json:"job"`
	SHA       string            `json:"sha"`
	Ref       string            `json:"ref"`
	Detector  *DetectorMetadata `json:"detector,omitempty"`
	Metadata  Metadata          `json:"metadata,omitempty"`
	Manifests Manifests         `json:"manifests,omitempty"`
	Scanned   time.Time         `json:"scanned"`
	Internal  bool              `json:"internal,omitempty"`

	// The ID and RepositoryID keys are not part of the public snapshot format.
	ID           uint64 `json:"-"`
	RepositoryID uint64 `json:"-"`
}

// Enum for the different snapshot querying modes:
// - Default: skips internal snapshots (for now)
// - IncludeInternal: includes internal snapshots
type SnapshotQueryMode int

const (
	DefaultQueryMode SnapshotQueryMode = iota
	IncludeInternal
)

type CanonicalUpdateMode int

const (
	DefaultUpdateMode = iota
	InternalUpdateMode
)

type SnapshotsQuery struct {
	SHA string
}

type Job struct {
	Correlator string `json:"correlator"`
	ID         string `json:"id"`
	HTMLUrl    string `json:"html_url,omitempty"`
}

func (j *Job) UnmarshalJSON(data []byte) error {
	type Alias Job
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

type DetectorMetadata struct {
	Name    string `json:"name"`
	URL     string `json:"url"`
	Version string `json:"version"`
}

type Manifests = map[string]*Manifest

type Manifest struct {
	Name       string          `json:"name"`
	File       FileInfo        `json:"file"`
	Metadata   Metadata        `json:"metadata,omitempty"`
	Resolved   DependencyGraph `json:"resolved"`
	SnapshotID uint64          `json:"snapshot_ids,omitempty"`
}

type FileInfo struct {
	SourceLocation string `json:"source_location"`
}

type DependencyNode struct {
	PackageURL   string                 `json:"package_url,omitempty"`
	Metadata     Metadata               `json:"metadata,omitempty"`
	Relationship DependencyRelationship `json:"relationship,omitempty"`
	Scope        DependencyScope        `json:"scope,omitempty"`
	Dependencies []string               `json:"dependencies,omitempty"`
}

func (d *DependencyNode) UnmarshalJSON(data []byte) error {
	type Alias DependencyNode
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

func (d *DependencyNode) Requirements() string {
	purl, err := packageurl.FromString(d.PackageURL)
	if err != nil {
		return ""
	}
	return purl.Version
}

func (d *DependencyNode) PackageName() string {
	purl, err := packageurl.FromString(d.PackageURL)
	if err != nil {
		return ""
	}
	packageName := purl.Name
	if len(purl.Namespace) > 0 {
		separator := "/"
		if purl.Type == "maven" {
			separator = ":"
		}
		packageName = purl.Namespace + separator + packageName
	}
	return packageName
}

func (d *DependencyNode) MarshalJSON() ([]byte, error) {
	// Prevent an endless loop by inserting this placeholder struct
	type Alias DependencyNode

	// we'll use the packageurl library to ensure that the purl is properly encoded
	// by round-tripping it here
	purl, err := packageurl.FromString(d.PackageURL)
	if err != nil {
		return nil, err
	}
	d.PackageURL = purl.String()

	return json.Marshal(&struct {
		Alias
	}{
		Alias: (Alias)(*d),
	})
}

type DependencyGraph = map[string]*DependencyNode

type Metadata = map[string]interface{}

type Commit struct {
	ID            uint64
	RepositoryID  uint64
	Ref           string
	SHA           string
	DefaultBranch bool
	EventTime     time.Time
}

type SnapshotResult int64

const (
	Error SnapshotResult = iota
	AcceptedNonDefaultBranch
	AcceptedCanonical
	AcceptedHistorical
	SnapshotRemoved
)

type CanonicalSnapshotInformation struct {
	SnapshotID uint64
	Detector   string
	Correlator string
}

type ActivityCounts struct {
	Total      uint64
	InLastDay  uint64
	InLastWeek uint64
}

type SnapshotsService interface {
	SnapshotByID(ctx context.Context, repositoryID uint64, snapshotID uint64) (*Snapshot, error)
	CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode SnapshotQueryMode) ([]*Snapshot, error)
	QuerySnapshots(ctx context.Context, repositoryID uint64, query SnapshotsQuery) ([]*Snapshot, error)
	StoreSnapshot(ctx context.Context, snapshot *Snapshot) (uint64, time.Time, SnapshotResult, error)
	HasManifests(ctx context.Context, snapshotID uint64) (bool, error)
	RepositoriesContainingDependency(ctx context.Context, purl, versionRange string) ([]uint64, error)
	ExcludeDependencySnapshots(ctx context.Context, repositoryID uint64, snapshotIDs []uint64) ([]uint64, error)
	UniqueRepositoryCounts(ctx context.Context) (*ActivityCounts, error)
	TotalSnapshotCounts(ctx context.Context) (*ActivityCounts, error)
}

var EmptyDetectorMetadata = DetectorMetadata{}

// Touch up `Detector` field to be missing instead of empty.
func (s *Snapshot) MarshalJSON() ([]byte, error) {
	// Replace empty `Detector` with nil, allowing the key to be removed
	if s.Detector != nil && *s.Detector == EmptyDetectorMetadata {
		s.Detector = nil
	}

	// Prevent an endless loop by inserting this placeholder struct
	type Alias Snapshot

	return json.Marshal(&struct {
		Detector *DetectorMetadata `json:"detector,omitempty"`
		*Alias
	}{
		Detector: s.Detector,
		Alias:    (*Alias)(s),
	})
}

// CombineManifests combines the manifests from the given snapshots into a single map of manifests.
// The map is keyed by the manifest's name.
// Dependencies are combined by taking the union of the dependencies in each manifest, unique by their name, which
// means it's possible to have multiple copies of the same dependency with different names.
func CombineManifests(ctx context.Context, snapshots []*Snapshot) map[string]*Manifest {
	_, ender, _ := contextlogger.LogStartAndStop(ctx, "CombineManifests", "CombineManifests")
	defer ender()
	manifests := map[string]*Manifest{}
	for _, snapshot := range snapshots {
		for manifestName, manifest := range snapshot.Manifests {
			if previous, ok := manifests[manifestName]; ok {
				maps.Copy(previous.Resolved, manifest.Resolved)
			} else {
				manifests[manifestName] = &Manifest{
					Name:       manifest.Name,
					File:       manifest.File,
					Resolved:   maps.Clone(manifest.Resolved),
					Metadata:   maps.Clone(manifest.Metadata),
					SnapshotID: manifest.SnapshotID,
				}
			}
		}
	}
	return manifests
}

func ExtractManifests(ctx context.Context, snapshots []*Snapshot) []Manifest {
	_, ender, _ := contextlogger.LogStartAndStop(ctx, "ExtractManifests", "ExtractManifests")
	defer ender()
	manifests := []Manifest{}
	for _, snapshot := range snapshots {
		for _, manifest := range snapshot.Manifests {
			newManifest := *manifest
			newManifest.SnapshotID = snapshot.ID
			manifests = append(manifests, newManifest)
		}
	}
	return manifests
}
