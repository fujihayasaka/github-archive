package interfaces

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"runtime/pprof"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func loadExampleSnapshot(t *testing.T, filename string) *Snapshot {
	t.Helper()

	payload, err := os.ReadFile(filename)
	require.NoError(t, err)

	out := &Snapshot{}
	err = json.Unmarshal(payload, out)
	require.NoError(t, err)
	return out
}

// Keeping this here for posterity in case anybody feels the need
// to run a CPU profile on this function again. It would be good to
// use a gigantic snapshot from prod, which I won't supply here
// because it would contain user data. This snapshot has about 500
// dependencies.
func TestProfileSnapshot(t *testing.T) {
	t.Skip()
	cpuprofile := "cpu.prof"
	f, err := os.Create(cpuprofile)
	require.NoError(t, err)

	snapshot := loadExampleSnapshot(t, "testdata/medium-snapshot.json")
	require.NotNil(t, snapshot)

	manifest := snapshot.Manifests["my-app"]
	require.NotNil(t, manifest)

	pprof.StartCPUProfile(f)
	defer pprof.StopCPUProfile()

	ctx := context.Background()
	_, err = GetRootAncestors(ctx, 1, manifest)
	require.NoError(t, err)
}

func TestGetRootAncestorsTimeout(t *testing.T) {
	snapshot := loadExampleSnapshot(t, "testdata/medium-snapshot.json")
	require.NotNil(t, snapshot)

	manifest := snapshot.Manifests["my-app"]
	require.NotNil(t, manifest)

	ctx := context.Background()
	// first run without a timeout as a sanity check
	res, err := GetRootAncestors(ctx, 1, manifest)
	require.NoError(t, err)
	require.NotEmpty(t, res)

	// set the timeout to 1 ns to force a timeout
	ctx, cancel := context.WithTimeout(ctx, 1*time.Nanosecond)
	defer cancel()

	res, err = GetRootAncestors(ctx, 1, manifest)
	require.Error(t, err)
	require.ErrorContains(t, err, "context deadline exceeded")
	require.Empty(t, res)
}

func TestGetRootAncestorsTimeoutFast(t *testing.T) {
	snapshot := loadExampleSnapshot(t, "testdata/medium-snapshot.json")
	require.NotNil(t, snapshot)

	manifest := snapshot.Manifests["my-app"]
	require.NotNil(t, manifest)

	ctx := context.Background()
	// set the timeout to 1 ns, which is unattainable
	ctx, cancel := context.WithTimeout(ctx, 1*time.Nanosecond)
	defer cancel()

	start := time.Now()
	// run the function 10000 times to ensure that the timeout is hit
	// quickly enough to actually save time.
	for range 10000 {
		res, err := GetRootAncestors(ctx, 1, manifest)
		require.Error(t, err)
		require.ErrorContains(t, err, "context deadline exceeded")
		require.Empty(t, res)
	}
	end := time.Now()
	require.LessOrEqual(t, end.Sub(start), 80*time.Millisecond, "GetRootAncestors took too long to timeout")
}

// unholyManifest returns a manifest above a specific complexity.
// Complexity is defined as DirectDependencies * (TotalDependencies + TotalEdges)
// This manifest may not be well-formed! Its purpose is to test the
// ability of GetRootAncestors to skip over complex manifests.
func unholyManifest(t *testing.T, targetComplexity int) *Manifest {
	t.Helper()
	manifest := &Manifest{
		Name:     "unholy",
		Resolved: make(map[string]*DependencyNode),
	}

	// complexity is defined as DirectDependencies * (TotalDependencies + TotalEdges)
	// if DirectDependencies is at least sqrt(targetComplexity) + 1, and if
	// each has at least one edge, then the total complexity
	// complexity will be at least targetComplexity
	numDirects := int(math.Sqrt(float64(targetComplexity)) + 1)

	for i := 0; i < numDirects; i++ {
		name := fmt.Sprintf("dep%d", i)
		subDep := fmt.Sprintf("dep%d", i+1)
		manifest.Resolved[name] = &DependencyNode{
			PackageURL:   "pkg:generic/" + name,
			Dependencies: []string{subDep},
			Relationship: Direct,
		}
	}

	stats := getManifestStats(manifest)
	if stats.complexity() < targetComplexity {
		t.Fatalf("complexity is %d, but expected at least %d", stats.complexity(), targetComplexity)
	}
	return manifest
}

func TestGetRootAncestorsSkipsComplex(t *testing.T) {
	targetComplexity := MAXIMUM_MANIFEST_COMPLEXITY + 1
	manifest := unholyManifest(t, targetComplexity)

	ctx := context.Background()

	start := time.Now()
	res, err := GetRootAncestors(ctx, 1, manifest)
	end := time.Now()
	require.NoError(t, err)
	require.Empty(t, res)
	require.LessOrEqual(t, end.Sub(start), 5*time.Millisecond, "GetRootAncestors took too long to skip complex manifest")
}
