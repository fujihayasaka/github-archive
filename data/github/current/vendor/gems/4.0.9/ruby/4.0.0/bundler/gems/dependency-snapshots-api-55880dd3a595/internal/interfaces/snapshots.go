package interfaces

import (
	"context"
	"encoding/json"
	"maps"
	"path/filepath"
	"time"

	jsonc "github.com/cyberphone/json-canonicalization/go/src/webpki.org/jsoncanonicalizer"
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

	// The ID, Type, RepositoryID and CreatedAt keys are not part of the public snapshot format.
	ID           uint64       `json:"-"`
	Type         SnapshotType `json:"-"`
	RepositoryID uint64       `json:"-"`
	CreatedAt    time.Time    `json:"-"`
}

// SnapshotType represents the type of snapshot,
// either incremental if submitted by dependabot,
// or complete if submitted by other means.
type SnapshotType string

const (
	SnapshotTypeComplete    SnapshotType = "complete"
	SnapshotTypeIncremental SnapshotType = "incremental"
)

var AllSnapshotTypes = []SnapshotType{
	SnapshotTypeComplete,
	SnapshotTypeIncremental,
}

// AutomaticDependencySubmissionName is the name of the detector used when automatic submission is running.
const AutomaticDependencySubmissionName = "Automatic Dependency Submission"

// DependabotDetectorName is the name of the detector used by the Dependabot Graph job.
const DependabotDetectorName = "dependabot"

// SubmissionType represents how a manifest was submitted.
type SubmissionType int

// Precedence: Manual > Auto > Dependabot
const (
	DependabotSubmission SubmissionType = iota
	AutoSubmission
	ManualSubmission
)

func (s SubmissionType) String() string {
	return [...]string{"dependabot", "auto", "manual"}[s]
}

// SubmissionType returns an enum representing how the snapshot was submitted.
func (s *Snapshot) SubmissionType() SubmissionType {
	if s.IsAutoSubmission() {
		return AutoSubmission
	} else if s.IsDependabot() {
		return DependabotSubmission
	}
	return ManualSubmission
}

// IsAutoSubmission attempts to identify whether the given snapshot
// was submitted via the automatic dependency submission feature.
// We can't be perfectly accurate here; if somebody wanted (for some reason)
// to fool us, they could. That said, I don't think that's likely.
func (s *Snapshot) IsAutoSubmission() bool {
	if s != nil && s.Detector != nil {
		return s.Detector.Name == AutomaticDependencySubmissionName
	}
	return false
}

// IsDependabot attempts to identify whether the given snapshot
// was submitted via Dependabot. We can't be perfectly accurate here;
// if somebody wanted (for some reason) to fool us, they could.
func (s *Snapshot) IsDependabot() bool {
	if s != nil && s.Detector != nil {
		return s.Detector.Name == DependabotDetectorName
	}
	return false
}

// MarshalJSON touches up `Detector` field to be missing instead of empty.
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

// CanonicalizeForHash returns a canonical JSON encoding of the snapshot, excluding volatile fields and normalizing order.
func (s *Snapshot) CanonicalizeForHash() ([]byte, error) {
	_, ender, _ := contextlogger.LogStartAndStop(context.Background(), "Snapshot.CanonicalizeForHash", "CanonicalizeForHash")
	defer ender()
	// Copy the snapshot and remove volatile fields
	snapCopy := *s
	snapCopy.SHA = ""
	snapCopy.Scanned = time.Time{}
	snapCopy.Job = s.Job // copy struct
	snapCopy.Job.ID = ""

	rawBytes, err := json.Marshal(snapCopy)
	if err != nil {
		return nil, err
	}

	canonicalized, err := jsonc.Transform(rawBytes)
	if err != nil {
		return nil, err
	}

	return canonicalized, nil
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
	IncrementalUpdateMode
)

func (m CanonicalUpdateMode) String() string {
	return [...]string{"default", "internal", "incremental"}[m]
}

type SnapshotsQuery struct {
	SHA   string
	Types []SnapshotType
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

// StoreSnapshotOutput holds the results of storing a snapshot.
type StoreSnapshotOutput struct {
	SnapshotID          uint64
	CreatedAt           time.Time
	Result              SnapshotResult
	DependenciesChanged bool
}

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
	QueryCompleteSnapshots(ctx context.Context, repositoryID uint64, sha string) ([]*Snapshot, error)
	StoreSnapshot(ctx context.Context, snapshot *Snapshot) (StoreSnapshotOutput, error)
	HasManifests(ctx context.Context, snapshotID uint64) (bool, error)
	HasCompleteManifests(ctx context.Context, snapshotID uint64) (bool, error)
	RepositoriesContainingDependency(ctx context.Context, purl, versionRange string) ([]uint64, error)
	ExcludeDependencySnapshots(ctx context.Context, repositoryID uint64, snapshotIDs []uint64) ([]uint64, error)
	UniqueRepositoryCounts(ctx context.Context) (*ActivityCounts, error)
	TotalSnapshotCounts(ctx context.Context) (*ActivityCounts, error)
	CountSnapshotsForSHA(ctx context.Context, repositoryID uint64, query SnapshotsQuery) (int, error)
	CountCompleteSnapshotsForSHA(ctx context.Context, repositoryID uint64, sha string) (int, error)
}

var EmptyDetectorMetadata = DetectorMetadata{}

type manifestResult struct {
	manifest       *Manifest
	submissionType SubmissionType
	detector       string
	correlator     string
}

type CombineManifestsOptions struct {
	// PreferDependabotSubmissionManifestTypes is the list of manifest types where
	// Dependabot submissions should be preferred over automatic submissions.
	// Manifest types are inferred via InferManifestType (for example: "pypi", "npm").
	PreferDependabotSubmissionManifestTypes []string
}

// CombineManifests combines the manifests from the given snapshots into a single map of manifests.
// The map is keyed by the manifest's source location, where available. Name is used as a fallback.
// If two snapshots have the same manifest, we will merge according to these rules:
// - If one is a manual submission and the other is automatic or dependabot, we will keep the manual one.
// - If one is dependabot and the other is automatic, we will keep the automatic one.
// - If both belong to the same detector, we will merge the resolved dependencies.
// - Otherwise, we will sort alphabetically by correlator and keep the first one.
func CombineManifests(ctx context.Context, snapshots []*Snapshot, options ...CombineManifestsOptions) map[string]*Manifest {
	_, ender, _ := contextlogger.LogStartAndStop(ctx, "CombineManifests", "CombineManifests")
	defer ender()

	preferDependabotSubmissionManifestTypes := map[string]bool{}
	for _, option := range options {
		for _, manifestType := range option.PreferDependabotSubmissionManifestTypes {
			preferDependabotSubmissionManifestTypes[manifestType] = true
		}
	}

	manifests := map[string]*manifestResult{}
	for _, current := range snapshots {
		for _, manifest := range current.Manifests {
			preferDependabotForCurrentManifestType := preferDependabotSubmissionManifestTypes[InferManifestType(manifest)]
			manifestID := manifest.File.SourceLocation
			if manifestID == "" {
				manifestID = manifest.Name
			}
			if previous, ok := manifests[manifestID]; ok {
				preferDependabotForPreviousManifestType := preferDependabotSubmissionManifestTypes[InferManifestType(previous.manifest)]
				preferCurrentDependabotOverPreviousAuto := previous.submissionType == AutoSubmission && current.SubmissionType() == DependabotSubmission && preferDependabotForCurrentManifestType
				overrideWithCurrent := false

				// If the previous has higher precedence, make no changes.
				if previous.submissionType > current.SubmissionType() {
					if !preferCurrentDependabotOverPreviousAuto {
						continue
					}

					// When the preference override applies, keep current regardless of
					// detector or correlator tie-break rules.
					overrideWithCurrent = true
				}

				if !overrideWithCurrent {
					// If the current has higher precedence, we normally replace the previous.
					// But when configured, keep preferred dependabot submissions over auto.
					if previous.submissionType < current.SubmissionType() {
						if previous.submissionType == DependabotSubmission && current.SubmissionType() == AutoSubmission && preferDependabotForPreviousManifestType {
							continue
						}
					}

					currentDetector := ""
					if current.Detector != nil {
						currentDetector = current.Detector.Name
					}

					// Check to see if we want to perform a merge
					if previous.detector == currentDetector {
						maps.Copy(previous.manifest.Resolved, manifest.Resolved)
						continue
					}

					// Since we're not merging, we need to decide if we stick with the previous manifest
					// or the current one. We compare the correlator names to make this decision.
					if previous.correlator < current.Job.Correlator {
						continue
					}
				}
			}
			detector := ""
			if current.Detector != nil {
				detector = current.Detector.Name
			}
			manifests[manifestID] = &manifestResult{
				manifest: &Manifest{
					Name:       manifest.Name,
					File:       manifest.File,
					Resolved:   maps.Clone(manifest.Resolved),
					Metadata:   maps.Clone(manifest.Metadata),
					SnapshotID: current.ID,
				},
				submissionType: current.SubmissionType(),
				detector:       detector,
				correlator:     current.Job.Correlator,
			}
		}
	}
	result := map[string]*Manifest{}
	for id, manifest := range manifests {
		result[id] = manifest.manifest
	}
	return result
}

func ExtractManifests(ctx context.Context, snapshots []*Snapshot) []*Manifest {
	_, ender, _ := contextlogger.LogStartAndStop(ctx, "ExtractManifests", "ExtractManifests")
	defer ender()
	manifests := []*Manifest{}
	for _, snapshot := range snapshots {
		for _, manifest := range snapshot.Manifests {
			newManifest := *manifest
			newManifest.SnapshotID = snapshot.ID
			manifests = append(manifests, &newManifest)
		}
	}
	return manifests
}

// InferManifestType gives the best guess as to the manifest type.
// First, it tries matching the filename against a list of known manifest types,
// then it tries to infer the type from the first dependency it finds in the
// manifest. Not guaranteed to be accurate. Should only be used for stats anyway.
func InferManifestType(manifest *Manifest) string {
	res := "unknown"
	if manifest == nil {
		return res
	}

	filename := filepath.Base(manifest.File.SourceLocation)
	if match, ok := manifestTypes[filename]; ok {
		return match
	}

	// try to get one (1) dependency out of the manifest
	// and check its type. heterogeneous manifests are unusual,
	// but not impossible. since this is only going towards stats,
	// it's not a big deal if this returns inconsistent results for those.
	if len(manifest.Resolved) > 0 {
		for _, dep := range manifest.Resolved {
			if dep != nil {
				purl, err := packageurl.FromString(dep.PackageURL)
				if err == nil {
					res = purl.Type
				}
			}
			break
		}
	}

	return res
}

// manifestTypes is only used as a rough guide
// to help infer manifest types for statting.
// Don't rely on it for anything more serious than that!
// In general, we don't assign "types" to a manifest anyway,
// we take it on a dependency-by-dependency basis.
// This list is not exhaustive.
var manifestTypes = map[string]string{
	"Gemfile.lock":        "gem",
	"Gemfile":             "gem",
	"gems.rb":             "gem",
	"gems.locked":         "gem",
	".gemspec":            "gem",
	"package.json":        "npm",
	"package-lock.json":   "npm",
	"pnpm-lock.yaml":      "npm",
	"yarn.lock":           "npm",
	"pipfile":             "pypi",
	"pipfile.lock":        "pypi",
	"setup.py":            "pypi",
	"pyproject.toml":      "pypi",
	"poetry.lock":         "pypi",
	"pom.xml":             "maven",
	"nuspec":              "nuget",
	"packages.config":     "nuget",
	"composer.lock":       "composer",
	"composer.json":       "composer",
	"go.mod":              "golang",
	"go.sum":              "golang",
	".github/workflows":   "github",
	"build.gradle":        "maven",
	"settings.gradle":     "maven",
	"build.gradle.kts":    "maven",
	"settings.gradle.kts": "maven",
	"Cargo.lock":          "cargo",
	"Cargo.toml":          "cargo",
	"pubspec.yaml":        "pub",
	"pubspec.yml":         "pub",
	"pubspec.lock":        "pub",
	"Package.resolved":    "swift",
	"stack.yaml":          "hackage",
	"stack.yaml.lock":     "hackage",
	"deps.edn":            "clojars",
}
