package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/github/sweagentd/internal/agent/sessionsv2"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/integrations/codereview"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/jobevents"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockEmitter records EmitJobProgress calls for test assertions.
type mockEmitter struct {
	calls []emitCall
}

type emitCall struct {
	job      *jobs.Job
	progress *jobevents.ProgressUpdate
}

func (m *mockEmitter) EmitJobProgress(_ context.Context, job *jobs.Job, p *jobevents.ProgressUpdate, _ observability.Exporters) {
	m.calls = append(m.calls, emitCall{job: job, progress: p})
}

func TestCreateProgressEventEmission(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()

	var jobCounter int
	seedJob := func(t *testing.T, useAsync bool) *jobs.Job {
		t.Helper()
		jobCounter++
		id := fmt.Sprintf("%s-%d", t.Name(), jobCounter)
		job := &jobs.Job{
			ID:               id,
			OwnerID:          1,
			RepoID:           2,
			AssignmentID:     "assignment-" + id,
			UseAsyncSessions: useAsync,
		}
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		return job
	}

	makeProgress := func(job *jobs.Job, namespace, kind string) *progress.Progress {
		return job.NewProgress(namespace, kind, 1, map[string]string{"msg": "hello"})
	}

	t.Run("integrator namespace emits without UseAsyncSessions", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, emitter, nil, nil, nil)
		job := seedJob(t, false)

		result, err := svc.CreateProgress(ctx, job, []*progress.Progress{
			makeProgress(job, codereview.ProgressNamespace, "review-status"),
		})
		require.NoError(t, err)
		require.Len(t, result, 1)

		require.Len(t, emitter.calls, 1)
		assert.Equal(t, codereview.ProgressNamespace, emitter.calls[0].progress.Namespace)
		assert.Equal(t, "review-status", emitter.calls[0].progress.Kind)
	})

	t.Run("integrator namespace emits with UseAsyncSessions", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, emitter, nil, nil, nil)
		job := seedJob(t, true)

		result, err := svc.CreateProgress(ctx, job, []*progress.Progress{
			makeProgress(job, codereview.ProgressNamespace, "review-status"),
		})
		require.NoError(t, err)
		require.Len(t, result, 1)

		require.Len(t, emitter.calls, 1)
		assert.Equal(t, codereview.ProgressNamespace, emitter.calls[0].progress.Namespace)
	})

	t.Run("sessions-legacy only emits with UseAsyncSessions", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, emitter, nil, nil, nil)

		// Without UseAsyncSessions — no emission
		jobNoAsync := seedJob(t, false)
		_, err := svc.CreateProgress(ctx, jobNoAsync, []*progress.Progress{
			makeProgress(jobNoAsync, jobevents.SessionsLegacyNamespace, "log"),
		})
		require.NoError(t, err)
		assert.Empty(t, emitter.calls)

		// With UseAsyncSessions — emits
		jobAsync := seedJob(t, true)
		_, err = svc.CreateProgress(ctx, jobAsync, []*progress.Progress{
			makeProgress(jobAsync, jobevents.SessionsLegacyNamespace, "log"),
		})
		require.NoError(t, err)
		require.Len(t, emitter.calls, 1)
		assert.Equal(t, jobevents.SessionsLegacyNamespace, emitter.calls[0].progress.Namespace)
	})

	t.Run("sessions-v2 only emits with UseAsyncSessions", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, emitter, nil, nil, nil)

		// sessions-v2 requires valid content for translation; use a response event.
		// Content must be a json.RawMessage so json.Marshal produces valid JSON for Translate.
		v2Content := json.RawMessage(`{"kind":"response","callId":"c1","response":{"content":"done"}}`)

		makeV2Progress := func(job *jobs.Job) *progress.Progress {
			return job.NewProgress("sessions-v2", "response", 1, v2Content)
		}

		// Without UseAsyncSessions — no emission
		jobNoAsync := seedJob(t, false)
		_, err := svc.CreateProgress(ctx, jobNoAsync, []*progress.Progress{
			makeV2Progress(jobNoAsync),
		})
		require.NoError(t, err)
		assert.Empty(t, emitter.calls)

		// With UseAsyncSessions — emits (translated to sessions-legacy namespace)
		jobAsync := seedJob(t, true)
		_, err = svc.CreateProgress(ctx, jobAsync, []*progress.Progress{
			makeV2Progress(jobAsync),
		})
		require.NoError(t, err)
		require.Len(t, emitter.calls, 1)
		assert.Equal(t, jobevents.SessionsLegacyNamespace, emitter.calls[0].progress.Namespace)
	})

	t.Run("sessions-v2 side-effect kind does not emit to session logs", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, emitter, nil, nil, nil)
		job := seedJob(t, true)

		_, err := svc.CreateProgress(ctx, job, []*progress.Progress{
			job.NewProgress(sessionsv2.Namespace, sessionsv2.KindReportProgress, 1, map[string]string{
				"pr_title":       "New title",
				"pr_description": "New description",
			}),
		})
		require.NoError(t, err)

		assert.Empty(t, emitter.calls)
	})

	t.Run("unknown namespace never emits", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, emitter, nil, nil, nil)
		job := seedJob(t, true)

		_, err := svc.CreateProgress(ctx, job, []*progress.Progress{
			makeProgress(job, "runtime", "log"),
		})
		require.NoError(t, err)
		assert.Empty(t, emitter.calls)
	})

	t.Run("nil emitter is safe for integrator namespaces", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, nil, nil)
		job := seedJob(t, false)

		result, err := svc.CreateProgress(ctx, job, []*progress.Progress{
			makeProgress(job, codereview.ProgressNamespace, "review-status"),
		})
		require.NoError(t, err)
		require.Len(t, result, 1)
	})

	t.Run("mixed namespaces emit correctly", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, emitter, nil, nil, nil)
		job := seedJob(t, true)

		_, err := svc.CreateProgress(ctx, job, []*progress.Progress{
			makeProgress(job, codereview.ProgressNamespace, "review-status"),
			makeProgress(job, jobevents.SessionsLegacyNamespace, "log"),
			makeProgress(job, "runtime", "log"),
		})
		require.NoError(t, err)

		// Only integrator + sessions-legacy should emit (not runtime)
		require.Len(t, emitter.calls, 2)
		assert.Equal(t, codereview.ProgressNamespace, emitter.calls[0].progress.Namespace)
		assert.Equal(t, jobevents.SessionsLegacyNamespace, emitter.calls[1].progress.Namespace)
	})
}

// mockPullDataStorer records StoreGeneratedPullData calls.
type mockPullDataStorer struct {
	calls []pullDataCall
	err   error
}

type pullDataCall struct {
	job   *jobs.Job
	title string
	desc  string
}

func (m *mockPullDataStorer) StoreGeneratedPullData(_ context.Context, job *jobs.Job, title, description string) error {
	m.calls = append(m.calls, pullDataCall{job: job, title: title, desc: description})
	return m.err
}

func TestDispatchSideEffects_PRSummary(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()

	seedJob := func(t *testing.T, prID int64, prNumber int, useAsync bool) *jobs.Job {
		t.Helper()
		job := &jobs.Job{
			ID:                t.Name(),
			OwnerID:           1,
			RepoID:            2,
			AssignmentID:      "a-" + t.Name(),
			PullRequestID:     prID,
			PullRequestNumber: prNumber,
			UseAsyncSessions:  useAsync,
		}
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		return job
	}

	t.Run("no PR persists generated pull data for deferred creation", func(t *testing.T) {
		storer := &mockPullDataStorer{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, storer, nil)
		job := seedJob(t, 0, 0, false)

		svc.dispatchSideEffects(ctx, job, []sessionsv2.ProgressItem{
			{Namespace: sessionsv2.Namespace, Kind: sessionsv2.KindPRSummary, Content: `{"pr_title":"Add auth","pr_description":"JWT-based auth"}`},
		})

		assert.Equal(t, "Add auth", job.PullRequestTitle)
		assert.Equal(t, "JWT-based auth", job.PullRequestDescription)
		require.Len(t, storer.calls, 1)
		assert.Equal(t, "Add auth", storer.calls[0].title)
		assert.Equal(t, "JWT-based auth", storer.calls[0].desc)
	})

	t.Run("with PR updates the existing PR not generated pull data", func(t *testing.T) {
		cf := &github.NoopClientFactory{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Old title"),
				Body:   gg.Ptr("Old body"),
			},
		}
		storer := &mockPullDataStorer{}
		svc := &Service{
			store:          store,
			cpf:            cf,
			obsv:           obsv,
			appProvider:    agenticapptest.NewTestProvider(t),
			pullDataStorer: storer,
		}
		job := seedJob(t, 100, 42, false)

		svc.dispatchSideEffects(ctx, job, []sessionsv2.ProgressItem{
			{Namespace: sessionsv2.Namespace, Kind: sessionsv2.KindPRSummary, Content: `{"pr_title":"New title","pr_description":"New body"}`},
		})

		// Storer must NOT be called when a PR exists (update path runs instead).
		assert.Empty(t, storer.calls)
		// In-memory fields are NOT set via storeGeneratedPullData.
		assert.Empty(t, job.PullRequestTitle)
	})

	t.Run("pr_summary uses post-session skip semantics for subsequent jobs", func(t *testing.T) {
		trackedClient := &github.NoopClient{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Old title"),
				Body:   gg.Ptr("Old body"),
			},
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
				return trackedClient, nil
			},
		}
		storer := &mockPullDataStorer{}
		svc := &Service{
			store:          store,
			cpf:            cf,
			obsv:           obsv,
			appProvider:    agenticapptest.NewTestProvider(t),
			pullDataStorer: storer,
			ff: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs: true,
			}),
		}
		job := seedJob(t, 100, 42, false)
		job.Action = jobs.AgentActionFixPRComment

		svc.dispatchSideEffects(ctx, job, []sessionsv2.ProgressItem{
			{Namespace: sessionsv2.Namespace, Kind: sessionsv2.KindPRSummary, Content: `{"pr_title":"Final title","pr_description":"Final body"}`},
		})

		assert.Empty(t, storer.calls)
		require.True(t, trackedClient.HasMethodCall("GetPullRequest"))
		require.True(t, trackedClient.HasMethodCall("UpdatePullRequest"))
		assert.Equal(t, "Final title", trackedClient.MockPullRequest.GetTitle())
		assert.Equal(t, "Final body", trackedClient.MockPullRequest.GetBody())
	})

	t.Run("report_progress keeps mid-session skip semantics for subsequent jobs", func(t *testing.T) {
		trackedClient := &github.NoopClient{
			MockPullRequest: &gg.PullRequest{
				ID:     gg.Ptr(int64(1)),
				Number: gg.Ptr(42),
				Title:  gg.Ptr("Old title"),
				Body:   gg.Ptr("Old body"),
			},
		}
		cf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
				return trackedClient, nil
			},
		}
		svc := &Service{
			store:       store,
			cpf:         cf,
			obsv:        obsv,
			appProvider: agenticapptest.NewTestProvider(t),
			ff: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs: true,
			}),
		}
		job := seedJob(t, 100, 42, false)
		job.Action = jobs.AgentActionFixPRComment

		svc.dispatchSideEffects(ctx, job, []sessionsv2.ProgressItem{
			{Namespace: sessionsv2.Namespace, Kind: sessionsv2.KindReportProgress, Content: `{"pr_title":"Progress title","pr_description":"Progress body"}`},
		})

		require.False(t, trackedClient.HasMethodCall("GetPullRequest"))
		require.False(t, trackedClient.HasMethodCall("UpdatePullRequest"))
		assert.Equal(t, "Old title", trackedClient.MockPullRequest.GetTitle())
		assert.Equal(t, "Old body", trackedClient.MockPullRequest.GetBody())
	})

	t.Run("report_progress does not persist generated pull data", func(t *testing.T) {
		storer := &mockPullDataStorer{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, storer, nil)
		job := seedJob(t, 0, 0, false)

		svc.dispatchSideEffects(ctx, job, []sessionsv2.ProgressItem{
			{Namespace: sessionsv2.Namespace, Kind: sessionsv2.KindReportProgress, Content: `{"pr_title":"Progress title","pr_description":"Progress desc"}`},
		})

		// report_progress only calls UpdateJobPullRequestMidSession (which returns nil for
		// no-PR jobs). It must never call storeGeneratedPullData.
		assert.Empty(t, storer.calls)
		assert.Empty(t, job.PullRequestTitle)
	})

	t.Run("async no-PR persists generated pull data for Mission Control", func(t *testing.T) {
		storer := &mockPullDataStorer{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, storer, nil)
		job := seedJob(t, 0, 0, true) // async session

		svc.dispatchSideEffects(ctx, job, []sessionsv2.ProgressItem{
			{Namespace: sessionsv2.Namespace, Kind: sessionsv2.KindPRSummary, Content: `{"pr_title":"Async PR","pr_description":"Async desc"}`},
		})

		// For CCA V3 async jobs without a PR, pr_summary must persist
		// GeneratedPullData so Mission Control can use it for deferred
		// PR creation. The storer (jobservice.StoreGeneratedPullData)
		// intentionally bypasses the UseAsyncSessions guard.
		assert.Equal(t, "Async PR", job.PullRequestTitle)
		assert.Equal(t, "Async desc", job.PullRequestDescription)
		require.Len(t, storer.calls, 1)
		assert.Equal(t, "Async PR", storer.calls[0].title)
		assert.Equal(t, "Async desc", storer.calls[0].desc)
		assert.True(t, storer.calls[0].job.UseAsyncSessions, "storer must receive the async job")
	})

	t.Run("nil storer is safe for no-PR jobs", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, nil, nil)
		// No storer set.
		job := seedJob(t, 0, 0, false)

		svc.dispatchSideEffects(ctx, job, []sessionsv2.ProgressItem{
			{Namespace: sessionsv2.Namespace, Kind: sessionsv2.KindPRSummary, Content: `{"pr_title":"T","pr_description":"D"}`},
		})

		// In-memory fields are still set even without a storer.
		assert.Equal(t, "T", job.PullRequestTitle)
		assert.Equal(t, "D", job.PullRequestDescription)
	})

	t.Run("storer error is logged not propagated", func(t *testing.T) {
		storer := &mockPullDataStorer{err: goerrors.New("capi down")}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, storer, nil)
		job := seedJob(t, 0, 0, false)

		// Should not panic; error is logged internally.
		svc.dispatchSideEffects(ctx, job, []sessionsv2.ProgressItem{
			{Namespace: sessionsv2.Namespace, Kind: sessionsv2.KindPRSummary, Content: `{"pr_title":"T","pr_description":"D"}`},
		})

		assert.Equal(t, "T", job.PullRequestTitle)
		require.Len(t, storer.calls, 1)
	})
}

// TestProgressContainsSession exercises the cross-job session lookup helper
// used by GetProgress when the resume-target session_id is set.
func TestProgressContainsSession(t *testing.T) {
	type sessionEventsRecord struct {
		Version           int    `json:"version"`
		RecordType        string `json:"recordType"`
		SessionID         string `json:"sessionId"`
		CreatedAt         string `json:"createdAt"`
		EventsJsonlBase64 string `json:"eventsJsonlBase64"`
	}

	mkRecord := func(namespace, kind string, content any) *progress.Progress {
		return &progress.Progress{
			Namespace: namespace,
			Kind:      kind,
			Content:   content,
		}
	}

	makeRecord := func(sessionID string) sessionEventsRecord {
		return sessionEventsRecord{
			Version:           3,
			RecordType:        "events-jsonl",
			SessionID:         sessionID,
			CreatedAt:         "2026-01-01T00:00:00Z",
			EventsJsonlBase64: "abc",
		}
	}

	t.Run("matches when content is a struct with sessionId", func(t *testing.T) {
		records := []*progress.Progress{
			mkRecord("cca-v3-agent", "session-events", makeRecord("session-A")),
		}
		assert.True(t, progressContainsSession(records, "session-A"))
		assert.False(t, progressContainsSession(records, "session-B"))
	})

	t.Run("matches when content is a JSON-stringified record", func(t *testing.T) {
		body, err := json.Marshal(makeRecord("session-S"))
		require.NoError(t, err)
		records := []*progress.Progress{
			mkRecord("cca-v3-agent", "session-events", string(body)),
		}
		assert.True(t, progressContainsSession(records, "session-S"))
		assert.False(t, progressContainsSession(records, "session-other"))
	})

	t.Run("ignores records from other namespaces", func(t *testing.T) {
		records := []*progress.Progress{
			mkRecord("not-our-namespace", "session-events", makeRecord("session-X")),
		}
		assert.False(t, progressContainsSession(records, "session-X"))
	})

	t.Run("ignores records of other kinds within the v3 namespace", func(t *testing.T) {
		records := []*progress.Progress{
			mkRecord("cca-v3-agent", "log", makeRecord("session-X")),
		}
		assert.False(t, progressContainsSession(records, "session-X"))
	})

	t.Run("handles malformed content gracefully", func(t *testing.T) {
		records := []*progress.Progress{
			mkRecord("cca-v3-agent", "session-events", "{not valid json"),
			mkRecord("cca-v3-agent", "session-events", nil),
		}
		assert.False(t, progressContainsSession(records, "session-X"))
	})

	t.Run("matches when at least one of multiple records contains the session", func(t *testing.T) {
		records := []*progress.Progress{
			mkRecord("cca-v3-agent", "session-events", makeRecord("session-A")),
			mkRecord("cca-v3-agent", "log", "noise"),
			mkRecord("cca-v3-agent", "session-events", makeRecord("session-B")),
		}
		assert.True(t, progressContainsSession(records, "session-B"))
	})
}

// TestService_GetProgress_ResumeWalkBack covers the new history walk-back
// behavior used by resume-after-permission-timeout in v3.
func TestService_GetProgress_ResumeWalkBack(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	type sessionEventsRecord struct {
		Version           int    `json:"version"`
		RecordType        string `json:"recordType"`
		SessionID         string `json:"sessionId"`
		CreatedAt         string `json:"createdAt"`
		EventsJsonlBase64 string `json:"eventsJsonlBase64"`
	}
	makeRecord := func(sessionID string) sessionEventsRecord {
		return sessionEventsRecord{
			Version:           3,
			RecordType:        "events-jsonl",
			SessionID:         sessionID,
			CreatedAt:         "2026-01-01T00:00:00Z",
			EventsJsonlBase64: "abc",
		}
	}
	addSnapshot := func(t *testing.T, store *memory.Store, job *jobs.Job, sessionID string) {
		t.Helper()
		_, err := store.CreateProgress(ctx, &progress.Progress{
			ID:           progress.NewID(),
			AssignmentID: job.AssignmentID,
			JobID:        job.ID,
			Namespace:    "cca-v3-agent",
			Kind:         "session-events",
			Content:      makeRecord(sessionID),
		})
		require.NoError(t, err)
	}

	seedJob := func(t *testing.T, store *memory.Store, assignment, id string, createdAt int64) *jobs.Job {
		t.Helper()
		job := &jobs.Job{
			ID:           id,
			OwnerID:      1,
			RepoID:       2,
			AssignmentID: assignment,
			CreatedAt:    createdAt,
		}
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		return job
	}

	t.Run("with empty targetSessionID, returns most-recent previous job's progress (legacy behavior)", func(t *testing.T) {
		store := memory.NewStore()
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, nil, nil)

		j1 := seedJob(t, store, "assignment-1", "j-old", 100)
		addSnapshot(t, store, j1, "session-old")
		j2 := seedJob(t, store, "assignment-1", "j-new", 200)
		// j2 is the current job — no progress yet.

		result, err := svc.GetProgress(ctx, j2, []string{"cca-v3-agent"}, true /* history */, "" /* targetSessionID */)
		require.NoError(t, err)
		require.Len(t, result, 1, "only j1's snapshot should be returned")
		assert.Equal(t, "j-old", result[0].JobID)
	})

	t.Run("with targetSessionID set and matching previousJobs[0], returns that job's progress", func(t *testing.T) {
		store := memory.NewStore()
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, nil, nil)

		j1 := seedJob(t, store, "assignment-2", "j-target", 100)
		addSnapshot(t, store, j1, "session-target")
		j2 := seedJob(t, store, "assignment-2", "j-resume", 200)

		result, err := svc.GetProgress(ctx, j2, []string{"cca-v3-agent"}, true, "session-target")
		require.NoError(t, err)
		require.Len(t, result, 1)
		assert.Equal(t, "j-target", result[0].JobID)
	})

	t.Run("with targetSessionID set and an unrelated newer job in between, walks back past it", func(t *testing.T) {
		// Scenario: S1 paused → user started S2 (new task) → S2 finished →
		// user clicked Approve on S1 → resume job j3 should re-hydrate
		// from j1's snapshot, not j2's.
		store := memory.NewStore()
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, nil, nil)

		j1 := seedJob(t, store, "assignment-3", "j-target-paused", 100)
		addSnapshot(t, store, j1, "session-paused")
		j2 := seedJob(t, store, "assignment-3", "j-unrelated", 200)
		addSnapshot(t, store, j2, "session-unrelated")
		j3 := seedJob(t, store, "assignment-3", "j-resume", 300)

		result, err := svc.GetProgress(ctx, j3, []string{"cca-v3-agent"}, true, "session-paused")
		require.NoError(t, err)
		require.Len(t, result, 1, "should walk back past the unrelated newer job")
		assert.Equal(t, "j-target-paused", result[0].JobID)
	})

	t.Run("with targetSessionID set and no match in any previous job, returns no history", func(t *testing.T) {
		store := memory.NewStore()
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, nil, nil)

		j1 := seedJob(t, store, "assignment-4", "j-old", 100)
		addSnapshot(t, store, j1, "session-X")
		j2 := seedJob(t, store, "assignment-4", "j-resume", 200)

		result, err := svc.GetProgress(ctx, j2, []string{"cca-v3-agent"}, true, "session-not-here")
		require.NoError(t, err)
		assert.Empty(t, result, "no historical progress should be returned when no match is found")
	})

	t.Run("walk-back is capped at resumeWalkBackLimit", func(t *testing.T) {
		store := memory.NewStore()
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, nil, nil, nil, nil)

		// Build resumeWalkBackLimit + 5 unrelated previous jobs, with the
		// target session in the OLDEST (deepest) one. Verifies the cap
		// prevents an unbounded scan.
		assignmentID := "assignment-cap"
		var oldestJob *jobs.Job
		for i := range resumeWalkBackLimit + 5 {
			job := seedJob(t, store, assignmentID, fmt.Sprintf("j-bg-%d", i), int64(100+i))
			addSnapshot(t, store, job, fmt.Sprintf("session-bg-%d", i))
			if oldestJob == nil {
				oldestJob = job
			}
		}
		// Add the resume job last (newest).
		jResume := seedJob(t, store, assignmentID, "j-resume", 1000)

		// The oldest job is now beyond the cap (walk-back checks the most
		// recent resumeWalkBackLimit jobs only). The target session is in
		// the oldest job, so it should NOT be found.
		result, err := svc.GetProgress(ctx, jResume, []string{"cca-v3-agent"}, true, "session-bg-0")
		require.NoError(t, err)
		assert.Empty(t, result, "walk-back should not extend past resumeWalkBackLimit")
	})
}
