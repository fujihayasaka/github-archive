package memoryhttp

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
)

func newKillSwitchTestHarness(t *testing.T, ffClient featureflags.Client) (*MemoryHandler, chi.Router) {
	t.Helper()

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:           &MockMemoryService{},
		GHFactory:         &github.NoopClientFactory{},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
	})

	r := chi.NewRouter()
	r.Route("/memory/v0", func(r chi.Router) {
		r.Use(handler.withMemoryRequest())
		r.Use(handler.withIntegrationKillSwitch())
		r.Get("/echo", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("ok"))
		})
	})

	return handler, r
}

func TestIntegrationKillSwitch_VSCodeBlocked(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryDisabledVSCode: true,
	})

	_, router := newKillSwitchTestHarness(t, ffClient)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/echo", "")
	req.Header.Set(capi.IntegrationIDHeader, "vscode-chat")

	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	assert.Equal(t, http.StatusForbidden, rr.Code)
	assert.Contains(t, rr.Body.String(), "memory is disabled for this client")
}

func TestIntegrationKillSwitch_VSCodeDevBlocked(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryDisabledVSCode: true,
	})

	_, router := newKillSwitchTestHarness(t, ffClient)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/echo", "")
	req.Header.Set(capi.IntegrationIDHeader, "vscode-chat-dev")

	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	assert.Equal(t, http.StatusForbidden, rr.Code)
}

func TestIntegrationKillSwitch_VSCodeAllowedWhenFlagDisabled(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryDisabledVSCode: false,
	})

	_, router := newKillSwitchTestHarness(t, ffClient)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/echo", "")
	req.Header.Set(capi.IntegrationIDHeader, "vscode-chat")

	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	assert.Equal(t, "ok", rr.Body.String())
}

func TestIntegrationKillSwitch_NonVSCodeUnaffected(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryDisabledVSCode: true,
	})

	_, router := newKillSwitchTestHarness(t, ffClient)

	integrations := []string{"copilot-developer", "copilot-developer-cli", "claude-code", "copilot-pr-reviews"}
	for _, integration := range integrations {
		t.Run(integration, func(t *testing.T) {
			ctx := createTestContext()
			req := createTestRequest(ctx, "GET", "/memory/v0/echo", "")
			req.Header.Set(capi.IntegrationIDHeader, integration)

			rr := httptest.NewRecorder()
			router.ServeHTTP(rr, req)

			assert.Equal(t, http.StatusOK, rr.Code)
		})
	}
}

func TestIntegrationKillSwitch_NoIntegrationIDPassesThrough(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryDisabledVSCode: true,
	})

	_, router := newKillSwitchTestHarness(t, ffClient)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/echo", "")

	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestIntegrationKillSwitch_NilFeatureFlagClientPassesThrough(t *testing.T) {
	_, router := newKillSwitchTestHarness(t, nil)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/echo", "")
	req.Header.Set(capi.IntegrationIDHeader, "vscode-chat")

	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}
