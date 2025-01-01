package graph

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/stretchr/testify/require"
)

func TestTxPathSimple(t *testing.T) {
	// represents a single "manifests" entry in a snapshot submission
	m := &interfaces.Manifest{
		Name: "simple",
		Resolved: map[string]*interfaces.DependencyNode{
			"direct_1": {
				Relationship: interfaces.Direct,
				Dependencies: []string{
					"tx_1_a",
					"tx_1_b",
					"tx_1_c",
				},
			},
			"direct_2": {
				Relationship: interfaces.Direct,
				Dependencies: []string{
					"tx_1_a",
					"tx_1_c",
				},
			},
			"direct_3": {
				Relationship: interfaces.Direct,
			},
			"tx_1_a": {
				Dependencies: []string{
					"tx_2_a",
					"tx_2_b",
				},
			},
			"tx_1_b": {
				Dependencies: []string{
					"tx_2_c",
				},
			},
			"tx_1_c": {
				Dependencies: []string{
					"tx_2_a",
					"tx_2_d",
				},
			},
		},
	}

	// create a Pathfinder from the manifests entry
	p, err := New(m)
	require.NoError(t, err)

	// direct dependencies (with or without child dependencies) should return no Paths
	got, err := p.PathsFrom("direct_1")
	require.NoError(t, err, "direct_1")
	require.Equal(t, []Path{}, got, "direct_1")

	got, err = p.PathsFrom("direct_2")
	require.NoError(t, err, "direct_2")
	require.Equal(t, []Path{}, got, "direct_2")

	got, err = p.PathsFrom("direct_3")
	require.NoError(t, err, "direct_3")
	require.Equal(t, []Path{}, got, "direct_3")

	// single Paths expected
	got, err = p.PathsFrom("tx_1_b")
	require.NoError(t, err)
	require.Len(t, got, 1, "expected tx_1_b to have 1 path, got: %d", len(got))
	checkPath(t, "tx_1_b -> direct_1", got[0], Path{"direct_1"})

	got, err = p.PathsFrom("tx_2_c")
	require.NoError(t, err)
	require.Len(t, got, 1, "expected tx_2_c to have 1 path, got: %d", len(got))
	checkPath(t, "tx_2_c -> direct_1", got[0], Path{"tx_1_b", "direct_1"})

	// multiple Paths expected
	tx2dExpected := []Path{
		{"tx_1_c", "direct_1"},
		{"tx_1_c", "direct_2"},
	}
	tx2dGot, err := p.PathsFrom("tx_2_d")
	require.NoError(t, err)
	checkPaths(t, tx2dExpected, tx2dGot)
}

func TestNoTxPathsIfNoDirectsMarked(t *testing.T) {
	// represents a single "manifests" entry in a snapshot submission
	m := &interfaces.Manifest{
		Name: "simple",
		Resolved: map[string]*interfaces.DependencyNode{
			// IMPORTANT: currently, if snapshot submission doesn't mark
			// direct dependencies as such, we won't return any Paths.
			// Without knowing which path elements are roots (direct deps)
			// we would have to capture every possible path from each
			// transitive to the rest of the graph.

			"direct_1": {
				Relationship: interfaces.NoRelationship,
				Dependencies: []string{
					"tx_1_a",
					"tx_1_b",
					"tx_1_c",
				},
			},
			"direct_2": {
				Relationship: interfaces.NoRelationship,
				Dependencies: []string{
					"tx_1_a",
					"tx_1_c",
				},
			},
			"direct_3": {
				Relationship: interfaces.NoRelationship,
			},
			"tx_1_a": {
				Dependencies: []string{
					"tx_2_a",
					"tx_2_b",
				},
			},
			"tx_1_b": {
				Dependencies: []string{
					"tx_2_c",
				},
			},
			"tx_1_c": {
				Dependencies: []string{
					"tx_2_a",
					"tx_2_d",
				},
			},
		},
	}

	// create a Pathfinder from the manifests entry
	p, err := New(m)
	require.NoError(t, err)

	// since we have no marked DependencyRelationship#Direct pkgs
	// in the input snapshot, there will be no Paths returned
	for depName := range m.Resolved {
		got, err := p.PathsFrom(depName)
		require.NoError(t, err)
		require.Equal(t, []Path{}, got, "unexpected paths returned for %q", depName)
	}
}

func TestTxPathMissingRoot(t *testing.T) {
	// represents a single "manifests" entry in a snapshot submission
	m := &interfaces.Manifest{
		Name: "simple",
		Resolved: map[string]*interfaces.DependencyNode{
			"direct_1": {
				Relationship: interfaces.Direct,
				Dependencies: []string{
					"tx_1_a",
					"tx_1_b",
					"tx_1_c",
				},
			},
			// In this test, no paths will be captured back to
			// direct_2 even though it is clearly a root node
			"direct_2": {
				Relationship: interfaces.NoRelationship,
				Dependencies: []string{
					"tx_1_a",
					"tx_1_c",
				},
			},
			"direct_3": {
				Relationship: interfaces.Direct,
			},
			"tx_1_a": {
				Dependencies: []string{
					"tx_2_a",
					"tx_2_b",
				},
			},
			"tx_1_b": {
				Dependencies: []string{
					"tx_2_c",
				},
			},
			"tx_1_c": {
				Dependencies: []string{
					"tx_2_a",
					"tx_2_d",
				},
			},
		},
	}

	// create a Pathfinder from the manifests entry
	p, err := New(m)
	require.NoError(t, err)

	// direct dependencies (with or without child dependencies) should return no Paths
	got, err := p.PathsFrom("direct_1")
	require.NoError(t, err, "direct_1")
	require.Equal(t, []Path{}, got, "direct_1")

	got, err = p.PathsFrom("direct_2")
	require.NoError(t, err, "direct_2")
	require.Equal(t, []Path{}, got, "direct_2")

	got, err = p.PathsFrom("direct_3")
	require.NoError(t, err, "direct_3")
	require.Equal(t, []Path{}, got, "direct_3")

	// single Paths expected
	got, err = p.PathsFrom("tx_1_b")
	require.NoError(t, err)
	require.Len(t, got, 1, "expected tx_1_b to have 1 path, got: %d", len(got))
	checkPath(t, "tx_1_b -> direct_1", got[0], Path{"direct_1"})

	got, err = p.PathsFrom("tx_2_c")
	require.NoError(t, err)
	require.Len(t, got, 1, "expected tx_2_c to have 1 path, got: %d", len(got))
	checkPath(t, "tx_2_c -> direct_1", got[0], Path{"tx_1_b", "direct_1"})

	// only valid path to a root (known direct dependency) is to direct_1
	tx2dExpected := []Path{
		{"tx_1_c", "direct_1"},
	}
	tx2dGot, err := p.PathsFrom("tx_2_d")
	require.NoError(t, err)
	require.Len(t, tx2dGot, 1)
	checkPath(t, "tx_2_d -> direct_1", tx2dExpected[0], tx2dGot[0])
}

func TestSnapshotManifest(t *testing.T) {
	// hydrate test snapshot
	snapshot, err := hydrateTestSnapshot(t, "testdata/gradle_snapshot.json")
	require.NoError(t, err)
	require.NotNil(t, snapshot.Manifests)
	require.GreaterOrEqual(t, 1, len(snapshot.Manifests))

	// create a Pathfinder from the manifests entry
	manifest, found := snapshot.Manifests["ci-build"]
	require.True(t, found)
	p, err := New(manifest)
	require.NoError(t, err)

	// a direct dependency normally won't have a Path to capture, it _is_ a root
	got1, err := p.PathsFrom("app.cash.sqldelight:async-extensions-iossimulatorarm64:2.0.0")
	require.NoError(t, err)
	require.Len(t, got1, 1)
	checkPath(t, "iosimulatorarm64:2.0.0 -> extensions:2.0.0", Path{"app.cash.sqldelight:async-extensions:2.0.0"}, got1[0])

	// a direct dependency _can_ be dependend on by other directs in the project
	expected2 := []Path{
		{"robotx.startup:startup-runtime:1.1.1"},
		{"robotx.activity:activity:1.7.2"},
		{"robotx.activity:activity:1.7.0"},
	}
	got2, err := p.PathsFrom("robotx.tracing:tracing:1.0.0")
	require.NoError(t, err)
	require.Len(t, got2, 3)
	checkPaths(t, expected2, got2)

	// a transitive can have many roots, and more than one path to each
	expected3 := []Path{
		{"com.android.tools.build:gradle:8.1.1", "com.android.application:com.android.application.gradle.plugin:8.1.1"},
		{"com.android.tools.build:apkzlib:8.1.1", "com.android.tools.build:builder:8.1.1", "com.android.tools.build:gradle:8.1.1", "com.android.application:com.android.application.gradle.plugin:8.1.1"},
		{"com.android.tools.build:builder:8.1.1", "com.android.tools.build:gradle:8.1.1", "com.android.application:com.android.application.gradle.plugin:8.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.lint:lint-model:31.1.1", "com.android.tools.build:gradle:8.1.1", "com.android.application:com.android.application.gradle.plugin:8.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.lint:lint-model:31.1.1", "com.android.tools.lint:lint-api:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.lint:lint-model:31.1.1", "com.android.tools.lint:lint-api:31.1.1", "com.android.tools.lint:lint-checks:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.build:gradle:8.1.1", "com.android.application:com.android.application.gradle.plugin:8.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.build:manifest-merger:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.build:manifest-merger:31.1.1", "com.android.tools.lint:lint-api:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.build:manifest-merger:31.1.1", "com.android.tools.lint:lint-api:31.1.1", "com.android.tools.lint:lint-checks:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.build:manifest-merger:31.1.1", "com.android.tools.build:builder:8.1.1", "com.android.tools.build:gradle:8.1.1", "com.android.application:com.android.application.gradle.plugin:8.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.lint:lint-checks:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.lint:lint-api:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.lint:lint-api:31.1.1", "com.android.tools.lint:lint-checks:31.1.1", "com.android.tools.lint:lint:31.1.1", "com.android.tools.lint:lint-gradle:31.1.1"},
		{"com.android.tools:sdk-common:31.1.1", "com.android.tools.build:builder:8.1.1", "com.android.tools.build:gradle:8.1.1", "com.android.application:com.android.application.gradle.plugin:8.1.1"},
	}
	got3, err := p.PathsFrom("org.bouncycastle:bcpkix-jdk15on:1.67")
	require.NoError(t, err)
	require.Len(t, got3, 16)
	checkPaths(t, expected3, got3)
}

func hydrateTestSnapshot(t *testing.T, filename string) (*interfaces.Snapshot, error) {
	t.Helper()

	payload, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	out := &interfaces.Snapshot{}
	err = json.Unmarshal(payload, out)
	return out, err
}

func checkPaths(t *testing.T, expected, got []Path) {
	t.Helper()

	require.Equal(t, len(expected), len(got), "%s: unmatching lengths expected: %v got: %v", "checkPaths", expected, got)

	gotMap := map[string]Path{}
	expMap := map[string]Path{}
	for i := 0; i < len(expected); i++ {
		gotKey := strings.Join(got[i], " ")
		gotMap[gotKey] = got[i]

		expKey := strings.Join(expected[i], " ")
		expMap[expKey] = expected[i]
	}

	for expKey, expected := range expMap {
		got, found := gotMap[expKey]
		require.True(t, found, "expected path %q not found in: %+v", expKey, got)
		checkPath(t, "<<"+expKey+">>", expected, got)
	}
	for gotKey, got := range gotMap {
		expected, found := expMap[gotKey]
		require.True(t, found, "got path %q not found in: %+v", gotKey, expected)
		checkPath(t, "<<"+gotKey+">>", got, expected)
	}
}

func checkPath(t *testing.T, label string, expected, got Path) {
	t.Helper()

	require.Equal(t, len(expected), len(got), "%s: unmatching lengths expected: %v got: %v", label, expected, got)

	for i := 0; i < len(got); i++ {
		require.Equal(t, expected[i], got[i], "%s: unexpected mismatch at elem %d expected: %v got: %v", label, i, expected, got)
	}
}
