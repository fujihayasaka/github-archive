package automations

import (
	"context"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/goerrors"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

type stubLookup struct {
	hasCalls       atomic.Int64
	listCalls      atomic.Int64
	disabledCalls  atomic.Int64
	hasResult      bool
	hasErr         error
	listResult     []RuntimeConfig
	listErr        error
	disabledResult bool
}

func (s *stubLookup) HasActiveForEvent(_ context.Context, _ EventMatchRequest) (bool, error) {
	s.hasCalls.Add(1)
	return s.hasResult, s.hasErr
}

func (s *stubLookup) ListForEvent(_ context.Context, _ ListForEventRequest) ([]RuntimeConfig, error) {
	s.listCalls.Add(1)
	return s.listResult, s.listErr
}

func (s *stubLookup) AutomationsDisabledFromConfig(_ context.Context, _ *sweagentdtwirp.ConfigurationForRepositoryResponse, _ int64, _ string) bool {
	s.disabledCalls.Add(1)
	return s.disabledResult
}

func TestNewCachedLookup_NilInnerReturnsNil(t *testing.T) {
	if got := NewCachedLookup(nil, 100, time.Minute); got != nil {
		t.Fatalf("expected nil when inner is nil, got %#v", got)
	}
}

func TestCachedLookup_CachesPositiveResult(t *testing.T) {
	inner := &stubLookup{hasResult: true}
	cached := NewCachedLookup(inner, 100, time.Minute)
	ctx := context.Background()
	req := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	for range 5 {
		got, err := cached.HasActiveForEvent(ctx, req)
		if err != nil || !got {
			t.Fatalf("iter unexpected result: got=%v err=%v", got, err)
		}
	}
	if calls := inner.hasCalls.Load(); calls != 1 {
		t.Fatalf("expected 1 underlying call, got %d", calls)
	}
}

func TestCachedLookup_CachesNegativeResult(t *testing.T) {
	inner := &stubLookup{hasResult: false}
	cached := NewCachedLookup(inner, 100, time.Minute)
	ctx := context.Background()
	req := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	for range 5 {
		got, err := cached.HasActiveForEvent(ctx, req)
		if err != nil || got {
			t.Fatalf("iter unexpected result: got=%v err=%v", got, err)
		}
	}
	if calls := inner.hasCalls.Load(); calls != 1 {
		t.Fatalf("expected 1 underlying call, got %d", calls)
	}
}

func TestCachedLookup_DistinctKeysAreCachedIndependently(t *testing.T) {
	inner := &stubLookup{hasResult: true}
	cached := NewCachedLookup(inner, 100, time.Minute)
	ctx := context.Background()

	issuesReq := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}
	workflowReq := EventMatchRequest{RepoID: 42, EventName: EventWorkflowRun, ActivityType: ActivityWorkflowRunFailed, WorkflowConclusion: WorkflowConclusionFailure}
	differentRepo := EventMatchRequest{RepoID: 43, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	_, _ = cached.HasActiveForEvent(ctx, issuesReq)
	_, _ = cached.HasActiveForEvent(ctx, workflowReq)
	_, _ = cached.HasActiveForEvent(ctx, differentRepo)
	_, _ = cached.HasActiveForEvent(ctx, issuesReq) // cache hit

	if calls := inner.hasCalls.Load(); calls != 3 {
		t.Fatalf("expected 3 underlying calls (one per distinct key), got %d", calls)
	}
}

func TestCachedLookup_DoesNotCacheErrors(t *testing.T) {
	inner := &stubLookup{hasErr: goerrors.New("boom")}
	cached := NewCachedLookup(inner, 100, time.Minute)
	ctx := context.Background()
	req := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	_, err1 := cached.HasActiveForEvent(ctx, req)
	_, err2 := cached.HasActiveForEvent(ctx, req)
	if err1 == nil || err2 == nil {
		t.Fatalf("expected errors, got err1=%v err2=%v", err1, err2)
	}
	if calls := inner.hasCalls.Load(); calls != 2 {
		t.Fatalf("errors should not be cached; expected 2 calls, got %d", calls)
	}
}

func TestCachedLookup_TTLExpiresEntries(t *testing.T) {
	inner := &stubLookup{hasResult: true}
	cached := NewCachedLookup(inner, 100, 10*time.Millisecond)
	ctx := context.Background()
	req := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	_, _ = cached.HasActiveForEvent(ctx, req)
	if got := inner.hasCalls.Load(); got != 1 {
		t.Fatalf("expected 1 call after first lookup, got %d", got)
	}

	time.Sleep(25 * time.Millisecond)

	_, _ = cached.HasActiveForEvent(ctx, req)
	if got := inner.hasCalls.Load(); got != 2 {
		t.Fatalf("expected 2 calls after TTL expiry, got %d", got)
	}
}

func TestCachedLookup_InvalidateRepoRemovesAllKeysForRepo(t *testing.T) {
	inner := &stubLookup{hasResult: true}
	cached := NewCachedLookup(inner, 100, time.Hour)
	ctx := context.Background()

	repo42Issues := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}
	repo42Wf := EventMatchRequest{RepoID: 42, EventName: EventWorkflowRun, ActivityType: ActivityWorkflowRunFailed, WorkflowConclusion: WorkflowConclusionFailure}
	repo43 := EventMatchRequest{RepoID: 43, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	_, _ = cached.HasActiveForEvent(ctx, repo42Issues)
	_, _ = cached.HasActiveForEvent(ctx, repo42Wf)
	_, _ = cached.HasActiveForEvent(ctx, repo43)
	if calls := inner.hasCalls.Load(); calls != 3 {
		t.Fatalf("setup: expected 3 calls, got %d", calls)
	}

	cached.InvalidateRepo(42)

	// repo 42's two entries should be gone; repo 43's should remain.
	_, _ = cached.HasActiveForEvent(ctx, repo42Issues) // miss
	_, _ = cached.HasActiveForEvent(ctx, repo42Wf)     // miss
	_, _ = cached.HasActiveForEvent(ctx, repo43)       // hit

	if calls := inner.hasCalls.Load(); calls != 5 {
		t.Fatalf("expected 5 total calls (3 initial + 2 after invalidate), got %d", calls)
	}
}

func TestCachedLookup_KeyPrefixDoesNotMatchUnrelatedRepos(t *testing.T) {
	// Make sure InvalidateRepo(4) doesn't accidentally evict repo 42 or 400.
	inner := &stubLookup{hasResult: true}
	cached := NewCachedLookup(inner, 100, time.Hour)
	ctx := context.Background()

	r4 := EventMatchRequest{RepoID: 4, EventName: EventIssues, ActivityType: ActivityIssueOpened}
	r42 := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}
	r400 := EventMatchRequest{RepoID: 400, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	_, _ = cached.HasActiveForEvent(ctx, r4)
	_, _ = cached.HasActiveForEvent(ctx, r42)
	_, _ = cached.HasActiveForEvent(ctx, r400)

	cached.InvalidateRepo(4)

	_, _ = cached.HasActiveForEvent(ctx, r4)   // miss
	_, _ = cached.HasActiveForEvent(ctx, r42)  // hit (must NOT have been invalidated)
	_, _ = cached.HasActiveForEvent(ctx, r400) // hit (must NOT have been invalidated)

	if calls := inner.hasCalls.Load(); calls != 4 {
		t.Fatalf("expected exactly 4 calls (3 initial + 1 for re-fetched r4), got %d", calls)
	}
}

func TestCachedLookup_NilReceiverIsSafe(t *testing.T) {
	var c *CachedLookup
	c.InvalidateRepo(42) // must not panic
	c.Purge()            // must not panic
}

func TestCachedLookup_PassThroughListForEventAndDisabled(t *testing.T) {
	inner := &stubLookup{listResult: []RuntimeConfig{{
		AutomationID:      "automation-1",
		AutomationOwnerID: 9001,
	}}}
	cached := NewCachedLookup(inner, 100, time.Minute)
	ctx := context.Background()

	configs, _ := cached.ListForEvent(ctx, ListForEventRequest{})
	_ = cached.AutomationsDisabledFromConfig(ctx, nil, 1, "issue_created")

	if len(configs) != 1 || configs[0].AutomationOwnerID != 9001 {
		t.Fatalf("ListForEvent should pass through automation owner identity, got %#v", configs)
	}
	if inner.listCalls.Load() != 1 {
		t.Fatalf("expected 1 ListForEvent call, got %d", inner.listCalls.Load())
	}
	if inner.disabledCalls.Load() != 1 {
		t.Fatalf("expected 1 AutomationsDisabledFromConfig call, got %d", inner.disabledCalls.Load())
	}
}

type stubStats struct {
	hits          atomic.Int64
	misses        atomic.Int64
	errs          atomic.Int64
	shared        atomic.Int64
	invalidations atomic.Int64
}

func (s *stubStats) Increment(_ context.Context, name string, _ stats.Tags) {
	switch name {
	case "automations.lookup.cache_hit":
		s.hits.Add(1)
	case "automations.lookup.cache_miss":
		s.misses.Add(1)
	case "automations.lookup.cache_error":
		s.errs.Add(1)
	case "automations.lookup.cache_shared":
		s.shared.Add(1)
	case "automations.lookup.cache_invalidate":
		s.invalidations.Add(1)
	default:
		// ignore unrecognized metric names
	}
}

func TestCachedLookup_StatsAreReported(t *testing.T) {
	inner := &stubLookup{hasResult: true}
	stats := &stubStats{}
	cached := NewCachedLookup(inner, 100, time.Hour).WithStats(stats)
	ctx := context.Background()
	req := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	_, _ = cached.HasActiveForEvent(ctx, req) // miss
	_, _ = cached.HasActiveForEvent(ctx, req) // hit
	_, _ = cached.HasActiveForEvent(ctx, req) // hit
	cached.InvalidateRepo(42)

	if got := stats.misses.Load(); got != 1 {
		t.Errorf("expected 1 miss, got %d", got)
	}
	if got := stats.hits.Load(); got != 2 {
		t.Errorf("expected 2 hits, got %d", got)
	}
	if got := stats.invalidations.Load(); got != 1 {
		t.Errorf("expected 1 invalidation, got %d", got)
	}
}

// blockingStubLookup blocks every call on a release channel so the test can
// stage many concurrent cache-miss callers before letting the underlying
// lookup return. Used to exercise the singleflight dedup path.
type blockingStubLookup struct {
	calls   atomic.Int64
	release chan struct{}
	result  bool
}

func (b *blockingStubLookup) HasActiveForEvent(_ context.Context, _ EventMatchRequest) (bool, error) {
	b.calls.Add(1)
	<-b.release
	return b.result, nil
}

func (b *blockingStubLookup) ListForEvent(_ context.Context, _ ListForEventRequest) ([]RuntimeConfig, error) {
	return nil, nil
}

func (b *blockingStubLookup) AutomationsDisabledFromConfig(_ context.Context, _ *sweagentdtwirp.ConfigurationForRepositoryResponse, _ int64, _ string) bool {
	return false
}

func TestCachedLookup_SingleflightDedupesConcurrentMisses(t *testing.T) {
	inner := &blockingStubLookup{release: make(chan struct{}), result: true}
	stats := &stubStats{}
	cached := NewCachedLookup(inner, 100, time.Hour).WithStats(stats)
	ctx := context.Background()
	req := EventMatchRequest{RepoID: 42, EventName: EventIssues, ActivityType: ActivityIssueOpened}

	const concurrent = 25
	var wg sync.WaitGroup
	results := make([]bool, concurrent)
	errs := make([]error, concurrent)
	wg.Add(concurrent)
	for i := range concurrent {
		go func(idx int) {
			defer wg.Done()
			got, err := cached.HasActiveForEvent(ctx, req)
			results[idx] = got
			errs[idx] = err
		}(i)
	}

	// Give every goroutine a chance to enter the singleflight slot before
	// we release the inner lookup. This is a soft schedule hint, not a
	// correctness requirement — singleflight only collapses concurrently
	// queued calls, but the test is robust because we assert the inner
	// call count is ≥ 1 and < concurrent, which proves dedup happened.
	time.Sleep(20 * time.Millisecond)
	close(inner.release)
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Fatalf("call %d: unexpected error: %v", i, err)
		}
		if !results[i] {
			t.Fatalf("call %d: expected true, got false", i)
		}
	}

	calls := inner.calls.Load()
	if calls < 1 || calls >= int64(concurrent) {
		t.Fatalf("expected singleflight to collapse concurrent misses: got %d underlying calls (concurrent=%d)", calls, concurrent)
	}
	// First caller records a miss; the rest should record cache_shared
	// or cache_hit depending on whether they raced into the singleflight
	// slot or arrived after the cache was populated.
	totalRecorded := stats.misses.Load() + stats.shared.Load() + stats.hits.Load()
	if totalRecorded != int64(concurrent) {
		t.Fatalf("expected %d total recorded metric increments, got %d (hits=%d misses=%d shared=%d)",
			concurrent, totalRecorded, stats.hits.Load(), stats.misses.Load(), stats.shared.Load())
	}
}
