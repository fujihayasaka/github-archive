package aqueduct

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/github-telemetry-go/trace"
	stats "github.com/github/go-stats"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

// ============================================================================
// Mock implementations for testing
// ============================================================================

// mockFeaturesClient implements features.Client for testing
type mockFeaturesClient struct {
	isFeatureFlagEnabledForRepoFn func(ctx context.Context, feature string, repoID uint64) (bool, error)
	isFeatureFlagEnabledForUserFn func(ctx context.Context, feature string, userID uint64) (bool, error)
	isFeatureFlagEnabledForOrgFn  func(ctx context.Context, feature string, orgID uint64) (bool, error)
}

func (m *mockFeaturesClient) IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error) {
	return nil, nil
}

func (m *mockFeaturesClient) IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repoID uint64) (bool, error) {
	if m.isFeatureFlagEnabledForRepoFn != nil {
		return m.isFeatureFlagEnabledForRepoFn(ctx, feature, repoID)
	}
	return false, nil
}

func (m *mockFeaturesClient) IsFeatureFlagEnabledForUser(ctx context.Context, feature string, userID uint64) (bool, error) {
	if m.isFeatureFlagEnabledForUserFn != nil {
		return m.isFeatureFlagEnabledForUserFn(ctx, feature, userID)
	}
	return false, nil
}

func (m *mockFeaturesClient) IsFeatureFlagEnabledForOrganization(ctx context.Context, feature string, orgID uint64) (bool, error) {
	if m.isFeatureFlagEnabledForOrgFn != nil {
		return m.isFeatureFlagEnabledForOrgFn(ctx, feature, orgID)
	}
	return false, nil
}

var _ features.Client = (*mockFeaturesClient)(nil)

// mockGitClient implements gitaccess.Client for testing with configurable
// function hooks. Any hook left nil returns the zero value.
type mockGitClient struct {
	compareTreesFn     func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error)
	resolveRefFn       func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error)
	listTreeByCommitFn func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error)
}

func (m *mockGitClient) GetDefaultBranch(ctx context.Context, repoID uint64) (string, error) {
	return "main", nil
}

func (m *mockGitClient) GetHEADCommit(ctx context.Context, repoID uint64, optionalBranchName ...string) (gitaccess.SHA, error) {
	return "", nil
}

func (m *mockGitClient) GetRecentCommits(ctx context.Context, repoID uint64, numCommits uint, optionalBranchName ...string) ([]gitaccess.SHA, error) {
	return nil, nil
}

func (m *mockGitClient) ListTreeByRef(ctx context.Context, repoID uint64, ref []byte) ([]*types.TreeEntry, error) {
	return nil, nil
}

func (m *mockGitClient) ListTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	if m.listTreeByCommitFn != nil {
		return m.listTreeByCommitFn(ctx, repoID, commitOID)
	}
	return nil, nil
}

func (m *mockGitClient) ListRootTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	return nil, nil
}

func (m *mockGitClient) CompareTrees(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
	if m.compareTreesFn != nil {
		return m.compareTreesFn(ctx, repoID, beforeCommit, afterCommit)
	}
	return nil, nil
}

func (m *mockGitClient) GetBlobByOID(ctx context.Context, repoID uint64, blobOID string) ([]byte, uint64, error) {
	return nil, 0, nil
}

func (m *mockGitClient) GetBlobByPath(ctx context.Context, repoID uint64, ref []byte, path string) ([]byte, uint64, error) {
	return nil, 0, nil
}

func (m *mockGitClient) GetBlobByPathAndCommit(ctx context.Context, repoID uint64, commit string, path string) ([]byte, uint64, error) {
	return nil, 0, nil
}

func (m *mockGitClient) ResolveRef(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
	if m.resolveRefFn != nil {
		return m.resolveRefFn(ctx, repoID, ref)
	}
	return nil, nil
}

var _ gitaccess.Client = (*mockGitClient)(nil)

// mockHydroPublisher implements hydro.Publisher for testing
type mockHydroPublisher struct {
	publishCallCount  int
	publishedMessages []proto.Message
	publishErr        error
	mutex             sync.Mutex
}

func (m *mockHydroPublisher) Publish(ctx context.Context, msg proto.Message) error {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.publishCallCount++
	m.publishedMessages = append(m.publishedMessages, msg)
	return m.publishErr
}

func (m *mockHydroPublisher) Close() error {
	return nil
}

func (m *mockHydroPublisher) PublishCallCount() int {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	return m.publishCallCount
}

func (m *mockHydroPublisher) PublishedMessages() []proto.Message {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	return m.publishedMessages
}

var _ hydro.Publisher = (*mockHydroPublisher)(nil)

// mockStatsClient implements stats.Client for testing with call tracking
type mockStatsClient struct {
	counterCalls        []counterCall
	distributionCalls   []distributionCall
	distributionMsCalls []distributionMsCall
	mutex               sync.Mutex
}

type counterCall struct {
	metric string
	tags   stats.Tags
	count  int64
}

type distributionCall struct {
	metric string
	tags   stats.Tags
	value  float64
}

type distributionMsCall struct {
	metric   string
	tags     stats.Tags
	duration time.Duration
}

func (m *mockStatsClient) Counter(metric string, tags stats.Tags, count int64) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.counterCalls = append(m.counterCalls, counterCall{metric, tags, count})
}

func (m *mockStatsClient) CounterCallCount() int {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	return len(m.counterCalls)
}

func (m *mockStatsClient) CounterArgsForCall(i int) (string, stats.Tags, int64) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	c := m.counterCalls[i]
	return c.metric, c.tags, c.count
}

func (m *mockStatsClient) DistributionMs(metric string, tags stats.Tags, duration time.Duration) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.distributionMsCalls = append(m.distributionMsCalls, distributionMsCall{metric, tags, duration})
}

func (m *mockStatsClient) DistributionMsCallCount() int {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	return len(m.distributionMsCalls)
}

func (m *mockStatsClient) DistributionCallCount() int {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	return len(m.distributionCalls)
}

func (m *mockStatsClient) DistributionArgsForCall(i int) (string, stats.Tags, float64) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	c := m.distributionCalls[i]
	return c.metric, c.tags, c.value
}

// Implement remaining stats.Client methods as no-ops
func (m *mockStatsClient) ClearTags() stats.Client { return m }
func (m *mockStatsClient) Distribution(metric string, tags stats.Tags, value float64) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.distributionCalls = append(m.distributionCalls, distributionCall{metric, tags, value})
}
func (m *mockStatsClient) Event(string, string, stats.Tags)                        {}
func (m *mockStatsClient) Gauge(string, stats.Tags, int64)                         {}
func (m *mockStatsClient) Histogram(string, stats.Tags, int64)                     {}
func (m *mockStatsClient) Increment(string, stats.Tags)                            {}
func (m *mockStatsClient) Report(stats.Type, string, float64, stats.Tags, float32) {}
func (m *mockStatsClient) Run()                                                    {}
func (m *mockStatsClient) Set(string, stats.Tags, string)                          {}
func (m *mockStatsClient) SetPrefix(string) stats.Client                           { return m }
func (m *mockStatsClient) Start()                                                  {}
func (m *mockStatsClient) Stop()                                                   {}
func (m *mockStatsClient) Timing(string, stats.Tags, time.Duration)                {}
func (m *mockStatsClient) WithTags(stats.Tags) stats.Client                        { return m }

var _ stats.Client = (*mockStatsClient)(nil)

// ============================================================================
// Test helpers
// ============================================================================

type testRuntime struct {
	Config *config.Config
	Tracer *trace.Tracer
	Logger log.Logger
}

func newTestRuntime(t *testing.T) testRuntime {
	t.Helper()
	telem, err := telemetry.NewFromEnv()
	require.NoError(t, err)
	cfg := &config.Config{}
	return testRuntime{
		Config: cfg,
		Tracer: telem.Tracer,
		Logger: telem.Logger.Named("test"),
	}
}

// newTestRuntimeWithConfig creates a test runtime with proper configuration
// for the manifest enumerator. The ManifestETLMaxChanges must be set to
// allow the grouper to collect multiple manifest groups.
func newTestRuntimeWithConfig(t *testing.T) testRuntime {
	t.Helper()
	rt := newTestRuntime(t)
	rt.Config = &config.Config{
		ManifestETLMaxChanges: 1000,
	}
	return rt
}
