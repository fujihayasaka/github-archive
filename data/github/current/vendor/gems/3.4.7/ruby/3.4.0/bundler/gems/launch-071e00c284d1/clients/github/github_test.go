package github

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/tokens"
	cu "github.com/github/launch/clients/utils"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/permitreplicas"
	"github.com/github/launch/utils/testutils"
)

const (
	env = "test"
)

type TestClient struct {
	Client
	GHTwirpClient *ghtwirp.MockClient
}

func createTestClient(t *testing.T, serverURL string, token string, isMultiTenant bool, options ...Option) *TestClient {
	c := newClientForServer(t, serverURL, token, isMultiTenant, options...)
	testClient, ok := c.(*TestClient)
	assert.True(t, ok, "incorrect client impl")
	return testClient
}

// newFactoryNoTokens returns a factory that ignores authentication, for tests:
func newFactoryNoTokens(apiURLs cu.GraphQLURLProvider, httpClient *http.Client) *clientFactory {
	breaker := testutils.NewNoopBreaker()

	ghTwirpClient := &ghtwirp.MockClient{}

	return &clientFactory{
		env:           "test",
		apiURLs:       apiURLs,
		serviceToken:  tokens.NullServiceToken,
		tokenService:  tokens.NoopService,
		obs:           observability.NewTestObservability(),
		breaker:       breaker,
		gqlClient:     githubv4.NewEnterpriseClient(apiURLs.GraphQLApiURL(), httpClient),
		httpClient:    httpClient,
		hooks:         &ClientHooks{},
		ghTwirpClient: ghTwirpClient,
	}
}

// newFactoryMockTokens returns a factory that uses a mock token service, for test
func newFactoryMockTokens(
	apiURLs cu.GraphQLURLProvider,
	tokensService tokens.Service,
	serviceToken tokens.ServiceToken,
	httpClient *http.Client,
	ghTwirpClient *ghtwirp.MockClient,
	isMultiTenant bool,
) *clientFactory {
	breaker := testutils.NewNoopBreaker()

	return &clientFactory{
		env:           "test",
		apiURLs:       apiURLs,
		serviceToken:  serviceToken,
		tokenService:  tokensService,
		obs:           observability.NewTestObservability(),
		breaker:       breaker,
		gqlClient:     githubv4.NewEnterpriseClient(apiURLs.GraphQLApiURL(), httpClient),
		httpClient:    httpClient,
		hooks:         &ClientHooks{},
		ghTwirpClient: ghTwirpClient,
		isMultiTenant: isMultiTenant,
	}
}

// newClientForServer is a utility function to avoid creating a Factory manually.
func newClientForServer(t *testing.T, apiBaseURL string, token string, isMultiTenant bool, options ...Option) Client {
	accessToken := tokens.AccessToken{Token: token}

	urlProvider, err := cu.NewGraphQLURLProvider(apiBaseURL, "/graphql")
	if err != nil {
		t.Fatalf("error creating URLProvider for client: %v", err)
	}

	mockTokenService := tokens.NewMockService(t)
	ghTwirpClient := ghtwirp.NewMockClient(t)

	factory := newFactoryMockTokens(
		urlProvider,
		mockTokenService,
		testServiceToken,
		apphttp.NewClient(),
		ghTwirpClient,
		isMultiTenant,
	)

	return &TestClient{
		Client:        factory.newClient(&accessToken, options...),
		GHTwirpClient: ghTwirpClient,
	}

}

var (
	testAppID        = types.GlobalID("github-actions-app")
	repoGID          = types.GlobalID("R_TestRepo")
	testServiceToken = tokens.ServiceToken("TEST_SERVICE_TOKEN")
)

func TestClient_Query_NoResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
	}))
	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", false)
	resp, err := testClient.do(context.Background(), "", "", "invalid query", nil, nil, nil)
	assert.Contains(t, err.Error(), "error parsing GQL response: EOF")
	assert.Nil(t, resp)
}

func TestClient_Query_InvalidQuery(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		body, err := io.ReadAll(req.Body)
		req.Body.Close()
		require.NoError(t, err)
		assert.Equal(t, `{"query":"invalid query"}`, string(body))

		fmt.Fprint(w, `{"errors": [{"message": "that's an invalid query"}]}`)
	}))
	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", false)
	resp, err := testClient.do(context.Background(), "", "", "invalid query", nil, nil, nil)
	assert.Contains(t, err.Error(), "Unexpected error: []github.GraphQLError{github.GraphQLError{Message:\"that's an invalid query\", Type:\"\"}}")
	require.NotNil(t, resp)
	assert.Len(t, resp.Errors, 1)
	e := resp.Errors[0]
	assert.Equal(t, e.Message, "that's an invalid query")
}

func TestClient_Query_InvalidResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		fmt.Fprint(w, `{"message": invalid json!}`)
	}))
	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", false)
	resp, err := testClient.do(context.Background(), "", "", "invalid query", nil, nil, nil)
	assert.EqualError(t, err, "error making graphql request: error parsing GQL response: invalid character 'i' looking for beginning of value")
	assert.Nil(t, resp)
}

func TestClient_Query_NoServiceToken(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		headerKey := http.CanonicalHeaderKey("GitHub-Internal-GraphQL-Token")
		_, ok := req.Header[headerKey]
		assert.False(t, ok, "Expected GitHub-Internal-GraphQL-Token to be absent for null service token")
		fmt.Fprint(w, `{"data": {"viewer": {"id": "MDQ6VXNlcjM1NDE3"}}}`)
	}))
	defer server.Close()

	urlProvider, err := cu.NewGraphQLURLProvider(server.URL, "/graphql")
	require.NoError(t, err)

	factory := newFactoryNoTokens(urlProvider, apphttp.NewClient())
	client := factory.newClient(&tokens.AccessToken{Token: "sekrit"})
	resp, err := client.do(context.Background(), "", "", "{ viewer { id } }", nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestClient_Query_Success(t *testing.T) {
	query := `query MyQuery {
		repository(owner: "bbq-beets", name:"pied-piper") {
			id
			issues(last: 10, states: [OPEN]) {
				nodes {
					id
					number
				}
			}
		}
	}`

	variables := map[string]any{"owner": "bbq-beets", "name": "pied-piper"}
	queryResp := struct {
		Repository struct {
			ID     string `json:"id"`
			Issues struct {
				Nodes []struct {
					ID     string `json:"id"`
					Number int    `json:"number"`
				} `json:"nodes"`
			} `json:"issues"`
		} `json:"repository"`
	}{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		body, err := io.ReadAll(req.Body)
		req.Body.Close()
		require.NoError(t, err)
		assert.Len(t, body, 275)
		fmt.Fprint(w, `{
		               "data": {
		                   "repository": {
		                       "id": "MDEwOlJlcG9zaXRvcnkxMTI5NzE5MzQ=",
		                       "issues": {
		                           "nodes": [
		                               {
		                                   "id": "abcdef",
		                                   "number": 119
		                               },
		                               {
		                                   "id": "abcdef",
		                                   "number": 117
		                               }
		                           ]
		                       }
		                   }
		               }
		           }`)
	}))
	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", false)
	resp, err := testClient.do(context.Background(), "", "", query, variables, &queryResp, nil)
	require.NoError(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, queryResp.Repository.ID, "MDEwOlJlcG9zaXRvcnkxMTI5NzE5MzQ=")
}

func TestClient_PotentialMergeCommitReturned(t *testing.T) {
	blob := `{
			"data": {
				"repository": {
					"pullRequest": {
						"merged": false,
						"closed": false,
						"mergeable": "MERGEABLE",
						"potentialMergeCommit": {
							"oid": "801cd2cc0378541d8b895a0791fd42c0553595f8",
							"parents": {
								"nodes": [
									{
										"oid": "3eaaf4881923f71ab73b9407da2bf2887431e0a0"
									},
									{
										"oid": "01d143989661e4614b7aaec1f37232469232a2d2"
									}
								]
							}
						},
						"mergeCommit": null,
						"headRef": {
							"target": {
								"oid": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
							}
						}
					}
				}
			}
		}`
	server, teardown := setupAuthenticatedServer(t, blob)
	defer teardown()

	testClient := createTestClient(t, server.URL, "sekrit", false)
	mergeState, err := testClient.GetMergeStatusForPullRequest(context.TODO(), repoGID, 1)
	require.NoError(t, err)
	assert.Equal(t, types.CommitSha("801cd2cc0378541d8b895a0791fd42c0553595f8"), mergeState.MergeCommit)
	assert.Equal(t, 2, len(mergeState.MergeCommitParents))
	assert.Equal(t, types.CommitSha("3eaaf4881923f71ab73b9407da2bf2887431e0a0"), mergeState.MergeCommitParents[0])
	assert.Equal(t, types.CommitSha("01d143989661e4614b7aaec1f37232469232a2d2"), mergeState.MergeCommitParents[1])
	assert.Equal(t, types.CommitSha("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"), mergeState.PRHeadCommit)
	assert.Equal(t, githubv4.MergeableStateMergeable, mergeState.Mergeable)
	assert.False(t, mergeState.Merged)
	assert.False(t, mergeState.Closed)
	// The event commit should match against the second parent.
	assert.True(t, mergeState.HasMergeCommitForEventCommit("01d143989661e4614b7aaec1f37232469232a2d2"))
	// The event commit shouldn't match against the first parent (the target branch's head commit).
	// If we match on both parents we'll get duplicate runs against the same merge commit when someone force pushes the target branch's head commit to the PR branch, followed by some more commits.
	assert.False(t, mergeState.HasMergeCommitForEventCommit("3eaaf4881923f71ab73b9407da2bf2887431e0a0"))
	// Random event commits shouldn't be a match either.
	assert.False(t, mergeState.HasMergeCommitForEventCommit("cafecafecafecafecafecafecafecafecafecafe"))
}

func TestClient_MergeCommitsMissing(t *testing.T) {
	blob := `{
			"data": {
				"repository": {
					"pullRequest": {
						"merged": false,
						"closed": false,
						"mergeable": "UNKNOWN",
						"potentialMergeCommit": null,
						"mergeCommit": null,
						"headRef": null
					}
				}
			}
		}`
	server, teardown := setupAuthenticatedServer(t, blob)
	defer teardown()

	testClient := createTestClient(t, server.URL, "sekrit", false)
	mergeState, err := testClient.GetMergeStatusForPullRequest(context.TODO(), repoGID, 1)
	require.NoError(t, err)
	assert.Empty(t, mergeState.MergeCommit)
	assert.Equal(t, 2, len(mergeState.MergeCommitParents))
	assert.Empty(t, mergeState.MergeCommitParents[0])
	assert.Empty(t, mergeState.MergeCommitParents[1])
	assert.Empty(t, mergeState.PRHeadCommit)
	assert.False(t, mergeState.Merged)
	assert.False(t, mergeState.Closed)
	assert.Equal(t, githubv4.MergeableStateUnknown, mergeState.Mergeable)
	assert.False(t, mergeState.HasMergeCommitForEventCommit("01d143989661e4614b7aaec1f37232469232a2d2"))
}

func TestClient_AlreadyMerged(t *testing.T) {
	blob := `{
			"data": {
				"repository": {
					"pullRequest": {
						"merged": true,
						"closed": true,
						"mergeable": "UNKNOWN",
						"potentialMergeCommit": null,
						"mergeCommit": {
							"oid": "801cd2cc0378541d8b895a0791fd42c0553595f8",
							"parents": {
								"nodes": [
									{
										"oid": "3eaaf4881923f71ab73b9407da2bf2887431e0a0"
									},
									{
										"oid": "01d143989661e4614b7aaec1f37232469232a2d2"
									}
								]
							}
						},
						"headRef": {
							"target": {
								"oid": "01d143989661e4614b7aaec1f37232469232a2d2"
							}
						}
					}
				}
			}
		}`
	server, teardown := setupAuthenticatedServer(t, blob)
	defer teardown()

	testClient := createTestClient(t, server.URL, "sekrit", false)
	mergeState, err := testClient.GetMergeStatusForPullRequest(context.TODO(), repoGID, 1)
	require.NoError(t, err)

	assert.Equal(t, types.CommitSha("801cd2cc0378541d8b895a0791fd42c0553595f8"), mergeState.MergeCommit)
	assert.Equal(t, 2, len(mergeState.MergeCommitParents))
	assert.Equal(t, types.CommitSha("3eaaf4881923f71ab73b9407da2bf2887431e0a0"), mergeState.MergeCommitParents[0])
	assert.Equal(t, types.CommitSha("01d143989661e4614b7aaec1f37232469232a2d2"), mergeState.MergeCommitParents[1])
	assert.Equal(t, types.CommitSha("01d143989661e4614b7aaec1f37232469232a2d2"), mergeState.PRHeadCommit)
	assert.True(t, mergeState.Merged)
	assert.True(t, mergeState.Closed)
	assert.Equal(t, githubv4.MergeableStateUnknown, mergeState.Mergeable)
	assert.True(t, mergeState.HasMergeCommitForEventCommit("01d143989661e4614b7aaec1f37232469232a2d2"))
	assert.False(t, mergeState.HasMergeCommitForEventCommit("cafecafecafecafecafecafecafecafecafecafe"))
}

func TestClient_ClosedWithoutMerging(t *testing.T) {
	blob := `{
			"data": {
				"repository": {
					"pullRequest": {
						"merged": false,
						"closed": true,
						"mergeable": "UNKNOWN",
						"potentialMergeCommit": null,
						"mergeCommit": null,
						"headRef": {
							"target": {
								"oid": "01d143989661e4614b7aaec1f37232469232a2d2"
							}
						}
					}
				}
			}
		}`
	server, teardown := setupAuthenticatedServer(t, blob)
	defer teardown()

	testClient := createTestClient(t, server.URL, "sekrit", false)

	mergeState, err := testClient.GetMergeStatusForPullRequest(context.TODO(), repoGID, 1)
	require.NoError(t, err)

	assert.Empty(t, mergeState.MergeCommit)
	assert.Equal(t, 2, len(mergeState.MergeCommitParents))
	assert.Empty(t, mergeState.MergeCommitParents[0])
	assert.Empty(t, mergeState.MergeCommitParents[1])
	assert.Equal(t, types.CommitSha("01d143989661e4614b7aaec1f37232469232a2d2"), mergeState.PRHeadCommit)
	assert.False(t, mergeState.Merged)
	assert.True(t, mergeState.Closed)
	assert.Equal(t, githubv4.MergeableStateUnknown, mergeState.Mergeable)
	assert.False(t, mergeState.HasMergeCommit())
	assert.False(t, mergeState.HasMergeCommitForEventCommit("01d143989661e4614b7aaec1f37232469232a2d2"))
}

func TestClient_MergeStatusFailure_PullRequestNotFound(t *testing.T) {
	blob := `{
			"data": {
				"repository": {
					"pullRequest": null
				}
			},
			"errors": [
				{
					"type": "NOT_FOUND",
					"path": ["repository", "pullRequest"]
				}
			]
		}`

	server, teardown := setupAuthenticatedServer(t, blob)
	defer teardown()

	testClient := createTestClient(t, server.URL, "sekrit", false)

	mergeState, err := testClient.GetMergeStatusForPullRequest(context.TODO(), repoGID, 1)
	require.Nil(t, mergeState)
	require.Error(t, err)
	assert.True(t, terrors.IsNotFoundError(err))
	// Replication lag can cause transient NOT_FOUND errors. Verify the error is retryable so the aqueduct job will be re-attempted.
	assert.True(t, terrors.IsRetryable(err))
}

func setupAuthenticatedServer(t *testing.T, blob string) (*httptest.Server, func()) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		fmt.Fprint(w, blob)
	}))

	return server, func() {
		server.Close()
	}
}

func TestGraphQLErrorRollup(t *testing.T) {
	wd, err := os.Getwd()
	require.NoError(t, err)

	type stackTracer interface {
		StackTrace() errors.StackTrace
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
	}))
	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", false)

	resp, err := testClient.do(context.Background(), "", "", "invalid query", nil, nil, nil)
	rollup := err.(*terrors.GraphQLError).Rollup(err.(stackTracer).StackTrace())
	expectedRollup := fmt.Sprintf("github.com/github/launch/clients/github.(*client).do\n\t%s/github.go", wd)

	require.Contains(t, rollup, expectedRollup)
	require.Nil(t, resp)
}

func TestGraphQLRateLimiting(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))

		w.Header().Set("X-RateLimit-Limit", "60")
		w.Header().Set("X-RateLimit-Remaining", "0")
		w.WriteHeader(http.StatusForbidden)
	}))
	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", false)

	resp, err := testClient.do(context.Background(), "", "", "{ viewer { id } }", nil, nil, nil)

	require.Error(t, err)
	require.Contains(t, err.Error(), "GitHub rate limit exceeded")
	require.True(t, terrors.IsRateLimitError(err))

	require.Nil(t, resp)
}

func TestOptionalHeaders(t *testing.T) {
	const optionalHeader = "Blah-Foo"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		assert.Equal(t, "true", req.Header.Get(optionalHeader))
		fmt.Fprint(w, `{"data": {"viewer": {"id": "MDQ6VXNlcjM1NDE3"}}}`)
	}))

	defer server.Close()

	optHeaders := http.Header{}
	optHeaders.Set(optionalHeader, "true")

	testClient := createTestClient(t, server.URL, "sekrit", false)

	resp, err := testClient.do(context.Background(), "", "", "{ viewer { id } }", nil, nil, optHeaders)

	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestPermitReplicasHeader(t *testing.T) {
	type requestAttempt func(w http.ResponseWriter, r *http.Request, attempt int)

	cases := []struct {
		name     string
		requests []requestAttempt
	}{
		{
			name: "header is removed after a not_found error",
			requests: []requestAttempt{
				// first attempt is a not found error
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "1")
					fmt.Fprint(w, `{"data": {"viewer": null}, "errors": [
						{
							"type": "NOT_FOUND",
							"locations": [{"line":3,"column":9}],
							"message": "Could not resolve to a node with the global id of 'R_kgDOMCNvuw'"
						}
					]}`)
				},
				// second attempt should not have the PermitReplicasHeader header
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "")
					fmt.Fprint(w, `{"data": {"viewer": {"id": "MDQ6VXNlcjM1NDE3"}}}`)
				},
			},
		},
		{
			name: "header is removed after a forbidden error",
			requests: []requestAttempt{
				// first attempt is a forbidden error
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "1")
					fmt.Fprint(w, `{"data": {"viewer": null}, "errors": [
						{
							"type": "FORBIDDEN",
							"message": "Resource not accessible by integration"
						}
					]}`)
				},
				// second attempt should not have the PermitReplicasHeader header
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "")
					fmt.Fprint(w, `{"data": {"viewer": {"id": "MDQ6VXNlcjM1NDE3"}}}`)
				},
			},
		},
		{
			name: "header stays for other errors",
			requests: []requestAttempt{
				// first attempt is something other than a not found error
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "1")
					fmt.Fprint(w, `{"data": {"viewer": null}, "errors": [
						{
							"type": "INTERNAL"
						}
					]}`)
				},
				// second attempt should still have the PermitReplicasHeader header
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "1")
					fmt.Fprint(w, `{"data": {"viewer": {"id": "MDQ6VXNlcjM1NDE3"}}}`)
				},
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			attempt := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				tc.requests[attempt](w, r, attempt)
				attempt++
			}))
			defer server.Close()

			testClient := createTestClient(t, server.URL, "sekrit", false)
			resp, err := testClient.do(context.Background(), "", "", "{ viewer { id } }", nil, nil, nil)
			require.NoError(t, err)
			require.NotNil(t, resp)
		})
	}
}

func TestMutationOptionalHeaders(t *testing.T) {
	const optionalHeader = "Blah-Foo"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, req.Header.Get(optionalHeader), "OptionalHeaderValue1") // Optional header should be passed through
	}))

	defer server.Close()

	accessToken := tokens.AccessToken{Token: "sekrit"}

	urlProvider, err := cu.NewGraphQLURLProvider(server.URL, "/graphql")
	if err != nil {
		t.Fatalf("error creating URLProvider for client: %v", err)
	}

	var m struct {
		CreateCheckSuite struct {
			CheckSuite struct {
				ID          githubv4.ID
				DatabaseID  githubv4.Int
				WorkflowRun struct {
					DatabaseID githubv4.Int
					RunNumber  githubv4.Int
				}
			}
			Errors []ErrorNode
		} `graphql:"createCheckSuite(input: $input)"`
	}

	input := githubv4.CreateCheckSuiteInput{
		ExternalID:   githubv4.NewString("abc"),
		RepositoryID: githubv4.NewID("1"),
	}

	mockTokenService := tokens.NewMockService(t)
	ghTwirpClient := ghtwirp.NewMockClient(t)

	f := newFactoryMockTokens(urlProvider, mockTokenService, testServiceToken, apphttp.NewClient(), ghTwirpClient, false)
	c := newClient(f.env, f.apiURLs, f.gqlClient, f.serviceToken, &accessToken, ahttp.NewClient(f.breaker, f.obs.Statter, ahttp.DefaultBackoffStrategy, f.httpClient, "github"), f.obs, time.Now, f.hooks, f.isMultiTenant, ghTwirpClient)

	optHeaders := http.Header{}
	optHeaders.Set(optionalHeader, "OptionalHeaderValue1")

	c.mutate(context.Background(), "CreateCheckSuite", &m, input, nil, optHeaders)
}

func TestMutationPermitReplicasHeader(t *testing.T) {
	type requestAttempt func(w http.ResponseWriter, r *http.Request, attempt int)

	cases := []struct {
		name     string
		requests []requestAttempt
	}{
		{
			name: "header is removed after a not_found error",
			requests: []requestAttempt{
				// first attempt is a not found error
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "1")
					fmt.Fprint(w, `{"data": {}, "errors": [
						{
							"type": "NOT_FOUND",
							"path": ["createCheckRun"],
							"locations": [{"line":3,"column":9}],
							"message": "Could not resolve to a node with the global id of 'R_kgDOMCNvuw'"
						}
					]}`)
				},
				// second attempt should not have the PermitReplicasHeader header
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "")
					fmt.Fprint(w, `{"data": {}}`)
				},
			},
		},
		{
			name: "header is removed after a forbidden error",
			requests: []requestAttempt{
				// first attempt is a not found error
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "1")
					fmt.Fprint(w, `{"data": {}, "errors": [
						{
							"type": "FORBIDDEN",
							"message": "Resource not accessible by integration"
						}
					]}`)
				},
				// second attempt should not have the PermitReplicasHeader header
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "")
					fmt.Fprint(w, `{"data": {}}`)
				},
			},
		},
		{
			name: "header stays for other errors",
			requests: []requestAttempt{
				// first attempt is something other than a not found error
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "1")
					fmt.Fprint(w, `{"data": {}, "errors": [
						{
							"type": "INTERNAL",
							"message": "Boom"
						}
					]}`)
				},
				// second attempt should still have the PermitReplicasHeader header
				func(w http.ResponseWriter, r *http.Request, attempt int) {
					assert.Equal(t, r.Header.Get(permitreplicas.PermitReplicasHeader), "1")
					fmt.Fprint(w, `{"data": {}}`)
				},
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			attempt := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				tc.requests[attempt](w, r, attempt)
				attempt++
			}))

			defer server.Close()

			urlProvider, err := cu.NewGraphQLURLProvider(server.URL, "/graphql")
			if err != nil {
				t.Fatalf("error creating URLProvider for client: %v", err)
			}

			var m struct {
				CreateCheckSuite struct {
					CheckSuite struct {
						ID          githubv4.ID
						DatabaseID  githubv4.Int
						WorkflowRun struct {
							DatabaseID githubv4.Int
							RunNumber  githubv4.Int
						}
					}
					Errors []ErrorNode
				} `graphql:"createCheckSuite(input: $input)"`
			}

			f := newFactoryMockTokens(urlProvider, nil, testServiceToken, apphttp.NewClient(), nil, false)
			c := newClient(f.env, f.apiURLs, f.gqlClient, f.serviceToken, nil, ahttp.NewClient(f.breaker, f.obs.Statter, ahttp.DefaultBackoffStrategy, f.httpClient, "github"), f.obs, time.Now, f.hooks, f.isMultiTenant, nil)

			err = c.mutate(context.Background(), "CreateCheckSuite", &m, githubv4.CreateCheckSuiteInput{
				ExternalID:   githubv4.NewString("abc"),
				RepositoryID: githubv4.NewID("1"),
			}, nil, nil)
			require.NoError(t, err)
		})
	}
}

func TestOptionalHeadersOverrideDefaultHeaders(t *testing.T) {
	const defaultHeader = "My-Default-Header"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		assert.Equal(t, "foo", req.Header.Get(defaultHeader))
		fmt.Fprint(w, `{"data": {"viewer": {"id": "MDQ6VXNlcjM1NDE3"}}}`)
	}))

	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", false, func(o *Options) {
		o.defaultRequestHeaders[defaultHeader] = "blahfoo"
	})

	optHeaders := http.Header{}
	optHeaders.Set(defaultHeader, "foo")

	resp, err := testClient.do(context.Background(), "", "", "{ viewer { id } }", nil, nil, optHeaders)

	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestNewClientWithOptions(t *testing.T) {
	const defaultHeader = "My-Default-Header"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		assert.Equal(t, "blahfoo", req.Header.Get(defaultHeader))
		fmt.Fprint(w, `{"data": {"viewer": {"id": "MDQ6VXNlcjM1NDE3"}}}`)
	}))

	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", false, func(o *Options) {
		o.defaultRequestHeaders[defaultHeader] = "blahfoo"
	})

	resp, err := testClient.do(context.Background(), "", "", "{ viewer { id } }", nil, nil, nil)

	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestGitHubTenantHeaderIsSet(t *testing.T) {
	validGitHubTenant := int64(4)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
		assert.Equal(t, testServiceToken.String(), req.Header.Get("GitHub-Internal-GraphQL-Token"))
		assert.Equal(t, "1", req.Header.Get("X-Github-Next-Global-ID"))
		assert.Equal(t, "4", req.Header.Get(ghtenant.GitHubTenantIDHeader))
		fmt.Fprint(w, `{"data": {"viewer": {"id": "MDQ6VXNlcjM1NDE3"}}}`)
	}))

	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", true)

	ctx, err := ghtenant.ContextWithTenantID(context.Background(), validGitHubTenant, true)
	require.NoError(t, err)

	resp, err := testClient.do(ctx, "", "", "{ viewer { id } }", nil, nil, nil)

	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestNoGitHubTenantHeaderSet(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		assert.Equal(t, req.Method, "POST")
		assert.Equal(t, req.URL.Path, "/graphql")
		assert.Equal(t, req.Header.Get("Authorization"), "Bearer sekrit")
	}))

	defer server.Close()

	testClient := createTestClient(t, server.URL, "sekrit", true)

	resp, err := testClient.do(context.Background(), "", "", "{ viewer { id } }", nil, nil, nil)
	expectedErrorMessage := "error making graphql request: error creating graphql request: github tenant id not found in context"
	require.Equal(t, expectedErrorMessage, err.Error(), "Error message not as expected")
	require.Error(t, err, "msg")
	require.Nil(t, resp)
}
