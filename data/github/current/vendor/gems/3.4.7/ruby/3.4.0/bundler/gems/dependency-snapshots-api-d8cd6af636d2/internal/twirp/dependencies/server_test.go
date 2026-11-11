package dependencies

import (
	"context"
	"maps"
	"slices"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func getServiceLayerFakeSnapshot() []*interfaces.Snapshot {
	snapshots := make([]*interfaces.Snapshot, 1)
	snapshots[0] = &interfaces.Snapshot{
		ID: 1,
		Detector: &interfaces.DetectorMetadata{
			Name: "my-detector",
		},
		Job: interfaces.Job{
			Correlator: "zzz build",
		},
		Scanned: time.Now(),
		Manifests: map[string]*interfaces.Manifest{
			"Path1": {
				SnapshotID: 1,
				Name:       "Path1",
				File:       interfaces.FileInfo{SourceLocation: "Path1"},
				Metadata:   interfaces.Metadata{"oid": "oid1"},
				Resolved: interfaces.DependencyGraph{
					"somepack1": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/somepack1@version1",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{"myGreatTransitiveDep"},
					},
					"myGreatTransitiveDep": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/myGreatTransitiveDep@2.0.0",
						Relationship: interfaces.Indirect,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{},
					},
				},
			},
			"Path2": {
				SnapshotID: 1,
				Name:       "Path2",
				File:       interfaces.FileInfo{SourceLocation: "Path2"},
				Metadata:   interfaces.Metadata{"oid": "oid2"},
				Resolved: interfaces.DependencyGraph{
					"somepack2": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/somepack2@version2",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{"Path1"},
					},
					"mysteryDependency": &interfaces.DependencyNode{
						PackageURL: "pkg:example/mystery@0.0.0",
						// Relationship missing
						Scope: interfaces.Runtime,
					},
				},
			},
		},
	}

	return snapshots
}

func getServiceLayerFakeSnapshotsThatCanMerge() []*interfaces.Snapshot {
	snapshots := getServiceLayerFakeSnapshot()
	secondSnapshot := &interfaces.Snapshot{
		ID: 2,
		Detector: &interfaces.DetectorMetadata{
			Name: "my-detector",
		},
		Job: interfaces.Job{
			Correlator: "yyy build",
		},
		Scanned: time.Now(),
		Manifests: map[string]*interfaces.Manifest{
			"Path1": {
				SnapshotID: 2,
				Name:       "Path1",
				File:       interfaces.FileInfo{SourceLocation: "Path1"},
				Metadata:   interfaces.Metadata{"oid": "oid1"},
				Resolved: interfaces.DependencyGraph{
					"otherpack": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/otherpack@version1",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{},
					},
				},
			},
		},
	}

	snapshots = append(snapshots, secondSnapshot)

	thirdSnapshot := &interfaces.Snapshot{
		ID: 3,
		Detector: &interfaces.DetectorMetadata{
			Name: "fancier-detector",
		},
		Job: interfaces.Job{
			Correlator: "aaa build",
		},
		Scanned: time.Now(),
		Manifests: map[string]*interfaces.Manifest{
			"Path1": {
				SnapshotID: 3,
				Name:       "Path1",
				File:       interfaces.FileInfo{SourceLocation: "Path1"},
				Metadata:   interfaces.Metadata{"oid": "oid1"},
				Resolved: interfaces.DependencyGraph{
					"goodpack": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/goodpack@version1",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{},
					},
				},
			},
		},
	}
	snapshots = append(snapshots, thirdSnapshot)
	return snapshots
}

func getServiceLayerFakeSnapshotWithMoreTransitives() []*interfaces.Snapshot {
	snapshot := getServiceLayerFakeSnapshot()[0]
	snapshot.Manifests = map[string]*interfaces.Manifest{}

	snapshot.Manifests["pom.xml"] = &interfaces.Manifest{
		SnapshotID: 1,
		Name:       "pom.xml",
		File:       interfaces.FileInfo{SourceLocation: "pom.xml"},
		// Edges defined in this manifest:
		// a -> b -> c -> d
		// a -> c
		// b -> c -> d
		// b -> d
		Resolved: interfaces.DependencyGraph{
			"a": &interfaces.DependencyNode{
				PackageURL:   "pkg:maven/a@1.0.0",
				Relationship: interfaces.Direct,
				Scope:        interfaces.Runtime,
				Dependencies: []string{"b", "c"},
			},
			"b": &interfaces.DependencyNode{
				PackageURL:   "pkg:maven/b@2.0.0",
				Relationship: interfaces.Direct,
				Scope:        interfaces.Runtime,
				Dependencies: []string{"c", "d"},
			},
			"c": &interfaces.DependencyNode{
				PackageURL:   "pkg:maven/c@3.0.0",
				Relationship: interfaces.Indirect,
				Scope:        interfaces.Runtime,
				Dependencies: []string{"d"},
			},
			"d": &interfaces.DependencyNode{
				PackageURL:   "pkg:maven/d@4.0.0",
				Relationship: interfaces.Indirect,
				Scope:        interfaces.Runtime,
				Dependencies: []string{},
			},
		},
	}

	return []*interfaces.Snapshot{snapshot}
}

type MockedDependenciesService struct {
	mock.Mock
}

func (s *MockedDependenciesService) CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode interfaces.SnapshotQueryMode) ([]*interfaces.Snapshot, error) {
	args := s.Called(ctx, repositoryID, mode)
	return args.Get(0).([]*interfaces.Snapshot), args.Error(1)
}

func (s *MockedDependenciesService) HasManifests(ctx context.Context, repositoryID uint64) (bool, error) {
	args := s.Called(ctx, repositoryID)
	return args.Bool(0), args.Error(1)
}

func (s *MockedDependenciesService) RepositoriesContainingDependency(ctx context.Context, purl, versionRange string, mode interfaces.SnapshotQueryMode) ([]uint64, error) {
	args := s.Called(ctx, purl, versionRange, mode)
	return args.Get(0).([]uint64), args.Error(1)
}

type MockedFeaturesClient struct {
	mock.Mock
}

func (s *MockedFeaturesClient) IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error) {
	args := s.Called(ctx, feature, actors)
	return args.Get(0).([]bool), args.Error(1)
}

func (s *MockedFeaturesClient) IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error) {
	args := s.Called(ctx, feature, repositoryID)
	return args.Bool(0), args.Error(1)
}

func TestGetDependenciesForRepositoryHappyPath(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1}
	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshot()
	snapshot := serviceLayerFakeSnapshot[0]

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)
	assert.NotNil(t, response)

	verifyServiceLayerFakeManifestsMatchesActual(t, snapshot.Manifests, response.Manifests)
	verifyServiceLayerFakeManifestListMatchesActual(t, snapshot, response.AllManifests)

	assert.Equal(t, snapshot.Detector.Name, response.Snapshots[snapshot.ID].Detector.Name)
	assert.Equal(t, snapshot.Scanned.UTC(), response.Snapshots[snapshot.ID].Scanned.AsTime())
}

func TestGetDependenciesForRepositoryRelationshipFilterEmpty(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1}

	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshot()
	snapshot := serviceLayerFakeSnapshot[0]

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)

	verifyServiceLayerFakeManifestsMatchesActual(t, snapshot.Manifests, response.Manifests)
	verifyServiceLayerFakeManifestListMatchesActual(t, snapshot, response.AllManifests)
}

func TestGetDependenciesForRepositoryWithMergedDeps(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1}

	serviceLayerFakeSnapshots := getServiceLayerFakeSnapshotsThatCanMerge()

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshots, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)

	assert.Len(t, response.Manifests, 2, "manifests are merged between snapshots")
	assert.Len(t, response.AllManifests, 2, "manifests are merged between snapshots")

	foundGoodPack := false
	for _, manifest := range response.AllManifests {
		depNames := slices.Collect(maps.Keys(manifest.Dependencies))
		assert.NotContains(t, depNames, "otherpack")
		assert.NotContains(t, depNames, "somepack1")
		assert.NotEqual(t, uint64(2), manifest.SnapshotId, "one of the snapshots should go away")
		assert.NotEqual(t, uint64(0), manifest.SnapshotId, "snapshotID should be set")
		if slices.Contains(depNames, "goodpack") {
			foundGoodPack = true
		}
	}
	assert.True(t, foundGoodPack, "expected to find 'goodpack' in the merged dependencies")

	foundGoodPack = false
	for _, manifest := range response.Manifests {
		depNames := slices.Collect(maps.Keys(manifest.Dependencies))
		assert.NotContains(t, depNames, "otherpack")
		assert.NotContains(t, depNames, "somepack1")
		assert.NotEqual(t, uint64(2), manifest.SnapshotId, "one of the snapshots should go away")
		assert.NotEqual(t, uint64(0), manifest.SnapshotId, "snapshotID should be set")
		if slices.Contains(depNames, "goodpack") {
			foundGoodPack = true
		}
	}
	assert.True(t, foundGoodPack, "expected to find 'goodpack' in the merged dependencies")
}

func TestGetDependenciesForRepositoryRelationshipFilterDirect(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1, RelationshipFilter: proto.Relationship_RELATIONSHIP_DIRECT.Enum()}

	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshot()
	snapshot := serviceLayerFakeSnapshot[0]

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)

	// delete the indirect and unknown dependencies from the snapshot so the following assertions will work
	delete(snapshot.Manifests["Path1"].Resolved, "myGreatTransitiveDep")
	delete(snapshot.Manifests["Path2"].Resolved, "mysteryDependency")

	verifyServiceLayerFakeManifestsMatchesActual(t, snapshot.Manifests, response.Manifests)
	verifyServiceLayerFakeManifestListMatchesActual(t, snapshot, response.AllManifests)
}

func TestGetDependenciesForRepositoryRelationshipFilterUnknown(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1, RelationshipFilter: proto.Relationship_RELATIONSHIP_UNKNOWN.Enum()}

	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshot()
	snapshot := serviceLayerFakeSnapshot[0]

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)

	// delete all direct and indirect dependencies from the snapshot so the following assertions will work
	delete(snapshot.Manifests["Path1"].Resolved, "somepack1")
	delete(snapshot.Manifests["Path1"].Resolved, "myGreatTransitiveDep")
	delete(snapshot.Manifests["Path2"].Resolved, "somepack2")

	verifyServiceLayerFakeManifestsMatchesActual(t, snapshot.Manifests, response.Manifests)
	verifyServiceLayerFakeManifestListMatchesActual(t, snapshot, response.AllManifests)
}

func TestGetDependenciesForRepositoryRelationshipFilterIndirect(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1, RelationshipFilter: proto.Relationship_RELATIONSHIP_TRANSITIVE.Enum()}

	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshot()
	snapshot := serviceLayerFakeSnapshot[0]

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)

	// delete the direct and unknown dependencies from the snapshot so the following assertions will work
	delete(snapshot.Manifests["Path1"].Resolved, "somepack1")
	delete(snapshot.Manifests["Path2"].Resolved, "somepack2")
	delete(snapshot.Manifests["Path2"].Resolved, "mysteryDependency")

	verifyServiceLayerFakeManifestsMatchesActual(t, snapshot.Manifests, response.Manifests)
	verifyServiceLayerFakeManifestListMatchesActual(t, snapshot, response.AllManifests)
}

func TestGetDependenciesForRepositoryRootAncestors(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1, IncludeRootAncestors: true}

	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshotWithMoreTransitives()
	snapshot := serviceLayerFakeSnapshot[0]

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)

	verifyServiceLayerFakeManifestsMatchesActual(t, snapshot.Manifests, response.Manifests)
	verifyServiceLayerFakeManifestListMatchesActual(t, snapshot, response.AllManifests)

	assert.Len(t, response.AllManifests[0].Dependencies, 4, "should have 4 dependencies: a, b, c, d")

	aAncestors := response.AllManifests[0].Dependencies["a"].RootAncestors
	bAncestors := response.AllManifests[0].Dependencies["b"].RootAncestors
	cAncestors := response.AllManifests[0].Dependencies["c"].RootAncestors
	dAncestors := response.AllManifests[0].Dependencies["d"].RootAncestors

	//            a (direct)
	//           / \
	//          /   c
	//         /     \
	//        /       d
	//       /
	//      b (direct + transitive)
	//     / \
	//    c   d
	//    |
	//    d

	assert.Empty(t, aAncestors, "a should have no ancestors")

	assert.ElementsMatch(t, bAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipParent),
	},
		"b should have one parent: a",
	)

	assert.ElementsMatch(t, cAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipParent),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipParent),
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipAncestor),
	},
		"c should have two parents: a and b, plus one ancestor: a",
	)

	assert.ElementsMatch(t, dAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipAncestor),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipAncestor),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipParent),
	},
		"d should have two ancestors: a and b, plus one parent: b",
	)
}

func TestGetDependenciesForRepositoryRootAncestorsCycle(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1, IncludeRootAncestors: true}

	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshotWithMoreTransitives()
	snapshot := serviceLayerFakeSnapshot[0]
	// add a cycle
	snapshot.Manifests["pom.xml"].Resolved["d"].Dependencies = []string{"a"}

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)

	verifyServiceLayerFakeManifestsMatchesActual(t, snapshot.Manifests, response.Manifests)
	verifyServiceLayerFakeManifestListMatchesActual(t, snapshot, response.AllManifests)

	assert.Len(t, response.AllManifests[0].Dependencies, 4, "should have 4 dependencies: a, b, c, d")

	aAncestors := response.AllManifests[0].Dependencies["a"].RootAncestors
	bAncestors := response.AllManifests[0].Dependencies["b"].RootAncestors
	cAncestors := response.AllManifests[0].Dependencies["c"].RootAncestors
	dAncestors := response.AllManifests[0].Dependencies["d"].RootAncestors

	//            a (direct)
	//           / \
	//          /   c
	//         /     \
	//        /       d -> a (cycle)
	//       /
	//      b (direct + transitive)
	//     / \
	//    c   d -> a (cycle)
	//    |
	//    d

	assert.ElementsMatch(t, aAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipAncestor),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipAncestor),
	},
		"'a' is its own ancestor, in addition to having 'b' as an ancestor",
	)

	assert.ElementsMatch(t, bAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipParent),
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipAncestor),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipAncestor),
	},
		"'b' is its own ancestor, in addition to having 'a' as a both a parent and an ancestor (via the cycle)",
	)

	assert.ElementsMatch(t, cAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipParent),
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipAncestor),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipParent),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipAncestor),
	},
		"'c' has both 'a' and 'b' as both parents and ancestors",
	)

	assert.ElementsMatch(t, dAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipAncestor),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipParent),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipAncestor),
	},
		"'d' has 'b' as a parent and 'a' and 'b' as ancestors",
	)
}

func TestGetDependenciesForRepositoryRootAncestorsMissingLinks(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependenciesForRepositoryRequest{RepositoryId: 1, IncludeRootAncestors: true}

	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshotWithMoreTransitives()
	snapshot := serviceLayerFakeSnapshot[0]
	// add a dependency on something that doesn't actually appear in the manifest.
	// there isn't much we can do with this data, so we just ignore it.
	// this test should show that we're able to recover the rest of the tree without crashing.
	snapshot.Manifests["pom.xml"].Resolved["d"].Dependencies = []string{"notarealdep"}

	mockedDependenciesService.On("CanonicalSnapshotsForRepository", mock.Anything, expectedRequest.RepositoryId, interfaces.DefaultQueryMode).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependenciesForRepository(expectedCtx, &expectedRequest)
	require.NoError(t, err)

	verifyServiceLayerFakeManifestsMatchesActual(t, snapshot.Manifests, response.Manifests)
	verifyServiceLayerFakeManifestListMatchesActual(t, snapshot, response.AllManifests)

	assert.Len(t, response.AllManifests[0].Dependencies, 4, "should have 4 dependencies: a, b, c, d")

	aAncestors := response.AllManifests[0].Dependencies["a"].RootAncestors
	bAncestors := response.AllManifests[0].Dependencies["b"].RootAncestors
	cAncestors := response.AllManifests[0].Dependencies["c"].RootAncestors
	dAncestors := response.AllManifests[0].Dependencies["d"].RootAncestors

	//            a (direct)
	//           / \
	//          /   c
	//         /     \
	//        /       d -> notarealdep (missing)
	//       /
	//      b (direct + transitive)
	//     / \
	//    c   d -> notarealdep (missing)
	//    |
	//    d

	assert.Empty(t, aAncestors, "a should have no ancestors")

	assert.ElementsMatch(t, bAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipParent),
	},
		"b should have one parent: a",
	)

	assert.ElementsMatch(t, cAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipParent),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipParent),
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipAncestor),
	},
		"c should have two parents: a and b, plus one ancestor: a",
	)

	assert.ElementsMatch(t, dAncestors, []*proto.RootAncestor{
		twirpAncestor("a", "1.0.0", interfaces.AncestorRelationshipAncestor),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipAncestor),
		twirpAncestor("b", "2.0.0", interfaces.AncestorRelationshipParent),
	},
		"d should have two ancestors: a and b, plus one parent: b",
	)
}

func twirpAncestor(packageName string, requirements string, relationship interfaces.AncestorRelationship) *proto.RootAncestor {
	twirpRel := proto.AncestorRelationship_ANCESTOR_RELATIONSHIP_UNKNOWN
	switch relationship {
	case interfaces.AncestorRelationshipParent:
		twirpRel = proto.AncestorRelationship_ANCESTOR_RELATIONSHIP_PARENT
	case interfaces.AncestorRelationshipAncestor:
		twirpRel = proto.AncestorRelationship_ANCESTOR_RELATIONSHIP_ANCESTOR
	}

	return &proto.RootAncestor{
		PackageName:  packageName,
		Requirements: requirements,
		Relationship: twirpRel,
	}
}

func TestHasManifestsHappyPath(t *testing.T) {
	mockedDependenciesService := MockedDependenciesService{}
	service := service{dependenciesSvc: &mockedDependenciesService}

	expectedCtx := context.Background()
	expectedRequest := proto.HasManifestsRequest{RepositoryId: 1}

	mockedDependenciesService.On("HasManifests", expectedCtx, expectedRequest.RepositoryId).Return(true, nil).Times(1)

	response, err := service.HasManifests(expectedCtx, &expectedRequest)
	require.NoError(t, err)
	assert.NotNil(t, response)

	assert.Equal(t, true, response.GetHasManifests())

	mockedDependenciesService.On("HasManifests", expectedCtx, expectedRequest.RepositoryId).Return(false, nil).Times(1)

	response, err = service.HasManifests(expectedCtx, &expectedRequest)
	require.NoError(t, err)
	assert.NotNil(t, response)

	assert.Equal(t, false, response.GetHasManifests())
}

func verifyServiceLayerFakeManifestsMatchesActual(t *testing.T, serviceLayerFakeManifests map[string]*interfaces.Manifest, actual map[string]*proto.Manifest) {
	t.Helper()

	assert.Equal(t, len(serviceLayerFakeManifests), len(actual))
	for key, manifest := range actual {
		serviceLayerManifest := serviceLayerFakeManifests[key]
		assert.Equal(t, serviceLayerManifest.Name, key)
		assert.Equal(t, serviceLayerManifest.File.SourceLocation, manifest.FilePath)

		for depName, dependency := range manifest.Dependencies {
			serviceLayerDependency := serviceLayerManifest.Resolved[depName]
			assert.NotNil(t, serviceLayerDependency)
			assert.Equal(t, serviceLayerDependency.PackageURL, dependency.PackageUrl)
			assert.Equal(t, serviceLayerDependency.Dependencies, dependency.Dependencies)
			assert.Equal(t, serviceLayerDependency.Scope, DependencyScopeFromTwirp(dependency.Scope))
			assert.Equal(t, serviceLayerDependency.Relationship, DependencyRelationshipFromTwirp(dependency.Relationship))
		}
		for depName, dependency := range serviceLayerManifest.Resolved {
			actualDependency, ok := manifest.Dependencies[depName]
			require.Truef(t, ok, "Dependency %s from expected manifest not found in actual manifest", depName)
			assert.NotNil(t, actualDependency)
			assert.Equal(t, dependency.PackageURL, actualDependency.PackageUrl)
			assert.Equal(t, dependency.Dependencies, actualDependency.Dependencies)
			assert.Equal(t, dependency.Scope, DependencyScopeFromTwirp(actualDependency.Scope))
			assert.Equal(t, dependency.Relationship, DependencyRelationshipFromTwirp(actualDependency.Relationship))
		}
	}
}

func verifyServiceLayerFakeManifestListMatchesActual(t *testing.T, snapshot *interfaces.Snapshot, actual []*proto.Manifest) {
	t.Helper()

	assert.Equal(t, len(snapshot.Manifests), len(actual))
	for _, manifest := range actual {
		// This is not technically correct since the manifest name (they key)
		// is not guaranteed to be the same as the file path. However, this
		// is a test, and this is how I'm choosing to live my life.
		serviceLayerManifest := snapshot.Manifests[manifest.FilePath]
		assert.Equal(t, serviceLayerManifest.File.SourceLocation, manifest.FilePath)
		assert.Equal(t, serviceLayerManifest.SnapshotID, manifest.SnapshotId)
		assert.Equal(t, serviceLayerManifest.Name, manifest.Name)

		for depName, dependency := range manifest.Dependencies {
			serviceLayerDependency := serviceLayerManifest.Resolved[depName]
			assert.NotNil(t, serviceLayerDependency)
			assert.Equal(t, serviceLayerDependency.PackageURL, dependency.PackageUrl)
			assert.Equal(t, serviceLayerDependency.Dependencies, dependency.Dependencies)
			assert.Equal(t, serviceLayerDependency.Scope, DependencyScopeFromTwirp(dependency.Scope))
		}
		for depName, dependency := range serviceLayerManifest.Resolved {
			actualDependency, ok := manifest.Dependencies[depName]
			require.Truef(t, ok, "Dependency %s from expected manifest not found in actual manifest", depName)
			assert.NotNil(t, actualDependency)
			assert.Equal(t, dependency.PackageURL, actualDependency.PackageUrl)
			assert.Equal(t, dependency.Dependencies, actualDependency.Dependencies)
			assert.Equal(t, dependency.Scope, DependencyScopeFromTwirp(actualDependency.Scope))
			assert.Equal(t, dependency.Relationship, DependencyRelationshipFromTwirp(actualDependency.Relationship))
		}
	}
}
