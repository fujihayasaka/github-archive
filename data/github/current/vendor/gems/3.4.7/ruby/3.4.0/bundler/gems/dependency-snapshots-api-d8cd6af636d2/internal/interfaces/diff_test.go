package interfaces

import (
	rand "math/rand/v2"
	"testing"
	"time"

	gitMock "github.com/github/dependency-snapshots-api/internal/gitaccess/mock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDiffableDepsEmpty(t *testing.T) {
	diffableDeps, err := toDiffableDeps([]*Snapshot{})
	require.NoError(t, err)

	assert.Empty(t, diffableDeps)
}

func TestDiffableDepsSimple(t *testing.T) {
	snap := makeSnapshotWith(t, map[string][]string{
		"Gemfile.lock": {railsPurl},
	})
	snap.ID = 1
	snap.Detector.Name = "snapshot detector"
	snap.Job.Correlator = "snapshot correlator"
	expectedMeta := DiffSnapshotMetadata{
		SnapshotID: snap.ID,
		Detector:   snap.Detector.Name,
		Correlator: snap.Job.Correlator,
	}

	diffableDeps, err := toDiffableDeps([]*Snapshot{snap})
	require.NoError(t, err)

	assert.Lenf(t, diffableDeps, 1, "expected 1 dep, got %d", len(diffableDeps))

	railsExpected := DiffableDep{
		SnapshotMeta: expectedMeta,
		Manifest:     "Gemfile.lock",
		Ecosystem:    "rubygems",
		Name:         "rails",
		Version:      "6.6.6",
		StablePurl:   purlKey(railsPurl + "?#"), // StablePurl always includes these separators
		PackageURL:   railsPurl,
		Scope:        Runtime,
	}
	assert.Equal(t, diffableDeps[0], railsExpected)
}

func TestDiffsWithDuplicates(t *testing.T) {
	testCases := []struct {
		name              string
		beforeSnapshots   []*Snapshot
		afterSnapshots    []*Snapshot
		expectedRemovals  []string
		expectedAdditions []string
	}{
		{
			name: "Duplicate dependencies before, nothing after",
			beforeSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl, activeRecordPurl}}),
			},
			afterSnapshots:   []*Snapshot{},
			expectedRemovals: []string{railsPurl, activeRecordPurl},
		},
		{
			name:            "Nothing before, duplicate dependencies after",
			beforeSnapshots: []*Snapshot{},
			afterSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl, activeRecordPurl}}),
			},
			expectedAdditions: []string{railsPurl, activeRecordPurl},
		},
		{
			name: "Duplicate dependencies before and after",
			beforeSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl, activeRecordPurl}}),
			},
			afterSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl, activeRecordPurl}}),
			},
			expectedRemovals:  []string{},
			expectedAdditions: []string{},
		},
		{
			name: "Duplicate dependency before, single after",
			beforeSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl, activeRecordPurl}}),
			},
			afterSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl, activeRecordPurl}}),
			},
			expectedRemovals:  []string{},
			expectedAdditions: []string{},
		},
		{
			name: "Single dependency before, duplicate after",
			beforeSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
			},
			afterSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
			},
			expectedRemovals:  []string{},
			expectedAdditions: []string{},
		},
		{
			name: "Duplicate dependency removed",
			beforeSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl, activeRecordPurl}}),
			},
			afterSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
			},
			expectedRemovals: []string{activeRecordPurl},
		},
		{
			name: "Duplicate dependency added",
			beforeSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
			},
			afterSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {activeRecordPurl}}),
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl, activeRecordPurl}}),
			},
			expectedAdditions: []string{activeRecordPurl},
		},
		{
			name: "Changes are not deduplicated when they're in different manifests",
			beforeSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
				makeSnapshotWith(t, map[string][]string{"other/Gemfile.lock": {railsPurl}}),
			},
			afterSnapshots: []*Snapshot{
				makeSnapshotWith(t, map[string][]string{"Gemfile.lock": {railsPurl}}),
			},
			expectedRemovals: []string{railsPurl},
		},
	}

	for _, tCase := range testCases {
		t.Run(tCase.name, func(t *testing.T) {
			diffableA, err := toDiffableDeps(tCase.beforeSnapshots)
			require.NoError(t, err, tCase.name)
			diffableB, err := toDiffableDeps(tCase.afterSnapshots)
			require.NoError(t, err, tCase.name)

			changes := diff(diffableA, diffableB)
			additions, removals := []string{}, []string{}
			for _, change := range changes {
				if change.ChangeType == ADDED {
					additions = append(additions, change.PackageURL)
				}
				if change.ChangeType == REMOVED {
					removals = append(removals, change.PackageURL)
				}
			}

			require.ElementsMatch(t, tCase.expectedAdditions, additions, tCase.name)
			require.ElementsMatch(t, tCase.expectedRemovals, removals, tCase.name)
		})
	}
}

func TestDiffableDepsWithScopeChanges(t *testing.T) {
	// In this test:
	// * lodash goes from NoScope to Development
	// * jquery goes from Development to Runtime
	// * react stays the same (Runtime in both snapshots)

	// two snapshots with the same dependencies
	oldSnap := makeSnapshotWith(t, map[string][]string{
		"package-lock.json": {jqueryPurl, lodashPurl, reactPurl},
	})
	newSnap := makeSnapshotWith(t, map[string][]string{
		"package-lock.json": {jqueryPurl, lodashPurl, reactPurl},
	})

	// modify the scopes as described above
	oldSnap.Manifests["package-lock.json"].Resolved[lodashPurl].Scope = NoScope
	oldSnap.Manifests["package-lock.json"].Resolved[jqueryPurl].Scope = Development
	oldSnap.Manifests["package-lock.json"].Resolved[reactPurl].Scope = Runtime

	newSnap.Manifests["package-lock.json"].Resolved[lodashPurl].Scope = Development
	newSnap.Manifests["package-lock.json"].Resolved[jqueryPurl].Scope = Runtime
	newSnap.Manifests["package-lock.json"].Resolved[reactPurl].Scope = Runtime

	diffableDepsOld, err := toDiffableDeps([]*Snapshot{oldSnap})
	require.NoError(t, err)
	diffableDepsNew, err := toDiffableDeps([]*Snapshot{newSnap})
	require.NoError(t, err)
	diff := diff(diffableDepsOld, diffableDepsNew)

	require.Lenf(t, diff, 4, "expected 4 deps, got %d", len(diff))
	assertContainsChange(t, diff, REMOVED, lodashPurl, NoScope)
	assertContainsChange(t, diff, ADDED, lodashPurl, Development)
	assertContainsChange(t, diff, REMOVED, jqueryPurl, Development)
	assertContainsChange(t, diff, ADDED, jqueryPurl, Runtime)
}

// TestDiffableDepsComplex tests that toDiffableDeps correctly handles multiple
// manifests and multiple dependencies per manifest.
func TestDiffableDepsComplex(t *testing.T) {
	snapA := makeSnapshotWith(t, map[string][]string{
		"package-lock.json": {jqueryPurl},
		"Gemfile.lock":      {railsPurl, activeRecordPurl},
	})
	snapA.ID = 1
	snapA.Detector.Name = "snapshot A detector"
	snapA.Job.Correlator = "snapshot A correlator"
	expectedMetaSnapA := DiffSnapshotMetadata{
		SnapshotID: snapA.ID,
		Detector:   snapA.Detector.Name,
		Correlator: snapA.Job.Correlator,
	}
	// Set the scope of the jquery dependency to Development
	snapA.Manifests["package-lock.json"].Resolved[jqueryPurl].Scope = Development

	snapB := makeSnapshotWith(t, map[string][]string{
		"requirements.txt": {numpyPurl},
	})
	snapB.ID = 2
	snapB.Detector.Name = "snapshot B detector"
	snapB.Job.Correlator = "snapshot B correlator"
	expectedMetaSnapB := DiffSnapshotMetadata{
		SnapshotID: snapB.ID,
		Detector:   snapB.Detector.Name,
		Correlator: snapB.Job.Correlator,
	}

	diffableDeps, err := toDiffableDeps([]*Snapshot{snapA, snapB})
	require.NoError(t, err)

	assert.Lenf(t, diffableDeps, 4, "expected 4 deps, got %d", len(diffableDeps))

	jqueryExpected := DiffableDep{
		SnapshotMeta: expectedMetaSnapA,
		Manifest:     "package-lock.json",
		Ecosystem:    "npm",
		Name:         "jquery",
		Version:      "1.2.3",
		StablePurl:   purlKey(jqueryPurl + "?#"), // StablePurl always includes these separators
		PackageURL:   jqueryPurl,
		Scope:        Development,
	}
	numpyExpected := DiffableDep{
		SnapshotMeta: expectedMetaSnapB,
		Manifest:     "requirements.txt",
		Ecosystem:    "pypy",
		Name:         "numpy",
		Version:      "1.0.0",
		StablePurl:   purlKey(numpyPurl + "?#"),
		PackageURL:   numpyPurl,
		Scope:        Runtime,
	}
	railsExpected := DiffableDep{
		SnapshotMeta: expectedMetaSnapA,
		Manifest:     "Gemfile.lock",
		Ecosystem:    "rubygems",
		Name:         "rails",
		Version:      "6.6.6",
		StablePurl:   purlKey(railsPurl + "?#"),
		PackageURL:   railsPurl,
		Scope:        Runtime,
	}
	activeRecordExpected := DiffableDep{
		SnapshotMeta: expectedMetaSnapA,
		Manifest:     "Gemfile.lock",
		Ecosystem:    "rubygems",
		Name:         "activerecord",
		Version:      "4.5.6",
		StablePurl:   purlKey(activeRecordPurl + "?#"),
		PackageURL:   activeRecordPurl,
		Scope:        Runtime,
	}
	assert.ElementsMatch(t, diffableDeps, []DiffableDep{jqueryExpected, numpyExpected, railsExpected, activeRecordExpected})
}

// TestDiffAgainstEmpty tests that diffing a manifest against an empty manifest
// returns either all additions or all removals, depending on which side is
// empty.
func TestDiffAgainstEmpty(t *testing.T) {
	withDeps := map[string][]string{
		"package.json": {jqueryPurl},
		"Gemfile.lock": {railsPurl, activeRecordPurl},
	}
	empty := map[string][]string{}

	additions := diffManifestMaps(t, empty, withDeps)
	removals := diffManifestMaps(t, withDeps, empty)

	assert.Len(t, additions, 3)
	assert.Len(t, removals, 3)

	assertContainsChange(t, additions, ADDED, jqueryPurl, Runtime)
	assertContainsChange(t, additions, ADDED, railsPurl, Runtime)
	assertContainsChange(t, additions, ADDED, activeRecordPurl, Runtime)

	assertContainsChange(t, removals, REMOVED, jqueryPurl, Runtime)
	assertContainsChange(t, removals, REMOVED, railsPurl, Runtime)
	assertContainsChange(t, removals, REMOVED, activeRecordPurl, Runtime)
}

// TestDiffAgainstSelf tests that diffing a manifest against itself returns no
// changes.
func TestDiffAgainstSelf(t *testing.T) {
	withDeps := map[string][]string{
		"package.json": {jqueryPurl},
		"Gemfile.lock": {railsPurl, activeRecordPurl},
	}

	changes := diffManifestMaps(t, withDeps, withDeps)
	assert.Len(t, changes, 0)
}

// TestDiffWithUpdate tests that replacing one version of a dependency
// with another results in two changes: a removal and an addition.
func TestDiffWithUpdate(t *testing.T) {
	updatedJqueryPurl := "pkg:npm/jquery@1.2.4"
	original := map[string][]string{
		"package.json": {jqueryPurl},
		"Gemfile.lock": {railsPurl, activeRecordPurl},
	}
	updated := map[string][]string{
		"package.json": {updatedJqueryPurl},
		"Gemfile.lock": {railsPurl, activeRecordPurl},
	}

	changes := diffManifestMaps(t, original, updated)
	assert.Len(t, changes, 2)

	assertContainsChange(t, changes, REMOVED, jqueryPurl, Runtime)
	assertContainsChange(t, changes, ADDED, updatedJqueryPurl, Runtime)
}

// TestDiffWithUpdate tests that package URLs are treated as equal
// iff they have the same content, even if they have a different
// order of attributes or have minor formatting differences
func TestDiffPurlVariations(t *testing.T) {
	jqueryA := jqueryPurl + "?variation=1&foo=bar"
	jqueryB := jqueryPurl + "?foo=bar&variation=1#"

	original := map[string][]string{
		"package.json": {jqueryA},
	}
	variation := map[string][]string{
		"package.json": {jqueryB},
	}

	changes := diffManifestMaps(t, original, variation)
	assert.Len(t, changes, 0)

	changes = diffManifestMaps(t, variation, original)
	assert.Len(t, changes, 0)
}

func TestDiffAttributes(t *testing.T) {
	railsB := railsPurl + "?source=github"

	original := map[string][]string{
		"Gemfile.lock": {railsPurl},
	}
	variation := map[string][]string{
		"Gemfile.lock": {railsB},
	}

	changes := diffManifestMaps(t, original, variation)
	assert.Len(t, changes, 2)

	assertContainsChange(t, changes, REMOVED, railsPurl, Runtime)
	assertContainsChange(t, changes, ADDED, railsB, Runtime)
}

func TestDiffSubpath(t *testing.T) {
	numpyB := numpyPurl + "#math/stuff"

	original := map[string][]string{
		"requirements.txt": {numpyPurl},
	}
	variation := map[string][]string{
		"requirements.txt": {numpyB},
	}

	changes := diffManifestMaps(t, original, variation)
	assert.Len(t, changes, 2)

	assertContainsChange(t, changes, REMOVED, numpyPurl, Runtime)
	assertContainsChange(t, changes, ADDED, numpyB, Runtime)
}

func TestToDiffableDeps_ManifestDeduplication(t *testing.T) {
	// Both snapshots have the same manifest file path, but different detector names and correlators
	manifestPath := "shared.json"
	// Correlator "aaa" < "zzz"
	before := makeSnapshotWith(t, map[string][]string{manifestPath: {jqueryPurl}})
	before.Detector.Name = "detector-A"
	before.Job.Correlator = "zzz"

	after := makeSnapshotWith(t, map[string][]string{manifestPath: {railsPurl}})
	after.Detector.Name = "detector-B"
	after.Job.Correlator = "aaa"

	// Both before and after have the same manifest path, but different correlators and detector names
	// Only the manifest from the snapshot with correlator "aaa" should be present after deduplication
	deps, err := toDiffableDeps([]*Snapshot{before, after})
	require.NoError(t, err)

	// Only railsPurl should be present, from the after snapshot (correlator "aaa")
	assert.ElementsMatch(t, []string{railsPurl}, collectPurls(deps))
	assert.Len(t, uniqueManifests(deps), 1)
	assert.Equal(t, manifestPath, uniqueManifests(deps)[0])
}

// TestDiffsComplex tests a more complex case where there are multiple manifests
// and multiple snapshots. It also validates every field on the resulting Change
// structs.
func TestDiffsComplex(t *testing.T) {
	snapA := makeSnapshotWith(t, map[string][]string{
		"manifest1": {jqueryPurl, railsPurl, numpyPurl},
	})
	snapA.ID = 1
	snapA.Detector.Name = "diff test"
	snapA.Job.Correlator = "snapshot A correlator"
	expectedMetaSnapA := DiffSnapshotMetadata{
		SnapshotID: snapA.ID,
		Detector:   snapA.Detector.Name,
		Correlator: snapA.Job.Correlator,
	}

	diffableDepsA, err := toDiffableDeps([]*Snapshot{snapA})
	require.NoError(t, err)

	snapB := makeSnapshotWith(t, map[string][]string{
		"manifest1": {"pkg:npm/jquery@1.2.4", numpyPurl},
		"manifest2": {"pkg:maven/mavenator@9"},
	})
	snapB.ID = 2
	snapB.Detector.Name = "diff test"
	snapB.Job.Correlator = "snapshot B correlator"
	expectedMetaSnapB := DiffSnapshotMetadata{
		SnapshotID: snapB.ID,
		Detector:   snapB.Detector.Name,
		Correlator: snapB.Job.Correlator,
	}

	diffableDepsB, err := toDiffableDeps([]*Snapshot{snapB})
	require.NoError(t, err)

	changes := diff(diffableDepsA, diffableDepsB)
	assert.Lenf(t, changes, 4, "expected 4 changes, got %d", len(changes))

	// Note that REMOVED changes have the old snapshot metadata
	// and ADDED changes have the new snapshot metadata
	expectedChanges := []Change{
		{
			ChangeType:   REMOVED,
			PackageURL:   jqueryPurl,
			SnapshotMeta: expectedMetaSnapA,
			Manifest:     "manifest1",
			Ecosystem:    "npm",
			Name:         "jquery",
			Version:      "1.2.3",
			Scope:        Runtime,
		},
		{
			ChangeType:   ADDED,
			PackageURL:   "pkg:npm/jquery@1.2.4",
			SnapshotMeta: expectedMetaSnapB,
			Manifest:     "manifest1",
			Ecosystem:    "npm",
			Name:         "jquery",
			Version:      "1.2.4",
			Scope:        Runtime,
		},
		{
			ChangeType:   REMOVED,
			PackageURL:   railsPurl,
			SnapshotMeta: expectedMetaSnapA,
			Manifest:     "manifest1",
			Ecosystem:    "rubygems",
			Name:         "rails",
			Version:      "6.6.6",
			Scope:        Runtime,
		},
		{
			ChangeType:   ADDED,
			PackageURL:   "pkg:maven/mavenator@9",
			SnapshotMeta: expectedMetaSnapB,
			Manifest:     "manifest2",
			Ecosystem:    "maven",
			Name:         "mavenator",
			Version:      "9",
			Scope:        Runtime,
		},
	}
	assert.ElementsMatch(t, changes, expectedChanges)

	diffableDepsBoth, err := toDiffableDeps([]*Snapshot{snapA, snapB})
	require.NoError(t, err)
	combinedLength := len(diffableDepsA) + len(diffableDepsB) - 1 // -1 because numpy@1.0.0 is in both and it gets deduped
	assert.Lenf(t, diffableDepsBoth, combinedLength, "expected %d deps, got %d", combinedLength, len(diffableDepsBoth))
}

// A helper that computes the diff (as []Change) between two maps of manifest path to packageURL.
// Used to make tests a bit more terse.
func diffManifestMaps(t *testing.T, a, b map[string][]string) []Change {
	t.Helper()

	snapA := makeSnapshotWith(t, a)
	snapB := makeSnapshotWith(t, b)

	diffableDepsA, err := toDiffableDeps([]*Snapshot{snapA})
	require.NoError(t, err)

	diffableDepsB, err := toDiffableDeps([]*Snapshot{snapB})
	require.NoError(t, err)

	return diff(diffableDepsA, diffableDepsB)
}

// A helper that asserts that a []Change contains a Change with the given ChangeType, PackgeURL, and Scope.
func assertContainsChange(t *testing.T, changes []Change, changeType ChangeType, purl string, scope DependencyScope) {
	t.Helper()

	for _, change := range changes {
		if change.ChangeType == changeType && change.PackageURL == purl && change.Scope == scope {
			return
		}
	}
	t.Errorf("expected changes to contain %v %s with scope '%s', but it didn't", changeType.String(), purl, scope.String())
}

// makeSnapshotWith creates a Snapshot with the given dependencies.
// The dependencies are specified as a map of manifest path to a list of packageURLs.
func makeSnapshotWith(t *testing.T, deps map[string][]string) *Snapshot {
	t.Helper()

	randomSnapshotID := rand.Uint64()

	snap := Snapshot{
		Version: 0,
		Job: Job{
			Correlator: "test-correlator",
			ID:         "job-id",
			HTMLUrl:    "example.com/job",
		},
		SHA: string(gitMock.ExpectedSHA),
		Ref: "refs/heads/main",
		Detector: &DetectorMetadata{
			Name:    "test-detector",
			URL:     "example.com/detector",
			Version: "1.1.1",
		},
		Metadata: Metadata{
			"push_id": "654321",
		},
		Manifests:    Manifests{},
		Scanned:      time.Now().Add(-time.Minute).Round(0),
		ID:           randomSnapshotID,
		RepositoryID: 1234,
	}
	for path, pkgURLs := range deps {
		if _, ok := snap.Manifests[path]; !ok {
			snap.Manifests[path] = &Manifest{
				Name:     path,
				File:     FileInfo{SourceLocation: path},
				Metadata: Metadata{"oid": "oid1"},
				Resolved: DependencyGraph{},
			}
		}
		for _, purl := range pkgURLs {
			snap.Manifests[path].Resolved[purl] = &DependencyNode{
				PackageURL:   purl,
				Relationship: Direct,
				Scope:        Runtime,
			}
		}
	}
	return &snap
}

func collectPurls(deps []DiffableDep) []string {
	out := make([]string, 0, len(deps))
	for _, d := range deps {
		out = append(out, d.PackageURL)
	}
	return out
}

func uniqueManifests(deps []DiffableDep) []string {
	m := map[string]struct{}{}
	for _, d := range deps {
		m[d.Manifest] = struct{}{}
	}
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

const (
	jqueryPurl       string = "pkg:npm/jquery@1.2.3"
	railsPurl        string = "pkg:rubygems/rails@6.6.6"
	numpyPurl        string = "pkg:pypy/numpy@1.0.0"
	activeRecordPurl string = "pkg:rubygems/activerecord@4.5.6"
	lodashPurl       string = "pkg:npm/lodash@4.4.4"
	reactPurl        string = "pkg:npm/react@2.5.6"
)
