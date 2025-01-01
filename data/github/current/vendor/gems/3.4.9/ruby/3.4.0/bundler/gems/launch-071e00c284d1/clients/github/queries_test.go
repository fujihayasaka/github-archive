package github

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/graph-gophers/graphql-go"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/flow/flowfile"
	hydro "github.com/github/launch/hydro/schemas/github/v1/entities"
	"github.com/github/launch/model"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/testutils"
)

// newRemoteServer boots up a server. It returns a mux, its url, and a teardown function.
func newRemoteServer(t *testing.T) (*testGraphQLServer, string, func()) {
	mux := http.NewServeMux()
	schema := loadSchema(t)
	testServer := &testGraphQLServer{mux, schema}
	server := httptest.NewServer(mux)
	return testServer, server.URL, server.Close
}

type testGraphQLServer struct {
	mux    *http.ServeMux
	schema *graphql.Schema
}

func (s *testGraphQLServer) handleGraphQLRequest(h func(w http.ResponseWriter, r *http.Request)) {
	s.mux.HandleFunc("/graphql", func(w http.ResponseWriter, r *http.Request) {
		h(w, r)
	})
}

func (s *testGraphQLServer) handleGraphQL(w http.ResponseWriter, r *http.Request, h func(w http.ResponseWriter, gql graphQLRequest)) {
	if "POST" != r.Method || "Bearer "+testGitHubToken != r.Header.Get("Authorization") || testServiceToken.String() != r.Header.Get("GitHub-Internal-GraphQL-Token") || "1" != r.Header.Get("X-Github-Next-Global-Id") {
		message := fmt.Sprintf("Invalid GraphQL request\nMethod: expect POST, received %s\nAuth: expect %s, received %s\nInternal Schema Auth: expect %s, received %s\n GlobalIdHeader expect %s, received %s,\n",
			r.Method,
			testGitHubToken, r.Header.Get("Authorization"),
			testServiceToken.String(), r.Header.Get("GitHub-Internal-GraphQL-Token"),
			"1", r.Header.Get("X-Github-Next-Global-Id"),
		)
		http.Error(w, message, http.StatusBadRequest)
		return
	}

	var gql graphQLRequest
	if err := json.NewDecoder(r.Body).Decode(&gql); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	queryErrors := s.schema.ValidateWithVariables(gql.Query, gql.Variables)
	if len(queryErrors) != 0 {
		fmt.Println("Failed", queryErrors, gql.Query)
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprintln(w, "Query is not valid!")
		for _, e := range queryErrors {
			fmt.Fprintln(w, e.Error())
		}
		fmt.Fprintln(w, "----")
		fmt.Fprintln(w, gql.Query)
		return
	}

	h(w, gql)
}

func TestQueries_GetEnvironment_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()
	id := types.GlobalID("ABCDEF==")
	environmentName := "integration"
	expectedVariables := map[string]any{"id": id.String(), "name": environmentName}
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, expectedVariables, gql.Variables)
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))
			resp := `
			{
				"data": {
				"repository": {
					"environment": {
					"id": "MDExOkVudmlyb25tZW50MQ==",
					"databaseId": 1,
					"name": "integration",
					"gates": {
						"edges": [
						{
							"node": {
							"id": "MDQ6R2F0ZTE=",
							"databaseId": 1,
							"type": "MANUAL_APPROVAL",
							"timeout": 0
							}
						}
						]
					}
					}
				}
				}
			}
			`
			fmt.Fprint(w, resp)
		})
	})
	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)
	environmentInfo, err := tc.GetEnvironment(ctx, id, environmentName)
	require.NoError(t, err)
	expectedGates := make([]*Gate, 1)
	expectedGates[0] = &Gate{
		GateID:           "MDQ6R2F0ZTE=",
		DatabaseID:       1,
		GateType:         "MANUAL_APPROVAL",
		TimeoutInMinutes: 0,
	}
	expectedInfo := EnvironmentResponse{
		EnvironmentID: "MDExOkVudmlyb25tZW50MQ==",
		DatabaseID:    1,
		Name:          "integration",
	}
	expectedInfo.Gates = expectedGates
	assert.ObjectsAreEqualValues(expectedInfo, environmentInfo)
}

func TestQueries_GetEnvironment_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("ABCDEF==")
	environmentName := "integration"
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	_, err := tc.GetEnvironment(ctx, id, environmentName)

	require.Error(t, err)
}

func TestQueries_CircuitBreaker(t *testing.T) {
	// this uses tracing to detect retries as it's an externally observable side-effect of them
	spanNames := testutils.CollectFinishedSpanNames(func() {
		tc, ok := newClientForServer(t, "https://localhost/graphql", testGitHubToken, false).(*TestClient)
		require.True(t, ok, "unexpected type for client")
		c := tc.Client.(*client)
		require.True(t, ok, "unexpected type for client")
		c.httpClient.Breaker.Break()
		_, err := c.RepositoryNWO(context.Background(), "foo")
		assert.EqualError(t, errors.Cause(err), "breaker open")
	})

	attempts := 0
	for _, n := range spanNames {
		if strings.HasSuffix(n, "do") {
			attempts++
		}
	}
	assert.Equal(t, 1, attempts, "should not have retried an open breaker")
}

func TestQueries_ResolveDefaultBranch_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("ABCDEF==")

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))
			assert.Equal(t, queryResolveDefaultBranch, gql.Query)
			assert.Equal(t, id.String(), gql.Variables["id"])

			resp := `
				{
					"data": {
						"repository": {
							"defaultBranch": {
								"name": "master",
								"target": {
									"commitSha": "c8cfbd75232e224c14ca613ff7d48c3499a1b1be"
								}
							}
						}
					}
				}
			`
			fmt.Fprint(w, resp)
		})
	})

	expectedCommit := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	expectedRef := types.NewBranchRef("master")

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)
	commit, ref, err := tc.ResolveDefaultBranch(ctx, id)

	require.NoError(t, err)
	assert.Equal(t, expectedCommit, commit)
	assert.Equal(t, expectedRef, ref)
}

func TestQueries_ResolveDefaultBranch_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("ABCDEF==")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	_, _, err := tc.ResolveDefaultBranch(ctx, id)

	require.Error(t, err)
}

func TestQueries_ResolveDefaultBranch_EmptyRepository(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("ABCDEF==")

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, queryResolveDefaultBranch, gql.Query)
			assert.Equal(t, id.String(), gql.Variables["id"])

			resp := `
				{
					"data": {
						"repository": {
							"defaultBranch": null
						}
					}
				}
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, false)
	ctx := context.Background()
	_, _, err := tc.ResolveDefaultBranch(ctx, id)

	require.Error(t, err)
}

func TestQueries_IsRefProtected_BranchProtectionRuleOnly_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))
			assert.Equal(t, queryIsRefProtected, gql.Query)
			assert.Equal(t, string(id), gql.Variables["id"])
			assert.Equal(t, string(ref), gql.Variables["ref"])

			resp := `
				{
					"data": {
						"repository": {
							"ref": {
								"name": "master",
								"prefix": "refs/heads/",
								"rules": {
									"totalCount": 0
								},
								"branchProtectionRule": {
									"id": "MDIwOkJyYW5jaFByb3RlY3Rpb25SdWxlMjE1Mzc1MjM="
								}
							}
						}
					}
				}
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)
	protected, err := tc.IsRefProtected(ctx, id, ref)

	require.NoError(t, err)
	assert.True(t, protected)
}

func TestQueries_IsRefProtected_RulesOnly(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, queryIsRefProtected, gql.Query)
			assert.Equal(t, string(id), gql.Variables["id"])
			assert.Equal(t, string(ref), gql.Variables["ref"])

			resp := `
				{
					"data": {
						"repository": {
							"ref": {
								"name": "master",
								"prefix": "refs/heads/",
								"rules": {
									"totalCount": 1
								},
								"branchProtectionRule": null
							}
						}
					}
				}
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, false)
	ctx := context.Background()
	protected, err := tc.IsRefProtected(ctx, id, ref)

	require.NoError(t, err)
	assert.True(t, protected)
}

func TestQueries_IsRefProtected_BranchProtectionRuleAndRules(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, queryIsRefProtected, gql.Query)
			assert.Equal(t, string(id), gql.Variables["id"])
			assert.Equal(t, string(ref), gql.Variables["ref"])

			resp := `
				{
					"data": {
						"repository": {
							"ref": {
								"name": "master",
								"prefix": "refs/heads/",
								"rules": {
									"totalCount": 1
								},
								"branchProtectionRule": {
									"id": "MDIwOkJyYW5jaFByb3RlY3Rpb25SdWxlMjE1Mzc1MjM="
								}
							}
						}
					}
				}
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, false)
	ctx := context.Background()
	protected, err := tc.IsRefProtected(ctx, id, ref)

	require.NoError(t, err)
	assert.True(t, protected)
}

func TestQueries_IsRefProtected_ReturnFalse(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, queryIsRefProtected, gql.Query)
			assert.Equal(t, string(id), gql.Variables["id"])
			assert.Equal(t, string(ref), gql.Variables["ref"])

			resp := `
				{
					"data": {
						"repository": {
							"ref": {
								"name": "master",
								"prefix": "refs/heads/",
								"rules": {
									"totalCount": 0
								},
								"branchProtectionRule": null
							}
						}
					}
				}
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, false)
	ctx := context.Background()
	protected, err := tc.IsRefProtected(ctx, id, ref)

	require.NoError(t, err)
	assert.False(t, protected)
}

func TestQueries_IsRefProtected_ReturnFalse_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	protected, err := tc.IsRefProtected(ctx, id, ref)

	require.Error(t, err)
	assert.False(t, protected)
}

func TestQueries_ResolveRef_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))
			assert.Equal(t, queryResolveRef, gql.Query)
			assert.Equal(t, string(id), gql.Variables["id"])
			assert.Equal(t, string(ref), gql.Variables["ref"])

			resp := `
				{
					"data": {
						"repository": {
							"ref": {
								"name": "master",
								"prefix": "refs/heads/"
							},
							"object": {
								"oid": "c8cfbd75232e224c14ca613ff7d48c3499a1b1be"
							}
						}
					}
				}
			`
			fmt.Fprint(w, resp)
		})
	})

	expectedCommit := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	expectedRef := types.NewBranchRef("master")

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)
	commit, gitRef, err := tc.ResolveRef(ctx, id, ref)

	require.NoError(t, err)
	assert.Equal(t, expectedCommit, commit)
	assert.Equal(t, expectedRef, gitRef)
}

func TestQueries_ResolveRef_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	_, _, err := tc.ResolveRef(ctx, id, ref)

	require.Error(t, err)
}

func TestQueries_ResolveRef_MissingRef(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	count := 0
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, queryResolveRef, gql.Query)
			assert.Equal(t, string(id), gql.Variables["id"])
			assert.Equal(t, string(ref), gql.Variables["ref"])
			count++
			resp := `
				{
					"data": {
						"repository": {
							"ref": null
						}
					}
				}
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, false)
	ctx := context.Background()
	_, _, err := tc.ResolveRef(ctx, id, ref, func(cfg *retryConfig) {
		cfg.backoff = time.Millisecond
		cfg.deadline = time.Now().Add(10 * time.Millisecond)
	})

	require.Error(t, err)
	require.Equal(t, err, &terrors.RefResolutionError{
		Count: count,
	})
}

func TestQueries_ResolveRef_MissingRefRetries(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("repo-1234")
	ref := types.GitRef("master")
	count := 0
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, queryResolveRef, gql.Query)
			assert.Equal(t, string(id), gql.Variables["id"])
			assert.Equal(t, string(ref), gql.Variables["ref"])

			var resp string
			if count == 0 {
				resp = `
					{
						"data": {
							"repository": {
								"ref": null
							}
						}
					}
				`
			} else {
				resp = `
					{
						"data": {
							"repository": {
								"ref": {
									"name": "master",
									"prefix": "refs/heads/"
								},
								"object": {
									"oid": "c8cfbd75232e224c14ca613ff7d48c3499a1b1be"
								}
							}
						}
					}
				`
			}
			count++
			fmt.Fprint(w, resp)
		})
	})

	expectedCommit := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	expectedRef := types.NewBranchRef("master")

	tc := createTestClient(t, serverURL, testGitHubToken, false)
	ctx := context.Background()
	commit, gitRef, err := tc.ResolveRef(ctx, id, ref)

	require.NoError(t, err)
	assert.Equal(t, expectedCommit, commit)
	assert.Equal(t, expectedRef, gitRef)
}

func TestQueries_GetDataForWorkflowInvocation_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("ABCDEF==")
	commit := types.CommitSha("abcdefggggg")

	examples := map[string]struct {
		expectedHasLaunchFlag              bool
		isPrivate                          bool
		actionInvocationBlocked            bool
		launchLabEnabled                   bool
		launchLabExpected                  bool
		isSpammyActor                      bool
		noVerifiedEmailActor               bool
		hasHostedRunnerCustomImagesEnabled bool
		owner                              string
		commitResult                       string
		pipelinesDirectory                 string
		expectedParseError                 string
	}{
		"base case, private repo": {
			isPrivate: true,

			expectedHasLaunchFlag: false,
		},

		"base case, public repo": {
			isPrivate: false,

			expectedHasLaunchFlag: false,
		},

		"private repo, action invocation blocked": {
			isPrivate: true,

			expectedHasLaunchFlag: true,

			actionInvocationBlocked: true,
		},

		"private repo, actor is spammy": {
			isPrivate: true,

			expectedHasLaunchFlag: true,

			actionInvocationBlocked: false,
			isSpammyActor:           true,
		},

		"private repo, actor does not have verified email": {
			isPrivate: true,

			expectedHasLaunchFlag: true,

			actionInvocationBlocked: false,
			noVerifiedEmailActor:    true,
		},

		"private repo, launch in lab enabled for user": {
			isPrivate: true,

			expectedHasLaunchFlag: true,

			actionInvocationBlocked: true,
			launchLabEnabled:        true,
			launchLabExpected:       true,
		},

		"public repo": {
			isPrivate: false,

			expectedHasLaunchFlag: true,
		},

		"debug flag enabled for repo": {
			isPrivate: false,
		},

		"repo is private": {
			isPrivate: true,
		},

		"actions-sauron is always given launch lab feature": {
			owner:             "actions-sauron",
			launchLabEnabled:  false,
			launchLabExpected: true,
		},

		"bbq-beets is always given launch lab feature": {
			owner:             "bbq-beets",
			launchLabEnabled:  false,
			launchLabExpected: true,
		},

		"null commit results in error": {
			commitResult:       "null",
			pipelinesDirectory: "null",
			expectedParseError: "Commit for workflow files retrieval not found (retryable)",
		},

		"hosted runner custom images enabled": {
			hasHostedRunnerCustomImagesEnabled: true,
		},
	}

	var graphQLResp string

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))
			assert.Equal(t, queryDataForWorkflowInvocation, gql.Query)
			assert.Equal(t, id.String(), gql.Variables["repo"], "query's variable $repo")

			w.Write([]byte(graphQLResp)) // nolint: errcheck
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)

	const userID = 20158
	userGlobalID := types.GlobalID(testutils.EncodeGlobalID("User", userID))

	for name, ex := range examples {
		t.Run(name, func(tt *testing.T) {

			/* result gathered using these vars:
			{
			  "repo": "MDEwOlJlcG9zaXRvcnkxNDI5ODU0NDY=",
			  "actorId": "MDQ6VXNlcjIwMTU4"
			}
			*/
			owner := ex.owner
			if owner == "" {
				owner = "fried-oreos"
			}
			commitResult := ex.commitResult
			if commitResult == "" {
				commitResult = fmt.Sprintf(`{
					"sha": %q
				}`, commit.String())
			}
			pipelinesDirectory := ex.pipelinesDirectory
			if pipelinesDirectory == "" {
				pipelinesDirectory = `{
					"entries": [
					  {
						"name": "workflow.yml",
						"object": {
						  "text": "on: push",
						  "sha": "aaff2"
						}
					  }
					]
				  }`
			}
			graphQLResp = fmt.Sprintf(`
				{
				  "data": {
				    "repository": {
				      "launchLabEnabled": %t,
				      "isPrivate": %t,
				      "name": "launch-test",
							"databaseId": 142985446,
							"actionsPlanOwner": {
								"id": "MDEyOk9yZ2FuaXphdGlvbjk5MTk=",
								"name": "github",
								"planName": "enterprise",
								"type": "Organization"
							},
				      "owner": {
				        "databaseId": 156456778,
				        "login": %q,
				        "hasHostedRunnerCustomImagesEnabled": %t
				      },
				      "workflowFilesCommit": %s,
 				      "pipelinesDirectory": %s
				    },
				    "actor": {
				      "type": "User",
					  "actionInvocationBlocked": %t,
					  "isSpammy": %t,
					  "noVerifiedEmail": %t,
				      "databaseId": %d
				    }
				  }
				}`,
				ex.launchLabEnabled,
				ex.isPrivate,
				owner,
				ex.hasHostedRunnerCustomImagesEnabled,
				commitResult,
				pipelinesDirectory,
				ex.actionInvocationBlocked,
				ex.isSpammyActor,
				ex.noVerifiedEmailActor,
				userID,
			)

			res, err := tc.GetDataForWorkflowInvocation(ctx, id, commit, userGlobalID, flowfile.ProdPipelinesDirectory)
			if ex.expectedParseError == "" {
				require.NoError(tt, err)
			} else {
				require.EqualError(tt, errors.Cause(err), ex.expectedParseError)
				return
			}
			assert.Equal(tt, owner, res.NWO.Owner, "NWO owner")
			assert.Equal(tt, "launch-test", res.NWO.Name, "NWO name")
			assert.Equal(tt, int64(142985446), res.RepoDatabaseID, "Repo database ID")
			assert.Equal(tt, int64(156456778), res.Owner.DatabaseID, "Owner database ID")
			assert.Equal(tt, int64(userID), res.Actor.DatabaseID, "Actor database ID")
			assert.Equal(tt, userGlobalID, res.Actor.GlobalID, "Actor global ID")
			assert.Equal(tt, "User", res.Actor.Type, "Actor type")
			assert.Equal(tt, "github", res.PlanOwner.Name, "Billing plan owner name")
			assert.Equal(tt, "enterprise", res.PlanOwner.PlanName, "Billing plan name")
			assert.Equal(tt, ex.actionInvocationBlocked, res.Actor.ActionInvocationBlocked, "has action invocation blocked")
			assert.Equal(tt, ex.launchLabExpected, res.FeatureFlags.LaunchLabEnabled, "has launch in lab flag")
			assert.Equal(tt, ex.isSpammyActor, res.Actor.IsSpammy, "is spammy actor")
			assert.Equal(tt, ex.noVerifiedEmailActor, res.Actor.NoVerifiedEmail, "no verified email actor")
			assert.Equal(tt, ex.hasHostedRunnerCustomImagesEnabled, res.HasHostedRunnerCustomImagesEnabled, "Owner has hosted runner custom images enabled")

			assert.ElementsMatch(tt, res.PipelineFiles, []types.ResolvedFile{
				{
					Path:          ".github/workflows/workflow.yml",
					SHA:           commit.String(),
					Text:          "on: push",
					RepositoryNwo: fmt.Sprintf("%s/launch-test", owner),
				},
			})
		})
	}
}

func TestQueries_GetDataForWorkflowInvocation_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	id := types.GlobalID("ABCDEF==")
	commit := types.CommitSha("abcdefggggg")
	const userID = 20158
	userGlobalID := types.GlobalID(testutils.EncodeGlobalID("User", userID))

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	_, err := tc.GetDataForWorkflowInvocation(ctx, id, commit, userGlobalID, flowfile.ProdPipelinesDirectory)

	require.Error(t, err)
}

func TestQueries_GetReportingMetadataMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()

	rID := types.GlobalID("repoIdOne")
	aID := types.GlobalID("actorIdOne")
	_, err := tc.GetReportingMetadata(ctx, rID, aID)
	assert.Error(t, err)
}

func TestQueries_GetReportingMetadata(t *testing.T) {
	actionRepo := &metadata.WorkflowRepositoryMetadata{
		GlobalRelayID: "MDEwOlJlcG9zaXRvcnk1",
		ID:            5,
		Visibility:    hydro.Repository_PUBLIC,
	}

	targetRepo := *actionRepo

	targetRepo.GlobalRelayID = "R_kgAD"
	targetRepo.ID = 3

	repoOwner := &metadata.WorkflowMetadataUser{
		GlobalRelayID: "U_kgDOAP3FAg",
		ID:            16631042,
		Login:         "otherUser",
	}

	dependabotActor := &metadata.WorkflowMetadataActor{
		IsDependabot: true,
		Login:        "otherUser", // Note: In reality this would be "dependabot[bot]", but that's not important here
	}

	nonDependabotActor := &metadata.WorkflowMetadataActor{
		IsDependabot: false,
		Login:        "otherUser",
	}

	type deps struct {
		actions  []*model.Action
		response string
	}

	type setup struct {
		deps
		expectedTargetRepo      *metadata.WorkflowRepositoryMetadata
		expectedInvokingActor   *metadata.WorkflowMetadataUser
		expectedTargetRepoOwner *metadata.WorkflowMetadataUser
		expectedActor           *metadata.WorkflowMetadataActor
	}

	repoID := types.GlobalID("repoIdOne")
	actorID := types.GlobalID("actorIdOne")

	doWithGitHubTenant := func(tt *testing.T, d deps) (metadata.WorkflowMetadata, error) {
		server, serverURL, teardown := newRemoteServer(t)
		defer teardown()
		server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
			server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
				assert.Contains(tt, gql.Query, "GetReportingMetadata")
				assert.True(tt, len(gql.Variables) > 0)
				assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))

				fmt.Fprint(w, d.response)
			})
		})

		tc := createTestClient(t, serverURL, testGitHubToken, true)
		ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)

		return tc.GetReportingMetadata(ctx, repoID, actorID)
	}

	runTest := func(tt *testing.T, test setup) {
		actualWithTenant, err := doWithGitHubTenant(tt, test.deps)
		require.NoError(tt, err)

		if test.expectedInvokingActor != nil {
			assert.Equal(tt, test.expectedInvokingActor, actualWithTenant.InvokingUser)
		}
		if test.expectedActor != nil {
			assert.Equal(tt, test.expectedActor, actualWithTenant.Actor)
		}
		if test.expectedTargetRepo != nil {
			assert.Equal(tt, test.expectedTargetRepo, actualWithTenant.Repository)
		}
		if test.expectedTargetRepoOwner != nil {
			assert.Equal(tt, test.expectedTargetRepoOwner, actualWithTenant.RepositoryOwner)
		}
	}

	t.Run("returns target repo", func(tt *testing.T) {
		runTest(tt,
			setup{
				deps: deps{
					actions: []*model.Action{
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/repo", Path: "action0", Ref: "master"}},
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/reponot", Path: "nope", Ref: "master"}},
					},
					response: fixture("action_metadata/responses/single_action.json"),
				},
				expectedTargetRepo: &targetRepo,
			},
		)
	})

	t.Run("returns target owner", func(tt *testing.T) {
		runTest(tt,
			setup{
				deps: deps{
					actions: []*model.Action{
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/repo", Path: "action0", Ref: "master"}},
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/reponot", Path: "nope", Ref: "master"}},
					},
					response: fixture("action_metadata/responses/single_action.json"),
				},
				expectedTargetRepoOwner: repoOwner,
			},
		)
	})

	t.Run("returns invoking actor", func(tt *testing.T) {
		runTest(tt,
			setup{
				deps: deps{
					actions: []*model.Action{
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/repo", Path: "action0", Ref: "master"}},
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/reponot", Path: "nope", Ref: "master"}},
					},
					response: fixture("action_metadata/responses/single_action.json"),
				},
				expectedInvokingActor: repoOwner,
			},
		)
	})

	t.Run("returns dependabot state as false when actor is not dependabot", func(tt *testing.T) {
		runTest(tt,
			setup{
				deps: deps{
					actions: []*model.Action{
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/repo", Path: "action0", Ref: "master"}},
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/reponot", Path: "nope", Ref: "master"}},
					},
					response: fixture("action_metadata/responses/not_dependabot_actor.json"),
				},
				expectedActor: nonDependabotActor,
			},
		)
	})

	t.Run("returns dependabot state", func(tt *testing.T) {
		runTest(tt,
			setup{
				deps: deps{
					actions: []*model.Action{
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/repo", Path: "action0", Ref: "master"}},
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/reponot", Path: "nope", Ref: "master"}},
					},
					response: fixture("action_metadata/responses/dependabot_actor.json"),
				},
				expectedActor: dependabotActor,
			},
		)
	})

	t.Run("returns dependabot state as non dependabot (disable enforcement FF is ON)", func(tt *testing.T) {
		runTest(tt,
			setup{
				deps: deps{
					actions: []*model.Action{
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/repo", Path: "action0", Ref: "master"}},
						{Identifier: "test", Uses: &model.UsesRepository{Repository: "owner/reponot", Path: "nope", Ref: "master"}},
					},
					response: fixture("action_metadata/responses/dependabot_actor_disable_enforcement.json"),
				},
				expectedActor: nonDependabotActor,
			},
		)
	})
}

func fixture(path string) string {
	str, err := os.ReadFile("fixtures/" + path)
	if err != nil {
		panic(err)
	}
	return string(str)
}

func TestQueries_RepositoryNWO(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const repoName = "test-repo"
	const repoOwner = "test-owner"

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			fmt.Fprintf(w, `{"data":{"node":{"name": %q,"owner":{"login":%q}}}}`, repoName, repoOwner)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, false)
	ctx := context.Background()
	repoNWO, err := tc.RepositoryNWO(ctx, types.GlobalID("repo-1"))
	require.NoError(t, err)
	assert.Equal(t, repoOwner, repoNWO.Owner)
	assert.Equal(t, repoName, repoNWO.Name)
}

func TestQueries_GetCurrentScheduleState_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const repoID = types.GlobalID("repo-1")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))
			fmt.Fprint(w, `{
				"data": {
					"repository": {
					"isFeatureEnabled": false,
					"head": {
						"sha": "7d2b54cbd378af0dde3df61f1186fb2b25de2f49"
					},
					"owner": {
						"isFeatureEnabled": true
					},
					"flow": {
						"text": "workflow text"
					},
					"pipelinesDirectory": {
						"entries": [
							{
								"name": "workflow.yml",
								"object": {
									"text": "on: push",
									"sha": "aaff2"
								},
								"workflow": {
									"state": "ACTIVE"
								}
							}
						]
					}
				}
				}
			}`)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)

	ret, err := tc.GetCurrentScheduleState(ctx, repoID, launchconfig.ProductionAppEnv)

	require.NoError(t, err)
	assert.Equal(t, "7d2b54cbd378af0dde3df61f1186fb2b25de2f49", ret.CurrentHeadSHA.String())
	assert.Equal(t, ".github/workflows/workflow.yml", ret.PipelineFiles[0].Path)
}

func TestQueries_GetCurrentScheduleState_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const repoID = types.GlobalID("repo-1")
	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	_, err := tc.GetCurrentScheduleState(ctx, repoID, launchconfig.ProductionAppEnv)

	require.Error(t, err)
}

func TestQueries_GetRepositoryScheduleData(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const repoID = types.GlobalID("MDQ6VXNlcjI")
	var responseJSON string

	setupTest := func(flowHeadJSON string) {
		responseJSON = fmt.Sprintf(`
			{
				"data": {
					"actor": {
						"login": "monalisa",
						"id": "MDQ6VXNlcjI="
					},
					"repository": {
						"id": "MDEwOlJlcG9zaXRvcnky",
						"name": "launch",
						"head": {
							"sha": "0f50ae779ac6b24fd066283d1f5b81878f7e8147"
						},
						"defaultBranchRef": {
							"prefix": "refs/heads/",
							"name": "master"
						},
						"actionsPlanOwner": {
							"id": "MDQ6VXNlcjA="
						},
						"owner": {
							"login": "monalisa"
						},
						"pipelinesDirectory": {
							"entries": [
								{
									"name": "workflow.yml",
									"object": {
										"text": "on: push",
										"sha": "aaff2"
									},
									"workflow": {
										"state": "ACTIVE"
									}
								},
								{
									"name": "deleted.yml",
									"object": {
										"text": "on: push",
										"sha": "aaff2"
									},
									"workflow": {
										"state": "DELETED"
									}
								},
								{
									"name": "disabled_fork.yml",
									"object": {
										"text": "on: push",
										"sha": "aaff2"
									},
									"workflow": {
										"state": "DISABLED_FORK"
									}
								},
								{
									"name": "disabled_inactivity.yml",
									"object": {
										"text": "on: push",
										"sha": "aaff2"
									},
									"workflow": {
										"state": "DISABLED_INACTIVITY"
									}
								},
								{
									"name": "disabled_manually.yml",
									"object": {
										"text": "on: push",
										"sha": "aaff2"
									},
									"workflow": {
										"state": "DISABLED_MANUALLY"
									}
								}
							]
						},
						"flow": %s
					}
				}
			}
		`, flowHeadJSON)
	}

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, string(repoID), gql.Variables["id"])
			data := map[string]any{}
			err := json.Unmarshal([]byte(responseJSON), &data)
			require.NoError(t, err, "invalid response JSON provided")
			fmt.Fprint(w, responseJSON)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, false)
	ctx := context.Background()

	flowfilePresentInHeadJSON := `{
		"sha": "da6929a004a7152a1c653626349e64921737bfc5",
		"text": "some workflow file"
	}`

	getDataWithCommits := func(_ types.BeforeAfterSHA) (*RepositoryScheduleData, error) {
		return tc.GetRepositoryScheduleData(
			ctx,
			repoID,
			"master",
			"MDQ6VXNlcjI=",
			launchconfig.ProductionAppEnv,
		)
	}

	t.Run("handles flow file missing", func(t *testing.T) {
		setupTest("null")
		_, err := getDataWithCommits(types.BeforeAfterSHAFromStrings("beforeSha", "afterSha"))
		require.NoError(t, err)
	})

	t.Run("Returns all expected data", func(t *testing.T) {
		setupTest(flowfilePresentInHeadJSON)
		data, err := getDataWithCommits(types.BeforeAfterSHAFromStrings("beforeSha", "afterSha"))
		require.NoError(t, err)

		assert.Equal(t, "monalisa", data.ActorLogin)
		assert.Equal(t, types.GlobalID("MDQ6VXNlcjI="), data.ActorGID)
		assert.Equal(t, "refs/heads/master", data.DefaultBranchFullRef)
		assert.Equal(t, types.CommitSha("0f50ae779ac6b24fd066283d1f5b81878f7e8147"), data.CurrentHeadSHA)
		assert.Equal(t, ".github/workflows/workflow.yml", data.PipelineFiles[0].Path)
		assert.Equal(t, ".github/workflows/deleted.yml", data.PipelineFiles[1].Path)
		assert.Equal(t, types.RepositoryFullName{Owner: "monalisa", Name: "launch"}, data.FullName)
		assert.Equal(t, types.GlobalID("MDQ6VXNlcjA="), data.ActionsPlanOwner)

		assert.Equal(t, 2, len(data.PipelineFiles))
	})
}

func TestQueries_CheckCommitReachability_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const repoID = types.GlobalID("MDQ6VXNlcjI")

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))

			resp := `
			{
				"data": {
					"repository": {
						"commitIsInBranchOrTag": true
					}
				}
			}
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)
	res, err := tc.CheckCommitReachability(ctx, repoID, "abcdefg")

	require.NoError(t, err)
	require.NoError(t, err)
	assert.True(t, *res)
}

func TestQueries_CheckCommitReachability_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const repoID = types.GlobalID("MDQ6VXNlcjI")

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	_, err := tc.CheckCommitReachability(ctx, repoID, "abcdefg")

	require.Error(t, err)
}

func TestQueries_GetFilterDiff_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const repoID = types.GlobalID("MDQ6VXNlcjI")

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))

			resp := `
			{
				"data": {
					"repository": {
						"actionsFilterDiff": {
							"paths": ["one", "two"]
						}
					}
				}
			}
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)
	res, err := tc.GetFilterDiff(ctx, repoID, types.BeforeAfterSHA{
		Before: "aabb",
		After:  "ccdd",
	}, ref, "")

	require.NoError(t, err)
	require.NotNil(t, res)
	assert.Equal(t, &FilterDiffResult{
		Paths:    []string{"one", "two"},
		Advisory: "",
	}, res)
}

func TestQueries_GetFilterDiff_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const repoID = types.GlobalID("MDQ6VXNlcjI")

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	_, err := tc.GetFilterDiff(ctx, repoID, types.BeforeAfterSHA{
		Before: "aabb",
		After:  "ccdd",
	}, ref, "")

	require.Error(t, err)
}

func TestQueries_GetCheckSuite_WithGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const checkSuiteID = types.GlobalID("check-suite-1")

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			assert.Equal(t, "3", r.Header.Get(ghtenant.GitHubTenantIDHeader))

			resp := `
			{
				"data": {
				  "node": {
					"status": "COMPLETED",
					"conclusion": "SUCCESS",
					"commit": {
					  "oid": "3d9215c3b150a5230c790241a4ffc73238260363"
					},
					"checkRuns": {
					  "totalCount": 1,
					  "nodes": [
						{
						  "id": "CR_kwDOIffJVM8AAAAFUiUGNg",
						  "status": "COMPLETED",
						  "conclusion": "SUCCESS",
						  "startedAt": "2024-03-19T19:51:22Z",
						  "steps": {
							"totalCount": 6,
							"nodes": [
							  {
								"number": 1,
								"status": "COMPLETED",
								"conclusion": "SUCCESS"
							  },
							  {
								"number": 2,
								"status": "COMPLETED",
								"conclusion": "SUCCESS"
							  },
							  {
								"number": 3,
								"status": "COMPLETED",
								"conclusion": "SUCCESS"
							  },
							  {
								"number": 4,
								"status": "COMPLETED",
								"conclusion": "SUCCESS"
							  },
							  {
								"number": 8,
								"status": "COMPLETED",
								"conclusion": "SUCCESS"
							  },
							  {
								"number": 9,
								"status": "COMPLETED",
								"conclusion": "SUCCESS"
							  }
							]
						  }
						}
					  ]
					}
				  }
				}
			  }
			`
			fmt.Fprint(w, resp)
		})
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx, _ := ghtenant.ContextWithTenantID(context.Background(), 3, true)
	res, err := tc.GetCheckSuiteFromDotcom(ctx, checkSuiteID)

	require.NoError(t, err)
	require.NotNil(t, res)
	assert.Equal(t, "3d9215c3b150a5230c790241a4ffc73238260363", res.SHA)
	assert.Equal(t, "CR_kwDOIffJVM8AAAAFUiUGNg", res.CheckRuns[0].ID)
	assert.Equal(t, 6, len(res.CheckRuns[0].Steps))
}

func TestQueries_GetCheckSuiteFromDotcom_WithMissingGitHubTenant(t *testing.T) {
	server, serverURL, teardown := newRemoteServer(t)
	defer teardown()

	const checkSuiteID = types.GlobalID("check-suite-1")

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		assert.FailNow(t, "request should not be made without GitHub tenant")
	})

	tc := createTestClient(t, serverURL, testGitHubToken, true)
	ctx := context.Background()
	_, err := tc.GetCheckSuiteFromDotcom(ctx, checkSuiteID)

	require.Error(t, err)
}

func init() {
	testutils.EnsureGlobalTracerIsMocked()
}
