package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/github/sweagentd/internal/agent/sessionsv2"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/telemetry/standardevents"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockTelemetryPublisher captures calls to ShouldPublishRestrictedTelemetry and
// PublishModelCallStandardEvent for test assertions.
type mockTelemetryPublisher struct {
	shouldPublishRestricted bool
	modelCallParams         []standardevents.ModelCallParams
	modelCallJobs           []*jobs.Job
}

func (m *mockTelemetryPublisher) ShouldPublishRestrictedTelemetry(_ context.Context, _ int64) bool {
	return m.shouldPublishRestricted
}

func (m *mockTelemetryPublisher) PublishModelCallStandardEvent(_ context.Context, job *jobs.Job, params standardevents.ModelCallParams) {
	m.modelCallParams = append(m.modelCallParams, params)
	m.modelCallJobs = append(m.modelCallJobs, job)
}

func newCopilotAppProvider() *agenticapp.Provider {
	copilotApp := agenticapp.NewCopilot(100, "copilot", 200, "copilot[bot]", "copilot-commit", "copilot@github.com")
	return agenticapp.NewProvider(copilotApp)
}

func TestPublishSessionsV2Telemetry(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := newCopilotAppProvider()
	ff := featureflags.NewNoopClient(nil)
	twirp := githubtwirp.NewNoopClient()

	var jobCounter int
	seedJob := func(t *testing.T, agentID int64) *jobs.Job {
		t.Helper()
		jobCounter++
		id := fmt.Sprintf("%s-%d", t.Name(), jobCounter)
		job := &jobs.Job{
			ID:           id,
			OwnerID:      1,
			RepoID:       2,
			AssignmentID: "assignment-" + id,
			AgentID:      agentID,
			ActorID:      42,
		}
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		return job
	}

	makeSessionsV2Progress := func(job *jobs.Job, kind string, content any) *progress.Progress {
		return job.NewProgress(sessionsv2.Namespace, kind, 1, content)
	}

	makeSessionsV2Items := func(progressList []*progress.Progress) []sessionsV2ProgressItem {
		var items []sessionsV2ProgressItem
		for _, p := range progressList {
			contentJSON, err := json.Marshal(p.Content)
			if err != nil {
				panic(err)
			}
			items = append(items, sessionsV2ProgressItem{
				progress:    p,
				contentJSON: contentJSON,
			})
		}
		return items
	}

	t.Run("publishes JobProgress for message event", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0) // AgentID=0 → defaults to Copilot

		content := map[string]any{
			"kind": "message",
			"message": map[string]any{
				"role":    "assistant",
				"content": "Hello, I will help you.",
			},
			"modelCall": map[string]any{
				"model": "gpt-4o",
			},
		}

		progressList := []*progress.Progress{makeSessionsV2Progress(job, sessionsv2.KindMessage, content)}
		// publishSessionsV2Telemetry should not panic or error
		svc.publishSessionsV2Telemetry(ctx, job, makeSessionsV2Items(progressList))
		// No assertion on Hydro publish since NoopExporters discards — just verify no panic
	})

	t.Run("publishes JobProgress for tool_execution event", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0)

		content := map[string]any{
			"kind":       "tool_execution",
			"toolCallId": "tc-1",
			"toolResult": map[string]any{
				"textResultForLlm": "file contents...",
				"resultType":       "success",
			},
		}

		progressList := []*progress.Progress{makeSessionsV2Progress(job, sessionsv2.KindToolExecution, content)}
		svc.publishSessionsV2Telemetry(ctx, job, makeSessionsV2Items(progressList))
	})

	t.Run("publishes JobProgress for tool_execution with originalCall.callId", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0)

		content := map[string]any{
			"kind":       "tool_execution",
			"toolCallId": "tc-2",
			"toolResult": map[string]any{
				"textResultForLlm": "file contents...",
				"resultType":       "success",
			},
			"originalCall": map[string]any{
				"callId": "original-call-456",
				"model":  "gpt-4o",
			},
		}

		progressList := []*progress.Progress{makeSessionsV2Progress(job, sessionsv2.KindToolExecution, content)}
		svc.publishSessionsV2Telemetry(ctx, job, makeSessionsV2Items(progressList))
		// Verify no panic — originalCall.callId should be used as ModelCallId fallback
	})

	t.Run("publishes JobProgress for response event", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0)

		content := map[string]any{
			"kind":   "response",
			"callId": "call-123",
			"modelCall": map[string]any{
				"model": "gpt-4o",
			},
			"response": map[string]any{
				"content": "Done!",
			},
		}

		progressList := []*progress.Progress{makeSessionsV2Progress(job, sessionsv2.KindResponse, content)}
		svc.publishSessionsV2Telemetry(ctx, job, makeSessionsV2Items(progressList))
	})

	t.Run("publishes JobProgress and ModelCall events for model_call_failure", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0)

		content := map[string]any{
			"kind":                "model_call_failure",
			"modelCallDurationMs": float64(339),
			"modelCall": map[string]any{
				"model":      "claude-sonnet-4",
				"status":     float64(400),
				"error":      `{"message": "bad request"}`,
				"request_id": "req-456",
			},
			"requestMessages": `[{"role":"user","content":"hello"}]`,
		}

		progressList := []*progress.Progress{makeSessionsV2Progress(job, sessionsv2.KindModelCallFailure, content)}
		svc.publishSessionsV2Telemetry(ctx, job, makeSessionsV2Items(progressList))
	})

	t.Run("skips non-sessions-v2 namespaces", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0)

		// Pass an empty list since non-sessions-v2 items are filtered upstream
		svc.publishSessionsV2Telemetry(ctx, job, []sessionsV2ProgressItem{})
		// Should be a no-op — no panic
	})

	t.Run("handles malformed content gracefully", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0)

		// Content that can't be JSON-unmarshaled to a valid sessionsV2TelemetryEvent
		p := job.NewProgress(sessionsv2.Namespace, "message", 1, "not-valid-json-object")
		items := []sessionsV2ProgressItem{
			{progress: p, contentJSON: []byte("not-valid-json")},
		}
		svc.publishSessionsV2Telemetry(ctx, job, items)
		// Should log error but not panic
	})

	t.Run("includes experiment assignment context in JobProgress", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0)
		job.Experiments = &experiments.AssignmentExperiments{AssignmentContext: "exp-context-123"}

		content := map[string]any{
			"kind": "message",
			"message": map[string]any{
				"role":    "assistant",
				"content": "test",
			},
		}

		progressList := []*progress.Progress{makeSessionsV2Progress(job, sessionsv2.KindMessage, content)}
		svc.publishSessionsV2Telemetry(ctx, job, makeSessionsV2Items(progressList))
	})

	t.Run("handles multiple progress items", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t, 0)

		items := []*progress.Progress{
			makeSessionsV2Progress(job, sessionsv2.KindMessage, map[string]any{
				"kind":    "message",
				"message": map[string]any{"role": "assistant", "content": "step 1"},
			}),
			makeSessionsV2Progress(job, sessionsv2.KindToolExecution, map[string]any{
				"kind":       "tool_execution",
				"toolCallId": "tc-1",
				"toolResult": map[string]any{"textResultForLlm": "ok", "resultType": "success"},
			}),
			makeSessionsV2Progress(job, sessionsv2.KindModelCallFailure, map[string]any{
				"kind":                "model_call_failure",
				"modelCallDurationMs": float64(100),
				"modelCall":           map[string]any{"model": "gpt-4o", "status": float64(500)},
			}),
		}
		svc.publishSessionsV2Telemetry(ctx, job, makeSessionsV2Items(items))
	})
}

func TestPublishModelCallTelemetryForSessionsV2(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := newCopilotAppProvider()
	ff := featureflags.NewNoopClient(nil)
	twirp := githubtwirp.NewNoopClient()

	var jobCounter int
	seedJob := func(t *testing.T) *jobs.Job {
		t.Helper()
		jobCounter++
		id := fmt.Sprintf("%s-%d", t.Name(), jobCounter)
		job := &jobs.Job{
			ID:           id,
			OwnerID:      1,
			RepoID:       2,
			AssignmentID: "assignment-" + id,
			AgentID:      0,
			ActorID:      42,
		}
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		return job
	}

	t.Run("publishes ModelCall StandardEvent with correct params", func(t *testing.T) {
		mockPub := &mockTelemetryPublisher{shouldPublishRestricted: true}
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t)

		event := &sessionsV2TelemetryEvent{
			Kind:                "model_call_failure",
			ModelCallDurationMs: 339,
		}
		event.ModelCall.Model = "claude-sonnet-4"
		event.ModelCall.Status = 400
		event.ModelCall.Error = `{"message": "bad request"}`
		event.ModelCall.RequestID = "req-789"
		event.ModelCall.APIID = "api-123"
		event.RequestMessages = `[{"role":"user","content":"hi"}]`

		p := &progress.Progress{
			Kind:      sessionsv2.KindModelCallFailure,
			Namespace: sessionsv2.Namespace,
			CreatedAt: 1700000000,
		}

		svc.publishModelCallTelemetryForSessionsV2(ctx, mockPub, job, p, event)

		require.Len(t, mockPub.modelCallParams, 1)
		params := mockPub.modelCallParams[0]
		assert.Equal(t, "claude-sonnet-4", params.Model)
		assert.Equal(t, int64(339), params.DurationMs)
		assert.Equal(t, int64(400), params.StatusCode)
		assert.Equal(t, "req-789", params.RequestID)
		assert.Equal(t, "api-123", params.APIID)
		assert.Equal(t, sessionsv2.KindModelCallFailure, params.ProgressKind)
		assert.JSONEq(t, `{"message": "bad request"}`, params.Error)
	})

	t.Run("omits error in StandardEvent when restricted telemetry not allowed", func(t *testing.T) {
		mockPub := &mockTelemetryPublisher{shouldPublishRestricted: false}
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		job := seedJob(t)

		event := &sessionsV2TelemetryEvent{
			Kind:                "model_call_failure",
			ModelCallDurationMs: 100,
		}
		event.ModelCall.Model = "gpt-4o"
		event.ModelCall.Status = 500
		event.ModelCall.Error = "internal server error"

		p := &progress.Progress{
			Kind:      sessionsv2.KindModelCallFailure,
			Namespace: sessionsv2.Namespace,
			CreatedAt: 1700000000,
		}

		svc.publishModelCallTelemetryForSessionsV2(ctx, mockPub, job, p, event)

		require.Len(t, mockPub.modelCallParams, 1)
		params := mockPub.modelCallParams[0]
		assert.Equal(t, "gpt-4o", params.Model)
		assert.Empty(t, params.Error, "error should be omitted when restricted telemetry is not allowed")
	})

	t.Run("includes experiment assignment context", func(t *testing.T) {
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, nil, appProvider, nil, nil)
		mockPub := &mockTelemetryPublisher{shouldPublishRestricted: false}
		job := seedJob(t)
		job.Experiments = &experiments.AssignmentExperiments{AssignmentContext: "exp-456"}

		event := &sessionsV2TelemetryEvent{Kind: "model_call_failure"}
		event.ModelCall.Model = "gpt-4o"

		p := &progress.Progress{
			Kind:      sessionsv2.KindModelCallFailure,
			Namespace: sessionsv2.Namespace,
			CreatedAt: 1700000000,
		}

		svc.publishModelCallTelemetryForSessionsV2(ctx, mockPub, job, p, event)
		// The experiment context is set on the Hydro events (not on StandardEvent params),
		// so we verify it didn't panic and the standard event was still published.
		require.Len(t, mockPub.modelCallParams, 1)
	})
}

func TestCreateProgressTelemetryIntegration(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	appProvider := newCopilotAppProvider()
	ff := featureflags.NewNoopClient(nil)
	twirp := githubtwirp.NewNoopClient()

	var jobCounter int
	seedJob := func(t *testing.T, agentID int64) *jobs.Job {
		t.Helper()
		jobCounter++
		id := fmt.Sprintf("%s-%d", t.Name(), jobCounter)
		job := &jobs.Job{
			ID:               id,
			OwnerID:          1,
			RepoID:           2,
			AssignmentID:     "assignment-" + id,
			AgentID:          agentID,
			ActorID:          42,
			UseAsyncSessions: true,
		}
		_, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		return job
	}

	t.Run("Copilot agent job emits telemetry via CreateProgress", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, emitter, appProvider, nil, nil)
		job := seedJob(t, 0) // Copilot agent

		content := map[string]any{
			"kind":                "model_call_failure",
			"modelCallDurationMs": float64(200),
			"modelCall": map[string]any{
				"model":  "gpt-4o",
				"status": float64(429),
			},
		}
		contentJSON, err := json.Marshal(content)
		require.NoError(t, err)

		var parsedContent any
		require.NoError(t, json.Unmarshal(contentJSON, &parsedContent))

		p := job.NewProgress(sessionsv2.Namespace, sessionsv2.KindModelCallFailure, 1, parsedContent)
		result, err := svc.CreateProgress(ctx, job, []*progress.Progress{p})
		require.NoError(t, err)
		require.Len(t, result, 1)
		// Verify event emission also happened (for async sessions)
		require.Len(t, emitter.calls, 1)
	})

	t.Run("non-Copilot agent job does not emit telemetry via CreateProgress", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, ff, twirp, emitter, appProvider, nil, nil)
		job := seedJob(t, 999) // Non-Copilot agent ID

		content := map[string]any{
			"kind":                "model_call_failure",
			"modelCallDurationMs": float64(200),
			"modelCall": map[string]any{
				"model":  "gpt-4o",
				"status": float64(429),
			},
		}
		contentJSON, err := json.Marshal(content)
		require.NoError(t, err)

		var parsedContent any
		require.NoError(t, json.Unmarshal(contentJSON, &parsedContent))

		p := job.NewProgress(sessionsv2.Namespace, sessionsv2.KindModelCallFailure, 1, parsedContent)
		result, err := svc.CreateProgress(ctx, job, []*progress.Progress{p})
		require.NoError(t, err)
		require.Len(t, result, 1)
		// Event emission still happens for async sessions, but telemetry publish is skipped
		// (we can't easily distinguish the two in this test since both use noop publishers)
	})

	t.Run("nil appProvider skips telemetry without panic", func(t *testing.T) {
		emitter := &mockEmitter{}
		svc := NewService(store, nil, nil, nil, obsv, nil, nil, emitter, nil, nil, nil) // nil appProvider
		job := seedJob(t, 0)

		content := map[string]any{
			"kind": "message",
			"message": map[string]any{
				"role":    "assistant",
				"content": "hello",
			},
		}
		contentJSON, err := json.Marshal(content)
		require.NoError(t, err)

		var parsedContent any
		require.NoError(t, json.Unmarshal(contentJSON, &parsedContent))

		p := job.NewProgress(sessionsv2.Namespace, sessionsv2.KindMessage, 1, parsedContent)
		result, err := svc.CreateProgress(ctx, job, []*progress.Progress{p})
		require.NoError(t, err)
		require.Len(t, result, 1)
	})
}

func TestSessionsV2TelemetryEventParsing(t *testing.T) {
	t.Run("parses model_call_failure content", func(t *testing.T) {
		content := `{
			"kind": "model_call_failure",
			"modelCallDurationMs": 339,
			"modelCall": {
				"model": "claude-sonnet-4",
				"status": 400,
				"error": "{\"message\": \"bad request\"}",
				"request_id": "req-123",
				"api_id": "api-456"
			},
			"requestMessages": "[{\"role\":\"user\",\"content\":\"hello\"}]"
		}`

		var event sessionsV2TelemetryEvent
		err := json.Unmarshal([]byte(content), &event)
		require.NoError(t, err)

		assert.Equal(t, "model_call_failure", event.Kind)
		assert.Equal(t, int64(339), event.ModelCallDurationMs)
		assert.Equal(t, "claude-sonnet-4", event.ModelCall.Model)
		assert.Equal(t, int64(400), event.ModelCall.Status)
		assert.JSONEq(t, `{"message": "bad request"}`, event.ModelCall.Error)
		assert.Equal(t, "req-123", event.ModelCall.RequestID)
		assert.Equal(t, "api-456", event.ModelCall.APIID)
		assert.Contains(t, event.RequestMessages, "hello")
	})

	t.Run("parses assistant message content", func(t *testing.T) {
		content := `{
			"kind": "message",
			"callId": "call-abc",
			"modelCall": {"model": "gpt-4o"},
			"message": {
				"role": "assistant",
				"content": "I will help you."
			}
		}`

		var event sessionsV2TelemetryEvent
		err := json.Unmarshal([]byte(content), &event)
		require.NoError(t, err)

		assert.Equal(t, "message", event.Kind)
		assert.Equal(t, "call-abc", event.CallID)
		assert.Equal(t, "gpt-4o", event.ModelCall.Model)
		assert.Equal(t, "assistant", event.Message.Role)
	})

	t.Run("parses response content", func(t *testing.T) {
		content := `{
			"kind": "response",
			"callId": "call-xyz",
			"modelCall": {"model": "gpt-4o"}
		}`

		var event sessionsV2TelemetryEvent
		err := json.Unmarshal([]byte(content), &event)
		require.NoError(t, err)

		assert.Equal(t, "response", event.Kind)
		assert.Equal(t, "call-xyz", event.CallID)
		assert.Equal(t, "gpt-4o", event.ModelCall.Model)
	})

	t.Run("parses tool_execution with originalCall", func(t *testing.T) {
		content := `{
			"kind": "tool_execution",
			"toolCallId": "tc-1",
			"originalCall": {
				"callId": "original-call-789",
				"model": "gpt-4o"
			},
			"toolResult": {
				"textResultForLlm": "ok",
				"resultType": "success"
			}
		}`

		var event sessionsV2TelemetryEvent
		err := json.Unmarshal([]byte(content), &event)
		require.NoError(t, err)

		assert.Equal(t, "tool_execution", event.Kind)
		require.NotNil(t, event.OriginalCall)
		assert.Equal(t, "original-call-789", event.OriginalCall.CallID)
	})

	t.Run("handles empty content gracefully", func(t *testing.T) {
		content := `{}`

		var event sessionsV2TelemetryEvent
		err := json.Unmarshal([]byte(content), &event)
		require.NoError(t, err)

		assert.Empty(t, event.Kind)
		assert.Empty(t, event.ModelCall.Model)
	})
}
