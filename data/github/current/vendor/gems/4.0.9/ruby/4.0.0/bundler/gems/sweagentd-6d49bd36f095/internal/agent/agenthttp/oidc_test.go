package agenthttp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/github/sweagentd/internal/agent"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/auth/oidc"
	"github.com/github/sweagentd/internal/auth/oidc/devsigner"
	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- helpers ---

func oidcDefaultFlags() map[string]bool {
	return map[string]bool{
		featureflags.CopilotSWEAgentOIDCTokenExchange:           true,
		featureflags.CopilotSWEAgentSkipCallbackEnablementCheck: true,
	}
}

func newOIDCTestHandler(t *testing.T, ffOverrides map[string]bool, isAgentEnabled bool) (*Handler, *memory.Store, *github.NoopClientFactory) {
	t.Helper()

	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: isAgentEnabled}
	spokes := customagenttest.MakeSpokes(t, map[string]string{})
	ffClient := featureflags.NewNoopClient(ffOverrides)
	customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)
	pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")

	signer, err := devsigner.NewSignerFromKey("https://test-issuer", nil)
	require.NoError(t, err)
	oidcSvc := oidc.NewLocalService(ffClient, signer, obsv, oidc.ServiceConfig{})

	h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), oidcSvc, "")
	return h, store, cf
}

func seedOIDCJob(t *testing.T, store *memory.Store, nonce string) *jobs.Job {
	t.Helper()
	return seedOIDCJobWithAgentID(t, store, nonce, 0)
}

func seedOIDCJobWithAgentID(t *testing.T, store *memory.Store, nonce string, agentID int64) *jobs.Job {
	t.Helper()
	job := &jobs.Job{
		ID:        "1-2-oidc-uuid",
		OwnerID:   1,
		RepoID:    2,
		NonceHash: jobs.HashNonce(nonce),
		AgentID:   agentID,
	}
	_, err := store.CreateJob(context.Background(), job)
	require.NoError(t, err)
	return job
}

func oidcBaseCtx(cf *github.NoopClientFactory) context.Context {
	return requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:    123,
			Login: "test-user",
			TokenInfo: &requestctx.TokenInfo{
				ApplicationID: uint64(cf.AppID()),
			},
		},
	})
}

func makeOIDCRequest(ctx context.Context, t *testing.T, jobID, nonce string, body io.Reader) *http.Request {
	t.Helper()
	req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/agent/jobs/"+jobID+"/tokens", body)
	if jobID != "" {
		req = muxSetParam(req, "jobID", jobID)
	}
	if nonce != "" {
		req.Header.Set(jobs.JobNonceHeader, nonce)
	}
	return req
}

func mustMarshalJSON(t *testing.T, v any) string {
	t.Helper()
	data, err := json.Marshal(v)
	require.NoError(t, err)
	return string(data)
}

// --- response codes ---

type oidcResponseCodeCase struct {
	name         string
	arrange      func(t *testing.T) (*Handler, *http.Request)
	wantStatuses []int
	wantBody     string
}

func runOIDCResponseCodeCases(t *testing.T, cases []oidcResponseCodeCase) {
	t.Helper()
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			h, req := tt.arrange(t)
			w := httptest.NewRecorder()
			h.exchangeTokens(w, req)
			assert.Contains(t, tt.wantStatuses, w.Code, "unexpected status code %d", w.Code)
			if tt.wantBody != "" {
				assert.Contains(t, w.Body.String(), tt.wantBody)
			}
		})
	}
}

func TestExchangeTokens_ResponseCodes(t *testing.T) {
	const validNonce = "test-nonce"

	t.Run("authentication", func(t *testing.T) {
		runOIDCResponseCodeCases(t, []oidcResponseCodeCase{
			{
				name: "missing user context",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, _, _ := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					return h, makeOIDCRequest(context.Background(), t, "1-2-uuid", "", http.NoBody)
				},
				wantStatuses: []int{http.StatusUnauthorized},
			},
			{
				name: "wrong application ID",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, _, _ := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
						UserInfo: &requestctx.UserInfo{
							ID:    1,
							Login: "user",
							TokenInfo: &requestctx.TokenInfo{
								ApplicationID: 9999,
							},
						},
					})
					return h, makeOIDCRequest(ctx, t, "1-2-uuid", "", http.NoBody)
				},
				wantStatuses: []int{http.StatusUnauthorized},
			},
		})
	})

	t.Run("nonce validation", func(t *testing.T) {
		runOIDCResponseCodeCases(t, []oidcResponseCodeCase{
			{
				name: "missing nonce",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					job := seedOIDCJob(t, store, "correct-nonce")
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, "", http.NoBody)
				},
				wantStatuses: []int{http.StatusUnauthorized},
			},
			{
				name: "wrong nonce",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					job := seedOIDCJob(t, store, "correct-nonce")
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, "wrong-nonce", http.NoBody)
				},
				wantStatuses: []int{http.StatusUnauthorized},
			},
		})
	})

	t.Run("job ID validation", func(t *testing.T) {
		runOIDCResponseCodeCases(t, []oidcResponseCodeCase{
			{
				name: "missing job ID",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, _, cf := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, "", "", http.NoBody)
				},
				wantStatuses: []int{http.StatusBadRequest},
				wantBody:     "job_id is required",
			},
			{
				name: "invalid format",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, _, cf := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, "bad-id", "", http.NoBody)
				},
				wantStatuses: []int{http.StatusBadRequest},
			},
		})
	})

	t.Run("job not found", func(t *testing.T) {
		runOIDCResponseCodeCases(t, []oidcResponseCodeCase{
			{
				name: "job does not exist",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					flags := oidcDefaultFlags()
					obsv := observability.NewNoopExporters()
					cf := &github.NoopClientFactory{}
					noopClient := githubtwirp.NewNoopClient()
					noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
					spokes := customagenttest.MakeSpokes(t, map[string]string{})
					ffClient := featureflags.NewNoopClient(flags)
					customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)

					signer, err := devsigner.NewSignerFromKey("https://test-issuer", nil)
					require.NoError(t, err)
					oidcSvc := oidc.NewLocalService(ffClient, signer, obsv, oidc.ServiceConfig{})

					nfSvc := agent.NewService(&notFoundStore{}, cf, customAgentSvc, nil, obsv, ffClient, noopClient, nil, agenticapptest.NewTestProvider(t), nil, oidcSvc)
					h, _, _ := newOIDCTestHandler(t, flags, true)
					hCopy := *h
					hCopy.svc = nfSvc

					return &hCopy, makeOIDCRequest(oidcBaseCtx(cf), t, "1-2-missing", "", http.NoBody)
				},
				wantStatuses: []int{http.StatusNotFound},
			},
		})
	})

	t.Run("app provider error", func(t *testing.T) {
		runOIDCResponseCodeCases(t, []oidcResponseCodeCase{
			{
				name: "unknown agent ID returns bad request",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					job := seedOIDCJobWithAgentID(t, store, validNonce, 9999)
					body := strings.NewReader(mustMarshalJSON(t, tokensRequestDTO{SecretNames: []string{"GITHUB_COPILOT_OIDC_MY_TOKEN"}}))
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, body)
				},
				wantStatuses: []int{http.StatusBadRequest},
			},
		})
	})

	t.Run("enablement and feature flags", func(t *testing.T) {
		runOIDCResponseCodeCases(t, []oidcResponseCodeCase{
			{
				name: "agent is disabled",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, map[string]bool{
						featureflags.CopilotSWEAgentOIDCTokenExchange: true,
					}, false)
					job := seedOIDCJob(t, store, validNonce)
					body := strings.NewReader(mustMarshalJSON(t, tokensRequestDTO{SecretNames: []string{"GITHUB_COPILOT_OIDC_MY_TOKEN"}}))
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, body)
				},
				wantStatuses: []int{http.StatusNotFound},
			},
			{
				name: "OIDC feature flag is disabled",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, map[string]bool{
						featureflags.CopilotSWEAgentSkipCallbackEnablementCheck: true,
					}, true)
					job := seedOIDCJob(t, store, validNonce)
					body := strings.NewReader(mustMarshalJSON(t, tokensRequestDTO{SecretNames: []string{"GITHUB_COPILOT_OIDC_MY_TOKEN"}}))
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, body)
				},
				wantStatuses: []int{http.StatusNotFound},
			},
			{
				name: "OIDC disallow feature flag is enabled",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, map[string]bool{
						featureflags.CopilotSWEAgentSkipCallbackEnablementCheck: true,
						featureflags.CopilotSWEAgentOIDCTokenExchange:           true,
						featureflags.CopilotSWEAgentOIDCTokenExchangeDisallow:   true,
					}, true)
					job := seedOIDCJob(t, store, validNonce)
					body := strings.NewReader(mustMarshalJSON(t, tokensRequestDTO{SecretNames: []string{"GITHUB_COPILOT_OIDC_MY_TOKEN"}}))
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, body)
				},
				wantStatuses: []int{http.StatusNotFound},
			},
			{
				name: "skip flag bypasses disabled agent",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, oidcDefaultFlags(), false)
					job := seedOIDCJob(t, store, validNonce)
					body := strings.NewReader(mustMarshalJSON(t, tokensRequestDTO{SecretNames: []string{"GITHUB_COPILOT_OIDC_MY_TOKEN"}}))
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, body)
				},
				wantStatuses: []int{http.StatusOK},
			},
		})
	})

	t.Run("request body validation", func(t *testing.T) {
		runOIDCResponseCodeCases(t, []oidcResponseCodeCase{
			{
				name: "malformed JSON",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					job := seedOIDCJob(t, store, validNonce)
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, strings.NewReader("not valid json{{{"))
				},
				wantStatuses: []int{http.StatusBadRequest},
				wantBody:     "invalid request body",
			},
			{
				name: "empty secret and MCP names",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					job := seedOIDCJob(t, store, validNonce)
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, strings.NewReader(mustMarshalJSON(t, tokensRequestDTO{})))
				},
				wantStatuses: []int{http.StatusBadRequest},
				wantBody:     "secret_names or mcp_server_names is required",
			},
			{
				name: "invalid secret name prefix",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					h, store, cf := newOIDCTestHandler(t, oidcDefaultFlags(), true)
					job := seedOIDCJob(t, store, validNonce)
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, strings.NewReader(mustMarshalJSON(t, tokensRequestDTO{SecretNames: []string{"INVALID_PREFIX_TOKEN"}})))
				},
				wantStatuses: []int{http.StatusBadRequest},
				wantBody:     "invalid prefix found in secret_names",
			},
		})
	})

	t.Run("token exchange permission errors", func(t *testing.T) {
		runOIDCResponseCodeCases(t, []oidcResponseCodeCase{
			{
				name: "agent variable permission denied returns forbidden",
				arrange: func(t *testing.T) (*Handler, *http.Request) {
					flags := oidcDefaultFlags()
					obsv := observability.NewNoopExporters()
					store := memory.NewStore()
					cf := &github.NoopClientFactory{}
					noopClient := githubtwirp.NewNoopClient()
					noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
					noopClient.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(_ context.Context, _ *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
						return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
							IsMcpEnabled: true,
							McpConfigurationJson: `{
								"mcpServers": {
									"var-server": {
										"type": "http",
										"url": "https://example.com/mcp",
										"tools": ["*"],
										"oidc": {
											"audience": "${{ vars.COPILOT_MCP_AUD }}",
											"grantType": "urn:ietf:params:oauth:grant-type:jwt-bearer",
											"endpoints": {"exchange": "https://issuer.example.com/token"}
										}
									}
								}
							}`,
						}, nil
					}
					ffClient := featureflags.NewNoopClient(flags)
					spokes := spokestest.NewClient(t)
					customAgentSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopClient, ffClient)
					pluginSvc := plugins.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopClient, "https://github.com")
					signer, err := devsigner.NewSignerFromKey("https://test-issuer", nil)
					require.NoError(t, err)
					fetcher := func(_ context.Context, _ sweagentd.AgenticApp, _ int64, _ []string) (map[string]string, error) {
						resp := &gg.Response{Response: &http.Response{StatusCode: http.StatusForbidden}}
						return nil, github.NewGitHubAPIError(resp, "failed to fetch agent variable", errors.New("forbidden"))
					}
					oidcSvc := oidc.NewService(ffClient, signer, spokes, noopClient, obsv, oidc.ServiceConfig{VariableFetcher: fetcher})
					h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), oidcSvc, "")
					job := seedOIDCJob(t, store, validNonce)
					body := strings.NewReader(mustMarshalJSON(t, tokensRequestDTO{MCPServerNames: []string{"var-server"}}))
					return h, makeOIDCRequest(oidcBaseCtx(cf), t, job.ID, validNonce, body)
				},
				wantStatuses: []int{http.StatusForbidden},
			},
		})
	})
}

func TestExchangeTokens_Success(t *testing.T) {
	// Set up a test exchange server that returns tokens and tracks call count.
	var exchangeCount atomic.Int32
	exchangeSvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		exchangeCount.Add(1)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(oidc.ExchangeResponse{
			AccessToken: "exchanged-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	}))
	t.Cleanup(exchangeSvr.Close)

	// Build settings.json with a secret-name-based OIDC entry.
	settingsJSON := fmt.Sprintf(`{
		"oidcConfig": [{
			"secretSuffix": "MY_API",
			"audience": "test-aud",
			"grantType": %q,
			"endpoints": {"exchange": %q, "revoke": %q}
		}]
	}`, oidcconfig.GrantTypeJWTBearer, exchangeSvr.URL+"/token", exchangeSvr.URL+"/revoke")

	// Build MCP config with server-name-based OIDC entries.
	mcpConfigJSON := fmt.Sprintf(`{
		"mcpServers": {
			"my-mcp-server": {
				"type": "http",
				"url": "https://example.com/mcp",
				"tools": ["*"],
				"oidc": {
					"audience": "test-aud",
					"grantType": %q,
					"endpoints": {"exchange": %q, "revoke": %q}
				}
			},
			"server-a": {
				"type": "http",
				"url": "https://example.com/mcp-a",
				"tools": ["*"],
				"oidc": {
					"audience": "test-aud",
					"grantType": %q,
					"endpoints": {"exchange": %q, "revoke": %q}
				}
			}
		}
	}`, oidcconfig.GrantTypeJWTBearer, exchangeSvr.URL+"/token", exchangeSvr.URL+"/revoke",
		oidcconfig.GrantTypeJWTBearer, exchangeSvr.URL+"/token", exchangeSvr.URL+"/revoke")

	// Feature flags: enable OIDC exchange and settings.json loading.
	flags := map[string]bool{
		featureflags.CopilotSWEAgentOIDCTokenExchange:           true,
		featureflags.CopilotSWEAgentSkipCallbackEnablementCheck: true,
		featureflags.CopilotSWEAgentOIDCSettingsJSON:            true,
	}

	obsv := observability.NewNoopExporters()
	store := memory.NewStore()
	cf := &github.NoopClientFactory{}
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}
	noopClient.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(_ context.Context, _ *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
			IsMcpEnabled:         true,
			McpConfigurationJson: mcpConfigJSON,
		}, nil
	}

	ffClient := featureflags.NewNoopClient(flags)
	spokes := spokestest.NewClient(t, spokestest.WithBlob(".github/copilot/settings.json", []byte(settingsJSON)))
	customAgentSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopClient, ffClient)
	pluginSvc := plugins.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopClient, "https://github.com")

	signer, err := devsigner.NewSignerFromKey("https://test-issuer", nil)
	require.NoError(t, err)
	oidcSvc := oidc.NewService(ffClient, signer, spokes, noopClient, obsv, oidc.ServiceConfig{})

	h := NewHandler(obsv, ffClient, store, cf, noopClient, &noopCallbackHandler{}, &noopCleanupHandler{}, customAgentSvc, nil, pluginSvc, agenticapptest.NewTestProvider(t), nil, "https://github.com", &noopPullRequestOpener{}, capi.NewNoopClient(), oidcSvc, "")

	nonce := "test-nonce"
	job := seedOIDCJob(t, store, nonce)
	baseCtx := oidcBaseCtx(cf)

	tests := []struct {
		name              string
		body              tokensRequestDTO
		wantSecrets       map[string]string
		wantMCPTokens     map[string]string
		wantExchangeCalls int32
	}{
		{
			name:              "with secret names",
			body:              tokensRequestDTO{SecretNames: []string{"GITHUB_COPILOT_OIDC_MY_API"}},
			wantSecrets:       map[string]string{"GITHUB_COPILOT_OIDC_MY_API": "exchanged-token"},
			wantExchangeCalls: 1,
		},
		{
			name:              "with mcp server names",
			body:              tokensRequestDTO{MCPServerNames: []string{"my-mcp-server"}},
			wantMCPTokens:     map[string]string{"my-mcp-server": "exchanged-token"},
			wantExchangeCalls: 1,
		},
		{
			name: "with both secret and mcp server names",
			body: tokensRequestDTO{
				SecretNames:    []string{"GITHUB_COPILOT_OIDC_MY_API"},
				MCPServerNames: []string{"server-a"},
			},
			wantSecrets:       map[string]string{"GITHUB_COPILOT_OIDC_MY_API": "exchanged-token"},
			wantMCPTokens:     map[string]string{"server-a": "exchanged-token"},
			wantExchangeCalls: 2,
		},
		{
			name:              "with exact MCP token placeholder filtered",
			body:              tokensRequestDTO{SecretNames: []string{"GITHUB_COPILOT_OIDC_MCP_TOKEN"}, MCPServerNames: []string{"server-a"}},
			wantSecrets:       map[string]string{},
			wantMCPTokens:     map[string]string{"server-a": "exchanged-token"},
			wantExchangeCalls: 1,
		},
		{
			name:              "with suffixed MCP token placeholder filtered",
			body:              tokensRequestDTO{SecretNames: []string{"GITHUB_COPILOT_OIDC_MCP_TOKEN_MY_SVC"}, MCPServerNames: []string{"server-a"}},
			wantSecrets:       map[string]string{},
			wantMCPTokens:     map[string]string{"server-a": "exchanged-token"},
			wantExchangeCalls: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			exchangeCount.Store(0)
			req := makeOIDCRequest(baseCtx, t, job.ID, nonce, strings.NewReader(mustMarshalJSON(t, tt.body)))
			w := httptest.NewRecorder()
			h.exchangeTokens(w, req)

			require.Equal(t, http.StatusOK, w.Code, "body: %s", w.Body.String())
			assert.Equal(t, "application/json", w.Header().Get("Content-Type"))

			var resp tokensResponseDTO
			require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))

			if tt.wantSecrets != nil {
				assert.Equal(t, tt.wantSecrets, resp.SecretTokens)
			}
			if tt.wantMCPTokens != nil {
				assert.Equal(t, tt.wantMCPTokens, resp.MCPServerTokens)
			}
			assert.Equal(t, tt.wantExchangeCalls, exchangeCount.Load(), "expected %d exchange calls", tt.wantExchangeCalls)
			assert.Empty(t, resp.Failures, "successful exchange should have no failures")
		})
	}
}
