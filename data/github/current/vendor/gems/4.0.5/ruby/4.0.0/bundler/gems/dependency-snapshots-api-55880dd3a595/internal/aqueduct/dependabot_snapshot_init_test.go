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
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func featureFlagEnabledClient() *mockFeaturesClient {
	return &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			switch feature {
			case ParseOnceGoFeatureFlag, ParseOnceNPMFeatureFlag:
				return true, nil
			default:
				return false, nil
			}
		},
	}
}

func newValidInitJob() *jobsproto.DependabotSnapshotInitJob {
	return &jobsproto.DependabotSnapshotInitJob{
		RequestId: "request-id-123",
		EventId:   "event-id-123",
		Repository: &jobsproto.DependabotSnapshotInitJob_Repository{
			Id:                  100,
			GlobalRelayId:       "global-relay-id-100",
			Name:                "test-repo",
			Visibility:          jobsproto.DependabotSnapshotInitJob_Repository_VISIBILITY_PUBLIC,
			ParentId:            400,
			DefaultBranch:       "main",
			PrimaryLanguageName: "Go",
		},
		Owner: &jobsproto.DependabotSnapshotInitJob_User{
			Id:            200,
			GlobalRelayId: "global-relay-id-200",
			Login:         "test-user",
			Type:          jobsproto.DependabotSnapshotInitJob_User_TYPE_USER,
		},
		Ref:             "refs/heads/main",
		IsDefaultBranch: true,
		PushedAt:        timestamppb.New(time.Now().Add(-time.Minute)),
		IngestedAt:      timestamppb.New(time.Now()),
		TriggeredBy:     jobsproto.DependabotSnapshotInitJob_TRIGGERED_BY_PUSH,
	}
}

// spokesRepoContents returns a sample tree with Go and NPM manifest files
func spokesRepoContents() []*types.TreeEntry {
	return []*types.TreeEntry{
		// Root level go.mod
		{
			Path:   types.NewPath([]byte("go.mod")),
			Object: types.NewBlobObject(types.NewObjectID("abc123")),
		},
		// Root level go.sum
		{
			Path:   types.NewPath([]byte("go.sum")),
			Object: types.NewBlobObject(types.NewObjectID("def456")),
		},
		// Nested go.mod in bar directory
		{
			Path:   types.NewPath([]byte("bar/go.mod")),
			Object: types.NewBlobObject(types.NewObjectID("ghi789")),
		},
		// NPM package.json in lib directory
		{
			Path:   types.NewPath([]byte("lib/package.json")),
			Object: types.NewBlobObject(types.NewObjectID("jkl012")),
		},
		// NPM package-lock.json in lib directory
		{
			Path:   types.NewPath([]byte("lib/package-lock.json")),
			Object: types.NewBlobObject(types.NewObjectID("mno345")),
		},
		// Non-manifest file (should be ignored)
		{
			Path:   types.NewPath([]byte("src/main.go")),
			Object: types.NewBlobObject(types.NewObjectID("pqr678")),
		},
		// Directory entry (should be ignored)
		{
			Path:   types.NewPath([]byte("src")),
			Object: types.NewTreeObject(types.NewObjectID("stu901")),
		},
	}
}

// ============================================================================
// Tests
// ============================================================================

func TestHandleDependabotSnapshotInitJob_SkipsInvalidRepos(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()
	job.Repository.Id = 0 // Invalid repo ID

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for invalid repo")

	// Verify skip metric was emitted
	require.GreaterOrEqual(t, st.CounterCallCount(), 1)
	metric, tags, count := st.CounterArgsForCall(st.CounterCallCount() - 1)
	require.Equal(t, "aqueduct.handler.dependabot_snapshot_init.skipped", metric)
	require.Equal(t, "invalid_repo", tags["reason"])
	require.Equal(t, int64(1), count)

	// Verify no hydro publishing happened
	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotInitJob_SkipsNonDefaultBranches(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()
	job.IsDefaultBranch = false

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for non-default branch")

	// Verify skip metric was emitted
	require.GreaterOrEqual(t, st.CounterCallCount(), 1)
	metric, tags, count := st.CounterArgsForCall(st.CounterCallCount() - 1)
	require.Equal(t, "aqueduct.handler.dependabot_snapshot_init.skipped", metric)
	require.Equal(t, "non_default_branch", tags["reason"])
	require.Equal(t, int64(1), count)

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotInitJob_EmptyRepo(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			// Spokes returns 404 when the repository is empty
			return nil, twirp.NewError(twirp.NotFound, "not found")
		},
	}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error for empty repo")

	// Verify skip metric was emitted
	skipFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_init.skipped" && tags["reason"] == "empty_repo" {
			skipFound = true
			break
		}
	}
	require.True(t, skipFound, "should emit skip metric for empty repo")

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotInitJob_SpokesError(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			// Non-404 error from Spokes
			return nil, errors.New("spokes unavailable")
		},
	}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.Error(t, err, "should return error when Spokes fails")
	require.Contains(t, err.Error(), "failed to obtain HEAD commit for repo")

	// Verify error metric was emitted
	found := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_init.error" && tags["reason"] == "resolve_head" {
			found = true
			break
		}
	}
	require.True(t, found, "should emit error metric for resolve_head failure")

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotInitJob_EnumeratorError(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			return nil, twirp.NewError(twirp.Internal, "internal error")
		},
	}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.Error(t, err, "should return error when enumerator fails")
	require.Contains(t, err.Error(), "failed to enumerate and classify repository content from init push")

	// Verify error metric was emitted
	found := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_init.error" && tags["reason"] == "enumerator" {
			found = true
			break
		}
	}
	require.True(t, found, "should emit error metric for enumerator failure")

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotInitJob_NoManifestChanges(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntime(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			// Return only non-manifest files
			return []*types.TreeEntry{
				{
					Path:   types.NewPath([]byte("src/main.go")),
					Object: types.NewBlobObject(types.NewObjectID("pqr678")),
				},
				{
					Path:   types.NewPath([]byte("README.md")),
					Object: types.NewBlobObject(types.NewObjectID("xyz123")),
				},
			}, nil
		},
	}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error when no manifest changes")

	// Verify skip metric was emitted
	skipFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_init.skipped" && tags["reason"] == "no_manifest_changes" {
			skipFound = true
			break
		}
	}
	require.True(t, skipFound, "should emit skip metric for no manifest changes")

	require.Equal(t, 0, fp.PublishCallCount())
}

func TestHandleDependabotSnapshotInitJob_Success_GoManifests(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			return spokesRepoContents(), nil
		},
	}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error on success")

	// Verify publishing happened
	require.Equal(t, 1, fp.PublishCallCount(), "should publish UpdateGraphEvent")
	published := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)
	require.Equal(t, "request-id-123", published.GetRequestId())
	require.Equal(t, uint32(100), published.GetRepository().GetId())
	require.Equal(t, uint32(200), published.GetOwner().GetId())
	// Feature flag enables Parse Once ecosystems, so NPM manifest is counted too
	require.Len(t, published.GetGraphChanges(), 3, "should have Go + NPM graph changes")
	require.NotNil(t, published.GetRequestedAt(), "should set requested_at")

	// Verify success metrics
	successFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, _, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_init.success" {
			successFound = true
			break
		}
	}
	require.True(t, successFound, "should emit success counter")
}

func TestHandleDependabotSnapshotInitJob_RecordsEventWhenAlertingFlagEnabled(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			return spokesRepoContents(), nil
		},
	}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			switch feature {
			case ParseOnceGoFeatureFlag, ParseOnceNPMFeatureFlag, RepositoryAlertingFeatureFlag:
				return true, nil
			default:
				return false, nil
			}
		},
	}
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}
	es := &dependabotmock.MockedDependabotEventService{}
	es.On("RecordDependabotEvent",
		mock.Anything,
		uint64(100),
		interfaces.EventTypeInit,
		"refs/heads/main",
		"abc123",
		(*uint64)(nil),
		mock.MatchedBy(func(entries []interfaces.DependabotRequestedSnapshot) bool {
			if len(entries) != 3 {
				return false
			}
			ecosystems := map[string]int{}
			for _, e := range entries {
				ecosystems[e.Ecosystem]++
			}
			return ecosystems["golang"] == 2 && ecosystems["npm"] == 1
		}),
	).Return(uint64(1), nil)

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, es, job)
	require.NoError(t, err)

	// Verify hydro publishing happened: UpdateGraphEvent + DependabotEventProcessed
	require.Equal(t, 2, fp.PublishCallCount(), "should publish UpdateGraphEvent and DependabotEventProcessed")

	// Verify DependabotEventProcessed
	processed := fp.PublishedMessages()[1].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, int64(1), processed.GetEventId(), "DependabotEventProcessed should include event_id")
	require.Equal(t, hydroproto.DependabotEventProcessed_EVENT_TYPE_INIT, processed.GetEventType())
	require.Equal(t, int64(100), processed.GetRepositoryId())
	require.Equal(t, "refs/heads/main", processed.GetRef())
	require.Equal(t, "abc123", processed.GetSha())
	require.Equal(t, "request-id-123", processed.GetRequestId())
	require.Equal(t, int64(0), processed.GetPushId(), "push_id should be 0 for init")
	require.NotNil(t, processed.GetProcessedAt())

	// Verify event was recorded with expected arguments
	es.AssertExpectations(t)
}

func TestHandleDependabotSnapshotInitJob_Success_WithNPMFeatureFlag(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			return spokesRepoContents(), nil
		},
	}
	// Enable NPM via feature flag
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			switch feature {
			case ParseOnceGoFeatureFlag, ParseOnceNPMFeatureFlag:
				return true, nil
			default:
				return false, nil
			}
		},
	}
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error on success")

	// Verify publishing happened
	require.Equal(t, 1, fp.PublishCallCount(), "should publish UpdateGraphEvent")
	published := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)
	// We should have 2 Go manifests + 1 NPM manifest (lib directory with package.json and package-lock.json grouped together)
	require.Len(t, published.GetGraphChanges(), 3, "should have Go + NPM graph changes")

	// Verify success metrics
	successFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, _, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_init.success" {
			successFound = true
			break
		}
	}
	require.True(t, successFound, "should emit success counter")
}

func TestHandleDependabotSnapshotInitJob_Success_PythonManifests(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			return []*types.TreeEntry{
				// Standard requirements.txt at root (exact match)
				{
					Path:   types.NewPath([]byte("requirements.txt")),
					Object: types.NewBlobObject(types.NewObjectID("py001")),
				},
				// Regex variant: dot-separated (REQUIREMENTS_TXT_PATTERN)
				{
					Path:   types.NewPath([]byte("requirements.prod.txt")),
					Object: types.NewBlobObject(types.NewObjectID("py002")),
				},
				// Regex variant in subdirectory (REQUIRE_TXT_PATTERN)
				{
					Path:   types.NewPath([]byte("backend/require-dev.txt")),
					Object: types.NewBlobObject(types.NewObjectID("py003")),
				},
				// Non-manifest file (should be ignored)
				{
					Path:   types.NewPath([]byte("src/main.py")),
					Object: types.NewBlobObject(types.NewObjectID("py999")),
				},
			}, nil
		},
	}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == ParseOncePythonFeatureFlag {
				return true, nil
			}
			return false, nil
		},
	}
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error on success")

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
	require.Equal(t, "refs/heads/main", rootChange.GetRefName())
	require.Equal(t, entities.Ecosystem_ECOSYSTEM_PYPI, rootChange.GetEcosystem())

	backendChange, ok := changesByDir["backend"]
	require.True(t, ok, "should have a graph change for the backend directory")
	require.Equal(t, "refs/heads/main", backendChange.GetRefName())
	require.Equal(t, entities.Ecosystem_ECOSYSTEM_PYPI, backendChange.GetEcosystem())
}

func TestHandleDependabotSnapshotInitJob_PublishFailure(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			return spokesRepoContents(), nil
		},
	}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{publishErr: errors.New("kafka unavailable")}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.Error(t, err, "should return error when publish fails")
	require.Contains(t, err.Error(), "failed to publish graph changes")

	// Verify error metric was emitted
	errorFound := false
	for i := 0; i < st.CounterCallCount(); i++ {
		metric, tags, _ := st.CounterArgsForCall(i)
		if metric == "aqueduct.handler.dependabot_snapshot_init.error" && tags["reason"] == "publish_failed" {
			errorFound = true
			break
		}
	}
	require.True(t, errorFound, "should emit error metric for publish failure")
}

func TestHandleDependabotSnapshotInitJob_LatencyMetrics(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			return spokesRepoContents(), nil
		},
	}
	ff := featureFlagEnabledClient()
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	pushedAt := time.Now().Add(-5 * time.Minute)
	ingestedAt := time.Now().Add(-4 * time.Minute)

	job := newValidInitJob()
	job.PushedAt = timestamppb.New(pushedAt)
	job.IngestedAt = timestamppb.New(ingestedAt)

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err, "should not return error on success")

	// Verify latency metrics were emitted
	require.GreaterOrEqual(t, st.DistributionMsCallCount(), 1, "should emit at least one latency metric")
}

func TestExtractInitJobData(t *testing.T) {
	job := &jobsproto.DependabotSnapshotInitJob{
		RequestId: "req-123",
		EventId:   "evt-456",
		Repository: &jobsproto.DependabotSnapshotInitJob_Repository{
			Id:                  100,
			GlobalRelayId:       "gri-100",
			Name:                "test-repo",
			Visibility:          jobsproto.DependabotSnapshotInitJob_Repository_VISIBILITY_PRIVATE,
			ParentId:            50,
			DefaultBranch:       "main",
			PrimaryLanguageName: "Go",
		},
		Owner: &jobsproto.DependabotSnapshotInitJob_User{
			Id:            200,
			GlobalRelayId: "gri-200",
			Login:         "test-owner",
			Type:          jobsproto.DependabotSnapshotInitJob_User_TYPE_ORGANIZATION,
		},
		Ref:             "refs/heads/main",
		IsDefaultBranch: true,
		TriggeredBy:     jobsproto.DependabotSnapshotInitJob_TRIGGERED_BY_ENROLLMENT,
	}

	data := extractInitJobData(job)

	require.Equal(t, "req-123", data.RequestID)
	require.Equal(t, "evt-456", data.EventID)
	require.Equal(t, uint64(100), data.Repository.ID)
	require.Equal(t, "gri-100", data.Repository.GlobalRelayID)
	require.Equal(t, "test-repo", data.Repository.Name)
	require.Equal(t, int32(jobsproto.DependabotSnapshotInitJob_Repository_VISIBILITY_PRIVATE), data.Repository.Visibility)
	require.Equal(t, uint32(50), data.Repository.ParentID)
	require.Equal(t, "main", data.Repository.DefaultBranch)
	require.Equal(t, "Go", data.Repository.PrimaryLanguage)
	require.Equal(t, uint64(200), data.Owner.ID)
	require.Equal(t, "gri-200", data.Owner.GlobalRelayID)
	require.Equal(t, "test-owner", data.Owner.Login)
	require.Equal(t, OwnerTypeOrganization, data.Owner.DecodedType)
	require.Equal(t, "refs/heads/main", data.Ref)
	require.True(t, data.IsDefaultBranch)
	require.Equal(t, "TRIGGERED_BY_ENROLLMENT", data.TriggeredBy)
}

func TestExtractOwnerFromInit_UserTypes(t *testing.T) {
	tests := []struct {
		name         string
		userType     jobsproto.DependabotSnapshotInitJob_User_Type
		expectedType OwnerType
	}{
		{
			name:         "User type",
			userType:     jobsproto.DependabotSnapshotInitJob_User_TYPE_USER,
			expectedType: OwnerTypeUser,
		},
		{
			name:         "Organization type",
			userType:     jobsproto.DependabotSnapshotInitJob_User_TYPE_ORGANIZATION,
			expectedType: OwnerTypeOrganization,
		},
		{
			name:         "Unknown type",
			userType:     jobsproto.DependabotSnapshotInitJob_User_TYPE_UNKNOWN,
			expectedType: OwnerTypeUnknown,
		},
		{
			name:         "Bot type (maps to unknown)",
			userType:     jobsproto.DependabotSnapshotInitJob_User_TYPE_BOT,
			expectedType: OwnerTypeUnknown,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			user := &jobsproto.DependabotSnapshotInitJob_User{
				Id:    100,
				Login: "test",
				Type:  tt.userType,
			}
			owner := extractOwnerFromInit(user)
			require.Equal(t, tt.expectedType, owner.DecodedType)
		})
	}
}

func TestCollectGraphChanges_GoEcosystem(t *testing.T) {
	// Create a RelatedManifests struct with Go manifests
	rm := createTestRelatedManifests()

	// With only Go enabled (default)
	ecos := []ecosystems.Ecosystem{ecosystems.Golang}
	changes := collectGraphChanges(rm, ecos)

	// Should have 2 Go changes (root and bar directories)
	require.Len(t, changes, 2)
}

func TestCollectGraphChanges_GoAndNPMEcosystems(t *testing.T) {
	// Create a RelatedManifests struct with Go and NPM manifests
	rm := createTestRelatedManifests()

	// With Go and NPM enabled
	ecos := []ecosystems.Ecosystem{ecosystems.Golang, ecosystems.NPM}
	changes := collectGraphChanges(rm, ecos)

	// Should have 2 Go changes + 1 NPM change
	require.Len(t, changes, 3)
}

// Helper function to create test RelatedManifests
func createTestRelatedManifests() manifests.RelatedManifests {
	return manifests.RelatedManifests{
		ToUpdate: [][]manifests.ManifestChange{
			// Root Go project (go.mod and go.sum)
			{
				{
					FileInfo: manifests.Info{
						Path:      ".",
						Name:      "go.mod",
						Ecosystem: ecosystems.Golang,
					},
					BlobOID: "abc123",
					Type:    manifests.ChangeAdded,
				},
				{
					FileInfo: manifests.Info{
						Path:      ".",
						Name:      "go.sum",
						Ecosystem: ecosystems.Golang,
					},
					BlobOID: "def456",
					Type:    manifests.ChangeAdded,
				},
			},
			// Nested Go project in bar
			{
				{
					FileInfo: manifests.Info{
						Path:      "bar",
						Name:      "go.mod",
						Ecosystem: ecosystems.Golang,
					},
					BlobOID: "ghi789",
					Type:    manifests.ChangeAdded,
				},
			},
			// NPM project in lib
			{
				{
					FileInfo: manifests.Info{
						Path:      "lib",
						Name:      "package.json",
						Ecosystem: ecosystems.NPM,
					},
					BlobOID: "jkl012",
					Type:    manifests.ChangeAdded,
				},
				{
					FileInfo: manifests.Info{
						Path:      "lib",
						Name:      "package-lock.json",
						Ecosystem: ecosystems.NPM,
					},
					BlobOID: "mno345",
					Type:    manifests.ChangeAdded,
				},
			},
		},
		ToDelete: []manifests.ManifestChange{},
	}
}

// ============================================================================
// DependabotEventProcessed emission tests
// ============================================================================

func TestHandleDependabotSnapshotInitJob_EmitsDependabotEventProcessedNoChanges(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			// No manifest files
			return []*types.TreeEntry{
				{
					Path:   types.NewPath([]byte("src/main.go")),
					Object: types.NewBlobObject(types.NewObjectID("abc123")),
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
	}
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err)

	// Only DependabotEventProcessed should be published (no UpdateGraphEvent since no changes)
	require.Equal(t, 1, fp.PublishCallCount(), "should publish DependabotEventProcessed only")
	processed := fp.PublishedMessages()[0].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, "request-id-123", processed.GetRequestId())
	require.Equal(t, int64(100), processed.GetRepositoryId())
	require.Equal(t, int64(0), processed.GetEventId(), "event_id should be 0 when no changes")
	require.Equal(t, hydroproto.DependabotEventProcessed_EVENT_TYPE_INIT, processed.GetEventType(), "event_type should be set")
	require.Equal(t, "abc123", processed.GetSha(), "sha should be set from resolved HEAD")
	require.Equal(t, "refs/heads/main", processed.GetRef(), "ref should be set from job")
}

func TestHandleDependabotSnapshotInitJob_EmitsDependabotEventProcessedNoEcosystems(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
	}
	ff := &mockFeaturesClient{
		isFeatureFlagEnabledForRepoFn: func(ctx context.Context, feature string, repoID uint64) (bool, error) {
			if feature == RepositoryAlertingFeatureFlag {
				return true, nil
			}
			// All ecosystem flags disabled
			return false, nil
		},
	}
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err)

	// DependabotEventProcessed should still be published even with no ecosystems enabled
	require.Equal(t, 1, fp.PublishCallCount(), "should publish DependabotEventProcessed even with no ecosystems")
	processed := fp.PublishedMessages()[0].(*hydroproto.DependabotEventProcessed)
	require.Equal(t, "request-id-123", processed.GetRequestId())
	require.Equal(t, int64(100), processed.GetRepositoryId())
	require.Equal(t, int64(0), processed.GetEventId(), "event_id should be 0")
	require.Equal(t, hydroproto.DependabotEventProcessed_EVENT_TYPE_INIT, processed.GetEventType(), "event_type should be set")
	require.Equal(t, "refs/heads/main", processed.GetRef(), "ref should be set from job")
	require.Equal(t, "abc123", processed.GetSha(), "sha should be set from resolved HEAD")
}

func TestHandleDependabotSnapshotInitJob_NoDependabotEventProcessedWhenAlertingDisabled(t *testing.T) {
	ctx := context.Background()
	rt := newTestRuntimeWithConfig(t)
	sc := &mockGitClient{
		resolveRefFn: func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
			return types.NewObjectID("abc123"), nil
		},
		listTreeByCommitFn: func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
			return spokesRepoContents(), nil
		},
	}
	ff := featureFlagEnabledClient() // alerting flag NOT enabled
	fp := &mockHydroPublisher{}
	st := &mockStatsClient{}

	job := newValidInitJob()

	err := HandleDependabotSnapshotInitJob(ctx, rt.Config, rt.Logger, st, rt.Tracer, sc, fp, ff, &dependabotmock.MockedDependabotEventService{}, job)
	require.NoError(t, err)

	// Only UpdateGraphEvent should be published (not DependabotEventProcessed)
	require.Equal(t, 1, fp.PublishCallCount(), "should only publish UpdateGraphEvent")
	_, ok := fp.PublishedMessages()[0].(*hydroproto.UpdateGraphEvent)
	require.True(t, ok, "only message should be UpdateGraphEvent")
}
