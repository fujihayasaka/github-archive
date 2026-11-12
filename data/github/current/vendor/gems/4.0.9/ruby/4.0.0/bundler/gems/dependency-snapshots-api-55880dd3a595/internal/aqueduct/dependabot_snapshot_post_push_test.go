package aqueduct

import (
	"context"
	"testing"
	"time"

	hydroproto "github.com/github/dependency-snapshots-api/hydro/schemas/dependency_graph/v0"
	"github.com/github/dependency-snapshots-api/hydro/schemas/dependency_graph/v0/entities"
	"github.com/github/dependency-snapshots-api/internal/aqueduct/manifests"
	dependabotmock "github.com/github/dependency-snapshots-api/internal/dependabot/mock"
	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/go-stats"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func newValidJob() *jobsproto.DependabotSnapshotPostPushJob {
	return &jobsproto.DependabotSnapshotPostPushJob{
		RequestId: "request-id-123",
		EventId:   "event-id-123",
		Repository: &jobsproto.DependabotSnapshotPostPushJob_Repository{
			Id:                  100,
			GlobalRelayId:       "global-relay-id-100",
			Name:                "test-repo",
			Visibility:          jobsproto.DependabotSnapshotPostPushJob_Repository_VISIBILITY_PUBLIC,
			ParentId:            400,
			DefaultBranch:       "main",
			PrimaryLanguageName: "Go",
		},
		Owner: &jobsproto.DependabotSnapshotPostPushJob_User{
			Id:            200,
			GlobalRelayId: "global-relay-id-200",
			Login:         "test-user",
			Type:          jobsproto.DependabotSnapshotPostPushJob_User_TYPE_USER,
		},
		Ref:             "main",
		IsDefaultBranch: true,
		BeforeOid:       "valid-oid-1",
		AfterOid:        "valid-oid-2",
		PushedAt:        timestamppb.New(time.Now().Add(-time.Minute)),
		IngestedAt:      timestamppb.New(time.Now()),
		TriggeredBy:     jobsproto.DependabotSnapshotPostPushJob_TRIGGERED_BY_PUSH,
	}
}

// newMockFeaturesClientWithParseOnceEnabled returns a mock features client that enables
//
//	both ecosystem flags for repository checks.
func newMockFeaturesClientWithParseOnceEnabled() *mockFeaturesClient {
	return &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == ParseOnceGoFeatureFlag || feature == ParseOnceNPMFeatureFlag || feature == ParseOncePythonFeatureFlag {
				return true, nil
			}
			return false, nil
		},
		isFeatureFlagEnabledForUserFn: func(ctx context.Context, feature string, userID uint64) (bool, error) {
			return false, nil
		},
		isFeatureFlagEnabledForOrgFn: func(ctx context.Context, feature string, orgID uint64) (bool, error) {
			return false, nil
		},
	}
}

// ============================================================================
// Tests
// ============================================================================

func TestHandleDependabotSnapshotPostReceive_SkipsInvalidRepos(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()
	job.Repository.Id = 0 // Invalid repo ID

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for invalid repo")

	// Verify skip metric was emitted
	require.GreaterOrEqual(t, st.CounterCallCount(), 1)
	metric, tags, count := st.CounterArgsForCall(st.CounterCallCount() - 1)
	require.Equal(t, "aqueduct.handler.dependabot_snapshot_post_push.skipped", metric)
	require.Equal(t, "invalid_repo", tags["reason"])
	require.Equal(t, int64(1), count)

	// Verify no hydro publishing happened
	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotPostReceive_SkipsNonDefaultBranches(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()
	job.IsDefaultBranch = false

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for non-default branch")

	// Verify skip metric was emitted
	require.GreaterOrEqual(t, st.CounterCallCount(), 1)
	metric, tags, count := st.CounterArgsForCall(st.CounterCallCount() - 1)
	require.Equal(t, "aqueduct.handler.dependabot_snapshot_post_push.skipped", metric)
	require.Equal(t, "non_default_branch", tags["reason"])
	require.Equal(t, int64(1), count)

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotPostReceive_SkipsDeletedRefs(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()
	job.AfterOid = manifests.ZeroOID // Deleted ref

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for deleted ref")

	require.GreaterOrEqual(t, st.CounterCallCount(), 1)
	metric, tags, count := st.CounterArgsForCall(st.CounterCallCount() - 1)
	require.Equal(t, "aqueduct.handler.dependabot_snapshot_post_push.skipped", metric)
	require.Equal(t, "deleted_ref", tags["reason"])
	require.Equal(t, int64(1), count)

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotPostReceive_SkipsInitPush(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()
	job.BeforeOid = manifests.ZeroOID // Init push

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for init push")

	require.GreaterOrEqual(t, st.CounterCallCount(), 1)
	metric, tags, count := st.CounterArgsForCall(st.CounterCallCount() - 1)
	require.Equal(t, "aqueduct.handler.dependabot_snapshot_post_push.skipped", metric)
	require.Equal(t, "init_push", tags["reason"])
	require.Equal(t, int64(1), count)

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestEnabledEcosystems(t *testing.T) {
	tests := []struct {
		name          string
		ownerType     OwnerType
		ownerID       uint64
		repoID        uint64
		repoFlags     map[string]bool
		userFlags     map[string]bool
		orgFlags      map[string]bool
		ffError       error
		expectedCount int
		expectError   bool
	}{
		{
			name:          "No ecosystems enabled when flags are off",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			repoFlags:     nil,
			userFlags:     nil,
			expectedCount: 0,
		},
		{
			name:          "Golang enabled by repo flag only",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			repoFlags:     map[string]bool{ParseOnceGoFeatureFlag: true},
			expectedCount: 1, // Golang
		},
		{
			name:          "NPM enabled by repo flag only",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			repoFlags:     map[string]bool{ParseOnceNPMFeatureFlag: true},
			expectedCount: 1, // NPM
		},
		{
			name:          "Golang + NPM enabled by repo flag",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			repoFlags:     map[string]bool{ParseOnceGoFeatureFlag: true, ParseOnceNPMFeatureFlag: true},
			expectedCount: 2, // Golang + NPM
		},
		{
			name:          "Golang + NPM enabled by user flag",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			userFlags:     map[string]bool{ParseOnceGoFeatureFlag: true, ParseOnceNPMFeatureFlag: true},
			expectedCount: 2, // Golang + NPM
		},
		{
			name:          "Golang + NPM enabled by org flag",
			ownerType:     OwnerTypeOrganization,
			ownerID:       100,
			repoID:        200,
			orgFlags:      map[string]bool{ParseOnceGoFeatureFlag: true, ParseOnceNPMFeatureFlag: true},
			expectedCount: 2, // Golang + NPM
		},
		{
			name:          "Python enabled by repo flag only",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			repoFlags:     map[string]bool{ParseOncePythonFeatureFlag: true},
			expectedCount: 1, // PyPi
		},
		{
			name:          "Python enabled by user flag",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			userFlags:     map[string]bool{ParseOncePythonFeatureFlag: true},
			expectedCount: 1, // PyPi
		},
		{
			name:          "Python enabled by org flag",
			ownerType:     OwnerTypeOrganization,
			ownerID:       100,
			repoID:        200,
			orgFlags:      map[string]bool{ParseOncePythonFeatureFlag: true},
			expectedCount: 1, // PyPi
		},
		{
			name:          "All ecosystems enabled by repo flag",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			repoFlags:     map[string]bool{ParseOnceGoFeatureFlag: true, ParseOnceNPMFeatureFlag: true, ParseOncePythonFeatureFlag: true},
			expectedCount: 3, // Golang + NPM + PyPi
		},
		{
			name:          "Feature flag check error",
			ownerType:     OwnerTypeUser,
			ownerID:       100,
			repoID:        200,
			ffError:       errors.New("feature flag check failed"),
			expectedCount: 0,
			expectError:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			ff := &mockFeaturesClient{
				isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
					if tt.ffError != nil {
						return false, tt.ffError
					}
					if tt.repoFlags == nil {
						return false, nil
					}
					return tt.repoFlags[feature], nil
				},
				isFeatureFlagEnabledForUserFn: func(ctx context.Context, feature string, userID uint64) (bool, error) {
					if tt.userFlags == nil {
						return false, nil
					}
					return tt.userFlags[feature], nil
				},
				isFeatureFlagEnabledForOrgFn: func(ctx context.Context, feature string, orgID uint64) (bool, error) {
					if tt.orgFlags == nil {
						return false, nil
					}
					return tt.orgFlags[feature], nil
				},
			}

			owner := Owner{
				ID:          tt.ownerID,
				DecodedType: tt.ownerType,
			}

			ecos, err := enabledEcosystems(ctx, ff, tt.repoID, owner)
			if tt.expectError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.Len(t, ecos, tt.expectedCount)
			}
		})
	}
}

func TestHandleDependabotSnapshotPostReceive_TreeComparisonError(t *testing.T) {
	// Tree comparison errors are logged but don't fail the job - they result in no manifest changes
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			return nil, errors.New("spokes unavailable")
		},
	}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	// Tree comparison errors are non-fatal - job continues with empty entries
	require.NoError(t, err, "tree comparison errors are non-fatal")

	// Verify the tree comparison error was recorded (via enumerator metrics)
	treeErrorFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "manifest.etl.changeset_enumerator.process.error" && tags["reason"] == "comparing_trees" {
			treeErrorFound = true
			break
		}
	}
	require.True(t, treeErrorFound, "should emit tree comparison error metric")

	// Verify job was skipped due to no manifest changes (since tree comparison failed)
	skipFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_post_push.skipped" && tags["reason"] == "no_manifest_changes" {
			skipFound = true
			break
		}
	}
	require.True(t, skipFound, "should emit skip metric for no manifest changes")

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotPostReceive_NoManifestChanges(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			// Return non-manifest changes only
			return []*types.DiffEntry{
				{
					DestinationOid: types.NewObjectID("12393b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`src/main.go`)), // not a manifest file
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
			}, nil
		},
	}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error when no manifest changes")

	// Verify skip metric was emitted
	found := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_post_push.skipped" && tags["reason"] == "no_manifest_changes" {
			found = true
			break
		}
	}
	require.True(t, found, "should emit skip metric for no manifest changes")

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotPostReceive_GoManifestAdditions(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			// Go manifest files added in multiple directories
			return []*types.DiffEntry{
				{
					DestinationOid: types.NewObjectID("12393b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.mod`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				{
					DestinationOid: types.NewObjectID("asd93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.sum`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				{
					DestinationOid: types.NewObjectID("bbb93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`bar/go.mod`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				{
					DestinationOid: types.NewObjectID("ccc93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`bar/go.sum`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
			}, nil
		},
	}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for valid manifest additions")

	// Verify publishing happened
	require.Equal(t, 1, fp.PublishCallCount(), "should publish UpdateGraphEvent")
	published := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)
	require.Equal(t, "request-id-123", published.GetRequestId())
	require.Equal(t, uint32(100), published.GetRepository().GetId())
	require.Equal(t, uint32(200), published.GetOwner().GetId())
	require.Len(t, published.GetGraphChanges(), 2, "should have 2 graph changes (root + bar)")
	require.NotNil(t, published.GetRequestedAt(), "should set requested_at")

	// Verify success metrics
	successFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, _, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_post_push.success" {
			successFound = true
			break
		}
	}
	require.True(t, successFound, "should emit success counter")

	require.Greater(t, st.DistributionMsCallCount(), 0, "should emit latency metrics")
}

func TestHandleDependabotSnapshotPostReceive_PythonManifestAdditions(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			return []*types.DiffEntry{
				// Standard requirements.txt at root (exact match)
				{
					DestinationOid: types.NewObjectID("aaa93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`requirements.txt`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				// Regex variant: dot-separated (REQUIREMENTS_TXT_PATTERN)
				{
					DestinationOid: types.NewObjectID("bbb93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`requirements.prod.txt`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				// Regex variant in subdirectory (REQUIRE_TXT_PATTERN)
				{
					DestinationOid: types.NewObjectID("ccc93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`backend/require-dev.txt`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				// Non-manifest file (should be ignored)
				{
					DestinationOid: types.NewObjectID("ddd93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`src/main.py`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
			}, nil
		},
	}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for valid Python manifest additions")

	require.Equal(t, 1, fp.PublishCallCount(), "should publish UpdateGraphEvent")
	published := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)
	// Root dir: requirements.txt + requirements.prod.txt grouped together = 1 graph change
	// backend dir: require-dev.txt = 1 graph change
	changes := published.GetGraphChanges()
	require.Len(t, changes, 2, "should have 2 PyPi graph changes (root + backend)")

	changesByDir := make(map[string]*hydroproto.UpdateGraphEvent_GraphChange, len(changes))
	for _, c := range changes {
		changesByDir[c.GetDirectory()] = c
	}

	rootChange, ok := changesByDir["."]
	require.True(t, ok, "should have a graph change for the root directory")
	require.Equal(t, "main", rootChange.GetRefName())
	require.Equal(t, entities.Ecosystem_ECOSYSTEM_PYPI, rootChange.GetEcosystem())

	backendChange, ok := changesByDir["backend"]
	require.True(t, ok, "should have a graph change for the backend directory")
	require.Equal(t, "main", backendChange.GetRefName())
	require.Equal(t, entities.Ecosystem_ECOSYSTEM_PYPI, backendChange.GetEcosystem())

	// Verify success metrics
	successFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, _, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_post_push.success" {
			successFound = true
			break
		}
	}
	require.True(t, successFound, "should emit success counter")
}

func TestHandleDependabotSnapshotPostReceive_RecordsEventWhenAlertingFlagEnabled(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			return []*types.DiffEntry{
				{
					DestinationOid: types.NewObjectID("12393b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.mod`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				{
					DestinationOid: types.NewObjectID("asd93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.sum`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
			}, nil
		},
	}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			switch feature {
			case ParseOnceGoFeatureFlag, RepositoryAlertingFeatureFlag:
				return true, nil
			default:
				return false, nil
			}
		},
		isFeatureFlagEnabledForUserFn: func(ctx context.Context, feature string, userID uint64) (bool, error) {
			return false, nil
		},
		isFeatureFlagEnabledForOrgFn: func(ctx context.Context, feature string, orgID uint64) (bool, error) {
			return false, nil
		},
	}
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}
	es := &dependabotmock.MockedDependabotEventService{}
	es.On("RecordDependabotEvent",
		mock.Anything,
		uint64(100),
		interfaces.EventTypePush,
		"main",
		"valid-oid-2",
		mock.AnythingOfType("*uint64"),
		mock.MatchedBy(func(entries []interfaces.DependabotRequestedSnapshot) bool {
			return len(entries) == 1 && entries[0].Ecosystem == "golang" && entries[0].ManifestPath == "."
		}),
	).Return(uint64(1), nil)

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, es, job)
	require.NoError(t, err)

	// Verify hydro publishing happened: UpdateGraphEvent + DependabotEventProcessed
	require.Equal(t, 2, fp.PublishCallCount(), "should publish UpdateGraphEvent and DependabotEventProcessed")
	published := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)
	require.Equal(t, uint64(1), published.GetEventId(), "should include event_id from recorded event")

	// Verify DependabotEventProcessed
	processed := fp.PublishedMessages()[1].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, int64(1), processed.GetEventId(), "DependabotEventProcessed should include event_id")
	require.Equal(t, hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH, processed.GetEventType())
	require.Equal(t, int64(100), processed.GetRepositoryId())
	require.Equal(t, "main", processed.GetRef())
	require.Equal(t, "valid-oid-2", processed.GetSha())
	require.Equal(t, "request-id-123", processed.GetRequestId())
	require.NotNil(t, processed.GetProcessedAt())

	// Verify event was recorded with expected arguments
	es.AssertExpectations(t)
}

func TestHandleDependabotSnapshotPostReceive_GoManifestDeletions(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			// Go manifest files deleted
			return []*types.DiffEntry{
				{
					SourceOid: types.NewObjectID("12393b9467ddfd3b20baaaa38934cda613ce2de0"),
					Source:    types.NewPath([]byte(`foo/go.mod`)),
					Status:    types.DiffEntry_STATUS_DELETION,
				},
				{
					SourceOid: types.NewObjectID("asd93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Source:    types.NewPath([]byte(`foo/go.sum`)),
					Status:    types.DiffEntry_STATUS_DELETION,
				},
			}, nil
		},
	}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for valid manifest deletions")

	// Verify publishing happened
	require.Equal(t, 1, fp.PublishCallCount(), "should publish UpdateGraphEvent")
	published := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)
	require.Len(t, published.GetGraphChanges(), 1, "should have 1 graph change for foo directory")

	require.Greater(t, st.DistributionMsCallCount(), 0, "should emit latency metrics")
}

func TestHandleDependabotSnapshotPostReceive_PublishFailure(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			return []*types.DiffEntry{
				{
					DestinationOid: types.NewObjectID("12393b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.mod`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				{
					DestinationOid: types.NewObjectID("asd93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.sum`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
			}, nil
		},
	}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{publishErr: errors.New("kafka unavailable")}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.Error(t, err, "should return error when publish fails")
	require.Contains(t, err.Error(), "failed to publish graph changes")

	// Verify error metric was emitted
	errorFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_post_push.error" && tags["reason"] == "publish_failed" {
			errorFound = true
			break
		}
	}
	require.True(t, errorFound, "should emit error metric for publish failure")
}

func TestHandleDependabotSnapshotPostReceive_PublishPayloadFields(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			return []*types.DiffEntry{
				{
					DestinationOid: types.NewObjectID("12393b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.mod`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				{
					DestinationOid: types.NewObjectID("asd93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.sum`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
			}, nil
		},
	}
	ff := newMockFeaturesClientWithParseOnceEnabled()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err)

	require.Equal(t, 1, fp.PublishCallCount())
	published := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)

	// Verify repository fields
	repo := published.GetRepository()
	require.Equal(t, uint32(100), repo.GetId())
	require.Equal(t, "global-relay-id-100", repo.GetGlobalRelayId())
	require.Equal(t, "test-repo", repo.GetName())
	require.Equal(t, hydroproto.UpdateGraphEvent_Repository_PUBLIC, repo.GetVisibility())
	require.Equal(t, uint32(400), repo.GetParentId())
	require.Equal(t, "main", repo.GetDefaultBranch())
	require.Equal(t, "Go", repo.GetPrimaryLanguageName())

	// Verify owner fields
	owner := published.GetOwner()
	require.Equal(t, uint32(200), owner.GetId())
	require.Equal(t, "global-relay-id-200", owner.GetGlobalRelayId())
	require.Equal(t, "test-user", owner.GetLogin())
	require.Equal(t, hydroproto.UpdateGraphEvent_User_USER, owner.GetType())

	// Verify graph changes
	changes := published.GetGraphChanges()
	require.Len(t, changes, 1, "should have 1 graph change for root go.mod")
	require.Equal(t, "main", changes[0].GetRefName())
	require.Equal(t, entities.Ecosystem_ECOSYSTEM_GO, changes[0].GetEcosystem())

	// Verify requested_at is recent
	require.NotNil(t, published.GetRequestedAt())
	requestTime := published.GetRequestedAt().AsTime()
	require.WithinDuration(t, time.Now(), requestTime, 5*time.Second)

	// event_id should be 0 when alerting flag is disabled
	require.Equal(t, uint64(0), published.GetEventId(), "event_id should be zero when alerting flag is not enabled")
}

// ============================================================================
// Unit tests for collectGraphChanges
// ============================================================================

func TestCollectGraphChanges_EmptyManifests(t *testing.T) {
	groupedManifests := manifests.RelatedManifests{
		ToUpdate: [][]manifests.ManifestChange{},
		ToDelete: []manifests.ManifestChange{},
	}
	ecos := []ecosystems.Ecosystem{ecosystems.Golang}

	graphChanges := collectGraphChanges(groupedManifests, ecos)

	require.Empty(t, graphChanges, "should return empty map for empty manifests")
}

func TestCollectGraphChanges_UpdatesForEnabledEcosystem(t *testing.T) {
	groupedManifests := manifests.RelatedManifests{
		ToUpdate: [][]manifests.ManifestChange{
			{
				{
					FileInfo: manifests.Info{
						Path:      "services/api/go.mod",
						Name:      "go.mod",
						Ecosystem: ecosystems.Golang,
						FileType:  manifests.GoMod,
					},
					BlobOID: "abc123",
					Type:    manifests.ChangeAdded,
				},
				{
					FileInfo: manifests.Info{
						Path:      "services/api/go.sum",
						Name:      "go.sum",
						Ecosystem: ecosystems.Golang,
						FileType:  manifests.GoSum,
					},
					BlobOID: "def456",
					Type:    manifests.ChangeAdded,
				},
			},
		},
		ToDelete: []manifests.ManifestChange{},
	}
	ecos := []ecosystems.Ecosystem{ecosystems.Golang}

	graphChanges := collectGraphChanges(groupedManifests, ecos)

	require.Len(t, graphChanges, 1, "should have one graph change for grouped manifests")
	_, ok := graphChanges[GraphChange{Ecosystem: ecosystems.Golang, Path: "services/api/go.mod"}]
	require.True(t, ok, "should contain graph change for go.mod path")
}

func TestCollectGraphChanges_DeletionsForEnabledEcosystem(t *testing.T) {
	groupedManifests := manifests.RelatedManifests{
		ToUpdate: [][]manifests.ManifestChange{},
		ToDelete: []manifests.ManifestChange{
			{
				FileInfo: manifests.Info{
					Path:      "old-service/go.mod",
					Name:      "go.mod",
					Ecosystem: ecosystems.Golang,
					FileType:  manifests.GoMod,
				},
				BlobOID: "",
				Type:    manifests.ChangeDeleted,
			},
			{
				FileInfo: manifests.Info{
					Path:      "another-service/go.mod",
					Name:      "go.mod",
					Ecosystem: ecosystems.Golang,
					FileType:  manifests.GoMod,
				},
				BlobOID: "",
				Type:    manifests.ChangeDeleted,
			},
		},
	}
	ecos := []ecosystems.Ecosystem{ecosystems.Golang}

	graphChanges := collectGraphChanges(groupedManifests, ecos)

	require.Len(t, graphChanges, 2, "should have two graph changes for deletions")
	_, ok1 := graphChanges[GraphChange{Ecosystem: ecosystems.Golang, Path: "old-service/go.mod"}]
	_, ok2 := graphChanges[GraphChange{Ecosystem: ecosystems.Golang, Path: "another-service/go.mod"}]
	require.True(t, ok1, "should contain graph change for first deleted manifest")
	require.True(t, ok2, "should contain graph change for second deleted manifest")
}

func TestCollectGraphChanges_FiltersByEnabledEcosystems(t *testing.T) {
	groupedManifests := manifests.RelatedManifests{
		ToUpdate: [][]manifests.ManifestChange{
			{
				{
					FileInfo: manifests.Info{
						Path:      "go.mod",
						Name:      "go.mod",
						Ecosystem: ecosystems.Golang,
						FileType:  manifests.GoMod,
					},
					BlobOID: "abc123",
					Type:    manifests.ChangeAdded,
				},
			},
			{
				{
					FileInfo: manifests.Info{
						Path:      "package.json",
						Name:      "package.json",
						Ecosystem: ecosystems.NPM,
						FileType:  manifests.PackageJSON,
					},
					BlobOID: "def456",
					Type:    manifests.ChangeAdded,
				},
			},
		},
		ToDelete: []manifests.ManifestChange{
			{
				FileInfo: manifests.Info{
					Path:      "old/package.json",
					Name:      "package.json",
					Ecosystem: ecosystems.NPM,
					FileType:  manifests.PackageJSON,
				},
				BlobOID: "",
				Type:    manifests.ChangeDeleted,
			},
		},
	}

	// Only Golang enabled, not NPM
	ecos := []ecosystems.Ecosystem{ecosystems.Golang}

	graphChanges := collectGraphChanges(groupedManifests, ecos)

	require.Len(t, graphChanges, 1, "should only have graph changes for enabled ecosystems")
	_, okGo := graphChanges[GraphChange{Ecosystem: ecosystems.Golang, Path: "go.mod"}]
	_, okNpmUpdate := graphChanges[GraphChange{Ecosystem: ecosystems.NPM, Path: "package.json"}]
	_, okNpmDelete := graphChanges[GraphChange{Ecosystem: ecosystems.NPM, Path: "old/package.json"}]
	require.True(t, okGo, "should contain graph change for Go manifest")
	require.False(t, okNpmUpdate, "should not contain graph change for NPM update (not enabled)")
	require.False(t, okNpmDelete, "should not contain graph change for NPM deletion (not enabled)")
}

func TestCollectGraphChanges_MultipleEcosystemsEnabled(t *testing.T) {
	groupedManifests := manifests.RelatedManifests{
		ToUpdate: [][]manifests.ManifestChange{
			{
				{
					FileInfo: manifests.Info{
						Path:      "go.mod",
						Name:      "go.mod",
						Ecosystem: ecosystems.Golang,
						FileType:  manifests.GoMod,
					},
					BlobOID: "abc123",
					Type:    manifests.ChangeModified,
				},
			},
			{
				{
					FileInfo: manifests.Info{
						Path:      "package.json",
						Name:      "package.json",
						Ecosystem: ecosystems.NPM,
						FileType:  manifests.PackageJSON,
					},
					BlobOID: "def456",
					Type:    manifests.ChangeModified,
				},
			},
		},
		ToDelete: []manifests.ManifestChange{},
	}

	// Both ecosystems enabled
	ecos := []ecosystems.Ecosystem{ecosystems.Golang, ecosystems.NPM}

	graphChanges := collectGraphChanges(groupedManifests, ecos)

	require.Len(t, graphChanges, 2, "should have graph changes for both ecosystems")
	_, okGo := graphChanges[GraphChange{Ecosystem: ecosystems.Golang, Path: "go.mod"}]
	_, okNpm := graphChanges[GraphChange{Ecosystem: ecosystems.NPM, Path: "package.json"}]
	require.True(t, okGo, "should contain graph change for Go manifest")
	require.True(t, okNpm, "should contain graph change for NPM manifest")
}

func TestCollectGraphChanges_MixedUpdatesAndDeletions(t *testing.T) {
	groupedManifests := manifests.RelatedManifests{
		ToUpdate: [][]manifests.ManifestChange{
			{
				{
					FileInfo: manifests.Info{
						Path:      "services/new/go.mod",
						Name:      "go.mod",
						Ecosystem: ecosystems.Golang,
						FileType:  manifests.GoMod,
					},
					BlobOID: "new123",
					Type:    manifests.ChangeAdded,
				},
			},
		},
		ToDelete: []manifests.ManifestChange{
			{
				FileInfo: manifests.Info{
					Path:      "services/old/go.mod",
					Name:      "go.mod",
					Ecosystem: ecosystems.Golang,
					FileType:  manifests.GoMod,
				},
				BlobOID: "",
				Type:    manifests.ChangeDeleted,
			},
		},
	}
	ecos := []ecosystems.Ecosystem{ecosystems.Golang}

	graphChanges := collectGraphChanges(groupedManifests, ecos)

	require.Len(t, graphChanges, 2, "should have graph changes for both update and deletion")
	_, okNew := graphChanges[GraphChange{Ecosystem: ecosystems.Golang, Path: "services/new/go.mod"}]
	_, okOld := graphChanges[GraphChange{Ecosystem: ecosystems.Golang, Path: "services/old/go.mod"}]
	require.True(t, okNew, "should contain graph change for new manifest")
	require.True(t, okOld, "should contain graph change for deleted manifest")
}

func TestCollectGraphChanges_DeduplicatesSamePath(t *testing.T) {
	// If the same ecosystem+path appears in both updates and deletes (edge case),
	// it should only appear once in the result
	groupedManifests := manifests.RelatedManifests{
		ToUpdate: [][]manifests.ManifestChange{
			{
				{
					FileInfo: manifests.Info{
						Path:      "go.mod",
						Name:      "go.mod",
						Ecosystem: ecosystems.Golang,
						FileType:  manifests.GoMod,
					},
					BlobOID: "abc123",
					Type:    manifests.ChangeModified,
				},
			},
		},
		ToDelete: []manifests.ManifestChange{
			{
				FileInfo: manifests.Info{
					Path:      "go.mod", // Same path as update
					Name:      "go.mod",
					Ecosystem: ecosystems.Golang,
					FileType:  manifests.GoMod,
				},
				BlobOID: "",
				Type:    manifests.ChangeDeleted,
			},
		},
	}
	ecos := []ecosystems.Ecosystem{ecosystems.Golang}

	graphChanges := collectGraphChanges(groupedManifests, ecos)

	// The map should deduplicate - same key overwrites
	require.Len(t, graphChanges, 1, "should deduplicate same ecosystem+path")
	_, ok := graphChanges[GraphChange{Ecosystem: ecosystems.Golang, Path: "go.mod"}]
	require.True(t, ok, "should contain the graph change")
}

// ============================================================================
// Unit tests for ecosystemToProto
// ============================================================================

func TestEcosystemToProto(t *testing.T) {
	tests := []struct {
		name     string
		input    ecosystems.Ecosystem
		expected entities.Ecosystem
	}{
		{
			name:     "Go maps to ECOSYSTEM_GO",
			input:    ecosystems.Golang,
			expected: entities.Ecosystem_ECOSYSTEM_GO,
		},
		{
			name:     "NPM maps to ECOSYSTEM_NPM",
			input:    ecosystems.NPM,
			expected: entities.Ecosystem_ECOSYSTEM_NPM,
		},
		{
			name:     "PyPi maps to ECOSYSTEM_PYPI",
			input:    ecosystems.PyPi,
			expected: entities.Ecosystem_ECOSYSTEM_PYPI,
		},
		{
			name:     "Unknown maps to ECOSYSTEM_UNKNOWN",
			input:    ecosystems.Unknown,
			expected: entities.Ecosystem_ECOSYSTEM_UNKNOWN,
		},
		{
			name:     "Maven maps to ECOSYSTEM_UNKNOWN (unsupported)",
			input:    ecosystems.Maven,
			expected: entities.Ecosystem_ECOSYSTEM_UNKNOWN,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ecosystemToProto(tt.input)
			require.Equal(t, tt.expected, result)
		})
	}
}

// ============================================================================
// Unit tests for buildPayload
// ============================================================================

func TestBuildPayload(t *testing.T) {
	jobData := snapshotJobData{
		RequestID: "req-123",
		Repository: Repository{
			ID:              100,
			GlobalRelayID:   "gri-100",
			Name:            "test-repo",
			Visibility:      1, // PUBLIC
			ParentID:        50,
			DefaultBranch:   "main",
			PrimaryLanguage: "Go",
		},
		Owner: Owner{
			ID:            200,
			GlobalRelayID: "gri-200",
			Login:         "test-owner",
			Type:          1, // USER
		},
		Ref: "refs/heads/main",
	}

	changes := map[GraphChange]struct{}{
		{Ecosystem: ecosystems.Golang, Path: "."}: {},
		{Ecosystem: ecosystems.NPM, Path: "lib"}:  {},
	}

	payload := buildPayload(jobData, changes, uint64(42))

	require.Equal(t, "req-123", payload.GetRequestId())
	require.Equal(t, uint64(42), payload.GetEventId())
	require.Equal(t, uint32(100), payload.GetRepository().GetId())
	require.Equal(t, "gri-100", payload.GetRepository().GetGlobalRelayId())
	require.Equal(t, "test-repo", payload.GetRepository().GetName())
	require.Equal(t, hydroproto.UpdateGraphEvent_Repository_PUBLIC, payload.GetRepository().GetVisibility())
	require.Equal(t, uint32(50), payload.GetRepository().GetParentId())
	require.Equal(t, "main", payload.GetRepository().GetDefaultBranch())
	require.Equal(t, "Go", payload.GetRepository().GetPrimaryLanguageName())
	require.Equal(t, uint32(200), payload.GetOwner().GetId())
	require.Equal(t, "gri-200", payload.GetOwner().GetGlobalRelayId())
	require.Equal(t, "test-owner", payload.GetOwner().GetLogin())
	require.Equal(t, hydroproto.UpdateGraphEvent_User_USER, payload.GetOwner().GetType())
	require.Len(t, payload.GetGraphChanges(), 2)
	require.NotNil(t, payload.GetRequestedAt())

	// All graph changes should use the job's ref
	for _, gc := range payload.GetGraphChanges() {
		require.Equal(t, "refs/heads/main", gc.GetRefName())
	}
}

// ============================================================================
// Unit tests for publishGraphChanges
// ============================================================================

func TestPublishGraphChanges_Success(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}
	tags := stats.Tags{"test": "true"}

	payload := &hydroproto.UpdateGraphEvent{
		RequestId: "req-123",
		GraphChanges: []*hydroproto.UpdateGraphEvent_GraphChange{
			{RefName: "main", Ecosystem: entities.Ecosystem_ECOSYSTEM_GO, Directory: "."},
		},
	}

	err := publishGraphChanges(ctx, fp, payload, rt.Logger, st, tags, "test.prefix.")
	require.NoError(t, err)
	require.Equal(t, 1, fp.PublishCallCount())

	// Verify success counter
	successFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, _, _ := st.CounterArgsForCall(i)
		if metric == "test.prefix.success" {
			successFound = true
			break
		}
	}
	require.True(t, successFound, "should emit success counter")

	// Verify graph_changes distribution
	require.Equal(t, 1, st.DistributionCallCount())
	metric, _, value := st.DistributionArgsForCall(0)
	require.Equal(t, "test.prefix.graph_changes", metric)
	require.Equal(t, float64(1), value)
}

func TestPublishGraphChanges_Error(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	fp := &mockHydroPublisher{publishErr: errors.New("publish failed")}
	st := &mockStatsClient{}
	tags := stats.Tags{"test": "true"}

	payload := &hydroproto.UpdateGraphEvent{
		RequestId: "req-123",
		GraphChanges: []*hydroproto.UpdateGraphEvent_GraphChange{
			{RefName: "main", Ecosystem: entities.Ecosystem_ECOSYSTEM_GO, Directory: "."},
		},
	}

	err := publishGraphChanges(ctx, fp, payload, rt.Logger, st, tags, "test.prefix.")
	require.Error(t, err)
	require.Contains(t, err.Error(), "failed to publish UpdateGraphEvent")

	// Verify error counter
	errorFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, metricTags, _ := st.CounterArgsForCall(i)
		if metric == "test.prefix.error" && metricTags["reason"] == "publish_failed" {
			errorFound = true
			break
		}
	}
	require.True(t, errorFound, "should emit error counter with publish_failed reason")
}

// ============================================================================
// recordDependabotEvent tests
// ============================================================================

func TestRecordDependabotEvent_SkipsWhenFlagDisabled(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	dependabotEventSvc := &dependabotmock.MockedDependabotEventService{}

	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return false, nil
			}
			return false, nil
		},
	}

	graphChanges := map[GraphChange]struct{}{
		{Ecosystem: ecosystems.Golang, Path: "go.mod"}: {},
	}

	_, err := recordDependabotEvent(ctx, ff, dependabotEventSvc, rt.Logger, st, 100, Owner{}, interfaces.EventTypePush, "main", "abc123", nil, graphChanges)
	require.NoError(t, err, "should not return error when flag is disabled")

	found := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, metricTags, _ := st.CounterArgsForCall(i)
		if metric == "record_dependabot_event.skipped" && metricTags["reason"] == "feature_flag_disabled" {
			found = true
			break
		}
	}
	require.True(t, found, "should emit skipped counter")
	dependabotEventSvc.AssertNotCalled(t, "RecordDependabotEvent")
}

func TestRecordDependabotEvent_ReturnsErrorOnFlagCheckFailure(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	dependabotEventSvc := &dependabotmock.MockedDependabotEventService{}

	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return false, errors.New("flag check failed")
			}
			return false, nil
		},
	}

	graphChanges := map[GraphChange]struct{}{
		{Ecosystem: ecosystems.Golang, Path: "go.mod"}: {},
	}

	_, err := recordDependabotEvent(ctx, ff, dependabotEventSvc, rt.Logger, st, 100, Owner{}, interfaces.EventTypePush, "main", "abc123", nil, graphChanges)
	require.Error(t, err, "should return error when flag check fails")
	require.Contains(t, err.Error(), "failed to check repository alerting feature flag")
	dependabotEventSvc.AssertNotCalled(t, "RecordDependabotEvent")
}

func TestRecordDependabotEvent_CallsEventServiceWhenFlagEnabled(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	dependabotEventSvc := &dependabotmock.MockedDependabotEventService{}

	pushID := uint64(999)

	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return true, nil
			}
			return false, nil
		},
	}

	graphChanges := map[GraphChange]struct{}{
		{Ecosystem: ecosystems.Golang, Path: "go.mod"}:        {},
		{Ecosystem: ecosystems.NPM, Path: "lib/package.json"}: {},
	}

	dependabotEventSvc.On("RecordDependabotEvent",
		mock.Anything,
		uint64(100),
		interfaces.EventTypePush,
		"refs/heads/main",
		"abc123",
		&pushID,
		mock.MatchedBy(func(entries []interfaces.DependabotRequestedSnapshot) bool {
			if len(entries) != 2 {
				return false
			}
			ecosystemSet := map[string]bool{}
			for _, entry := range entries {
				ecosystemSet[entry.Ecosystem] = true
				if entry.Deadline.IsZero() {
					return false
				}
			}
			return ecosystemSet["golang"] && ecosystemSet["npm"]
		}),
	).Return(uint64(42), nil)

	_, err := recordDependabotEvent(ctx, ff, dependabotEventSvc, rt.Logger, st, 100, Owner{}, interfaces.EventTypePush, "refs/heads/main", "abc123", &pushID, graphChanges)
	require.NoError(t, err, "should not return error when recording succeeds")

	dependabotEventSvc.AssertExpectations(t)
}

func TestRecordDependabotEvent_ReturnsEventServiceError(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	dependabotEventSvc := &dependabotmock.MockedDependabotEventService{}

	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return true, nil
			}
			return false, nil
		},
	}

	graphChanges := map[GraphChange]struct{}{
		{Ecosystem: ecosystems.Golang, Path: "go.mod"}: {},
	}

	dependabotEventSvc.On("RecordDependabotEvent",
		mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything,
	).Return(uint64(0), errors.New("database write failed"))

	_, err := recordDependabotEvent(ctx, ff, dependabotEventSvc, rt.Logger, st, 100, Owner{}, interfaces.EventTypePush, "main", "abc123", nil, graphChanges)
	require.Error(t, err, "should return error from event service")
	require.Contains(t, err.Error(), "database write failed")
}

// ============================================================================
// publishDependabotEventProcessed / publishDependabotEventFallback tests
// ============================================================================

func TestPublishDependabotEventProcessed_EmitsWhenFlagEnabled(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	fp := &mockHydroPublisher{}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return true, nil
			}
			return false, nil
		},
	}

	err := publishDependabotEventProcessed(ctx, fp, ff, rt.Logger, st, dependabotEventProcessedMsg{
		RepoID:    100,
		Owner:     Owner{ID: 200, DecodedType: OwnerTypeUser},
		EventID:   42,
		EventType: hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH,
		Ref:       "main",
		SHA:       "abc123",
		RequestID: "req-1",
	})
	require.NoError(t, err)

	require.Equal(t, 1, fp.PublishCallCount(), "should publish DependabotEventProcessed")
	msg := fp.PublishedMessages()[0].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, "req-1", msg.GetRequestId())
	require.Equal(t, int64(100), msg.GetRepositoryId())
	require.Equal(t, int64(42), msg.GetEventId())
	require.Equal(t, hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH, msg.GetEventType())
	require.Equal(t, "main", msg.GetRef())
	require.Equal(t, "abc123", msg.GetSha())
	require.Equal(t, int64(0), msg.GetPushId(), "push_id should be 0 when nil")
	require.NotNil(t, msg.GetProcessedAt())
}

func TestPublishDependabotEventProcessed_SkipsWhenFlagDisabled(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	fp := &mockHydroPublisher{}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			return false, nil
		},
	}

	err := publishDependabotEventProcessed(ctx, fp, ff, rt.Logger, st, dependabotEventProcessedMsg{
		RepoID:    100,
		EventType: hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH,
		Ref:       "main",
		SHA:       "abc123",
		RequestID: "req-1",
	})
	require.NoError(t, err)

	require.Equal(t, 0, fp.PublishCallCount(), "should not publish when flag disabled")
}

func TestPublishDependabotEventFallback_EmitsMinimalMessage(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	fp := &mockHydroPublisher{}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return true, nil
			}
			return false, nil
		},
	}

	err := publishDependabotEventFallback(ctx, fp, ff, rt.Logger, st, 100, Owner{}, hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH, "req-1", "refs/heads/main", "abc123")
	require.NoError(t, err)

	require.Equal(t, 1, fp.PublishCallCount())
	msg := fp.PublishedMessages()[0].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, "req-1", msg.GetRequestId())
	require.Equal(t, int64(100), msg.GetRepositoryId())
	require.Equal(t, int64(0), msg.GetEventId(), "event_id should be 0")
	require.Equal(t, hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH, msg.GetEventType(), "event_type should be set")
	require.Equal(t, "refs/heads/main", msg.GetRef(), "ref should be set")
	require.Equal(t, "abc123", msg.GetSha(), "sha should be set")
	require.Nil(t, msg.GetProcessedAt(), "processed_at should be nil")
}

func TestPublishDependabotEventProcessed_SetsPushID(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	fp := &mockHydroPublisher{}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return true, nil
			}
			return false, nil
		},
	}

	pushID := uint64(999)
	err := publishDependabotEventProcessed(ctx, fp, ff, rt.Logger, st, dependabotEventProcessedMsg{
		RepoID:    100,
		EventID:   42,
		EventType: hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH,
		Ref:       "main",
		SHA:       "abc123",
		PushID:    &pushID,
		RequestID: "req-1",
	})
	require.NoError(t, err)

	require.Equal(t, 1, fp.PublishCallCount())
	msg := fp.PublishedMessages()[0].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, int64(999), msg.GetPushId())
}

func TestPublishDependabotEventProcessed_PublishError(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	st := &mockStatsClient{}
	fp := &mockHydroPublisher{publishErr: errors.New("kafka unavailable")}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return true, nil
			}
			return false, nil
		},
	}

	// Should not panic; errors are returned to the caller
	err := publishDependabotEventProcessed(ctx, fp, ff, rt.Logger, st, dependabotEventProcessedMsg{
		RepoID:    100,
		EventID:   1,
		EventType: hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH,
		Ref:       "main",
		SHA:       "abc123",
		RequestID: "req-1",
	})
	require.Error(t, err)

	errorFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "dependabot_event_processed.error" && tags["reason"] == "publish_failed" {
			errorFound = true
			break
		}
	}
	require.True(t, errorFound, "should emit error metric on publish failure")
}

// ============================================================================
// End-to-end handler tests for DependabotEventProcessed emission
// ============================================================================

func TestHandleDependabotSnapshotPostReceive_EmitsDependabotEventProcessedNoChanges(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			// No manifest files in changeset
			return []*types.DiffEntry{
				{
					DestinationOid: types.NewObjectID("12393b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`src/main.go`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
			}, nil
		},
	}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			switch feature {
			case ParseOnceGoFeatureFlag, RepositoryAlertingFeatureFlag:
				return true, nil
			default:
				return false, nil
			}
		},
		isFeatureFlagEnabledForUserFn: func(ctx context.Context, feature string, userID uint64) (bool, error) {
			return false, nil
		},
		isFeatureFlagEnabledForOrgFn: func(ctx context.Context, feature string, orgID uint64) (bool, error) {
			return false, nil
		},
	}
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err)

	// Only DependabotEventProcessed should be published (no UpdateGraphEvent since no changes)
	require.Equal(t, 1, fp.PublishCallCount(), "should publish DependabotEventProcessed only")
	processed := fp.PublishedMessages()[0].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, "request-id-123", processed.GetRequestId())
	require.Equal(t, int64(100), processed.GetRepositoryId())
	require.Equal(t, int64(0), processed.GetEventId(), "event_id should be 0 when no changes")
	require.Equal(t, hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH, processed.GetEventType(), "event_type should be set")
	require.Equal(t, "valid-oid-2", processed.GetSha(), "sha should be set from afterOid")
	require.Equal(t, "main", processed.GetRef(), "ref should be set from job")
}

func TestHandleDependabotSnapshotPostReceive_EmitsDependabotEventProcessedNoEcosystems(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return true, nil
			}
			// All ecosystem flags disabled
			return false, nil
		},
		isFeatureFlagEnabledForUserFn: func(ctx context.Context, feature string, userID uint64) (bool, error) {
			return false, nil
		},
		isFeatureFlagEnabledForOrgFn: func(ctx context.Context, feature string, orgID uint64) (bool, error) {
			return false, nil
		},
	}
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err)

	// DependabotEventProcessed should still be published even with no ecosystems enabled
	require.Equal(t, 1, fp.PublishCallCount(), "should publish DependabotEventProcessed even with no ecosystems")
	processed := fp.PublishedMessages()[0].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, "request-id-123", processed.GetRequestId())
	require.Equal(t, int64(100), processed.GetRepositoryId())
	require.Equal(t, int64(0), processed.GetEventId(), "event_id should be 0")
	require.Equal(t, hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH, processed.GetEventType(), "event_type should be set")
	require.Equal(t, "main", processed.GetRef(), "ref should be set from job")
	require.Equal(t, "valid-oid-2", processed.GetSha(), "sha should be set from afterOid")
}

func TestHandleDependabotSnapshotPostReceive_NoDependabotEventProcessedWhenAlertingDisabled(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		compareTreesFn: func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
			return []*types.DiffEntry{
				{
					DestinationOid: types.NewObjectID("12393b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.mod`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
				{
					DestinationOid: types.NewObjectID("asd93b9467ddfd3b20baaaa38934cda613ce2de0"),
					Destination:    types.NewPath([]byte(`go.sum`)),
					Status:         types.DiffEntry_STATUS_ADDITION,
				},
			}, nil
		},
	}
	ff := newMockFeaturesClientWithParseOnceEnabled() // alerting flag NOT enabled
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidJob()

	err := HandleDependabotSnapshotPostReceiveJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err)

	// Only UpdateGraphEvent should be published (not DependabotEventProcessed)
	require.Equal(t, 1, fp.PublishCallCount(), "should only publish UpdateGraphEvent")
	_, ok := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)
	require.True(t, ok, "only message should be UpdateGraphEvent")
}
