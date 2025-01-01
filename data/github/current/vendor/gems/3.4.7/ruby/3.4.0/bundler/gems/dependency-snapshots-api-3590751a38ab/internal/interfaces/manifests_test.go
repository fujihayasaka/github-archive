// These tests focus on the CombineManifests function.
package interfaces

import (
	"context"
	"fmt"
	"math/rand"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// purlsToManifest wraps the given purls in a Manifest. It assigns a _random_
// name to each dependency.
func purlsToManifest(name string, purls ...string) Manifest {
	resolved := map[string]*DependencyNode{}
	for _, purl := range purls {
		resolved[purl] = &DependencyNode{
			PackageURL: purl,
		}
	}
	return Manifest{
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
	}
}

// Test the very ordinary case of two completely independent manifests.
func TestCombineManifestsSimple(t *testing.T) {
	ctx := context.Background()
	a, b, c := randomPurl(), randomPurl(), randomPurl()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b, c)
	manifest2 := purlsToManifest("manifest-2", x, y, z)
	snapA := wrapSnapshots(&manifest1)
	snapB := wrapSnapshots(&manifest2)

	combined := CombineManifests(ctx, []*Snapshot{&snapA, &snapB})

	require.Len(t, combined, 2)
	require.Contains(t, combined, "manifest-1")
	require.Contains(t, combined, "manifest-2")

	require.Len(t, combined["manifest-1"].Resolved, 3)
	assert.Contains(t, combined["manifest-1"].Resolved, a)
	assert.Contains(t, combined["manifest-1"].Resolved, b)
	assert.Contains(t, combined["manifest-1"].Resolved, c)

	require.Len(t, combined["manifest-2"].Resolved, 3)
	assert.Contains(t, combined["manifest-2"].Resolved, x)
	assert.Contains(t, combined["manifest-2"].Resolved, y)
	assert.Contains(t, combined["manifest-2"].Resolved, z)
}

// Regression test: https://github.com/github/dependency-snapshots-api/pull/869
func TestCombineDoesNotMutate(t *testing.T) {
	ctx := context.Background()
	a, b, c := randomPurl(), randomPurl(), randomPurl()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b, c)
	manifest2 := purlsToManifest("manifest-1", x, y, z)
	snapA := wrapSnapshots(&manifest1)
	snapB := wrapSnapshots(&manifest2)

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
	snapA := wrapSnapshots(&manifest1)
	snapB := wrapSnapshots(&manifest1prime, &manifest2)

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
	snapA := wrapSnapshots(&manifest1)
	snapB := wrapSnapshots(&manifest1prime)

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
	snapA := wrapSnapshots(&manifest1)
	snapB := wrapSnapshots(&manifest2)
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

	snapA := wrapSnapshots(&manifestA)
	snapB := wrapSnapshots(&manifestB)
	snapC := wrapSnapshots(&manifestC)
	snapD := wrapSnapshots(&manifestD)

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

// Test the very ordinary case of two completely independent manifests.
func TestExtractManifestsSimple(t *testing.T) {
	ctx := context.Background()
	a, b, c := randomPurl(), randomPurl(), randomPurl()
	x, y, z := randomPurl(), randomPurl(), randomPurl()
	manifest1 := purlsToManifest("manifest-1", a, b, c)
	manifest2 := purlsToManifest("manifest-2", x, y, z)
	snapA := wrapSnapshots(&manifest1)
	snapA.ID = manifest1.SnapshotID // Make sure the snapshot has the same ID as the manifest
	snapB := wrapSnapshots(&manifest2)
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
	var letters = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
	s := make([]rune, length)
	for i := range s {
		s[i] = letters[rand.Intn(len(letters))]
	}
	return string(s)
}
