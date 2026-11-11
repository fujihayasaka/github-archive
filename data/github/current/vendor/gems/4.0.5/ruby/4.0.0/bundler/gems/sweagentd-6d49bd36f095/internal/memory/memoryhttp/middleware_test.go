package memoryhttp

import (
	"context"
	"maps"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// recordingStatter captures Counter/DistributionMs calls so tests can assert on
// the metrics emitted by the middleware.
type recordingStatter struct {
	stats.NullClient

	mu       sync.Mutex
	counters []recordedMetric
	dists    []recordedDistribution
}

type recordedMetric struct {
	key  string
	tags stats.Tags
}

type recordedDistribution struct {
	key      string
	tags     stats.Tags
	duration time.Duration
}

func (s *recordingStatter) Counter(key string, tags stats.Tags, _ int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.counters = append(s.counters, recordedMetric{key: key, tags: cloneTags(tags)})
}

func (s *recordingStatter) DistributionMs(key string, tags stats.Tags, duration time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.dists = append(s.dists, recordedDistribution{key: key, tags: cloneTags(tags), duration: duration})
}

func (s *recordingStatter) WithTags(tags stats.Tags) stats.Client { return s }

func (s *recordingStatter) countersFor(key string) []recordedMetric {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []recordedMetric
	for _, c := range s.counters {
		if c.key == key {
			out = append(out, c)
		}
	}
	return out
}

func (s *recordingStatter) distributionsFor(key string) []recordedDistribution {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []recordedDistribution
	for _, d := range s.dists {
		if d.key == key {
			out = append(out, d)
		}
	}
	return out
}

func cloneTags(tags stats.Tags) stats.Tags {
	out := make(stats.Tags, len(tags))
	maps.Copy(out, tags)
	return out
}

// middlewareTestHarness wires a MemoryHandler with a recording statter behind
// a chi router that exposes two routes under /memory/v0:
//   - GET /echo/{id}         invokes the caller-supplied handler
//   - GET /requestctx        reports whether requestctx start time was set
//
// The harness gives each test full control over the handler while letting the
// middleware do its real work.
type middlewareTestHarness struct {
	handler *MemoryHandler
	router  chi.Router
	statter *recordingStatter
}

func newMiddlewareTestHarness(t *testing.T, inner http.HandlerFunc) *middlewareTestHarness {
	t.Helper()

	statter := &recordingStatter{}
	obsv := observability.NewNoopExporters()
	obsv.Statter = statter

	mockGHFactory := &github.NoopClientFactory{}
	appProvider := agenticapptest.NewTestProvider(t)
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     &MockMemoryService{},
		GHFactory:   mockGHFactory,
		Obsv:        obsv,
		AppProvider: appProvider,
	})

	r := chi.NewRouter()
	r.Route("/memory/v0", func(r chi.Router) {
		r.Use(handler.withMemoryRequest())
		r.Get("/echo/{id}", inner)
	})

	return &middlewareTestHarness{
		handler: handler,
		router:  r,
		statter: statter,
	}
}

// doRequest runs a GET against the harness router, wrapping the context with
// requestctx so the middleware can record the start time.
func doRequest(t *testing.T, h *middlewareTestHarness, path, integrationID string) *httptest.ResponseRecorder {
	t.Helper()

	req := httptest.NewRequest(http.MethodGet, path, http.NoBody)
	req = req.WithContext(requestctx.NewContext(req.Context()))
	if integrationID != "" {
		req.Header.Set(capi.IntegrationIDHeader, integrationID)
	}

	rr := httptest.NewRecorder()
	h.router.ServeHTTP(rr, req)
	return rr
}

// assertTagsContain verifies every expected tag is present with the expected value.
func assertTagsContain(t *testing.T, got stats.Tags, want map[string]string) {
	t.Helper()
	for k, v := range want {
		assert.Equalf(t, v, got[k], "tag %q", k)
	}
}

func TestWithMemoryRequest_SuccessResponse(t *testing.T) {
	var (
		observedCtxIntegrationID string
		observedStartTime        time.Time
		observedStartOK          bool
	)

	h := newMiddlewareTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		observedCtxIntegrationID = featureflags.IntegrationIDFromContext(r.Context())
		st, ok := requestctx.RequestStartedAt(r.Context())
		observedStartOK = ok
		if ok {
			observedStartTime = *st
		}
		w.WriteHeader(http.StatusOK)
	})

	rr := doRequest(t, h, "/memory/v0/echo/42", "copilot-developer")

	require.Equal(t, http.StatusOK, rr.Code)

	// Handler saw the integration ID seeded into ctx and the request start time.
	assert.Equal(t, "copilot-developer", observedCtxIntegrationID)
	assert.True(t, observedStartOK, "request start time should be set on ctx")
	assert.WithinDuration(t, time.Now(), observedStartTime, 2*time.Second)

	// Entry metric: request_count is emitted once with endpoint + method + integration id.
	counts := h.statter.countersFor(metricRequestCount)
	require.Len(t, counts, 1)
	assertTagsContain(t, counts[0].tags, map[string]string{
		"endpoint":               "/memory/v0/echo/:id",
		"method":                 http.MethodGet,
		"copilot_integration_id": "copilot-developer",
	})

	// Completion metrics: duration + status + outcome with success.
	dists := h.statter.distributionsFor(metricRequestDuration)
	require.Len(t, dists, 1)
	assertTagsContain(t, dists[0].tags, map[string]string{
		"endpoint":               "/memory/v0/echo/:id",
		"method":                 http.MethodGet,
		"copilot_integration_id": "copilot-developer",
	})
	assert.GreaterOrEqual(t, dists[0].duration, time.Duration(0))

	statuses := h.statter.countersFor(metricResponseStatus)
	require.Len(t, statuses, 1)
	assertTagsContain(t, statuses[0].tags, map[string]string{
		"endpoint":     "/memory/v0/echo/:id",
		"method":       http.MethodGet,
		"status_code":  "200",
		"status_class": "2xx",
	})

	outcomes := h.statter.countersFor(metricRequestOutcome)
	require.Len(t, outcomes, 1)
	assertTagsContain(t, outcomes[0].tags, map[string]string{
		"endpoint": "/memory/v0/echo/:id",
		"method":   http.MethodGet,
		"outcome":  outcomeSuccess,
	})
}

func TestWithMemoryRequest_RuntimeVersionTagged(t *testing.T) {
	h := newMiddlewareTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/memory/v0/echo/1", http.NoBody)
	req = req.WithContext(requestctx.NewContext(req.Context()))
	req.Header.Set(RuntimeClientVersionHeaderName, "1.2.3")

	rr := httptest.NewRecorder()
	h.router.ServeHTTP(rr, req)
	require.Equal(t, http.StatusOK, rr.Code)

	for _, metric := range []string{metricRequestCount, metricResponseStatus, metricRequestOutcome} {
		counters := h.statter.countersFor(metric)
		require.Lenf(t, counters, 1, "metric %q", metric)
		assert.Equalf(t, "1.2.3", counters[0].tags["copilot_agent_runtime_version"], "metric %q", metric)
	}
	dists := h.statter.distributionsFor(metricRequestDuration)
	require.Len(t, dists, 1)
	assert.Equal(t, "1.2.3", dists[0].tags["copilot_agent_runtime_version"])
}

func TestWithMemoryRequest_ClientErrorStatus(t *testing.T) {
	h := newMiddlewareTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "bad request", http.StatusBadRequest)
	})

	rr := doRequest(t, h, "/memory/v0/echo/1", "")
	require.Equal(t, http.StatusBadRequest, rr.Code)

	statuses := h.statter.countersFor(metricResponseStatus)
	require.Len(t, statuses, 1)
	assertTagsContain(t, statuses[0].tags, map[string]string{
		"status_code":  "400",
		"status_class": "4xx",
	})

	outcomes := h.statter.countersFor(metricRequestOutcome)
	require.Len(t, outcomes, 1)
	assert.Equal(t, outcomeFailure, outcomes[0].tags["outcome"])
}

func TestWithMemoryRequest_ServerErrorStatus(t *testing.T) {
	h := newMiddlewareTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	})

	rr := doRequest(t, h, "/memory/v0/echo/1", "")
	require.Equal(t, http.StatusInternalServerError, rr.Code)

	statuses := h.statter.countersFor(metricResponseStatus)
	require.Len(t, statuses, 1)
	assertTagsContain(t, statuses[0].tags, map[string]string{
		"status_code":  "500",
		"status_class": "5xx",
	})

	outcomes := h.statter.countersFor(metricRequestOutcome)
	require.Len(t, outcomes, 1)
	assert.Equal(t, outcomeFailure, outcomes[0].tags["outcome"])
}

func TestWithMemoryRequest_OverriddenOutcome(t *testing.T) {
	// Handlers can override the derived outcome (e.g., partial success) via setRequestOutcome.
	h := newMiddlewareTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		setRequestOutcome(r.Context(), outcomePartial)
		w.WriteHeader(http.StatusOK)
	})

	rr := doRequest(t, h, "/memory/v0/echo/1", "")
	require.Equal(t, http.StatusOK, rr.Code)

	outcomes := h.statter.countersFor(metricRequestOutcome)
	require.Len(t, outcomes, 1)
	assert.Equal(t, outcomePartial, outcomes[0].tags["outcome"])
}

func TestWithMemoryRequest_SetRequestTags(t *testing.T) {
	// Handlers can attach per-request tags (e.g., voting_enabled) via addRequestTags;
	// the middleware merges them into all completion metrics.
	h := newMiddlewareTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		addRequestTags(r.Context(), map[string]string{"voting_enabled": "true"})
		w.WriteHeader(http.StatusOK)
	})

	rr := doRequest(t, h, "/memory/v0/echo/1", "")
	require.Equal(t, http.StatusOK, rr.Code)

	for _, metric := range []string{metricRequestCount, metricResponseStatus, metricRequestOutcome} {
		entries := h.statter.countersFor(metric)
		require.Len(t, entries, 1, metric)
		assert.Equal(t, "true", entries[0].tags["voting_enabled"], metric)
	}
	dists := h.statter.distributionsFor(metricRequestDuration)
	require.Len(t, dists, 1)
	assert.Equal(t, "true", dists[0].tags["voting_enabled"])
}

func TestWithMemoryRequest_RecoversFromPanic(t *testing.T) {
	h := newMiddlewareTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		panic("boom")
	})

	// The middleware finishes telemetry before re-panicking; wrap the router call
	// so the test doesn't abort.
	func() {
		defer func() {
			rec := recover()
			assert.Equal(t, "boom", rec, "middleware should re-raise the original panic")
		}()
		doRequest(t, h, "/memory/v0/echo/1", "")
	}()

	statuses := h.statter.countersFor(metricResponseStatus)
	require.Len(t, statuses, 1)
	assertTagsContain(t, statuses[0].tags, map[string]string{
		"status_code":  "500",
		"status_class": "5xx",
	})

	outcomes := h.statter.countersFor(metricRequestOutcome)
	require.Len(t, outcomes, 1)
	assert.Equal(t, outcomeFailure, outcomes[0].tags["outcome"])
}

func TestWithMemoryRequest_RequestLoggerAccessibleFromHandler(t *testing.T) {
	var (
		h            *middlewareTestHarness
		stateLogger  log.Logger
		stateRouteOK bool
	)
	inner := func(w http.ResponseWriter, r *http.Request) {
		state, ok := memoryRequestFromContext(r.Context())
		require.True(t, ok)
		stateLogger = state.logger
		// The handler-level logger is obtained via requestLogger; smoke-test it
		// does not panic and returns a non-nil logger.
		assert.NotNil(t, h.handler.requestLogger(r.Context()))
		// state.r must be populated so requestLogger can resolve the route lazily.
		stateRouteOK = state.r != nil
		w.WriteHeader(http.StatusOK)
	}
	h = newMiddlewareTestHarness(t, inner)

	doRequest(t, h, "/memory/v0/echo/1", "integration-xyz")
	require.NotNil(t, stateLogger, "middleware should stash a per-request logger in state")
	assert.True(t, stateRouteOK, "middleware should stash the request so requestLogger can lazily resolve http.route")
}

func TestRequestLogger_FallsBackWhenNoState(t *testing.T) {
	h := newMiddlewareTestHarness(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	got := h.handler.requestLogger(t.Context())
	assert.Equal(t, h.handler.obsv.Logger, got)
}

func TestMemoryRequestEndpoint(t *testing.T) {
	// Build a mini chi router so we exercise the actual route-matching logic.
	var captured string
	r := chi.NewRouter()
	capture := func(w http.ResponseWriter, req *http.Request) {
		captured = memoryRequestEndpoint(req)
		w.WriteHeader(http.StatusOK)
	}

	r.Get("/a/{id}", capture)
	r.Get("/", capture)
	r.Route("/nested/", func(r chi.Router) {
		r.Get("/leaf", capture)
	})

	tests := []struct {
		name string
		path string
		want string
	}{
		{"parameterized", "/a/42", "/a/:id"},
		{"root", "/", "/"},
		{"nested_trims_trailing_slash", "/nested/leaf", "/nested/leaf"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			rr := httptest.NewRecorder()
			r.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, tc.path, http.NoBody))
			require.Equal(t, http.StatusOK, rr.Code)
			assert.Equal(t, tc.want, captured)
		})
	}
}

func TestMemoryRequestEndpoint_Unrouted(t *testing.T) {
	// When called outside a chi route context, ghchi.Route returns the literal
	// "unknownroute" sentinel; memoryRequestEndpoint passes it through.
	req := httptest.NewRequest(http.MethodGet, "/anything", http.NoBody)
	assert.Equal(t, "unknownroute", memoryRequestEndpoint(req))
}

func TestMemoryRequestMetricTags(t *testing.T) {
	t.Run("returns nil when no state or tags or integration id", func(t *testing.T) {
		got := memoryRequestMetricTags(t.Context(), nil)
		assert.Nil(t, got)
	})

	t.Run("copies state fields and integration id", func(t *testing.T) {
		ctx := t.Context()
		ctx = featureflags.ContextWithIntegrationID(ctx, "copilot-developer")
		state := &memoryRequestState{endpoint: "/memory/v0/echo/:id", method: http.MethodGet, runtimeVersion: "1.2.3"}
		ctx = contextWithMemoryRequestStateForTest(ctx, state)

		got := memoryRequestMetricTags(ctx, nil)
		assert.Equal(t, map[string]string{
			"endpoint":                      "/memory/v0/echo/:id",
			"method":                        http.MethodGet,
			"copilot_integration_id":        "copilot-developer",
			"copilot_agent_runtime_version": "1.2.3",
		}, got)
	})

	t.Run("omits integration id and runtime version when empty", func(t *testing.T) {
		ctx := t.Context()
		state := &memoryRequestState{endpoint: "/memory/v0/echo/:id", method: http.MethodGet}
		ctx = contextWithMemoryRequestStateForTest(ctx, state)

		got := memoryRequestMetricTags(ctx, nil)
		assert.Equal(t, map[string]string{
			"endpoint": "/memory/v0/echo/:id",
			"method":   http.MethodGet,
		}, got)
	})

	t.Run("caller tags override seeded ones", func(t *testing.T) {
		ctx := t.Context()
		ctx = featureflags.ContextWithIntegrationID(ctx, "copilot-developer")
		state := &memoryRequestState{endpoint: "/memory/v0/echo/:id", method: http.MethodGet}
		ctx = contextWithMemoryRequestStateForTest(ctx, state)

		got := memoryRequestMetricTags(ctx, map[string]string{
			"endpoint": "override",
			"extra":    "yes",
		})
		assert.Equal(t, "override", got["endpoint"])
		assert.Equal(t, "yes", got["extra"])
		assert.Equal(t, "copilot-developer", got["copilot_integration_id"])
	})

	t.Run("merges extra tags stashed via addRequestTags", func(t *testing.T) {
		ctx := t.Context()
		state := &memoryRequestState{endpoint: "/memory/v0/echo/:id", method: http.MethodGet}
		ctx = contextWithMemoryRequestStateForTest(ctx, state)
		addRequestTags(ctx, map[string]string{"voting_enabled": "true"})

		got := memoryRequestMetricTags(ctx, nil)
		assert.Equal(t, "true", got["voting_enabled"])
	})

	t.Run("caller tags override extra tags", func(t *testing.T) {
		ctx := t.Context()
		state := &memoryRequestState{endpoint: "/memory/v0/echo/:id", method: http.MethodGet}
		ctx = contextWithMemoryRequestStateForTest(ctx, state)
		addRequestTags(ctx, map[string]string{"voting_enabled": "true"})

		got := memoryRequestMetricTags(ctx, map[string]string{"voting_enabled": "false"})
		assert.Equal(t, "false", got["voting_enabled"])
	})
}

func TestOutcomeFromStatusCode(t *testing.T) {
	tests := []struct {
		statusCode int
		want       string
	}{
		{http.StatusOK, outcomeSuccess},
		{http.StatusNoContent, outcomeSuccess},
		{http.StatusMovedPermanently, outcomeFailure},
		{http.StatusBadRequest, outcomeFailure},
		{http.StatusInternalServerError, outcomeFailure},
	}
	for _, tc := range tests {
		assert.Equalf(t, tc.want, outcomeFromStatusCode(tc.statusCode), "status %d", tc.statusCode)
	}
}

func TestStatusClass(t *testing.T) {
	tests := []struct {
		statusCode int
		want       string
	}{
		{http.StatusContinue, "other"},
		{http.StatusOK, "2xx"},
		{http.StatusFound, "other"},
		{http.StatusBadRequest, "4xx"},
		{http.StatusInternalServerError, "5xx"},
	}
	for _, tc := range tests {
		assert.Equalf(t, tc.want, statusClass(tc.statusCode), "status %d", tc.statusCode)
	}
}

// contextWithMemoryRequestStateForTest attaches a middleware request-state
// value to ctx so helpers that depend on it can be exercised in isolation.
func contextWithMemoryRequestStateForTest(ctx context.Context, state *memoryRequestState) context.Context {
	return context.WithValue(ctx, memoryRequestStateKey{}, state)
}
