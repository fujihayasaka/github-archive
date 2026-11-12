package jobapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	authd "github.com/github/authnd/client"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
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
)

const (
	sweagentdAppID = 1
	testAppID      = 2
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

func NewTestHandler(t *testing.T, obsv observability.Exporters, cf github.ClientFactoryInterface, jobsStore db.JobsStore, ffClient featureflags.Client, capiClient capi.Client, ghTwirp githubtwirp.ClientInterface, privilegedAppCheckerResult bool) (*Handler, *jobexecutor.TestJobExecutor) {
	jobLimiter := limiter.NewJobLimiter(jobsStore, 10, time.Hour)
	aq := aqueduct.NewMemoryClient(obsv)
	spokes := spokestest.NewClient(t)
	jobService := jobservice.New(obsv, ffClient, jobsStore, capiClient, cf, ghTwirp, aq, jobLimiter, experiments.NewNoopClient(), customagent.NewService(obsv, spokes, ghTwirp, ffClient), "test@example.com", spokes)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, jobsStore, cf, ghTwirp, capiClient, jobLimiter, jobService)
	handler := NewHandler(obsv, cf, jobService, jobsStore, ffClient, executor, ghTwirp, sweagentdAppID)
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
		RepoOwner: *owner.Login,
		OwnerID:   *owner.ID,
		RepoID:    *repo.ID,
		RepoName:  *repo.Name,
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
			"owner": testJob.RepoOwner,
			"repo":  testJob.RepoName,
			"job":   testJob.ID,
		},
		"POST:/jobs/{owner}/{repo}/sessions/{session}/cancel": {
			"owner":   testJob.RepoOwner,
			"repo":    testJob.RepoName,
			"session": testJob.SessionID,
		},
		"GET:/jobs/{owner}/{repo}/{job}": {
			"owner": testJob.RepoOwner,
			"repo":  testJob.RepoName,
			"job":   testJob.ID,
		},
		"GET:/jobs/{owner}/{repo}/sessions/{session}": {
			"owner":   testJob.RepoOwner,
			"repo":    testJob.RepoName,
			"session": testJob.SessionID,
		},
		"GET:/jobs/{owner}/{repo}/pulls/{prNumber}": {
			"owner":    testJob.RepoOwner,
			"repo":     testJob.RepoName,
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
			altH, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirp, true)
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
				altH, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirp, true)
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
		h, _ := NewTestHandler(t, obsv, args.cf, args.jobsStore, ffAltClient, capiClient, ghTwirp, privilegedAppCheckerResult)
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
				assert.Equal(t, http.StatusCreated, resp.StatusCode)
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
				IsSweagentdEnabled: true,
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
							Id:         2,
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

	h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

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
		h1, _ := NewTestHandler(t, obsv, cfTest, jobsStore, ffClient, capiClient, ghTwirp, true)
		resp1, w1 := callAPI(h1)
		assert.Equal(t, http.StatusBadRequest, resp1.StatusCode)
		assert.NotEmpty(t, resp1.Body)
		result1 := make(map[string]interface{})
		err1 := json.NewDecoder(w1.Body).Decode(&result1)
		require.NoError(t, err1)
		assert.Equal(t, "invalid repository: failed to get required information: invalid repository: bad request", result1["message"])

		// Simulate internal error
		ghTwirpAlt := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return nil, errors.New("internal error")
				},
			},
			NoopLimiterAPI:       &githubtwirp.NoopLimiterAPI{},
			NoopUserDetailAPI:    &githubtwirp.NoopUserDetailAPI{},
			NoopAuthorizationAPI: &githubtwirp.NoopAuthorizationAPI{},
		}
		h2, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirpAlt, true)
		resp2, w2 := callAPI(h2)
		assert.Equal(t, http.StatusInternalServerError, resp2.StatusCode)
		assert.NotEmpty(t, resp2.Body)
		result2 := make(map[string]interface{})
		err2 := json.NewDecoder(w2.Body).Decode(&result2)
		require.NoError(t, err2)
		assert.Equal(t, "failed to draft job: failed to create pull request: failed to create pull request: internal error", result2["message"])
	})

	t.Run("custom agent not found returns 404 version", func(t *testing.T) {
		ffAltClient := featureflags.NewNoopClientWithAppID(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: true,
		}, testAppID)
		ctx := addUserToContext(context.Background(), t)
		requestBody := &NewJobAPIRequest{}
		requestBody.ProblemStatement = problemStatement
		requestBody.RunName = runName
		requestBody.CustomAgent = "does-not-exist"
		reqBytes, err := json.Marshal(requestBody)
		require.NoError(t, err)

		hAlt, _ := NewTestHandler(t, obsv, cf, jobsStore, ffAltClient, capiClient, ghTwirp, true)
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

	t.Run("rules validation error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := newTestTwirpAPI()

		// Create a client factory that will trigger a rules validation error
		// by mocking the CheckIfBranchExists to return true for "copilot" branch
		cfRules := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
			MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
						// When checking for "copilot" branch, return true to trigger rules violation
						if branchName == "copilot" {
							return true, nil
						}
						return false, nil
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
		h, _ := NewTestHandler(t, obsv, cfRules, jobsStore, ffClient, capiClient, ghTwirp, true)

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
			h, _ := NewTestHandler(t, obsv, cf, jobsStore, testFFClient, capiClient, ghTwirp, true)

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

		// Create a client factory that will trigger a rules validation error
		// by mocking the CheckIfBranchExists to return true for "copilot" branch
		cfRules := &github.NoopClientFactory{
			MockRepositories: &map[string]gg.Repository{
				"oregon/trail": repo,
			},
			MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
						// When checking for "copilot" branch, return true to trigger rules violation
						if branchName == "copilot" {
							return true, nil
						}
						return false, nil
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
		h, _ := NewTestHandler(t, obsv, cfRules, jobsStore, ffClient, capiClient, ghTwirp, true)

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
		require.NoError(t, err)

		// Should return 422 Unprocessable Entity for rules validation error
		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)

		// Response body should contain the error message about copilot branch existing
		responseBody := w.Body.String()
		assert.Contains(t, responseBody, "A branch named `copilot` already exists")
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

	// Create a client factory that will trigger a rules validation error
	// by mocking the CheckIfBranchExists to return true for "copilot/" branch
	cf := &github.NoopClientFactory{
		MockRepositories: &map[string]gg.Repository{
			"oregon/trail": repo,
		},
		MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{
				MockRepositories: &map[string]gg.Repository{
					"oregon/trail": repo,
				},
				MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
					// When checking for "copilot" branch, return true to trigger rules violation
					if branchName == "copilot" {
						return true, nil
					}
					return false, nil
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
	h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

	urlPath := "/jobs/v1/{owner}/{repo}"
	urlParams := map[string]string{"owner": *owner.Login, "repo": *repo.Name}

	ctx := addUserToContext(context.Background(), t)
	resp, w, err := callHandler(ctx, t, h, http.MethodPost, urlPath, urlParams, problemStatement, runName)
	require.NoError(t, err)

	// Should return 422 Unprocessable Entity for rules validation error
	assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)

	// Response body should contain the error message about copilot branch existing
	responseBody := w.Body.String()
	assert.Contains(t, responseBody, "A branch named `copilot` already exists")
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

	// Create a client factory that will trigger a rules validation error
	// by mocking the CheckIfBranchExists to return true for "copilot" branch
	cf := &github.NoopClientFactory{
		MockRepositories: &map[string]gg.Repository{
			"oregon/trail": repo,
		},
		MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{
				MockRepositories: &map[string]gg.Repository{
					"oregon/trail": repo,
				},
				MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
					// When checking for "copilot" branch, return true to trigger rules violation
					if branchName == "copilot" {
						return true, nil
					}
					return false, nil
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
	h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

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
}

func TestCancelJob(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ghTwirp := newTestTwirpAPI()

	h, executor := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

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

	testJob, _ := jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:        "job-1234",
		SessionID: "session-1234",
		RepoOwner: *owner.Login,
		OwnerID:   *owner.ID,
		RepoID:    *repo.ID,
		RepoName:  *repo.Name,
		ComputeID: "test-compute-id",
		Status:    jobs.JobStatusRunning,
	})

	urlParams := map[string]string{"owner": testJob.RepoOwner, "repo": testJob.RepoName, "job": testJob.ID, "session": testJob.SessionID}
	for _, urlPath := range []string{
		"/jobs/{owner}/{repo}/{job}",
		"/jobs/{owner}/{repo}/sessions/{session}",
	} {
		t.Run(fmt.Sprintf("cancel job via %s", urlPath), func(t *testing.T) {
			executor.Launcher.TerminateAgentCalls = []launcher.TerminateAgentOpts{}
			ctx := addUserToContext(context.Background(), t)
			resp, _, err := callHandler(ctx, t, h, http.MethodDelete, urlPath, urlParams, problemStatement, runName)
			require.NoError(t, err)
			assert.Equal(t, http.StatusNoContent, resp.StatusCode)
			assert.Equal(t, apiVersion, resp.Header.Get("X-GitHub-Api-Version"))
			assert.Equal(t, 1, len(executor.TerminateAgentCalls()))
			terminateCallOpts := executor.TerminateAgentCalls()[0]
			assert.Equal(t, testJob.RepoID, terminateCallOpts.RepoID)
			assert.Equal(t, testJob.OwnerID, terminateCallOpts.OwnerID)
			assert.Equal(t, testJob.RepoName, terminateCallOpts.RepoName)
			assert.Equal(t, testJob.RepoOwner, terminateCallOpts.RepoOwner)
			assert.Equal(t, testJob.ComputeID, terminateCallOpts.ComputeID)
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

	h, executor := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

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
		RepoOwner:         *owner.Login,
		OwnerID:           *owner.ID,
		RepoID:            *repo.ID,
		RepoName:          *repo.Name,
		ComputeID:         fmt.Sprintf("%d", *workflowRun.ID),
		PullRequestID:     *pr.ID,
		PullRequestNumber: *pr.Number,
		ActorID:           2,
		ActorLogin:        "test-user",
		Status:            jobs.JobStatusRunning,
		ProblemStatement: jobs.ProblemStatement{
			Content:           problemStatement,
			ContentFilterMode: jobs.ProblemStatementContentFilterModeMarkdown,
		},
	})

	urlParams := map[string]string{"owner": testJob.RepoOwner, "repo": testJob.RepoName, "job": testJob.ID, "session": testJob.SessionID}
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
			"owner":   testJob.RepoOwner,
			"repo":    testJob.RepoName,
			"session": "non-existent-session-id", // Use non-existent session ID with existing repo
		}

		resp, _, err := callHandler(ctx, t, h, http.MethodGet, urlPath, urlParams, "", "")
		require.NoError(t, err)
		assert.Equal(t, http.StatusNotFound, resp.StatusCode)
		assert.Equal(t, "text/plain; charset=utf-8", resp.Header.Get("Content-Type"))
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
				ApplicationID:   testAppID,
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
		if strings.HasPrefix(urlPath, "/jobs/v1") {
			h.middleware(h.HandleNewJobAsync)(w, req)
		} else {
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
		}
	}
	return callHandlerWithRequest(ctx, t, h, method, urlPath, urlParams, requestBody)
}

func TestHandleListJobsForPullRequest(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	obsv := observability.NewNoopExporters()
	cf := &github.NoopClientFactory{}
	capiClient := capi.NewNoopClient()
	jobsStore := memory.NewStore()
	ghTwirp := newTestTwirpAPI()

	h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

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

	// Create test jobs with different PR numbers
	testJob1, _ := jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:                "job-1",
		SessionID:         "session-1",
		RepoOwner:         *owner.Login,
		OwnerID:           *owner.ID,
		RepoID:            *repo.ID,
		RepoName:          *repo.Name,
		PullRequestNumber: 123,
		ActorID:           2,
		ActorLogin:        "test-user",
		Status:            jobs.JobStatusCompleted,
	})

	_, _ = jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:                "job-2",
		SessionID:         "session-2",
		RepoOwner:         *owner.Login,
		OwnerID:           *owner.ID,
		RepoID:            *repo.ID,
		RepoName:          *repo.Name,
		PullRequestNumber: 123, // Same PR as job-1
		ActorID:           3,
		ActorLogin:        "another-user",
		Status:            jobs.JobStatusFailed,
	})

	_, _ = jobsStore.CreateJob(context.Background(), &jobs.Job{
		ID:                "job-3",
		SessionID:         "session-3",
		RepoOwner:         *owner.Login,
		OwnerID:           *owner.ID,
		RepoID:            *repo.ID,
		RepoName:          *repo.Name,
		PullRequestNumber: 456, // Different PR
		ActorID:           2,
		ActorLogin:        "test-user",
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
				"owner":    testJob1.RepoOwner,
				"repo":     testJob1.RepoName,
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
			"owner": testJob1.RepoOwner,
			"repo":  testJob1.RepoName,
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

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

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
					IsSweagentdEnabled: false, // CCA disabled
				},
			},
			NoopAuthorizationAPI: &githubtwirp.NoopAuthorizationAPI{},
		}

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

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

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

		// Mock the jobService to return rules violations
		mockJobService := &MockJobService{
			MockCheckRules: func(ctx context.Context, gh jobservice.BranchRuleChecker, job *jobs.Job, branchName string) *jobservice.CheckRulesResult {
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

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

		// Mock the jobService to return no rules violations
		mockJobService := &MockJobService{
			MockCheckRules: func(ctx context.Context, gh jobservice.BranchRuleChecker, job *jobs.Job, branchName string) *jobservice.CheckRulesResult {
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

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

		// Mock the jobService to capture the job data passed to CheckRules
		var capturedJob *jobs.Job
		mockJobService := &MockJobService{
			MockCheckRules: func(ctx context.Context, gh jobservice.BranchRuleChecker, job *jobs.Job, branchName string) *jobservice.CheckRulesResult {
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
		assert.Equal(t, repo.GetName(), capturedJob.RepoName)
		assert.Equal(t, repo.Owner.GetLogin(), capturedJob.RepoOwner)
		assert.Equal(t, "copilot/not-a-real-branch", capturedJob.BranchName)
	})
}

// MockJobService is a mock implementation of the jobService interface for testing
type MockJobService struct {
	MockGetJobByID            func(ctx context.Context, ownerID, repoID int64, jobID string) (*jobs.Job, error)
	MockGetJobBySessionID     func(ctx context.Context, ownerID, repoID int64, sessionID string) (*jobs.Job, error)
	MockGetCustomAgent        func(ctx context.Context, params jobservice.GetCustomAgentParams) (sweagentd.CustomAgent, error)
	MockNewJobBuilder         func(action jobs.AgentAction, baseCommit string) *jobservice.JobBuilder
	MockQueueJobForProcessing func(ctx context.Context, job *jobs.Job) (*aqueductJobs.APIJob, error)
	MockQueueJobForExecution  func(ctx context.Context, job *jobs.Job) (*aqueductJobs.AgentJob, error)
	MockCheckRules            func(ctx context.Context, gh jobservice.BranchRuleChecker, job *jobs.Job, branchName string) *jobservice.CheckRulesResult
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

func (m *MockJobService) NewJobBuilder(action jobs.AgentAction, baseCommit string) *jobservice.JobBuilder {
	if m.MockNewJobBuilder != nil {
		return m.MockNewJobBuilder(action, baseCommit)
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

func (m *MockJobService) CheckRules(ctx context.Context, gh jobservice.BranchRuleChecker, job *jobs.Job, branchName string) *jobservice.CheckRulesResult {
	if m.MockCheckRules != nil {
		return m.MockCheckRules(ctx, gh, job, branchName)
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

		cf := &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockCheckIfRefExists: func(ctx context.Context, ownerLogin, repoName, ref string) (bool, error) {
						assert.Equal(t, "feature-branch", ref)
						return true, nil // ref exists
					},
				}, nil
			},
		}

		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

		// Create request with pull request feature that has base ref
		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Features: EnvironmentFeatures{
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

		cf := &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockCheckIfRefExists: func(ctx context.Context, ownerLogin, repoName, ref string) (bool, error) {
						assert.Equal(t, "nonexistent-branch", ref)
						return false, nil // ref does not exist
					},
				}, nil
			},
		}

		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

		// Create request with pull request feature that has non-existent base ref
		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Features: EnvironmentFeatures{
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

	t.Run("CheckIfRefExists error - request proceeds with best effort", func(t *testing.T) {
		// Enable the feature flag
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		cf := &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockCheckIfRefExists: func(ctx context.Context, ownerLogin, repoName, ref string) (bool, error) {
						return false, errors.New("GitHub API error")
					},
				}, nil
			},
		}

		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

		// Create request with pull request feature that has base ref
		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Features: EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					BaseRef: "some-branch",
				},
			},
		}

		ctx := addUserToContext(context.Background(), t)
		resp, _, err := callHandlerWithRequest(ctx, t, h, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusCreated, resp.StatusCode)
	})

	t.Run("no base ref specified - default to main", func(t *testing.T) {
		// Enable the feature flag
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		cf := &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{
					MockRepositories: &map[string]gg.Repository{
						"oregon/trail": repo,
					},
					MockCheckIfRefExists: func(ctx context.Context, ownerLogin, repoName, ref string) (bool, error) {
						return ref != "main", nil
					},
				}, nil
			},
		}

		capiClient := capi.NewNoopClient()
		jobsStore := memory.NewStore()
		ghTwirp := newTestTwirpAPI()

		h, _ := NewTestHandler(t, obsv, cf, jobsStore, ffClient, capiClient, ghTwirp, true)

		// Create request without base ref specified
		requestBody := &NewJobAPIRequest{
			ProblemStatement: problemStatement,
			RunName:          runName,
			Features: EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					// No BaseRef specified
				},
			},
		}

		ctx := addUserToContext(context.Background(), t)
		resp, w, err := callHandlerWithRequest(ctx, t, h, http.MethodPost, urlPath, urlParams, requestBody)
		require.NoError(t, err)
		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)
		assert.Contains(t, w.Body.String(), "base ref does not exist")
	})
}
