package jobapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	authd "github.com/github/authnd/client"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/go-chi/chi/v5"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap/zapcore"
)

const (
	// Test constants for app IDs
	testAppID      = int64(12345)
	sweagentdAppID = uint64(12345) // Use same ID for consistency in uint64 contexts
)

var authZScenarios = map[string]map[string][]string{
	string(authd.CredentialTypeUserToServerToken): {
		"authorized-with-token-privs":      requiredAccessActionsDefault,
		"unauthorized":                     {},
		"privileged":                       requiredAccessActionsPrivileged,
		"unauthorized-privileged-no-scope": {},
	},
	string(authd.CredentialTypeOauthApplicationAccessToken): {
		"authorized-with-token-privs":      requiredAccessActionsDefault,
		"unauthorized":                     {},
		"unauthorized-privileged":          requiredAccessActionsPrivileged,
		"unauthorized-privileged-no-scope": {},
	},
	string(authd.CredentialTypeLegacyPersonalAccessToken): {
		"authorized-with-token-privs":      requiredAccessActionsDefault,
		"unauthorized":                     {},
		"unauthorized-privileged":          requiredAccessActionsPrivileged,
		"unauthorized-privileged-no-scope": {},
	},
	string(authd.CredentialTypeFineGrainedPersonalAccessToken): {
		"authorized-with-token-privs":      requiredAccessActionsDefault,
		"unauthorized":                     {},
		"unauthorized-privileged":          requiredAccessActionsPrivileged,
		"unauthorized-privileged-no-scope": {},
	},
	string(authd.CredentialTypeServerToServerToken): {
		"unauthorized-with-token-privs":    requiredAccessActionsDefault,
		"unauthorized":                     {},
		"unauthorized-privileged":          requiredAccessActionsPrivileged,
		"unauthorized-privileged-no-scope": {},
	},
}

type authZTestArgs struct {
	tokenType        string
	authZTest        string
	requiredActions  []string
	method           string
	urlPath          string
	urlParams        map[string]string
	runName          string
	problemStatement string
	cf               github.ClientFactoryInterface
	jobsStore        db.JobsStore
}

func NewTestHandler(t *testing.T, obsv observability.Exporters, cf github.ClientFactoryInterface, jobsStore db.JobsStore, ffClient featureflags.Client, capiClient capi.Client, ghTwirp githubtwirp.ClientInterface, privilegedAppCheckerResult bool, spokes sweagentd.Spokes) (*Handler, *jobexecutor.TestJobExecutor) {
	countTracker := limiter.NewJobCountMemoryTracker(10, time.Hour)
	jobLimiter := limiter.NewJobLimiter(jobsStore, countTracker)
	aq := aqueduct.NewMemoryClient(obsv)
	appProvider := agenticapptest.NewTestProviderWithID(t, int64(sweagentdAppID))
	jobService := jobservice.New(obsv, ffClient, jobsStore, capiClient, cf, ghTwirp, aq, jobLimiter, experiments.NewNoopClient(), customagent.NewService(obsv, spokes, ghTwirp, ffClient), "test@example.com", spokes, appProvider, nil)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, jobsStore, cf, ghTwirp, capiClient, jobLimiter, jobService)
	handler := NewHandler(obsv, cf, jobService, jobsStore, ffClient, executor, ghTwirp, appProvider, spokes)
	handler.privilegedAppChecker = &github.MockPrivilegedAppChecker{
		MockHasCapabilityResult: privilegedAppCheckerResult,
	}
	return handler, executor
}

// Generate test scenario data for auth tests
func prepAuthTestScenarios(cf *github.NoopClientFactory, jobsStore db.JobsStore) (map[string]map[string]string, error) {
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(1)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}
	cf.MockRepositories = &map[string]gg.Repository{
		"oregon/trail": repo,
	}
	testJob, err := jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:        "job-1234",
		SessionID: "session-1234",
		OwnerID:   *owner.ID,
		RepoID:    *repo.ID,
		AgentID:   int64(sweagentdAppID),
		Status:    jobs.JobStatusRunning,
	})
	if err != nil {
		return nil, err
	}

	return map[string]map[string]string{
		"POST:/jobs/{owner}/{repo}": {
			"owner": *owner.Login,
			"repo":  *repo.Name,
		},
		"POST:/jobs/{owner}/{repo}/{job}/cancel": {
			"owner": *owner.Login,
			"repo":  *repo.Name,
			"job":   testJob.ID,
		},
		"POST:/jobs/{owner}/{repo}/session/{session}/cancel": {
			"owner":   *owner.Login,
			"repo":    *repo.Name,
			"session": testJob.SessionID,
		},
		"GET:/jobs/{owner}/{repo}/{job}": {
			"owner": *owner.Login,
			"repo":  *repo.Name,
			"job":   testJob.ID,
		},
		"GET:/jobs/{owner}/{repo}/session/{session}": {
			"owner":   *owner.Login,
			"repo":    *repo.Name,
			"session": testJob.SessionID,
		},
		"GET:/jobs/{owner}/{repo}/pulls/{prNumber}": {
			"owner":    *owner.Login,
			"repo":     *repo.Name,
			"prNumber": "123",
		},
	}, nil
}

// Given the risk associated with auth not being correct, we will test each endpoint for a
// number of scenarios to make sure that there's not a path that results in a missed step.
func TestAuthLogic(t *testing.T) {
	cf := &github.NoopClientFactory{}
	jobsStore := memory.NewStore()
	runName := "Oregon Trail Problem"
	problemStatement := "You died of dysentery"
	urlScenarios, err := prepAuthTestScenarios(cf, jobsStore)
	require.NoError(t, err)

	// For each supported auth URL above...
	for scenario, params := range urlScenarios {
		scenarioParts := strings.Split(scenario, ":")
		method := scenarioParts[0]
		urlPath := scenarioParts[1]
		// Run authZ tests for each authZ scenario
		for tokenType, authZScenario := range authZScenarios {
			for authZTest, requiredActions := range authZScenario {
				runAuthZTest(t, &authZTestArgs{
					tokenType:        tokenType,
					authZTest:        authZTest,
					requiredActions:  requiredActions,
					method:           method,
					urlPath:          urlPath,
					urlParams:        params,
					runName:          runName,
					problemStatement: problemStatement,
					cf:               cf,
					jobsStore:        jobsStore,
				})
			}
		}

		// Test that, even if authorized from the token, users can't push unless their user really does have push rights
		t.Run(fmt.Sprintf("user with no push rights %s %s", method, strings.ReplaceAll(urlPath, "/", "_")), func(t *testing.T) {
			obsv := observability.NewNoopExporters()
			capiClient := capi.NewNoopClient()
			ffAltClient := featureflags.NewNoopClientWithAppID(map[string]bool{}, testAppID)
			ghTwirp := newAuthTestTwirpAPI(true, []string{})
			ctx := addUserWithoutRepoPushAccessToContext(context.Background(), t)
			altH, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirp, true, spokestest.NewClient(t))
			resp, _, err := callHandler(ctx, t, altH, method, urlPath, params, problemStatement, runName)
			require.NoError(t, err)
			assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
		})

		// Test that disallowed users or apps are in fact disallowed
		t.Run(fmt.Sprintf("disallowed user %s %s", method, strings.ReplaceAll(urlPath, "/", "_")), func(t *testing.T) {
			testAPI := func(ffAltClient featureflags.Client) {
				obsv := observability.NewNoopExporters()
				capiClient := capi.NewNoopClient()
				ghTwirp := newAuthTestTwirpAPI(true, []string{})
				ctx := addUserWithoutRepoPushAccessToContext(context.Background(), t)
				altH, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirp, true, spokestest.NewClient(t))
				resp, _, err := callHandler(ctx, t, altH, method, urlPath, params, problemStatement, runName)
				require.NoError(t, err)
				assert.Equal(t, http.StatusNotFound, resp.StatusCode)
			}
			// Test user
			testAPI(featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentAPIDisallow: true,
			}))
			// Test app
			testAPI(featureflags.NewNoopClientWithAppID(map[string]bool{
				featureflags.CopilotSWEAgentAPIDisallow: true,
			}, testAppID))
		})
	}
}

// Actual AuthZ test
func runAuthZTest(t *testing.T, args *authZTestArgs) {
	isAuthZFailureScenario := strings.HasPrefix(args.authZTest, "unauthorized")
	privilegedAppCheckerResult := strings.Contains(args.authZTest, "privileged")

	obsv := observability.NewNoopExporters()
	capiClient := capi.NewNoopClient()
	ffAltClient := featureflags.NewNoopClientWithAppID(map[string]bool{}, testAppID)

	ghTwirp := newAuthTestTwirpAPI(isAuthZFailureScenario, args.requiredActions)

	t.Run(fmt.Sprintf("AuthZ %s %s %s %s", args.method, strings.ReplaceAll(args.urlPath, "/", "_"), args.authZTest, args.tokenType), func(t *testing.T) {
		h, _ := NewTestHandler(t, obsv, args.cf, args.jobsStore, ffAltClient, capiClient, ghTwirp, privilegedAppCheckerResult, spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
				results := make([]bool, len(refs))
				for i, ref := range refs {
					results[i] = ref == "main" || ref == "refs/heads/main"
				}

				return results, nil
			})))
		ctx := context.Background()
		if args.tokenType == string(authd.CredentialTypeLegacyPersonalAccessToken) || args.tokenType == string(authd.CredentialTypeFineGrainedPersonalAccessToken) {
			ctx = addPATToContext(ctx, t, args.tokenType)
		} else {
			ctx = addAppIDToContext(ctx, t, args.tokenType)
		}
		resp, _, err := callHandler(ctx, t, h, args.method, args.urlPath, args.urlParams, args.problemStatement, args.runName)
		require.NoError(t, err)
		if isAuthZFailureScenario {
			assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
		} else {
			switch args.method {
			case http.MethodGet:
				assert.Equal(t, http.StatusOK, resp.StatusCode)
			case http.MethodPost:
				// Cancel endpoints return 204 No Content, others return 201 Created
				if strings.Contains(args.urlPath, "/cancel") {
					assert.Equal(t, http.StatusNoContent, resp.StatusCode)
				} else {
					assert.Equal(t, http.StatusCreated, resp.StatusCode)
				}
			default:
				t.Fatal("test setup error - shouldn't be here")
			}
		}
	})
}

// newTestTwirpAPI creates a mock GitHub Twirp client for testing
func newTestTwirpAPI() *githubtwirp.NoopClient {
	return &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: true,
			},
		},
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							Remaining:        1,
							Entitlement:      100,
							OveragePermitted: true,
						},
					},
				}, nil
			},
		},
		NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
			MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{
							Id:         100, // Match the repo ID used in the test
							Name:       "testrepo",
							OwnerId:    1,
							OwnerLogin: "testowner",
						},
					},
				}, nil
			},
		},
		NoopAuthorizationAPI: &githubtwirp.NoopAuthorizationAPI{},
	}
}

// newAuthTestTwirpAPI creates a twirp API instance that is appropriate for the authZ test
func newAuthTestTwirpAPI(isAuthFailureScenario bool, requiredActions []string) *githubtwirp.NoopClient {
	client := newTestTwirpAPI()
	client.NoopAuthorizationAPI = newAuthZTestNoopAuthorizationAPI(isAuthFailureScenario, requiredActions)
	client.NoopBillingClient = &billingMocks.MockClientInterface{}
	// Set up repositories API to return the test repository for auth tests
	client.NoopRepositoriesAPI = &githubtwirp.NoopRepositoriesAPI{
		MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         1,
						OwnerId:    1,
						Name:       "trail",
						OwnerLogin: "oregon",
					},
				},
			}, nil
		},
	}
	return client
}

// Creates an authorization API instance that is appropriate for the authZ test
func newAuthZTestNoopAuthorizationAPI(authFailureScenario bool, requiredActions []string) *githubtwirp.NoopAuthorizationAPI {
	return &githubtwirp.NoopAuthorizationAPI{
		MockBatchControlAccess: func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
			if authFailureScenario {
				return &coreTwirp.BatchControlAccessResponse{
					Decisions: []*coreTwirp.AuthorizationDecision{
						{
							Id:       "test-id",
							Decision: false,
						},
					},
				}, nil
			}
			if len(req.AuthorizationRequests) != len(requiredActions) {
				return nil, errors.New("test failed - error to trigger 500 response")
			}
			for i, action := range req.AuthorizationRequests {
				if action.Action != requiredActions[i] {
					return nil, errors.New("test failed - error to trigger 500 response")
				}
			}
			return &coreTwirp.BatchControlAccessResponse{
				Decisions: []*coreTwirp.AuthorizationDecision{
					{
						Id:       "test-id",
						Decision: true,
					},
				},
			}, nil
		},
	}
}

func TestCreateJob(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	runName := "Oregon Trail Problem"
	problemStatement := "You died of dysentery"
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(2)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}
	cf.MockRepositories = &map[string]gg.Repository{
		"oregon/trail": repo,
	}

	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ghTwirp := newTestTwirpAPI()

	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
			results := make([]bool, len(refs))
			for i, ref := range refs {
				results[i] = ref == "main" || ref == "refs/heads/main"
			}

			return results, nil
		}))

	h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

	urlPath := "/jobs/{owner}/{repo}"
	urlParams := map[string]string{"owner": *owner.Login, "repo": *repo.Name}

	t.Run("create new job for API v0, 2025-06-19", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)
		assert.NotEmpty(t, resp.Body)
		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)
		assert.NotNil(t, result.PullRequest)
		assert.Equal(t, apiVersion, resp.Header.Get("X-GitHub-Api-Version"))

		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
	})

	// Most of the tests here set the header to test the functionality w/o worrying about versioning, this tests defaulting
	t.Run("create new job using default API version", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)
		assert.NotEmpty(t, resp.Body)
		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)
		assert.NotNil(t, result.PullRequest)
		assert.Equal(t, apiVersion, resp.Header.Get("X-GitHub-Api-Version"))
	})

	t.Run("Handle 4xx and 5xx errors", func(t *testing.T) {
		callAPI := func(h *Handler) (*http.Response, *httptest.ResponseRecorder) {
			ctx := addUserToContext(context.Background(), t)
			resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
			require.NoError(t, err)
			return resp, w
		}

		// Simulate a bad argument error
		cfTest := &github.NoopClientFactory{}
		cfTest.MockGetRepository = func(ctx context.Context, owner, repo string) (*gg.Repository, error) {
			resp := gg.Response{Response: &http.Response{
				StatusCode: http.StatusBadRequest,
			}}
			return nil, github.NewGitHubAPIError(&resp, "failed to get required information", errors.New("invalid repository"))
		}
		h1, _ := NewTestHandler(t, obsv, cfTest, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)
		resp1, w1 := callAPI(h1)
		assert.Equal(t, http.StatusBadRequest, resp1.StatusCode)
		assert.NotEmpty(t, resp1.Body)
		result1 := make(map[string]any)
		err1 := json.NewDecoder(w1.Body).Decode(&result1)
		require.NoError(t, err1)
		assert.Equal(t, "invalid API request for repo: failed to get repository: failed to get required information: invalid repository: bad request", result1["message"])

		// Simulate internal error
		ghTwirpAlt := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return nil, errors.New("internal error")
				},
			},
			NoopLimiterAPI:       &githubtwirp.NoopLimiterAPI{},
			NoopUserDetailAPI:    &githubtwirp.NoopUserDetailAPI{},
			NoopAuthorizationAPI: &githubtwirp.NoopAuthorizationAPI{},
		}
		h2, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirpAlt, true, spokes)
		resp2, w2 := callAPI(h2)
		assert.Equal(t, http.StatusInternalServerError, resp2.StatusCode)
		assert.NotEmpty(t, resp2.Body)
		result2 := make(map[string]any)
		err2 := json.NewDecoder(w2.Body).Decode(&result2)
		require.NoError(t, err2)
		assert.Equal(t, "failed to draft job: failed to create pull request: failed to create pull request: internal error", result2["message"])
	})

	t.Run("custom agent not found returns 404 version", func(t *testing.T) {
		ffAltClient := featureflags.NewNoopClientWithAppID(map[string]bool{}, testAppID)
		ctx := addUserToContext(context.Background(), t)
		requestBody := &NewJobAPIRequest{}
		requestBody.ProblemStatement = problemStatement
		requestBody.RunName = runName
		requestBody.CustomAgent = "does-not-exist"
		reqBytes, err := json.Marshal(requestBody)
		require.NoError(t, err)

		hAlt, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirp, true, spokes)
		req := httptest.NewRequestWithContext(ctx, http.MethodPost, "/jobs/{owner}/{repo}", bytes.NewReader(reqBytes))
		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", *owner.Login)
		rctx.URLParams.Add("repo", *repo.Name)
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)
		w := httptest.NewRecorder()

		hAlt.middleware(hAlt.HandleNewJobAsync)(w, req)
		resp := w.Result()
		require.NoError(t, err)

		assert.Equal(t, http.StatusNotFound, resp.StatusCode)
		assert.Contains(t, w.Body.String(), "specified custom agent not found")
	})

	t.Run("custom agent not found returns 404 for sync endpoint", func(t *testing.T) {
		ffAltClient := featureflags.NewNoopClientWithAppID(map[string]bool{}, testAppID)
		ctx := addUserToContext(context.Background(), t)
		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			CustomAgent:      "does-not-exist",
		}

		hAlt, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirp, true, spokes)

		// Use v0 URL path to test the synchronous endpoint (HandleNewJob)
		urlPath := "/jobs/{owner}/{repo}"
		urlParams := map[string]string{"owner": *owner.Login, "repo": *repo.Name}

		resp, w, err := callHandlerWithRequest(ctx, t, hAlt, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)

		assert.Equal(t, http.StatusNotFound, resp.StatusCode)
		assert.Contains(t, w.Body.String(), "specified custom agent not found")
	})

	t.Run("custom agent with version parses correctly", func(t *testing.T) {
		ffAltClient := featureflags.NewNoopClientWithAppID(map[string]bool{}, testAppID)
		ctx := addUserToContext(context.Background(), t)

		// Custom agent configuration
		agentConfig := `
---
display_name: "My Test Agent"
description: "A test custom agent"
prompt: "You are a helpful assistant"
---
`
		testSHA := "abc123def456abc123def456abc123def456abc1"

		// Create a custom ghTwirp with mock for custom agent authorization
		ghTwirpCustom := newTestTwirpAPI()
		ghTwirpCustom.NoopSweagentdAPI.MockAuthorizeCustomAgentRepoForUser = func(ctx context.Context, req *sweagentdTwirp.AuthorizeCustomAgentRepoForUserRequest) (*sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse, error) {
			return &sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse{
				CanAccess: true,
			}, nil
		}
		// Mock the repository lookup by ID
		ghTwirpCustom.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
			return &repositoriesTwirp.FindRepositoriesResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         *repo.ID,
						OwnerId:    *owner.ID,
						OwnerLogin: *owner.Login,
						Name:       *repo.Name,
					},
				},
			}, nil
		}

		t.Run("when version is specified", func(t *testing.T) {
			// Create spokes client with custom agent config at a specific version (SHA)
			// When version is specified, ReadBlobByObjectIDPath is called with the version as OID
			spokesCustom := spokestest.NewClient(t,
				spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
					results := make([]bool, len(refs))
					for i, ref := range refs {
						results[i] = ref == "main" || ref == "refs/heads/main"
					}

					return results, nil
				}),
				// Mock the blob at the versioned path - this is how spokes reads a file at a specific commit
				spokestest.WithCommitSHAAndBlob(".github/agents/my-agent.md", testSHA, []byte(agentConfig)),
			)

			hAlt, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirpCustom, true, spokesCustom)

			requestBody := &NewJobAPIRequest{
				ProblemStatement: problemStatement,
				RunName:          runName,
				CustomAgent:      fmt.Sprintf("my-agent@%s", testSHA),
			}

			resp, w, err := callHandlerWithRequest(ctx, t, hAlt, http.MethodPost, urlPath, urlParams, requestBody)
			require.NoError(t, err)
			assert.Equal(t, http.StatusCreated, resp.StatusCode)

			// Decode the response to get the job ID
			result := &BaseJobResponse{}
			err = json.NewDecoder(w.Body).Decode(&result)
			require.NoError(t, err)
			assert.NotEmpty(t, result.ID)

			// Verify the job was created with the custom agent and correct version
			job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
			require.NoError(t, err)
			require.NotNil(t, job)
			assert.Equal(t, "my-agent", job.CustomAgent.Name, "Agent name should be parsed without version")
			assert.Equal(t, testSHA, job.CustomAgent.Version, "Version (SHA) should be extracted and stored")
		})

		t.Run("when no version is specified", func(t *testing.T) {
			defaultSHA := "sha-0123456789101112131415161718192021222324252627" // Default commit SHA from spokestest
			// Create spokes client with custom agent config at default location
			spokesCustom := spokestest.NewClient(t,
				spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
					results := make([]bool, len(refs))
					for i, ref := range refs {
						results[i] = ref == "main" || ref == "refs/heads/main"
					}

					return results, nil
				}),
				spokestest.WithRepoBlob(uint64(*repo.ID), ".github/agents/my-agent.md", []byte(agentConfig)),
			)

			hAlt, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirpCustom, true, spokesCustom)

			requestBody := &NewJobAPIRequest{
				ProblemStatement: problemStatement,
				RunName:          runName,
				CustomAgent:      "my-agent",
			}

			resp, w, err := callHandlerWithRequest(ctx, t, hAlt, http.MethodPost, urlPath, urlParams, requestBody)
			require.NoError(t, err)
			assert.Equal(t, http.StatusCreated, resp.StatusCode)

			// Decode the response to get the job ID
			result := &BaseJobResponse{}
			err = json.NewDecoder(w.Body).Decode(&result)
			require.NoError(t, err)
			assert.NotEmpty(t, result.ID)

			// Verify the job was created with the custom agent and default SHA as version
			job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
			require.NoError(t, err)
			require.NotNil(t, job)
			assert.Equal(t, "my-agent", job.CustomAgent.Name, "Agent name should be the full custom agent string when no version is specified")
			assert.Equal(t, defaultSHA, job.CustomAgent.Version, "Version should be set to the commit SHA of the config file from ReadBlob")
		})
	})

	t.Run("rules validation error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := newTestTwirpAPI()
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
				results := make([]bool, len(refs))
				for i, ref := range refs {
					results[i] = ref == "refs/heads/main" || ref == "refs/heads/copilot"
				}

				return results, nil
			}))

		// Create a client factory that will trigger a rules validation error
		// by mocking the CheckIfBranchExists to return true for "copilot" branch
		cfRules := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
						return &[]github.GQLBranchProtectionRule{}, nil
					},
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{}, nil
					},
				}, nil
			},
		}

		// Create the handler using normal setup but with our mocked GitHub client factory
		h, _ := NewTestHandler(t, obsv, cfRules, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

		// Use v0 URL path to test the synchronous endpoint (HandleNewJob)
		urlPath := "/jobs/{owner}/{repo}"
		urlParams := map[string]string{"owner": *owner.Login, "repo": *repo.Name}

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
		require.NoError(t, err)

		// Should return 422 Unprocessable Entity for rules validation error
		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)

		// Response body should contain the error message about copilot branch existing
		responseBody := w.Body.String()
		assert.Contains(t, responseBody, "A branch named `copilot` already exists")
	})

	t.Run("model field is passed through for Pro/Pro+ users", func(t *testing.T) {
		// Model selection is always available for Pro/Pro+ individual plans
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		modelName := "super-duper-amazing-model"

		// Mock ListCodingAgentModels to include the test model
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{ID: modelName, Name: "Super Duper Amazing Model", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
			}, nil
		}

		// Create a twirp client that returns an Individual plan with paid access
		// so that model selection is allowed
		ghTwirpIndividual := newTestTwirpAPI()
		ghTwirpIndividual.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					AnalyticsTrackingId: "test-tracking-id",
					CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
					HasPaidAccess:       true,
				},
			}, nil
		}

		hWithFlag, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirpIndividual, true, spokes)

		ctx := addUserToContext(context.Background(), t)

		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Model:            modelName,
		}

		resp, w, err := callHandlerWithRequest(ctx, t, hWithFlag, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)
		assert.NotEmpty(t, resp.Body)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)

		// Verify the model was set correctly on the job when flag is enabled
		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, "sweagent-capi:"+modelName, job.Model, "job.Model should have sweagent-capi: prefix for individual users")
	})

	t.Run("model field is ignored for Enterprise plan users without all-SKUs flag", func(t *testing.T) {
		// Enterprise users don't get model selection without CodingAgentModelSelectionAllSKUs flag
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		modelName := "super-duper-amazing-model"

		// Mock ListCodingAgentModels to include the test model
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{ID: modelName, Name: "Super Duper Amazing Model"},
			}, nil
		}

		// Create a twirp client that returns an Enterprise plan
		// Model selection should NOT be allowed for Enterprise users without the all-SKUs flag
		ghTwirpEnterprise := newTestTwirpAPI()
		ghTwirpEnterprise.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					AnalyticsTrackingId: "test-tracking-id",
					CopilotPlan:         copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		hWithFlag, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirpEnterprise, true, spokes)

		ctx := addUserToContext(context.Background(), t)

		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Model:            modelName,
		}

		resp, w, err := callHandlerWithRequest(ctx, t, hWithFlag, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)
		assert.NotEmpty(t, resp.Body)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)

		// Verify the model was NOT set to the user-provided value for Enterprise users
		// Instead, it should fall back to the system-determined model (auto mode)
		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.NotEqual(t, "sweagent-capi:"+modelName, job.Model, "job.Model should NOT match the user-specified model for Enterprise users without all-SKUs flag")
		assert.NotEmpty(t, job.Model, "job.Model should be set to a default value determined by the system")
	})

	t.Run("model field defaults to system-determined value when not provided", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)

		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			// Model not set
		}

		resp, w, err := callHandlerWithRequest(ctx, t, h, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)
		assert.NotEmpty(t, resp.Body)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)

		// Verify the model is set to a default when not provided in the request
		// The system will determine an appropriate model based on feature flags and user settings
		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.NotEmpty(t, job.Model, "job.Model should be set to a default value when not specified in the API request")
	})

	// Integration tests using raw JSON strings
	t.Run("JSON request with minimal payload creates job with a pull request", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Fix the bug in the login page"
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)

		// Verify that omitting PR features still creates a PR
		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.NotNil(t, job.Features.PullRequest, "job.Features.PullRequest should be present when features is omitted")
	})

	t.Run("JSON request with features.branch creates a branch without a PR", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Fix the bug in the login page",
			"features": {
				"branch": {
					"base_branch": "main"
				}
			}
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)

		// Verify that explicitly requesting a branch creates only a branch without a PR
		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.NotNil(t, job.Features.Branch, "job.Features.Branch should be set even when PR features are omitted")
		assert.Nil(t, job.Features.PullRequest, "job.Features.PullRequest should be nil when PR features are omitted")
	})

	t.Run("JSON request with pull_request features creates job", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Implement user authentication",
			"run_name": "Auth Implementation",
			"features": {
				"pull_request": {
					"title": "Add user authentication",
					"body_suffix": "Fixes #123",
					"labels": ["enhancement", "auth"]
				}
			}
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)
		assert.NotNil(t, result.PullRequest)
	})

	t.Run("JSON request missing problem_statement returns 400", func(t *testing.T) {
		jsonBody := `{
			"run_name": "Some task"
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, _, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
	})

	t.Run("JSON request with empty problem_statement returns 400", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "",
			"run_name": "Empty problem"
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, _, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
	})

	t.Run("JSON request with invalid JSON returns error", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Some task",
			invalid json here
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, _, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.GreaterOrEqual(t, resp.StatusCode, 400, "Expected error status code for invalid JSON")
	})

	t.Run("JSON request with extra unknown fields is accepted", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Add new feature",
			"unknown_field": "should be ignored",
			"another_unknown": 123
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)
	})

	t.Run("JSON request with deprecated pull_request at root level is handled", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Fix deprecated API usage",
			"pull_request": {
				"title": "Deprecated field test"
			}
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)
	})

	t.Run("JSON request with event_type and event_url creates job", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Handle issue from GitHub",
			"event_type": "github.issue.opened",
			"event_url": "https://github.com/oregon/trail/issues/456"
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)
	})

	t.Run("JSON request with custom_agent_attributes creates job", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Use custom agent configuration",
			"custom_agent_attributes": {
				"name": "My Custom Agent",
				"description": "A custom agent for testing",
				"prompt": "You are a helpful coding assistant."
			}
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)
	})

	t.Run("JSON request with invalid head_ref prefix returns 400", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Test invalid head_ref",
			"features": {
				"pull_request": {
					"head_ref": "invalid-branch-name"
				}
			}
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)

		body := w.Body.String()
		assert.Contains(t, body, "head_ref must start with")
	})

	t.Run("JSON request with valid copilot head_ref prefix creates job", func(t *testing.T) {
		jsonBody := `{
			"problem_statement": "Test valid head_ref",
			"features": {
				"pull_request": {
					"head_ref": "copilot/my-feature-branch"
				}
			}
		}`

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithJSONString(ctx, t, h, http.MethodPost, urlPath, urlParams, jsonBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)
	})

	t.Run("job action is task when no PR and feature flag enabled", func(t *testing.T) {
		ffClientWithTaskFlag := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentProposeTasks: true,
		})

		hWithTaskFlag, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClientWithTaskFlag, capiClient, ghTwirp, true, spokes)

		// Request without pull_request feature
		requestBody := &NewJobAPIRequest{
			ProblemStatement: "Build a new feature",
			RunName:          "New Feature Task",
			Features: &EnvironmentFeatures{
				// No pull_request feature - only creates a branch
				Branch: &BranchFeature{
					BaseRef: "main",
				},
			},
		}

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithRequest(ctx, t, hWithTaskFlag, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)

		// Verify the job action is "task" when no PR and feature flag is enabled
		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, jobs.AgentActionTask, job.Action, "job.Action should be 'task' when no PR and CodingAgentProposeTasks is enabled")
		assert.Nil(t, job.Features.PullRequest, "job.Features.PullRequest should be nil")
		assert.NotNil(t, job.Features.Branch, "job.Features.Branch should be set")
	})

	t.Run("job action is fix when no PR and feature flag disabled", func(t *testing.T) {
		// Use the default handler which has the feature flag disabled
		requestBody := &NewJobAPIRequest{
			ProblemStatement: "Build a new feature",
			RunName:          "New Feature Fix",
			// No pull_request feature
		}

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithRequest(ctx, t, h, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)

		// Verify the job action is "fix" when feature flag is disabled
		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, jobs.AgentActionFix, job.Action, "job.Action should be 'fix' when CodingAgentProposeTasks is disabled")
	})

	t.Run("job action is fix when PR is requested even with feature flag enabled", func(t *testing.T) {
		ffClientWithTaskFlag := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentProposeTasks: true,
		})

		hWithTaskFlag, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClientWithTaskFlag, capiClient, ghTwirp, true, spokes)

		// Request WITH pull_request feature
		requestBody := &NewJobAPIRequest{
			ProblemStatement: "Fix a bug",
			RunName:          "Bug Fix",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					Title: "Fix the bug",
				},
			},
		}

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithRequest(ctx, t, hWithTaskFlag, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		result := &BaseJobResponse{}
		err = json.NewDecoder(w.Body).Decode(&result)
		require.NoError(t, err)
		assert.NotEmpty(t, result.ID)

		// Verify the job action is "fix" when PR is requested, even with feature flag enabled
		job, err := jobsStore.GetJob(ctx, *owner.ID, *repo.ID, result.ID)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, jobs.AgentActionFix, job.Action, "job.Action should be 'fix' when PR is requested, even with CodingAgentProposeTasks enabled")
		assert.NotNil(t, job.Features.PullRequest, "job.Features.PullRequest should be set")
	})
}

func TestCreateJobAsync(t *testing.T) {
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()

	runName := "Oregon Trail Problem"
	problemStatement := "You died of dysentery"
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(1)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}
	cf.MockRepositories = &map[string]gg.Repository{
		"oregon/trail": repo,
	}

	urlPath := "/jobs/v1/{owner}/{repo}"
	urlParams := map[string]string{"owner": *owner.Login, "repo": *repo.Name}

	testCases := []struct {
		name              string
		requestsRemaining int32
		code              int
	}{
		{
			name:              "success",
			requestsRemaining: 1,
			code:              http.StatusCreated,
		}, {
			name:              "insufficient_quota",
			requestsRemaining: 0,
			code:              http.StatusCreated, // Job queuing globally enabled, quota check is deferred
		},
	}

	for _, tt := range testCases {
		t.Run(tt.name, func(t *testing.T) {
			testFFClient := featureflags.NewNoopClient(map[string]bool{})
			ghTwirp := newTestTwirpAPI()
			ghTwirp.NoopLimiterAPI.MockGetQuotaRemaining = func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{{
						Remaining: tt.requestsRemaining,
					}},
				}, nil
			}
			h, _ := NewTestHandler(t, obsv, cf, jobsStore, testFFClient, capiClient, ghTwirp, true, spokestest.NewClient(t,
				spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
					results := make([]bool, len(refs))
					for i, ref := range refs {
						results[i] = ref == "main" || ref == "refs/heads/main"
					}

					return results, nil
				}),
			))

			ctx := addUserToContext(context.Background(), t)
			resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
			require.NoError(t, err)
			assert.Equal(t, tt.code, resp.StatusCode)
			if tt.code != http.StatusCreated {
				return
			}

			assert.NotEmpty(t, resp.Body)
			result := &BaseJobResponse{}
			err = json.NewDecoder(w.Body).Decode(&result)
			require.NoError(t, err)
			assert.NotEmpty(t, result.ID)
		})
	}

	t.Run("rules validation error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := newTestTwirpAPI()

		spokes := spokestest.NewClient(t)
		spokes.MockCheckForExistingRefs = func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
			results := make([]bool, len(refs))
			for i, ref := range refs {
				results[i] = ref == "refs/heads/main" || ref == "refs/heads/copilot"
			}

			return results, nil
		}

		// Create a client factory that will trigger a rules validation error
		// by mocking the CheckIfBranchExists to return true for "copilot" branch
		cfRules := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockGetRepository: func(ctx context.Context, ownerName, repoName string) (*gg.Repository, error) {
						return &repo, nil
					},
					MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
						return &[]github.GQLBranchProtectionRule{}, nil
					},
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{}, nil
					},
				}, nil
			},
		}

		// Create the handler using normal setup but with our mocked GitHub client factory
		h, _ := NewTestHandler(t, obsv, cfRules, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
		require.NoError(t, err)

		// Should return 422 Unprocessable Entity for rules validation error
		require.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)

		// Response body should contain the error message about copilot branch existing
		responseBody := w.Body.String()
		require.Contains(t, responseBody, "A branch named `copilot` already exists")
	})

	t.Run("request validation error returns 400 Bad Request", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := newTestTwirpAPI()

		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
				results := make([]bool, len(refs))
				for i, ref := range refs {
					results[i] = ref == "refs/heads/main"
				}

				return results, nil
			}))

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

		// Create a problem statement that exceeds the maximum length to trigger validation error
		// Maximum is 30000 characters, so create a string longer than that
		longProblemStatement := strings.Repeat("a", 30001)

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, longProblemStatement, runName)
		require.NoError(t, err)

		// Should return 400 Bad Request for validation error
		require.Equal(t, http.StatusBadRequest, resp.StatusCode)

		// Response body should contain the error message about exceeding maximum length
		responseBody := w.Body.String()
		require.Contains(t, responseBody, "problem_statement exceeds maximum length")
	})
}

func TestCreateJobAsyncRulesValidationError(t *testing.T) {
	obsv := observability.NewNoopExporters()
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghTwirp := newTestTwirpAPI()

	runName := "Oregon Trail Problem"
	problemStatement := "You died of dysentery"
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(1)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}

	spokes := spokestest.NewClient(t)
	spokes.MockCheckForExistingRefs = func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
		results := make([]bool, len(refs))
		for i, ref := range refs {
			results[i] = ref == "refs/heads/main" || ref == "refs/heads/copilot"
		}

		return results, nil
	}

	// Create a client factory that will trigger a rules validation error
	// by mocking the CheckIfBranchExists to return true for "copilot" branch
	cf := &github.NoopClientFactory{
		MockRepositories: &map[string]gg.Repository{
			"oregon/trail": repo,
		},
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{
				MockRepositories: &map[string]gg.Repository{
					"oregon/trail": repo,
				},
				MockGetRepository: func(ctx context.Context, ownerName, repoName string) (*gg.Repository, error) {
					return &repo, nil
				},
				MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
					return &[]github.GQLBranchProtectionRule{}, nil
				},
				MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
					return &gg.BranchRules{}, nil
				},
			}, nil
		},
	}

	// Create the handler using normal setup but with our mocked GitHub client factory
	h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

	urlPath := "/jobs/v1/{owner}/{repo}"
	urlParams := map[string]string{"owner": *owner.Login, "repo": *repo.Name}

	ctx := addUserToContext(context.Background(), t)
	resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
	require.NoError(t, err)

	// Should return 422 Unprocessable Entity for rules validation error
	require.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)

	// Response body should contain the error message about copilot branch existing
	responseBody := w.Body.String()
	require.Contains(t, responseBody, "A branch named `copilot` already exists")
}

func TestCreateJobSyncRulesValidationError(t *testing.T) {
	obsv := observability.NewNoopExporters()
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghTwirp := newTestTwirpAPI()

	runName := "Oregon Trail Problem"
	problemStatement := "You died of dysentery"
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(1)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}

	spokes := spokestest.NewClient(t)
	spokes.MockCheckForExistingRefs = func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
		results := make([]bool, len(refs))
		for i, ref := range refs {
			results[i] = ref == "refs/heads/main" || ref == "refs/heads/copilot"
		}

		return results, nil
	}

	// Create a client factory that will trigger a rules validation error
	// by mocking the CheckIfBranchExists to return true for "copilot" branch
	cf := &github.NoopClientFactory{
		MockRepositories: &map[string]gg.Repository{
			"oregon/trail": repo,
		},
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{
				MockRepositories: &map[string]gg.Repository{
					"oregon/trail": repo,
				},
				MockGetRepository: func(ctx context.Context, ownerName, repoName string) (*gg.Repository, error) {
					return &repo, nil
				},
				MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
					return &[]github.GQLBranchProtectionRule{}, nil
				},
				MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
					return &gg.BranchRules{}, nil
				},
			}, nil
		},
	}

	// Create the handler using normal setup but with our mocked GitHub client factory
	h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

	// Use v0 URL path to test the synchronous endpoint (HandleNewJob)
	urlPath := "/jobs/{owner}/{repo}"
	urlParams := map[string]string{"owner": *owner.Login, "repo": *repo.Name}

	ctx := addUserToContext(context.Background(), t)
	resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
	require.NoError(t, err)

	// Should return 422 Unprocessable Entity for rules validation error
	require.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)

	// Response body should contain the error message about copilot branch existing
	responseBody := w.Body.String()
	require.Contains(t, responseBody, "A branch named `copilot` already exists")
}

func TestCancelJob(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ghTwirp := newTestTwirpAPI()

	runName := "Oregon Trail Problem"
	problemStatement := "You died of dysentery"
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(1)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}

	cf := &github.NoopClientFactory{
		MockRepositories: &map[string]gg.Repository{
			"oregon/trail": repo,
		},
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{
				MockRepositories: &map[string]gg.Repository{
					"oregon/trail": repo,
				},
				MockGetRepository: func(ctx context.Context, ownerName, repoName string) (*gg.Repository, error) {
					return &repo, nil
				},
			}, nil
		},
	}

	h, executor := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

	// Set up repositories API to return the test repository
	ghTwirp.NoopRepositoriesAPI = &githubtwirp.NoopRepositoriesAPI{
		MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         repo.GetID(),
						OwnerId:    repo.Owner.GetID(),
						Name:       repo.GetName(),
						OwnerLogin: repo.Owner.GetLogin(),
					},
				},
			}, nil
		},
	}

	testJob, _ := jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:        "job-1234",
		SessionID: "session-1234",
		OwnerID:   *owner.ID,
		RepoID:    *repo.ID,
		ComputeID: "test-compute-id",
		AgentID:   int64(sweagentdAppID),
		Status:    jobs.JobStatusRunning,
	})

	urlParams := map[string]string{"owner": owner.GetLogin(), "repo": repo.GetName(), "job": testJob.ID, "session": testJob.SessionID}
	for _, urlPath := range []string{
		"/jobs/{owner}/{repo}/{job}",
		"/jobs/{owner}/{repo}/sessions/{session}",
	} {
		t.Run(fmt.Sprintf("cancel job via %s", urlPath), func(t *testing.T) {
			executor.Launcher.TerminateAgentCalls = []launcher.TerminateAgentOpts{}
			ctx := addUserToContext(context.Background(), t)
			resp, _, err := callHandler(ctx, t, h, http.MethodDelete, urlPath, urlParams, problemStatement, runName)
			require.NoError(t, err)
			require.Equal(t, http.StatusNoContent, resp.StatusCode)
			require.Equal(t, apiVersion, resp.Header.Get("X-GitHub-Api-Version"))
			require.Equal(t, 1, len(executor.TerminateAgentCalls()))
			terminateCallOpts := executor.TerminateAgentCalls()[0]
			require.Equal(t, testJob.RepoID, terminateCallOpts.RepoID)
			require.Equal(t, testJob.OwnerID, terminateCallOpts.OwnerID)
			require.Equal(t, repo.GetName(), terminateCallOpts.RepoName)
			require.Equal(t, owner.GetLogin(), terminateCallOpts.RepoOwner)
			require.Equal(t, testJob.ComputeID, terminateCallOpts.ComputeID)
		})
	}
}

func TestGetJob(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ghTwirp := newTestTwirpAPI()

	h, executor := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

	runName := "Oregon Trail Problem"
	problemStatement := "You died of dysentery"
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(1)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}

	// Set up repositories API to return the test repository
	ghTwirp.NoopRepositoriesAPI = &githubtwirp.NoopRepositoriesAPI{
		MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         repo.GetID(),
						OwnerId:    repo.Owner.GetID(),
						Name:       repo.GetName(),
						OwnerLogin: repo.Owner.GetLogin(),
					},
				},
			}, nil
		},
	}

	cf.MockRepositories = &map[string]gg.Repository{
		"oregon/trail": repo,
	}
	pr := &gg.PullRequest{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("pull-request-node-id"),
		Title:  gg.Ptr("Pull Request Title"),
		Body:   gg.Ptr("Pull Request Body"),
		Number: gg.Ptr(1),
		Base: &gg.PullRequestBranch{
			SHA: gg.Ptr("base-sha"),
		},
		Head: &gg.PullRequestBranch{
			Ref: gg.Ptr("head-ref"),
		},
	}
	cf.MockPullRequest = pr
	workflowRun := gg.WorkflowRun{
		ID:         gg.Ptr(int64(12345678)),
		NodeID:     gg.Ptr("workflow-run-node-id"),
		Status:     gg.Ptr("completed"),
		HeadSHA:    gg.Ptr("head-sha"),
		HeadBranch: gg.Ptr("head-branch"),
		Name:       gg.Ptr("test-workflow"),
		Repository: &repo,
	}
	cf.MockWorkflowRun = &workflowRun

	testJob, _ := jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:                "job-1234",
		SessionID:         "session-1234",
		OwnerID:           *owner.ID,
		RepoID:            *repo.ID,
		ComputeID:         fmt.Sprintf("%d", *workflowRun.ID),
		PullRequestID:     *pr.ID,
		PullRequestNumber: *pr.Number,
		ActorID:           2,
		ActorLogin:        "test-user",
		AgentID:           int64(sweagentdAppID),
		Status:            jobs.JobStatusRunning,
		ProblemStatement: jobs.ProblemStatement{
			Content:           problemStatement,
			ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown,
		},
	})

	urlParams := map[string]string{"owner": "test-owner", "repo": "test-repo", "job": testJob.ID, "session": testJob.SessionID}
	for _, urlPath := range []string{
		"/jobs/{owner}/{repo}/{job}",
		"/jobs/{owner}/{repo}/sessions/{session}",
	} {
		t.Run(fmt.Sprintf("get job via %s", strings.ReplaceAll(urlPath, "/", "_")), func(t *testing.T) {
			executor.Launcher.TerminateAgentCalls = []launcher.TerminateAgentOpts{}
			ctx := addUserToContext(context.Background(), t)
			resp, w, err := callHandler(ctx, t, h, http.MethodGet, urlPath, urlParams, problemStatement, runName)
			require.NoError(t, err)
			assert.Equal(t, http.StatusOK, resp.StatusCode)
			assert.NotEmpty(t, resp.Body)
			result := &FullJobResponse{}
			err = json.NewDecoder(w.Body).Decode(&result)
			require.NoError(t, err)
			assert.NotEmpty(t, result.ID)
			assert.Nil(t, result.Error)
			assert.Equal(t, apiVersion, resp.Header.Get("X-GitHub-Api-Version"))
			assert.Equal(t, testJob.SessionID, result.SessionID)
			assert.Equal(t, testJob.ActorID, *result.Actor.ID)
			assert.Equal(t, testJob.ActorLogin, *result.Actor.Login)
			assert.Equal(t, jobs.JobStatusRunning, result.Status)
			assert.Equal(t, testJob.PullRequestID, *result.PullRequest.ID)
			assert.Equal(t, testJob.PullRequestNumber, *result.PullRequest.Number)
			assert.Equal(t, testJob.ComputeID, fmt.Sprintf("%d", *result.WorkflowRun.ID))
			assert.Equal(t, testJob.PullRequestNumber, *result.PullRequest.Number)
			assert.Equal(t, testJob.ProblemStatement.Content, result.ProblemStatement)
			assert.Equal(t, testJob.ProblemStatement.ContentFilterMode, result.ContentFilterMode)
			// Since this API does not return details, verify that we're not outputting the PR title and run status
			assert.Empty(t, result.PullRequest.GetTitle())
			assert.Empty(t, result.WorkflowRun.GetStatus())
		})
	}

	t.Run("job not found by session ID returns 404", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		urlPath := "/jobs/{owner}/{repo}/sessions/{session}"
		urlParams := map[string]string{
			"owner":   "test-owner",
			"repo":    "test-repo",
			"session": "non-existent-session-id", // Use non-existent session ID with existing repo
		}

		resp, _, err := callHandler(ctx, t, h, http.MethodGet, urlPath, urlParams, "", "")
		require.NoError(t, err)
		assert.Equal(t, http.StatusNotFound, resp.StatusCode)
		assert.Equal(t, "text/plain; charset=utf-8", resp.Header.Get("Content-Type"))
	})
}

func TestFeatureFlagClientRecreation(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	obsv := observability.NewNoopExporters()
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ghTwirp := newTestTwirpAPI()

	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("owner-node-id"),
		Login:  gg.Ptr("testowner"),
		Type:   gg.Ptr("organization"),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(100)),
		NodeID:        gg.Ptr("repo-node-id"),
		Name:          gg.Ptr("testrepo"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}

	cf := &github.NoopClientFactory{
		MockRepositories: &map[string]gg.Repository{
			"testowner/testrepo": repo,
		},
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{
				MockRepositories: &map[string]gg.Repository{
					"testowner/testrepo": repo,
				},
				MockGetRepository: func(ctx context.Context, ownerName, repoName string) (*gg.Repository, error) {
					return &repo, nil
				},
			}, nil
		},
	}

	h, executor := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

	// Override appProvider to include the custom agent with ID 67890
	customAgent := agenticapptest.NewTestCopilotWithID(t, 67890)
	h.appProvider = agenticapp.NewProvider(h.appProvider.CopilotApp(), customAgent)

	// Create a job with custom AgentID for cancellation test
	customAgentID := int64(67890)
	cancelJob, _ := jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:        "job-cancel",
		SessionID: "session-cancel",
		OwnerID:   *owner.ID,
		RepoID:    *repo.ID,
		ComputeID: "",
		Status:    jobs.JobStatusRunning, // Running status to test agent termination
		AgentID:   customAgentID,
	})

	// Create a completed job for the get test
	getJob, _ := jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:        "job-get",
		SessionID: "session-get",
		OwnerID:   *owner.ID,
		RepoID:    *repo.ID,
		ComputeID: "", // Empty to avoid validation errors
		Status:    jobs.JobStatusCompleted,
		AgentID:   customAgentID,
	})

	t.Run("cancel job with feature flag enabled", func(t *testing.T) {
		executor.Launcher.TerminateAgentCalls = []launcher.TerminateAgentOpts{}
		// Reset call tracking
		ghTwirp.IsAgentEnabledCalls = []githubtwirp.IsAgentEnabledCall{}
		ctx := addUserToContext(context.Background(), t)

		urlParams := map[string]string{
			"owner": *owner.Login,
			"repo":  *repo.Name,
			"job":   cancelJob.ID,
		}

		// With feature flag enabled, the handler should:
		// 1. Get repo info via twirp to fetch the job
		// 2. Fetch the job using those IDs
		// 3. Recreate client with job's AgentID
		// 4. Verify agent is enabled for that AgentID
		// 5. Cancel the job
		resp, recorder, err := callHandler(ctx, t, h, http.MethodDelete, "/jobs/{owner}/{repo}/{job}", urlParams, "", "")
		require.NoError(t, err)
		if resp.StatusCode != http.StatusNoContent {
			t.Logf("Response body: %s", recorder.Body.String())
		}
		require.Equal(t, http.StatusNoContent, resp.StatusCode)

		// Verify the job was cancelled
		require.Equal(t, 1, len(executor.TerminateAgentCalls()))

		// Verify IsAgentEnabled was called with the job's AgentID
		require.NotEmpty(t, ghTwirp.IsAgentEnabledCalls, "IsAgentEnabled should be called when feature flag is enabled")
		lastCall := ghTwirp.IsAgentEnabledCalls[len(ghTwirp.IsAgentEnabledCalls)-1]
		require.Equal(t, customAgentID, lastCall.AgentID, "IsAgentEnabled should be called with the job's AgentID")
		require.Equal(t, *repo.ID, lastCall.RepositoryID, "IsAgentEnabled should be called with the correct repository ID")
	})

	t.Run("get job with feature flag enabled", func(t *testing.T) {
		// Reset call tracking
		ghTwirp.IsAgentEnabledCalls = []githubtwirp.IsAgentEnabledCall{}
		ctx := addUserToContext(context.Background(), t)

		urlParams := map[string]string{
			"owner": *owner.Login,
			"repo":  *repo.Name,
			"job":   getJob.ID,
		}

		// With feature flag enabled, the handler should:
		// 1. Get repo info via twirp to fetch the job
		// 2. Fetch the job using those IDs
		// 3. Recreate client with job's AgentID
		// 4. Verify agent is enabled for that AgentID
		// 5. Return job details
		resp, recorder, err := callHandler(ctx, t, h, http.MethodGet, "/jobs/{owner}/{repo}/{job}", urlParams, "", "")
		require.NoError(t, err)
		if resp.StatusCode != http.StatusOK {
			t.Logf("Response body: %s", recorder.Body.String())
		}
		require.Equal(t, http.StatusOK, resp.StatusCode)

		// Verify IsAgentEnabled was called with the job's AgentID
		require.NotEmpty(t, ghTwirp.IsAgentEnabledCalls, "IsAgentEnabled should be called when feature flag is enabled")
		lastCall := ghTwirp.IsAgentEnabledCalls[len(ghTwirp.IsAgentEnabledCalls)-1]
		require.Equal(t, customAgentID, lastCall.AgentID, "IsAgentEnabled should be called with the job's AgentID")
		require.Equal(t, *repo.ID, lastCall.RepositoryID, "IsAgentEnabled should be called with the correct repository ID")
	})
}

func addUserToContext(ctx context.Context, t *testing.T) context.Context {
	t.Helper()
	return requestctx.AddData(ctx, &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         42,
			Login:      "user-login",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Type:          string(authd.CredentialTypeUserToServerToken),
				ApplicationID: 1,
				Token:         "test-token",
			},
		},
	})
}

func addUserWithoutRepoPushAccessToContext(ctx context.Context, t *testing.T) context.Context {
	t.Helper()
	return requestctx.AddData(ctx, &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "user-login-with-access-level-none", // Users ending in "-none" are treated as having no privs in github.NoopClient
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Type:          string(authd.CredentialTypeUserToServerToken),
				ApplicationID: 1,
				Token:         "test-token",
			},
		},
	})
}

func addPATToContext(ctx context.Context, t *testing.T, strType string) context.Context {
	t.Helper()
	return requestctx.AddData(ctx, &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "user-login",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Type:            strType,
				ApplicationType: "",
				Token:           "test-token",
			},
		},
	})
}

func addAppIDToContext(ctx context.Context, t *testing.T, strType string) context.Context {
	t.Helper()
	return requestctx.AddData(ctx, &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "user-login",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Type:            strType,
				ApplicationID:   sweagentdAppID,
				ApplicationType: "Integration",
				Token:           "test-token",
			},
		},
	})
}

// callHandlerWithRequest is the core handler function that allows for custom request bodies
func callHandlerWithRequest(ctx context.Context, t *testing.T, h *Handler, method, urlPath string, urlParams map[string]string, requestBody *NewJobAPIRequest) (*http.Response, *httptest.ResponseRecorder, error) {
	t.Helper()
	var err error
	reqBytes := []byte{}
	if method == http.MethodPost && requestBody != nil {
		reqBytes, err = json.Marshal(requestBody)
		if err != nil {
			return nil, nil, err
		}
	}
	req := httptest.NewRequestWithContext(ctx, method, urlPath, bytes.NewReader(reqBytes))
	if apiVersion != "" {
		req.Header.Set("X-GitHub-Api-Version", apiVersion)
	}
	rctx := chi.NewRouteContext()
	for k, v := range urlParams {
		rctx.URLParams.Add(k, v)
	}
	reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
	req = req.WithContext(reqCtx)
	w := httptest.NewRecorder()
	switch method {
	case http.MethodPost:
		switch {
		case strings.Contains(urlPath, "/cancel"):
			h.middleware(h.HandleCancelJob)(w, req)
		case strings.HasPrefix(urlPath, "/jobs/v1"):
			h.middleware(h.HandleNewJobAsync)(w, req)
		default:
			h.middleware(h.HandleNewJob)(w, req)
		}
	case http.MethodDelete:
		h.middleware(h.HandleCancelJob)(w, req)
	case http.MethodGet:
		if strings.Contains(urlPath, "/pulls/") {
			h.middleware(h.HandleListJobsForPullRequest)(w, req)
		} else {
			h.middleware(h.HandleGetJobByIDOrSessionID)(w, req)
		}
	default:
		return nil, nil, fmt.Errorf("unsupported method %s", method)
	}
	resp := w.Result()
	return resp, w, nil
}

func callHandler(ctx context.Context, t *testing.T, h *Handler, method, urlPath string, urlParams map[string]string, problemStatement, runName string) (*http.Response, *httptest.ResponseRecorder, error) {
	t.Helper()
	var requestBody *NewJobAPIRequest
	if method == http.MethodPost {
		requestBody = &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{},
			},
		}
	}
	return callHandlerWithRequest(ctx, t, h, method, urlPath, urlParams, requestBody)
}

// callHandlerWithJSONString sends a raw JSON string to the handler, simulating an HTTP request
// with a JSON body. This is useful for integration tests that want to test the full request/response cycle.
func callHandlerWithJSONString(ctx context.Context, t *testing.T, h *Handler, method, urlPath string, urlParams map[string]string, jsonBody string) (*http.Response, *httptest.ResponseRecorder, error) {
	t.Helper()
	req := httptest.NewRequestWithContext(ctx, method, urlPath, strings.NewReader(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	if apiVersion != "" {
		req.Header.Set("X-GitHub-Api-Version", apiVersion)
	}
	rctx := chi.NewRouteContext()
	for k, v := range urlParams {
		rctx.URLParams.Add(k, v)
	}
	reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
	req = req.WithContext(reqCtx)
	w := httptest.NewRecorder()

	switch method {
	case http.MethodPost:
		if strings.HasPrefix(urlPath, "/jobs/v1") {
			h.middleware(h.HandleNewJobAsync)(w, req)
		} else {
			h.middleware(h.HandleNewJob)(w, req)
		}
	default:
		return nil, nil, fmt.Errorf("unsupported method %s", method)
	}
	resp := w.Result()
	return resp, w, nil
}

func TestHandleListJobsForPullRequest(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ghTwirp := newTestTwirpAPI()

	h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(1)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}

	// Set up repositories API to return the test repository
	ghTwirp.NoopRepositoriesAPI = &githubtwirp.NoopRepositoriesAPI{
		MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         repo.GetID(),
						OwnerId:    repo.Owner.GetID(),
						Name:       repo.GetName(),
						OwnerLogin: repo.Owner.GetLogin(),
					},
				},
			}, nil
		},
	}

	cf.MockRepositories = &map[string]gg.Repository{
		"oregon/trail": repo,
	}

	// Create test jobs with different PR numbers
	_, _ = jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:                "job-1",
		SessionID:         "session-1",
		OwnerID:           *owner.ID,
		RepoID:            *repo.ID,
		PullRequestNumber: 123,
		ActorID:           2,
		ActorLogin:        "test-user",
		AgentID:           int64(sweagentdAppID),
		Status:            jobs.JobStatusCompleted,
	})

	_, _ = jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:                "job-2",
		SessionID:         "session-2",
		OwnerID:           *owner.ID,
		RepoID:            *repo.ID,
		PullRequestNumber: 123, // Same PR as job-1
		ActorID:           3,
		ActorLogin:        "another-user",
		AgentID:           int64(sweagentdAppID),
		Status:            jobs.JobStatusFailed,
	})

	_, _ = jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:                "job-3",
		SessionID:         "session-3",
		OwnerID:           *owner.ID,
		RepoID:            *repo.ID,
		PullRequestNumber: 456, // Different PR
		ActorID:           2,
		ActorLogin:        "test-user",
		AgentID:           int64(sweagentdAppID),
		Status:            jobs.JobStatusRunning,
	})

	testCases := []struct {
		name               string
		prNumber           string
		expectedStatusCode int
		expectedJobCount   int
		expectedJobIDs     []string
		checkAPIVersion    bool
	}{
		{
			name:               "list jobs for existing PR",
			prNumber:           "123",
			expectedStatusCode: http.StatusOK,
			expectedJobCount:   2,
			expectedJobIDs:     []string{"job-1", "job-2"},
			checkAPIVersion:    true,
		},
		{
			name:               "list jobs for PR with single job",
			prNumber:           "456",
			expectedStatusCode: http.StatusOK,
			expectedJobCount:   1,
			expectedJobIDs:     []string{"job-3"},
			checkAPIVersion:    false,
		},
		{
			name:               "list jobs for non-existent PR",
			prNumber:           "999",
			expectedStatusCode: http.StatusOK,
			expectedJobCount:   0,
			expectedJobIDs:     []string{},
			checkAPIVersion:    false,
		},
		{
			name:               "invalid PR number",
			prNumber:           "invalid",
			expectedStatusCode: http.StatusBadRequest,
			expectedJobCount:   -1, // -1 indicates we don't check job count for error cases
			expectedJobIDs:     nil,
			checkAPIVersion:    false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			ctx := addUserToContext(context.Background(), t)
			urlPath := "/jobs/{owner}/{repo}/pulls/{prNumber}"
			urlParams := map[string]string{
				"owner":    *owner.Login,
				"repo":     *repo.Name,
				"prNumber": tc.prNumber,
			}

			resp, w, err := callHandler(ctx, t, h, http.MethodGet, urlPath, urlParams, "", "")
			require.NoError(t, err)
			assert.Equal(t, tc.expectedStatusCode, resp.StatusCode)

			if tc.expectedStatusCode == http.StatusOK {
				assert.NotEmpty(t, resp.Body)

				var result []*FullJobResponse
				err = json.NewDecoder(w.Body).Decode(&result)
				require.NoError(t, err)
				assert.Len(t, result, tc.expectedJobCount)

				if tc.expectedJobCount > 0 {
					// Verify the correct jobs are returned
					jobIDs := make([]string, len(result))
					for i, job := range result {
						jobIDs[i] = job.ID
					}
					for _, expectedID := range tc.expectedJobIDs {
						assert.Contains(t, jobIDs, expectedID)
					}
				}

				if tc.checkAPIVersion {
					assert.Equal(t, apiVersion, resp.Header.Get("X-GitHub-Api-Version"))
				}
			}
		})
	}

	// Test missing PR number separately since it requires different URL params
	t.Run("missing PR number", func(t *testing.T) {
		ctx := addUserToContext(context.Background(), t)
		urlPath := "/jobs/{owner}/{repo}/pulls/{prNumber}"
		urlParams := map[string]string{
			"owner": *owner.Login,
			"repo":  *repo.Name,
			// prNumber is intentionally missing
		}
		resp, _, err := callHandler(ctx, t, h, http.MethodGet, urlPath, urlParams, "", "")
		require.NoError(t, err)
		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
	})
}

func TestHandleCheckEnablement(t *testing.T) {
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(2)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}

	t.Run("returns unauthorized for unauthenticated requests", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		obsv := observability.NewNoopExporters()
		cf := &github.NoopClientFactory{}
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

		// Context without user info - simulates unauthenticated request
		ctx := context.Background()
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/oregon/trail/enabled", nil)
		req.Header.Set("X-GitHub-Api-Version", apiVersion)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "oregon")
		rctx.URLParams.Add("repo", "trail")
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)

		w := httptest.NewRecorder()
		h.middleware(h.HandleCheckEnablement)(w, req)

		resp := w.Result()
		assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("returns forbidden when CCA is not enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		obsv := observability.NewNoopExporters()
		cf := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
		}
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()

		// Set up twirp client with CCA disabled
		ghTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: false, // CCA disabled
				},
			},
			NoopAuthorizationAPI: &githubtwirp.NoopAuthorizationAPI{},
		}

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/oregon/trail/enabled", nil)
		req.Header.Set("X-GitHub-Api-Version", apiVersion)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "oregon")
		rctx.URLParams.Add("repo", "trail")
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)

		w := httptest.NewRecorder()
		h.middleware(h.HandleCheckEnablement)(w, req)

		resp := w.Result()
		assert.Equal(t, http.StatusForbidden, resp.StatusCode)
	})

	t.Run("returns forbidden with error message when repository rules fail", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		obsv := observability.NewNoopExporters()
		cf := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
		}
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()

		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

		// Mock the jobService to return rules violations
		mockJobService := &MockJobService{
			MockCheckRules: func(ctx context.Context, gh jobservice.BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string) *jobservice.CheckRulesResult {
				return &jobservice.CheckRulesResult{
					Rules: []string{"branch protection rule violated", "repository rule violated"},
				}
			},
		}
		h.jobService = mockJobService

		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/oregon/trail/enabled", nil)
		req.Header.Set("X-GitHub-Api-Version", apiVersion)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "oregon")
		rctx.URLParams.Add("repo", "trail")
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)

		w := httptest.NewRecorder()
		h.middleware(h.HandleCheckEnablement)(w, req)

		resp := w.Result()
		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)

		// Read response body to check error message
		body := make([]byte, w.Body.Len())
		_, err := w.Body.Read(body)
		require.NoError(t, err)
		bodyStr := string(body)
		assert.Contains(t, bodyStr, "repository rules violation")
		assert.Contains(t, bodyStr, "branch protection rule violated")
		assert.Contains(t, bodyStr, "repository rule violated")
	})

	t.Run("returns 200 when everything checks out", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		obsv := observability.NewNoopExporters()
		cf := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
		}
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()

		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

		// Mock the jobService to return no rules violations
		mockJobService := &MockJobService{
			MockCheckRules: func(ctx context.Context, gh jobservice.BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string) *jobservice.CheckRulesResult {
				return &jobservice.CheckRulesResult{
					Rules: []string{}, // No rules violations
				}
			},
		}
		h.jobService = mockJobService

		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/oregon/trail/enabled", nil)
		req.Header.Set("X-GitHub-Api-Version", apiVersion)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "oregon")
		rctx.URLParams.Add("repo", "trail")
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)

		w := httptest.NewRecorder()
		h.middleware(h.HandleCheckEnablement)(w, req)

		resp := w.Result()
		assert.Equal(t, http.StatusOK, resp.StatusCode)
	})

	t.Run("uses correct job data for rules checking", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		obsv := observability.NewNoopExporters()
		cf := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
		}
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

		// Mock the jobService to capture the job data passed to CheckRules
		var capturedJob *jobs.Job
		mockJobService := &MockJobService{
			MockCheckRules: func(ctx context.Context, gh jobservice.BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string) *jobservice.CheckRulesResult {
				capturedJob = job
				return &jobservice.CheckRulesResult{
					Rules: []string{}, // No rules violations
				}
			},
		}
		h.jobService = mockJobService

		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/oregon/trail/enabled", nil)
		req.Header.Set("X-GitHub-Api-Version", apiVersion)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "oregon")
		rctx.URLParams.Add("repo", "trail")
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)

		w := httptest.NewRecorder()
		h.middleware(h.HandleCheckEnablement)(w, req)

		resp := w.Result()
		assert.Equal(t, http.StatusOK, resp.StatusCode)

		// Verify the job data passed to CheckRules
		require.NotNil(t, capturedJob)
		assert.Equal(t, repo.Owner.GetID(), capturedJob.OwnerID)
		assert.Equal(t, repo.GetID(), capturedJob.RepoID)
		assert.Equal(t, repo.GetNodeID(), capturedJob.RepoNodeID)
		// RepoName and RepoOwner fields removed - they were stale and can be fetched dynamically
		assert.Equal(t, "copilot/not-a-real-branch", capturedJob.BranchName)
	})

	t.Run("handles AbuseRateLimitError", func(t *testing.T) {
		testCases := []struct {
			name                  string
			resetAfter            time.Duration
			isPrimaryRateLimit    bool
			expectedStatusCode    int
			expectedMinRetryAfter int
			expectedMaxRetryAfter int
		}{
			{
				name:                  "5 minute reset (primary)",
				resetAfter:            5 * time.Minute,
				isPrimaryRateLimit:    true,
				expectedStatusCode:    429,
				expectedMinRetryAfter: 290,
				expectedMaxRetryAfter: 300,
			},
			{
				name:                  "0 reset should use default (primary)",
				resetAfter:            0 * time.Minute,
				isPrimaryRateLimit:    true,
				expectedStatusCode:    429,
				expectedMinRetryAfter: 1,
				expectedMaxRetryAfter: 3,
			},
			{
				name:                  "negative reset should use default (primary)",
				resetAfter:            -10 * time.Minute,
				isPrimaryRateLimit:    true,
				expectedStatusCode:    429,
				expectedMinRetryAfter: 1,
				expectedMaxRetryAfter: 3,
			},
			{
				name:                  "5 minute reset (secondary)",
				resetAfter:            5 * time.Minute,
				isPrimaryRateLimit:    false,
				expectedStatusCode:    503,
				expectedMinRetryAfter: 290,
				expectedMaxRetryAfter: 300,
			},
			{
				name:                  "0 reset should use default (secondary)",
				resetAfter:            0 * time.Minute,
				isPrimaryRateLimit:    false,
				expectedStatusCode:    503,
				expectedMinRetryAfter: 1,
				expectedMaxRetryAfter: 3,
			},
			{
				name:                  "negative reset should use default (secondary)",
				resetAfter:            -10 * time.Minute,
				isPrimaryRateLimit:    false,
				expectedStatusCode:    503,
				expectedMinRetryAfter: 1,
				expectedMaxRetryAfter: 3,
			},
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		obsv := observability.NewNoopExporters()
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		// Set up repositories API to return the test repository
		ghTwirp.NoopRepositoriesAPI = &githubtwirp.NoopRepositoriesAPI{
			MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{
							Id:         repo.GetID(),
							OwnerId:    repo.Owner.GetID(),
							Name:       repo.GetName(),
							OwnerLogin: repo.Owner.GetLogin(),
						},
					},
				}, nil
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				var rateLimitErr error
				if tc.isPrimaryRateLimit {
					rateLimitErr = limiter.NewTargetRateLimitError(
						sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
						"rate limit exceeded",
						limiter.Rate{Reset: time.Now().Add(tc.resetAfter)})
				} else {
					rateLimitErr = limiter.NewTargetAbuseRateLimitError(
						sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
						"rate limit exceeded",
						tc.resetAfter)
				}

				// Create a job in the store so GetJobByID succeeds
				_, err := jobsStore.CreateJob(context.Background(), &jobs.Job{
					ID:      "job123",
					OwnerID: repo.Owner.GetID(),
					RepoID:  repo.GetID(),
					AgentID: int64(sweagentdAppID),
					Status:  jobs.JobStatusRunning,
				})
				require.NoError(t, err)

				cf := &github.NoopClientFactory{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockNewClientFromRepoName: func(ctx context.Context, app sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
						return nil, rateLimitErr
					},
				}

				h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

				ctx := addUserToContext(context.Background(), t)
				req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/owner/repo/job123", nil)

				// Set up route context
				rctx := chi.NewRouteContext()
				rctx.URLParams.Add("owner", "oregon")
				rctx.URLParams.Add("repo", "trail")
				rctx.URLParams.Add("job", "job123")
				reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
				req = req.WithContext(reqCtx)

				w := httptest.NewRecorder()

				// Call the middleware wrapped handler
				h.middleware(h.HandleGetJobByIDOrSessionID)(w, req)

				resp := w.Result()
				defer resp.Body.Close()

				// Verify the response
				assert.Equal(t, tc.expectedStatusCode, resp.StatusCode)

				// Verify Retry-After header is set correctly
				retryAfter := resp.Header.Get("Retry-After")
				assert.NotEmpty(t, retryAfter)

				// Parse the retry after value and verify it's reasonable
				retryAfterSeconds, err := strconv.Atoi(retryAfter)
				require.NoError(t, err)
				assert.GreaterOrEqual(t, retryAfterSeconds, tc.expectedMinRetryAfter) // Allow some tolerance for timing
				assert.LessOrEqual(t, retryAfterSeconds, tc.expectedMaxRetryAfter)

				// Verify response body
				if tc.isPrimaryRateLimit {
					assert.Contains(t, w.Body.String(), "primary rate limit exceeded")
				} else {
					assert.Contains(t, w.Body.String(), "secondary rate limit exceeded")
				}
			})
		}
	})
}

// MockJobService is a mock implementation of the jobService interface for testing
type MockJobService struct {
	MockGetJobByID            func(ctx context.Context, ownerID, repoID int64, jobID string) (*jobs.Job, error)
	MockGetJobBySessionID     func(ctx context.Context, ownerID, repoID int64, sessionID string) (*jobs.Job, error)
	MockGetCustomAgent        func(ctx context.Context, params jobservice.GetCustomAgentParams) (sweagentd.CustomAgent, error)
	MockNewJobBuilder         func(action jobs.AgentAction, repo *gg.Repository, baseCommit string) *jobservice.JobBuilder
	MockQueueJobForProcessing func(ctx context.Context, job *jobs.Job) (*aqueductJobs.APIJob, error)
	MockQueueJobForExecution  func(ctx context.Context, job *jobs.Job) (*aqueductJobs.AgentJob, error)
	MockCheckRules            func(ctx context.Context, gh jobservice.BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string) *jobservice.CheckRulesResult
}

func (m *MockJobService) GetJobByID(ctx context.Context, ownerID, repoID int64, jobID string) (*jobs.Job, error) {
	if m.MockGetJobByID != nil {
		return m.MockGetJobByID(ctx, ownerID, repoID, jobID)
	}
	return nil, errors.New("mock not implemented")
}

func (m *MockJobService) GetJobBySessionID(ctx context.Context, ownerID, repoID int64, sessionID string) (*jobs.Job, error) {
	if m.MockGetJobBySessionID != nil {
		return m.MockGetJobBySessionID(ctx, ownerID, repoID, sessionID)
	}
	return nil, errors.New("mock not implemented")
}

func (m *MockJobService) GetCustomAgent(ctx context.Context, params jobservice.GetCustomAgentParams) (sweagentd.CustomAgent, error) {
	if m.MockGetCustomAgent != nil {
		return m.MockGetCustomAgent(ctx, params)
	}
	return nil, errors.New("mock not implemented")
}

func (m *MockJobService) NewJobBuilder(action jobs.AgentAction, repo *gg.Repository, baseCommit string) *jobservice.JobBuilder {
	if m.MockNewJobBuilder != nil {
		return m.MockNewJobBuilder(action, repo, baseCommit)
	}
	return nil
}

func (m *MockJobService) QueueJobForProcessing(ctx context.Context, job *jobs.Job) (*aqueductJobs.APIJob, error) {
	if m.MockQueueJobForProcessing != nil {
		return m.MockQueueJobForProcessing(ctx, job)
	}
	return nil, errors.New("mock not implemented")
}

func (m *MockJobService) QueueJobForExecution(ctx context.Context, job *jobs.Job) (*aqueductJobs.AgentJob, error) {
	if m.MockQueueJobForExecution != nil {
		return m.MockQueueJobForExecution(ctx, job)
	}
	return nil, errors.New("mock not implemented")
}

func (m *MockJobService) CheckRules(ctx context.Context, gh jobservice.BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string) *jobservice.CheckRulesResult {
	if m.MockCheckRules != nil {
		return m.MockCheckRules(ctx, gh, agent, job, repoOwner, repoName, branchName)
	}
	return &jobservice.CheckRulesResult{Rules: []string{}}
}

func TestBaseRefValidation(t *testing.T) {
	obsv := observability.NewNoopExporters()
	runName := "Test Problem"
	problemStatement := "Test problem statement"
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("test-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(2)),
		NodeID:        gg.Ptr("repo-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}
	urlPath := "/jobs/{owner}/{repo}"
	urlParams := map[string]string{"owner": *owner.Login, "repo": *repo.Name}

	t.Run("base ref exists - pull request", func(t *testing.T) {
		// Enable the feature flag
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		spokesCalls := 0
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				defer func() {
					spokesCalls++
				}()

				// First call is for the base ref as provided in the request; subsequent calls
				// are for the branch that would be created for the job
				if spokesCalls == 0 {
					require.Equal(t, 1, len(refNames))
					require.Equal(t, "refs/heads/feature-branch", refNames[0])
					return []bool{true}, nil // ref exists
				}
				return make([]bool, len(refNames)), nil
			}))

		cf := &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
				}, nil
			},
		}

		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

		// Create request with pull request feature that has base ref
		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					BaseRef: "feature-branch",
				},
			},
		}

		ctx := addUserToContext(context.Background(), t)
		resp, _, err := callHandlerWithRequest(ctx, t, h, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)
	})

	t.Run("base ref does not exist - pull request", func(t *testing.T) {
		// Enable the feature flag
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				require.Equal(t, 1, len(refNames))
				require.Equal(t, "refs/heads/nonexistent-branch", refNames[0])
				return make([]bool, len(refNames)), nil // ref does not exist
			}))

		cf := &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
				}, nil
			},
		}

		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

		// Create request with pull request feature that has non-existent base ref
		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					BaseRef: "nonexistent-branch",
				},
			},
		}

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithRequest(ctx, t, h, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)

		responseBody := w.Body.String()
		assert.Contains(t, responseBody, "base ref does not exist")
	})

	t.Run("no base ref specified - default to main", func(t *testing.T) {
		// Enable the feature flag
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		spokesCalls := 0
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				defer func() {
					spokesCalls++
				}()

				// First call is for the base ref as provided in the request; subsequent calls
				// are for the branch that would be created for the job
				if spokesCalls == 0 {
					require.Equal(t, 1, len(refNames))
					require.Equal(t, "refs/heads/main", refNames[0])
					return []bool{true}, nil // ref exists
				}
				return make([]bool, len(refNames)), nil
			}))

		cf := &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
				}, nil
			},
		}

		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokes)

		// Create request without base ref specified
		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					// No BaseRef specified
				},
			},
		}

		ctx := addUserToContext(context.Background(), t)
		resp, _, err := callHandlerWithRequest(ctx, t, h, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)
	})
}

func TestSessionErrorsRelayed(t *testing.T) {
	t.Run("session errors are relayed to appropriate HTTP status code in jobs API", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		handler := &Handler{obsv: obsv}
		logger := obsv.Logger

		testCases := []struct {
			name               string
			err                error
			expectedStatusCode int
		}{
			{
				name:               "SessionNotFound error returns 404",
				err:                capi.ErrSessionNotFound,
				expectedStatusCode: http.StatusNotFound,
			},
			{
				name:               "SessionUnauthorized error returns 401",
				err:                capi.ErrSessionUnauthorized,
				expectedStatusCode: http.StatusUnauthorized,
			},
			{
				name:               "SessionRateLimited error returns 429",
				err:                capi.ErrSessionRateLimited,
				expectedStatusCode: http.StatusTooManyRequests,
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				ctx := context.Background()
				w := httptest.NewRecorder()

				err := handler.errorResponseWithError(ctx, w, nil, logger, tc.err, "error message")

				require.NoError(t, err)
				require.Equal(t, tc.expectedStatusCode, w.Code)
				require.Equal(t, "text/plain; charset=utf-8", w.Header().Get("Content-Type"))
			})
		}
	})
}

func TestMiddlewareRequestLogging(t *testing.T) {
	t.Run("logs request completion with duration and status code for successful request", func(t *testing.T) {
		// Capture log output
		var logBuffer bytes.Buffer
		logger, err := log.NewFromConfig(log.Config{}, log.WithWriteSyncer(zapcore.AddSync(&logBuffer)), log.WithJSONConsole())
		require.NoError(t, err)

		obsv := observability.NewNoopExporters()
		obsv.Logger = logger

		cf := &github.NoopClientFactory{}
		jobsStore := memory.NewStore()
		ffClient := featureflags.NewNoopClientWithAppID(map[string]bool{}, testAppID)
		capiClient := capi.NewNoopClient()
		ghTwirp := newTestTwirpAPI()
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
				return slices.Repeat([]bool{true}, len(refs)), nil
			}))

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, false, spokes)

		// Create a request with valid auth context
		req := httptest.NewRequest(http.MethodGet, "/jobs/testowner/testrepo/testjobid", http.NoBody)
		ctx := addAppIDToContext(req.Context(), t, string(authd.CredentialTypeUserToServerToken))
		req = req.WithContext(ctx)

		// Add chi URL params
		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "testowner")
		rctx.URLParams.Add("repo", "testrepo")
		rctx.URLParams.Add("job", "testjobid")
		req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

		w := httptest.NewRecorder()

		// Call the middleware wrapped handler
		h.middleware(h.HandleGetJobByIDOrSessionID)(w, req)

		// Sync logger to flush buffer
		_ = logger.Sync()

		// Verify the log contains the expected fields
		logOutput := logBuffer.String()

		// Should contain the request completion log with duration and status code
		assert.Contains(t, logOutput, "job api request completed")
		assert.Contains(t, logOutput, "duration_ms")
		assert.Contains(t, logOutput, "http.status_code")
	})

	t.Run("logs error message, duration, and status code for failed request", func(t *testing.T) {
		// Capture log output
		var logBuffer bytes.Buffer
		logger, err := log.NewFromConfig(log.Config{}, log.WithWriteSyncer(zapcore.AddSync(&logBuffer)), log.WithJSONConsole())
		require.NoError(t, err)

		obsv := observability.NewNoopExporters()
		obsv.Logger = logger

		cf := &github.NoopClientFactory{}
		jobsStore := memory.NewStore()
		ffClient := featureflags.NewNoopClientWithAppID(map[string]bool{}, testAppID)
		capiClient := capi.NewNoopClient()
		ghTwirp := newTestTwirpAPI()
		spokes := spokestest.NewClient(t)

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, false, spokes)

		// Create a request WITHOUT chi URL params to trigger an error
		req := httptest.NewRequest(http.MethodGet, "/jobs/", http.NoBody)
		ctx := addAppIDToContext(req.Context(), t, string(authd.CredentialTypeUserToServerToken))
		req = req.WithContext(ctx)

		// Add empty chi URL params (missing owner/repo)
		rctx := chi.NewRouteContext()
		req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

		w := httptest.NewRecorder()

		// Call the middleware wrapped handler
		h.middleware(h.HandleGetJobByIDOrSessionID)(w, req)

		// Sync logger to flush buffer
		_ = logger.Sync()

		// Verify the response is an error
		assert.Equal(t, http.StatusBadRequest, w.Code)

		// Verify the log contains the error
		logOutput := logBuffer.String()

		assert.Contains(t, logOutput, "job api request completed")
		assert.Contains(t, logOutput, "exception.message")
		assert.Contains(t, logOutput, "API call requires repo_owner and repo_name")
		assert.Contains(t, logOutput, `"http.status_code":400`)
		assert.Contains(t, logOutput, "duration_ms")
	})
}

func TestAuthorizationFailureLogging(t *testing.T) {
	t.Run("logs authorization failed for 401 errors", func(t *testing.T) {
		// Capture log output
		var logBuffer bytes.Buffer
		logger, err := log.NewFromConfig(log.Config{}, log.WithWriteSyncer(zapcore.AddSync(&logBuffer)), log.WithJSONConsole())
		require.NoError(t, err)

		obsv := observability.NewNoopExporters()
		obsv.Logger = logger

		cf := &github.NoopClientFactory{}
		jobsStore := memory.NewStore()
		ffClient := featureflags.NewNoopClientWithAppID(map[string]bool{}, testAppID)
		capiClient := capi.NewNoopClient()
		ghTwirp := newTestTwirpAPI()
		spokes := spokestest.NewClient(t)

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, false, spokes)

		// Create a request with an unsupported token type (ServerToServerToken is not allowed)
		req := httptest.NewRequest(http.MethodGet, "/jobs/testowner/testrepo/testjobid", http.NoBody)
		ctx := addAppIDToContext(req.Context(), t, string(authd.CredentialTypeServerToServerToken))
		req = req.WithContext(ctx)

		// Add chi URL params
		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "testowner")
		rctx.URLParams.Add("repo", "testrepo")
		rctx.URLParams.Add("job", "testjobid")
		req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

		w := httptest.NewRecorder()

		// Call the middleware wrapped handler
		h.middleware(h.HandleGetJobByIDOrSessionID)(w, req)

		// Sync logger to flush buffer
		_ = logger.Sync()

		// Verify the response is 401 Unauthorized
		assert.Equal(t, http.StatusUnauthorized, w.Code)

		// Verify the log contains the authorization failure info
		logOutput := logBuffer.String()

		assert.Contains(t, logOutput, "authorization failed")
		assert.Contains(t, logOutput, "exception.message")
		assert.Contains(t, logOutput, `"http.status_code":401`)
		assert.Contains(t, logOutput, "repo_owner")
		assert.Contains(t, logOutput, "repo_name")
	})
}

func TestRepoPassedAsParameter(t *testing.T) {
	owner := gg.User{
		ID:     gg.Ptr(int64(1)),
		NodeID: gg.Ptr("oregon-node-id"),
		Login:  gg.Ptr("oregon"),
		Type:   gg.Ptr("organization"),
		Name:   gg.Ptr("Oregon Wagon Co. Inc."),
	}
	repo := gg.Repository{
		ID:            gg.Ptr(int64(2)),
		NodeID:        gg.Ptr("trail-node-id"),
		Name:          gg.Ptr("trail"),
		Owner:         &owner,
		DefaultBranch: gg.Ptr("main"),
	}

	t.Run("feature flag off - repo fetched in getClientWithRepo", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWERepoFromParams: false,
		})
		obsv := observability.NewNoopExporters()

		getRepoCallCount := 0
		cf := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockGetRepository: func(ctx context.Context, o, r string) (*gg.Repository, error) {
						getRepoCallCount++
						return &repo, nil
					},
				}, nil
			},
		}
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/oregon/trail/enabled", nil)
		req.Header.Set("X-GitHub-Api-Version", apiVersion)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "oregon")
		rctx.URLParams.Add("repo", "trail")
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)

		w := httptest.NewRecorder()
		h.middleware(h.HandleCheckEnablement)(w, req)

		resp := w.Result()
		assert.Equal(t, http.StatusOK, resp.StatusCode)
		// With FF off, GetRepository should be called once in getClientWithRepo
		assert.Equal(t, 1, getRepoCallCount, "GetRepository should be called once in getClientWithRepo when FF is off")
	})

	t.Run("feature flag on - repo fetched in authorizeUser and passed to handler", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWERepoFromParams: true,
		})
		obsv := observability.NewNoopExporters()

		getRepoCallCountInHandler := 0
		cf := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockGetRepository: func(ctx context.Context, o, r string) (*gg.Repository, error) {
						getRepoCallCountInHandler++
						return &repo, nil
					},
				}, nil
			},
		}
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/oregon/trail/enabled", nil)
		req.Header.Set("X-GitHub-Api-Version", apiVersion)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "oregon")
		rctx.URLParams.Add("repo", "trail")
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)

		w := httptest.NewRecorder()
		h.middleware(h.HandleCheckEnablement)(w, req)

		resp := w.Result()
		assert.Equal(t, http.StatusOK, resp.StatusCode)
		// With FF on, GetRepository should NOT be called in getClientWithRepo (repo passed as parameter from middleware)
		assert.Equal(t, 0, getRepoCallCountInHandler, "GetRepository should not be called in getClientWithRepo when FF is on")
	})

	t.Run("feature flag on - uses canonical repo name for renamed repos", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWERepoFromParams: true,
		})
		obsv := observability.NewNoopExporters()

		// The canonical (new) repo name returned by GitHub
		canonicalOwner := gg.User{
			ID:     gg.Ptr(int64(1)),
			NodeID: gg.Ptr("owner-node-id"),
			Login:  gg.Ptr("new-owner"),
			Type:   gg.Ptr("organization"),
		}
		canonicalRepo := gg.Repository{
			ID:            gg.Ptr(int64(2)),
			NodeID:        gg.Ptr("repo-node-id"),
			Name:          gg.Ptr("new-repo"),
			Owner:         &canonicalOwner,
			DefaultBranch: gg.Ptr("main"),
		}

		var usedOwnerInClient string
		var usedRepoInClient string

		cf := &github.NoopClientFactory{
			// When GetRepository is called with old name, return the canonical repo
			MockRepositories: &map[string]gg.Repository{
				"old-owner/old-repo": canonicalRepo,
			},
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				usedOwnerInClient = ownerName
				usedRepoInClient = repoName
				return &github.NoopClient{}, nil
			},
		}
		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true, spokestest.NewClient(t))

		// Use old names in URL params
		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/jobs/old-owner/old-repo/enabled", nil)
		req.Header.Set("X-GitHub-Api-Version", apiVersion)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("owner", "old-owner")
		rctx.URLParams.Add("repo", "old-repo")
		reqCtx := context.WithValue(ctx, chi.RouteCtxKey, rctx)
		req = req.WithContext(reqCtx)

		w := httptest.NewRecorder()
		h.middleware(h.HandleCheckEnablement)(w, req)

		resp := w.Result()
		assert.Equal(t, http.StatusOK, resp.StatusCode)
		// Verify that the canonical (new) names were used when creating the client
		assert.Equal(t, "new-owner", usedOwnerInClient, "Should use canonical owner name from repo parameter")
		assert.Equal(t, "new-repo", usedRepoInClient, "Should use canonical repo name from repo parameter")
	})
}
