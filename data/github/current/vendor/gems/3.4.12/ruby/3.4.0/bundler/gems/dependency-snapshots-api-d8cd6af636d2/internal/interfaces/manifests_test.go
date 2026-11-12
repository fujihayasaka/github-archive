// These tests focus on the CombineManifests function.
package interfaces

import (
	"context"
	"fmt"
	"maps"
	"math/rand"
	"slices"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// purlsToManifest wraps the given purls in a Manifest. It assigns a _random_
// name to each dependency.
func purlsToManifest(name string, purls ...string) *Manifest {
	resolved := map[string]*DependencyNode{}
	for _, purl := range purls {
		resolved[purl] = &DependencyNode{
			PackageURL: purl,
		}
	}
	return &Manifest{
		Name:     name,
		Resolved: resolved,
	}
}

func wrapSnapshots(manifests ...*Manifest) Snapshot {
	manifestMap := map[string]*Manifest{}
	for _, manifest := range manifests {
		manifestMap[manifest.Name] = manifest
	}
	return Snapshot{
		Manifests: manifestMap,
		ID:        rand.Uint64(),
	}
}

// Test the very ordinary case of two completely independent manifests.
func TestCombineManifestsSimple(t *testing.T) {
	ctx := context.Background()
	a, b, c := randomPurl(), randomPurl(), randomPurl()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b, c)
	manifest2 := purlsToManifest("manifest-2", x, y, z)
	snapA := wrapSnapshots(manifest1)
	snapB := wrapSnapshots(manifest2)

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapB})

	require.Len(t, combined, 2)
	require.Contains(t, combined, "manifest-1")
	require.Contains(t, combined, "manifest-2")

	require.Len(t, combined["manifest-1"].Resolved, 3)
	assert.Contains(t, combined["manifest-1"].Resolved, a)
	assert.Contains(t, combined["manifest-1"].Resolved, b)
	assert.Contains(t, combined["manifest-1"].Resolved, c)
	assert.Equal(t, snapA.ID, combined["manifest-1"].SnapshotID)

	require.Len(t, combined["manifest-2"].Resolved, 3)
	assert.Contains(t, combined["manifest-2"].Resolved, x)
	assert.Contains(t, combined["manifest-2"].Resolved, y)
	assert.Contains(t, combined["manifest-2"].Resolved, z)
	assert.Equal(t, snapB.ID, combined["manifest-2"].SnapshotID)
}

// If the file path is available, we want to prefer that when combining
// manifests instead of using the name. This is more intuitive for users
// because the file path is displayed in the UI.
// See https://github.com/github/dependency-graph/issues/5915
func TestCombineManifestsByFilePath(t *testing.T) {
	ctx := context.Background()
	a, b, c := randomPurl(), randomPurl(), randomPurl()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b, c)
	manifest1.File = FileInfo{
		SourceLocation: "pom.xml",
	}
	manifest2 := purlsToManifest("manifest-2", x, y, z)
	manifest2.File = FileInfo{
		SourceLocation: "pom.xml",
	}
	snapA := wrapSnapshots(manifest1)
	snapB := wrapSnapshots(manifest2)

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapB})

	require.Len(t, combined, 1)
	assert.Contains(t, combined, "pom.xml")

	returnedManifest := combined["pom.xml"]
	assert.Len(t, returnedManifest.Resolved, 6)
	assert.ElementsMatch(t, []string{a, b, c, x, y, z}, slices.Collect(maps.Keys(returnedManifest.Resolved)))
	assert.Equal(t, snapA.ID, returnedManifest.SnapshotID)
}

// Regression test: https://github.com/github/dependency-snapshots-api/pull/869
func TestCombineDoesNotMutate(t *testing.T) {
	ctx := context.Background()
	a, b, c := randomPurl(), randomPurl(), randomPurl()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b, c)
	manifest2 := purlsToManifest("manifest-1", x, y, z)
	snapA := wrapSnapshots(manifest1)
	snapB := wrapSnapshots(manifest2)

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapB})

	require.Len(t, combined, 1)
	require.Len(t, combined["manifest-1"].Resolved, 6)
	// ensure the input manifests have not been mutated
	require.Len(t, manifest1.Resolved, 3)
	require.Len(t, manifest2.Resolved, 3)
}

// Test a case where the dependencies for a manifest are
// spread between two snapshots.
func TestCombineManifestsSharedManifest(t *testing.T) {
	ctx := context.Background()
	a, b, c, d := randomPurl(), randomPurl(), randomPurl(), randomPurl()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b)
	manifest1prime := purlsToManifest("manifest-1", b, c, d)
	manifest2 := purlsToManifest("manifest-2", x, y, z)
	snapA := wrapSnapshots(manifest1)
	snapB := wrapSnapshots(manifest1prime, manifest2)

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapB})

	require.Len(t, combined, 2)
	require.Contains(t, combined, "manifest-1")
	require.Contains(t, combined, "manifest-2")

	require.Len(t, combined["manifest-1"].Resolved, 4)
	assert.Contains(t, combined["manifest-1"].Resolved, a)
	assert.Contains(t, combined["manifest-1"].Resolved, b)
	assert.Contains(t, combined["manifest-1"].Resolved, c)
	assert.Contains(t, combined["manifest-1"].Resolved, d)

	require.Len(t, combined["manifest-2"].Resolved, 3)
	assert.Contains(t, combined["manifest-2"].Resolved, x)
	assert.Contains(t, combined["manifest-2"].Resolved, y)
	assert.Contains(t, combined["manifest-2"].Resolved, z)
}

// Test a case where the same dependency is present in two copies of the manifest,
// but with different names.
func TestCombineManifestsSamePurl(t *testing.T) {
	ctx := context.Background()
	a, b, c := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b, c)
	manifest1prime := purlsToManifest("manifest-1", a, c)
	// add b to manifest1prime, but with a different name
	manifest1prime.Resolved["b-prime"] = &DependencyNode{
		PackageURL: b,
	}
	snapA := wrapSnapshots(manifest1)
	snapB := wrapSnapshots(manifest1prime)

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapB})

	require.Len(t, combined, 1)
	require.Contains(t, combined, "manifest-1")
	require.Len(t, combined["manifest-1"].Resolved, 4)
	assert.Contains(t, combined["manifest-1"].Resolved, a)
	assert.Contains(t, combined["manifest-1"].Resolved, b)
	assert.Contains(t, combined["manifest-1"].Resolved, c)

	assert.Contains(t, combined["manifest-1"].Resolved, "b-prime")
	assert.Equal(t, combined["manifest-1"].Resolved["b-prime"].PackageURL, b)
}

func TestCombineManifestsButOneIsEmpty(t *testing.T) {
	ctx := context.Background()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1")
	manifest2 := purlsToManifest("manifest-2", x, y, z)
	snapA := wrapSnapshots(manifest1)
	snapB := wrapSnapshots(manifest2)
	snapC := wrapSnapshots()
	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapB, &snapC})

	require.Len(t, combined, 2)
	require.Contains(t, combined, "manifest-1")
	require.Contains(t, combined, "manifest-2")

	require.Len(t, combined["manifest-1"].Resolved, 0)

	require.Len(t, combined["manifest-2"].Resolved, 3)
	assert.Contains(t, combined["manifest-2"].Resolved, x)
	assert.Contains(t, combined["manifest-2"].Resolved, y)
	assert.Contains(t, combined["manifest-2"].Resolved, z)
}

func TestCombineManifestsWithMoreManifests(t *testing.T) {
	ctx := context.Background()
	a, b, c, d := randomPurl(), randomPurl(), randomPurl(), randomPurl()
	manifestA := purlsToManifest("manifest-a", a)
	manifestB := purlsToManifest("manifest-b", b)
	manifestC := purlsToManifest("manifest-c", c)
	manifestD := purlsToManifest("manifest-d", d)

	snapA := wrapSnapshots(manifestA)
	snapB := wrapSnapshots(manifestB)
	snapC := wrapSnapshots(manifestC)
	snapD := wrapSnapshots(manifestD)

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapB, &snapC, &snapD})

	require.Len(t, combined, 4)
	require.Contains(t, combined, "manifest-a")
	require.Contains(t, combined, "manifest-b")
	require.Contains(t, combined, "manifest-c")
	require.Contains(t, combined, "manifest-d")

	require.Len(t, combined["manifest-a"].Resolved, 1)
	assert.Contains(t, combined["manifest-a"].Resolved, a)
	require.Len(t, combined["manifest-b"].Resolved, 1)
	assert.Contains(t, combined["manifest-b"].Resolved, b)
	require.Len(t, combined["manifest-c"].Resolved, 1)
	assert.Contains(t, combined["manifest-c"].Resolved, c)
	require.Len(t, combined["manifest-d"].Resolved, 1)
	assert.Contains(t, combined["manifest-d"].Resolved, d)
}

func TestCombineManifestsWithAutoAndManual(t *testing.T) {
	ctx := context.Background()
	a, b := randomPurl(), randomPurl()
	manifestA := purlsToManifest("manifest-a", a)
	manifestA2 := purlsToManifest("manifest-a", b)

	snapA := wrapSnapshots(manifestA)
	snapA2 := wrapSnapshots(manifestA2)

	snapA.Detector = &DetectorMetadata{
		Name: AutomaticDependencySubmissionName,
	}
	snapA2.Detector = &DetectorMetadata{
		Name: "OmniDetector",
	}

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapA2})
	assert.Equal(t, 1, len(combined))
	assert.Equal(t, 1, len(combined["manifest-a"].Resolved))
	assert.NotNil(t, combined["manifest-a"].Resolved[b], "expected package b because we prefer manual submissions")
	assert.Equal(t, snapA2.ID, combined["manifest-a"].SnapshotID, "expected the ID of the manual submission")

	// Reverse the order and expect the same result.
	combined2 := CombineManifests(ctx, []*Snapshot{&snapA2, &snapA})
	assert.Equal(t, 1, len(combined2))
	assert.NotNil(t, combined2["manifest-a"].Resolved[b], "expected package b because we prefer manual submissions")
	assert.Equal(t, snapA2.ID, combined2["manifest-a"].SnapshotID, "expected the ID of the manual submission")
}

func TestCombineManifestsWithDifferentDetectorsDifferentCorrelators(t *testing.T) {
	ctx := context.Background()
	a, b := randomPurl(), randomPurl()
	manifestA := purlsToManifest("manifest-a", a)
	manifestA2 := purlsToManifest("manifest-a", b)

	snapA := wrapSnapshots(manifestA)
	snapA2 := wrapSnapshots(manifestA2)

	snapA.Detector = &DetectorMetadata{
		Name: "FooDetector",
	}
	snapA.Job.Correlator = "AAA Correlator"

	snapA2.Detector = &DetectorMetadata{
		Name: "OmniDetector",
	}
	snapA2.Job.Correlator = "Better Correlator"

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapA2})
	assert.Equal(t, 1, len(combined))
	assert.Equal(t, 1, len(combined["manifest-a"].Resolved))
	assert.Equal(t, a, combined["manifest-a"].Resolved[a].PackageURL, "expected package a because we prefer alphabetically first correlators")

	// Try the other ordering and expect the same result.
	combined2 := CombineManifests(ctx, []*Snapshot{&snapA2, &snapA})
	assert.Equal(t, 1, len(combined2))
	assert.Equal(t, a, combined2["manifest-a"].Resolved[a].PackageURL, "expected package a because we prefer alphabetically first correlators")
}

func TestCombineManifestsWithSameDetectorsDifferentCorrelators(t *testing.T) {
	ctx := context.Background()
	a, b := randomPurl(), randomPurl()
	manifestA := purlsToManifest("manifest-a", a)
	manifestA2 := purlsToManifest("manifest-a", b)

	snapA := wrapSnapshots(manifestA)
	snapA2 := wrapSnapshots(manifestA2)

	snapA.Detector = &DetectorMetadata{
		Name: "FooDetector",
	}
	snapA.Job.Correlator = "AAA Correlator"

	snapA2.Detector = &DetectorMetadata{
		Name: "FooDetector",
	}
	snapA2.Job.Correlator = "Better Correlator"

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapA2})
	assert.Equal(t, 1, len(combined))
	assert.Equal(t, 2, len(combined["manifest-a"].Resolved))
	assert.NotNil(t, combined["manifest-a"].Resolved[a], "should be present because of merge")
	assert.NotNil(t, combined["manifest-a"].Resolved[b], "should be present because of merge")
}

func TestCombineManifestsWithSameDetectorsSameCorrelators(t *testing.T) {
	// This shouldn't _really_ happen, but it could and if it does, it should
	// have the same result as if the correlators were different.
	ctx := context.Background()
	a, b := randomPurl(), randomPurl()
	manifestA := purlsToManifest("manifest-a", a)
	manifestA2 := purlsToManifest("manifest-a", b)

	snapA := wrapSnapshots(manifestA)
	snapA2 := wrapSnapshots(manifestA2)

	snapA.Detector = &DetectorMetadata{
		Name: "FooDetector",
	}
	snapA.Job.Correlator = "AAA Correlator"

	snapA2.Detector = &DetectorMetadata{
		Name: "FooDetector",
	}
	snapA2.Job.Correlator = "AAA Correlator"

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapA2})
	assert.Equal(t, 1, len(combined))
	assert.Equal(t, 2, len(combined["manifest-a"].Resolved))
	assert.NotNil(t, combined["manifest-a"].Resolved[a], "should be present because of merge")
	assert.NotNil(t, combined["manifest-a"].Resolved[b], "should be present because of merge")
}

// Test the very ordinary case of two completely independent manifests.
func TestExtractManifestsSimple(t *testing.T) {
	ctx := context.Background()
	a, b, c := randomPurl(), randomPurl(), randomPurl()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b, c)
	manifest2 := purlsToManifest("manifest-2", x, y, z)
	snapA := wrapSnapshots(manifest1)
	snapA.ID = manifest1.SnapshotID // Make sure the snapshot has the same ID as the manifest
	snapB := wrapSnapshots(manifest2)
	snapB.ID = manifest2.SnapshotID

	extracted := ExtractManifests(ctx, []*Snapshot{&snapA, &snapB})

	require.Len(t, extracted, 2)
	require.Contains(t, extracted, manifest1)
	require.Contains(t, extracted, manifest2)
}

func randomPurl() string {
	x := rand.Intn(20)
	y := rand.Intn(20)
	z := rand.Intn(20)
	version := fmt.Sprintf("%d.%d.%d", x, y, z)
	name := randomString(6)
	ecosystem := "go"

	return fmt.Sprintf("pkg:%s/%s@%s", ecosystem, name, version)
}

func randomString(length int) string {
	letters := []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
	s := make([]rune, length)
	for i := range s {
		s[i] = letters[rand.Intn(len(letters))]
	}
	return string(s)
}
