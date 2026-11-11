package memoryhttp

import (
	"context"
	"maps"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/api"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/ghchi"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// memoryRequestSpanName is the operation name for the server-side span.
const memoryRequestSpanName = "memory.http.request"

// Tag/attribute/log-field keys used across spans, metrics, and loggers.
const (
	tagKeyIntegrationID  = core.TagKeyIntegrationID
	tagKeyRuntimeVersion = core.TagKeyRuntimeVersion
)

// Outcome values for metricRequestOutcome.
const (
	outcomeSuccess = "success"
	outcomeFailure = "failure"
	outcomePartial = "partial"
)

type memoryRequestStateKey struct{}

type memoryRequestState struct {
	endpoint       string
	method         string
	outcome        string
	runtimeVersion string
	extraTags      map[string]string
	logger         log.Logger
	span           trace.Span
	rw             *api.ResponseWrapper
	r              *http.Request
}

// withMemoryRequest starts the server-side span, stashes per-request state in ctx, wraps the ResponseWriter to capture the status code, logs a request-start entry, and defers completion telemetry (span end, metrics, completion log).
func (h *MemoryHandler) withMemoryRequest() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			ctx, span := h.obsv.Tracer.Start(r.Context(), memoryRequestSpanName)
			defer span.End()

			span.SetAttributes(attribute.String("http.method", r.Method))

			integrationID := r.Header.Get(capi.IntegrationIDHeader)
			ctx = featureflags.ContextWithIntegrationID(ctx, integrationID)
			if integrationID != "" {
				span.SetAttributes(attribute.String(tagKeyIntegrationID, integrationID))
			}

			runtimeVersion := r.Header.Get(RuntimeClientVersionHeaderName)
			if runtimeVersion != "" {
				span.SetAttributes(attribute.String(tagKeyRuntimeVersion, runtimeVersion))
			}

			rw := api.NewResponseWrapper(w)
			state := &memoryRequestState{
				method:         r.Method,
				runtimeVersion: runtimeVersion,
				span:           span,
				rw:             rw,
			}
			ctx = context.WithValue(ctx, memoryRequestStateKey{}, state)
			r = r.WithContext(ctx)
			state.r = r
			// http.route is resolved at completion time because chi may not have
			// matched the final pattern yet when the middleware is mounted under r.Route.
			loggerFields := []kvp.Field{kvp.String("http.method", r.Method)}
			if integrationID != "" {
				loggerFields = append(loggerFields, kvp.String(tagKeyIntegrationID, integrationID))
			}
			if runtimeVersion != "" {
				loggerFields = append(loggerFields, kvp.String(tagKeyRuntimeVersion, runtimeVersion))
			}
			state.logger = h.obsv.LoggerWithRequestTelemetry(ctx, r).WithFields(loggerFields...)

			err := requestctx.AddRequestStartedAt(ctx, start)
			if err != nil {
				// requestctx must be initialized upstream; if not, helpers that
				// rely on RequestStartedAt silently fall back to time.Now().
				state.logger.WithError(err).Warn("failed to record request start time")
			}

			state.logger.Info("memory request started")

			defer func() {
				rec := recover()
				if rec != nil {
					if !rw.WroteHeader {
						rw.StatusCode = http.StatusInternalServerError
					}
					state.outcome = outcomeFailure
					err := goerrors.Errorf("panic: %v", rec)
					span.RecordError(err)
					span.SetStatus(codes.Error, err.Error())
					h.requestLogger(ctx).WithError(err).Error("memory request panicked")
				}
				h.finishMemoryRequest(ctx)
				// Re-raise so any outer recoverer still writes the response and logs the stack trace.
				if rec != nil {
					panic(rec)
				}
			}()

			next.ServeHTTP(rw, r)
		})
	}
}

// withIntegrationKillSwitch returns a middleware that rejects requests when
// memory is disabled for the requesting client integration (e.g. VS Code).
// It checks the per-client feature flag resolved from the integration ID
// that was stashed in the context by withMemoryRequest.
//
// NOTE: This is best-effort — it relies on clients sending the integration ID
// header (Copilot-Integration-Id). If the header is absent, the flag lookup is
// skipped and the request proceeds normally. Keep this in mind when using this
// as an incident kill switch.
func (h *MemoryHandler) withIntegrationKillSwitch() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := r.Context()
			if h.checkIntegrationMemoryDisabled(ctx) {
				h.requestLogger(ctx).Info("memory disabled for integration (kill switch)")
				http.Error(w, "memory is disabled for this client", http.StatusForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// finishMemoryRequest annotates the span with the final status and emits request-completion telemetry.
func (h *MemoryHandler) finishMemoryRequest(ctx context.Context) {
	state, ok := memoryRequestFromContext(ctx)
	if !ok {
		return
	}
	rw := state.rw

	// Resolve endpoint now that chi has matched the final route.
	state.endpoint = memoryRequestEndpoint(state.r)
	state.span.SetAttributes(
		attribute.String("http.route", state.endpoint),
		attribute.Int("http.status_code", rw.StatusCode),
	)
	if rw.StatusCode >= 500 {
		state.span.SetStatus(codes.Error, http.StatusText(rw.StatusCode))
	}

	outcome := state.outcome
	if outcome == "" {
		outcome = outcomeFromStatusCode(rw.StatusCode)
	}

	duration := time.Since(requestctx.RequestStartedAtOrNow(ctx))

	h.obsv.Increment(ctx, metricRequestCount, memoryRequestMetricTags(ctx, nil))

	h.obsv.DistributionMs(ctx, metricRequestDuration, memoryRequestMetricTags(ctx, nil), duration)

	h.obsv.Increment(ctx, metricResponseStatus, memoryRequestMetricTags(ctx, map[string]string{
		"status_code":  strconv.Itoa(rw.StatusCode),
		"status_class": statusClass(rw.StatusCode),
	}))

	// Outcome drives the success-rate SLO; handlers may call setRequestOutcome to
	// override the status-derived value (e.g., outcomePartial for soft failures).
	h.obsv.Increment(ctx, metricRequestOutcome, memoryRequestMetricTags(ctx, map[string]string{
		"outcome": outcome,
	}))

	logFields := []kvp.Field{
		kvp.Int64("duration_ms", duration.Milliseconds()),
		kvp.Int("http.status_code", rw.StatusCode),
	}
	if rw.ErrMsg != "" {
		logFields = append(logFields, kvp.String("exception.message", rw.ErrMsg))
	}

	h.requestLogger(ctx).WithFields(logFields...).Info("memory request completed")
}

func (h *MemoryHandler) requestLogger(ctx context.Context) log.Logger {
	state, ok := memoryRequestFromContext(ctx)
	if !ok || state.logger == nil {
		return h.obsv.Logger
	}
	// http.route is resolved lazily because chi may not have matched the final
	// pattern when the logger was constructed (middleware attached under r.Route).
	// By the time handlers call requestLogger, chi has matched the leaf route.
	if state.r != nil {
		return state.logger.WithFields(kvp.String("http.route", memoryRequestEndpoint(state.r)))
	}
	return state.logger
}

func memoryRequestFromContext(ctx context.Context) (*memoryRequestState, bool) {
	state, ok := ctx.Value(memoryRequestStateKey{}).(*memoryRequestState)
	return state, ok && state != nil
}

// memoryRequestEndpoint returns the normalized chi route pattern.
func memoryRequestEndpoint(r *http.Request) string {
	route := ghchi.Route(r)
	normalized := strings.TrimSuffix(route, "/")
	if normalized == "" {
		return "/"
	}
	return normalized
}

// memoryRequestMetricTags seeds endpoint/method/integration_id/runtime_version and any handler-set
// extras from ctx, then applies caller-provided tags last so direct callers can override.
func memoryRequestMetricTags(ctx context.Context, tags map[string]string) map[string]string {
	state, ok := memoryRequestFromContext(ctx)

	// Start with integration ID from core (applies allow-list filtering).
	merged := core.MetricTags(ctx, nil)

	if !ok && merged == nil && len(tags) == 0 {
		return nil
	}

	if merged == nil {
		merged = make(map[string]string, len(tags)+4)
	}

	if ok {
		if state.endpoint != "" {
			merged["endpoint"] = state.endpoint
		}
		if state.method != "" {
			merged["method"] = state.method
		}
		if state.runtimeVersion != "" {
			merged[tagKeyRuntimeVersion] = state.runtimeVersion
		}
		maps.Copy(merged, state.extraTags)
	}
	maps.Copy(merged, tags)
	return merged
}

// setRequestOutcome overrides the status-code-derived outcome for the current request.
func setRequestOutcome(ctx context.Context, outcome string) {
	if state, ok := memoryRequestFromContext(ctx); ok {
		state.outcome = outcome
	}
}

// addRequestTags attaches additional tags to the current request's completion metrics.
// Handlers use it to record dimensions resolved mid-request (e.g., voting_enabled).
func addRequestTags(ctx context.Context, tags map[string]string) {
	if len(tags) == 0 {
		return
	}
	state, ok := memoryRequestFromContext(ctx)
	if !ok {
		return
	}
	if state.extraTags == nil {
		state.extraTags = make(map[string]string, len(tags))
	}
	maps.Copy(state.extraTags, tags)
}

func outcomeFromStatusCode(statusCode int) string {
	switch {
	case statusCode >= 200 && statusCode < 300:
		return outcomeSuccess
	default:
		return outcomeFailure
	}
}

func statusClass(statusCode int) string {
	switch {
	case statusCode >= 200 && statusCode < 300:
		return "2xx"
	case statusCode >= 400 && statusCode < 500:
		return "4xx"
	case statusCode >= 500:
		return "5xx"
	default:
		return "other"
	}
}
