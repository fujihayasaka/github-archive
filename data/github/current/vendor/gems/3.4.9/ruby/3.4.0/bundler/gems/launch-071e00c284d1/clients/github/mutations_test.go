package github

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/types"
	"github.com/github/launch/utils/haswaitedforrep"
	"github.com/github/launch/utils/permitreplicas"
	"github.com/github/launch/utils/testutils"
)

const testGitHubToken = "i-am-a-github-api-token"

func TestCreateCheckSuite(t *testing.T) {
	const repoID = types.GlobalID("repo-1")
	const forkID = types.GlobalID("repo-2")
	const commitSha = types.CommitSha("abc123")
	const ref = types.GitRef("refs/heads/master")
	const checkSuiteID = types.GlobalID("check-suite-1")
	const checkSuiteDatabaseID = int64(1234)
	const name = "the-name"
	const event = "issue"
	const action = "opened"
	const workflowDatabaseID = int64(1)
	const workflowRunNumber = int64(2)
	const triggerID = types.GlobalID("trigger-id-1")
	const treeID = types.CommitSha("123abc")

	req := CreateCheckSuiteRequest{
		RepositoryID:     repoID,
		HeadSHA:          commitSha,
		HeadRef:          ref,
		HeadRepositoryID: forkID,
		Name:             name,
		EventName:        event,
		TriggerID:        triggerID,
	}

	ctx := context.Background()

	createCheckSuiteMutationEndpoint := func(tt *testing.T, format string, a ...any) (Client, func()) {
		return createGraphqlEndpoint(tt, func(gql graphQLRequest, r *http.Request) string {
			assertDig(tt, repoID.String(), gql.Variables, "input", "repositoryId")
			assertDig(tt, commitSha.String(), gql.Variables, "input", "headSha")
			refuteDig(tt, gql.Variables, "input", "creatorId")
			assertDig(tt, ref.String(), gql.Variables, "input", "headBranch")
			assertDig(tt, forkID.String(), gql.Variables, "input", "headRepositoryId")
			assertDig(tt, name, gql.Variables, "input", "name")
			assertDig(tt, event, gql.Variables, "input", "event")
			assertDig(tt, triggerID.String(), gql.Variables, "input", "triggerId")
			assertDig(tt, nil, gql.Variables, "input", "conclusion")
			return fmt.Sprintf(format, a...)
		})
	}

	t.Run("success without creator", func(tt *testing.T) {
		c, teardown := createCheckSuiteMutationEndpoint(tt, `{ "data": { "createCheckSuite": { "checkSuite": {"id": %q, "databaseId": %d, "workflowRun": { "databaseId": %d, "runNumber": %d } } } } }`, checkSuiteID, checkSuiteDatabaseID, workflowDatabaseID, workflowRunNumber)
		defer teardown()

		res, err := c.CreateCheckSuite(ctx, req)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
		assert.Equal(tt, checkSuiteDatabaseID, res.CheckSuiteIDPair.DatabaseID)
		assert.Equal(tt, workflowDatabaseID, res.WorkflowRun.DatabaseID)
		assert.Equal(tt, workflowRunNumber, res.WorkflowRun.RunNumber)
	})

	t.Run("returns error when commit not found", func(tt *testing.T) {
		c, teardown := createCheckSuiteMutationEndpoint(tt, `{"data":{"createCheckSuite":null},"errors":[{"type":"VALIDATION","path":["createCheckSuite"],"locations":[{"line":2,"column":2}],"message":"No commit found for SHA: %s"}]}`, commitSha)
		defer teardown()

		_, err := c.CreateCheckSuite(ctx, req)
		assert.EqualError(tt, errors.Cause(err), "not found")
	})

	t.Run("success with creator", func(tt *testing.T) {
		reqWithCreator := CreateCheckSuiteRequest{
			RepositoryID:     repoID,
			HeadSHA:          commitSha,
			HeadRepositoryID: forkID,
			Name:             name,
			EventName:        event,
			EventAction:      action,
			CreatorID:        types.GlobalID("creator-1"),
		}
		c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
			assertDig(t, "creator-1", gql.Variables, "input", "creatorId")
			return fmt.Sprintf(`{ "data": { "createCheckSuite": { "checkSuite": { "id": %q, "databaseId": %d } } } }`, checkSuiteID, checkSuiteDatabaseID)
		})
		defer teardown()

		res, err := c.CreateCheckSuite(ctx, reqWithCreator)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
	})

	t.Run("with workflowFilePath", func(tt *testing.T) {
		reqWithCreator := CreateCheckSuiteRequest{
			RepositoryID:     repoID,
			HeadSHA:          commitSha,
			HeadRepositoryID: forkID,
			Name:             name,
			EventName:        event,
			WorkflowFilePath: ".github/workflows/main.yml",
		}
		c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
			assertDig(t, ".github/workflows/main.yml", gql.Variables, "input", "workflowFilePath")
			return fmt.Sprintf(`{ "data": { "createCheckSuite": { "checkSuite": { "id": %q, "databaseId": %d } } } }`, checkSuiteID, checkSuiteDatabaseID)
		})
		defer teardown()

		res, err := c.CreateCheckSuite(ctx, reqWithCreator)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
	})

	t.Run("with workflowName", func(tt *testing.T) {
		reqWithCreator := CreateCheckSuiteRequest{
			RepositoryID:     repoID,
			HeadSHA:          commitSha,
			HeadRepositoryID: forkID,
			Name:             name,
			EventName:        event,
			WorkflowName:     "some-workflow",
		}
		c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
			assertDig(t, "some-workflow", gql.Variables, "input", "workflowName")
			return fmt.Sprintf(`{ "data": { "createCheckSuite": { "checkSuite": { "id": %q, "databaseId": %d } } } }`, checkSuiteID, checkSuiteDatabaseID)
		})
		defer teardown()

		res, err := c.CreateCheckSuite(ctx, reqWithCreator)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
	})

	t.Run("with tree_id", func(tt *testing.T) {
		reqWithTreeId := CreateCheckSuiteRequest{
			RepositoryID:      repoID,
			HeadSHA:           commitSha,
			WorkflowRunTreeID: treeID,
		}
		c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
			assertDig(t, "123abc", gql.Variables, "input", "workflowRunTreeId")
			return fmt.Sprintf(`{ "data": { "createCheckSuite": { "checkSuite": { "id": %q, "databaseId": %d } } } }`, checkSuiteID, checkSuiteDatabaseID)
		})
		defer teardown()

		res, err := c.CreateCheckSuite(ctx, reqWithTreeId)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
	})

	t.Run("with HIDDEN parameter", func(tt *testing.T) {
		reqWithHidden := CreateCheckSuiteRequest{
			Visibility:       githubv4.CheckSuiteVisibilityHidden,
			RepositoryID:     repoID,
			HeadSHA:          commitSha,
			HeadRepositoryID: forkID,
			Name:             name,
			EventName:        "dynamic",
			WorkflowName:     "dynamic-workflow",
		}
		c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
			assertDig(t, "HIDDEN", gql.Variables, "input", "visibility")
			return fmt.Sprintf(`{ "data": { "createCheckSuite": { "checkSuite": { "id": %q, "databaseId": %d } } } }`, checkSuiteID, checkSuiteDatabaseID)
		})
		defer teardown()

		res, err := c.CreateCheckSuite(ctx, reqWithHidden)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
	})

	t.Run("with an empty string visibility ", func(tt *testing.T) {
		reqWithHidden := CreateCheckSuiteRequest{
			RepositoryID:     repoID,
			HeadSHA:          commitSha,
			HeadRepositoryID: forkID,
			Name:             name,
			EventName:        "dynamic",
			WorkflowName:     "dynamic-workflow",
		}
		c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
			refuteDig(t, gql.Variables, "input", "visibility")
			return fmt.Sprintf(`{ "data": { "createCheckSuite": { "checkSuite": { "id": %q, "databaseId": %d } } } }`, checkSuiteID, checkSuiteDatabaseID)
		})
		defer teardown()

		res, err := c.CreateCheckSuite(ctx, reqWithHidden)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
	})

	t.Run("has not waited for replication", func(tt *testing.T) {
		reqWithTreeId := CreateCheckSuiteRequest{
			RepositoryID:      repoID,
			HeadSHA:           commitSha,
			WorkflowRunTreeID: treeID,
		}
		c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
			assert.Equal(t, "", r.Header.Get("X-HasWaitedForReplication"))
			return fmt.Sprintf(`{ "data": { "createCheckSuite": { "checkSuite": { "id": %q, "databaseId": %d } } } }`, checkSuiteID, checkSuiteDatabaseID)
		})
		defer teardown()

		ctx = haswaitedforrep.ContextWithHasWaitedForReplicas(ctx)

		res, err := c.CreateCheckSuite(ctx, reqWithTreeId)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
	})

	t.Run("has waited for replication", func(tt *testing.T) {
		reqWithTreeId := CreateCheckSuiteRequest{
			RepositoryID:      repoID,
			HeadSHA:           commitSha,
			WorkflowRunTreeID: treeID,
		}
		c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
			assert.Equal(t, "1", r.Header.Get("X-PermitReplicas"))
			return fmt.Sprintf(`{ "data": { "createCheckSuite": { "checkSuite": { "id": %q, "databaseId": %d } } } }`, checkSuiteID, checkSuiteDatabaseID)
		})
		defer teardown()

		ctx = haswaitedforrep.ContextWithHasWaitedForReplicas(ctx)

		res, err := c.CreateCheckSuite(ctx, reqWithTreeId)
		require.NoError(tt, err)

		assert.Equal(tt, checkSuiteID, res.CheckSuiteIDPair.GlobalID)
	})
}

func TestCreateCheckRun(t *testing.T) {
	startedAt := time.Unix(1537471774, 0)
	req := CreateCheckRunRequest{
		CheckSuiteID: types.GlobalID("123f"),
		RepositoryID: types.GlobalID("repo-1"),
		HeadSHA:      "abc123",
		StartedAt:    &startedAt,
		Name:         "check-run",
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationCreateCheckRun, gql.Query)
		assertDig(t, "123f", gql.Variables, "create", "checkSuiteId")
		assertDig(t, "repo-1", gql.Variables, "create", "repositoryId")
		assertDig(t, "abc123", gql.Variables, "create", "headSha")
		assertDig(t, "check-run", gql.Variables, "create", "name")
		assertDig(t, startedAt.Format(time.RFC3339), gql.Variables, "create", "startedAt")
		refuteDig(t, gql.Variables, "create", "completedAt")
		return `{ "data": { "createCheckRun": { "checkRun": {"id": "check-run-1", "databaseId": 1234, "checkSuite": { "id": "check-suite-1", "databaseId": 5678 } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.CreateCheckRun(ctx, req)
	t.Log(res, err)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-1"), res.CheckSuiteIDPair.GlobalID)
	assert.Equal(t, int64(5678), res.CheckSuiteIDPair.DatabaseID)
	assert.Equal(t, types.GlobalID("check-run-1"), res.CheckRunIDPair.GlobalID)
	assert.Equal(t, int64(1234), res.CheckRunIDPair.DatabaseID)
}

func TestCreateGateRequest(t *testing.T) {
	expiresAt := time.Now().Add(-1 * time.Hour).UTC()
	expiresAtText, _ := expiresAt.MarshalText()
	req := CreateGateRequestRequest{
		GateID:     types.GlobalID("gate-1"),
		CheckRunID: types.GlobalID("check-run-1"),
		Token:      "abc123",
		State:      "CLOSED",
		ExpiresAt:  expiresAt,
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationCreateGateRequest, gql.Query)
		assertDig(t, "gate-1", gql.Variables, "input", "gateId")
		assertDig(t, "check-run-1", gql.Variables, "input", "checkRunId")
		assertDig(t, "abc123", gql.Variables, "input", "token")
		assertDig(t, "CLOSED", gql.Variables, "input", "state")
		assertDig(t, string(expiresAtText), gql.Variables, "input", "expiresAt")
		return `{ "data": { "createGateRequest": { "gateRequest": {"id": "gate-request-1", "databaseId": 1234 } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.CreateGateRequest(ctx, req)
	t.Log(res, err)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("gate-request-1"), res.GlobalID)
	assert.Equal(t, int64(1234), res.DatabaseID)
}

func TestCreateCheckRunWithoutStartedAt(t *testing.T) {
	req := CreateCheckRunRequest{
		CheckSuiteID: types.GlobalID("123f"),
		RepositoryID: types.GlobalID("repo-1"),
		HeadSHA:      "abc123",
		Name:         "check-run",
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationCreateCheckRun, gql.Query)
		assertDig(t, "123f", gql.Variables, "create", "checkSuiteId")
		assertDig(t, "repo-1", gql.Variables, "create", "repositoryId")
		assertDig(t, "abc123", gql.Variables, "create", "headSha")
		assertDig(t, "check-run", gql.Variables, "create", "name")
		refuteDig(t, gql.Variables, "create", "startedAt")
		refuteDig(t, gql.Variables, "create", "completedAt")
		return `{ "data": { "createCheckRun": { "checkRun": {"id": "check-run-1", "databaseId": 1234, "checkSuite": { "id": "check-suite-1", "databaseId": 5678 } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.CreateCheckRun(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-1"), res.CheckSuiteIDPair.GlobalID)
	assert.Equal(t, int64(5678), res.CheckSuiteIDPair.DatabaseID)
	assert.Equal(t, types.GlobalID("check-run-1"), res.CheckRunIDPair.GlobalID)
	assert.Equal(t, int64(1234), res.CheckRunIDPair.DatabaseID)
}

func TestCreateCheckRunWithHeader(t *testing.T) {
	req := CreateCheckRunRequest{
		CheckSuiteID: types.GlobalID("123f"),
		RepositoryID: types.GlobalID("repo-1"),
		HeadSHA:      "abc123",
		Name:         "check-run",
	}

	attempt := 0
	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		attempt++
		if attempt == 1 {
			// On the first request, assert the header is present
			assert.Equal(t, "1", r.Header.Get(permitreplicas.PermitReplicasHeader))
		} else {
			// On the second request, assert the header is not present
			assert.Equal(t, "", r.Header.Get(permitreplicas.PermitReplicasHeader))
		}

		if attempt == 1 {
			// Return a "not found" error on the first attempt
			return `{ "errors": [ { "type": "NOT_FOUND", "message": "Could not resolve to a node with the global id of 'R_kgDOMCNvuw'" } ] }`
		} else {
			// Return a successful response on the second attempt
			return `{ "data": { "createCheckRun": { "checkRun": {"id": "check-run-1", "databaseId": 1234, "checkSuite": { "id": "check-suite-1", "databaseId": 5678 } } } } }`
		}
	})
	defer teardown()

	ctx := context.Background()
	_, err := c.CreateCheckRun(ctx, req)
	require.NoError(t, err)
}

func TestUpdateCheckSuite(t *testing.T) {
	req := UpdateCheckSuiteRequest{
		RepositoryID: types.GlobalID("repo-1"),
		CheckSuiteID: types.GlobalID("123f"),
		Artifacts:    []*CheckRunArtifact{},
		Conclusion:   "success",
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationUpdateCheckSuite, gql.Query)
		assertDig(t, "repo-1", gql.Variables, "input", "repositoryId")
		assertDig(t, "123f", gql.Variables, "input", "checkSuiteId")
		assertDig(t, "success", gql.Variables, "input", "conclusion")
		return `{ "data": { "updateCheckSuite": { "checkSuite": { "id": "check-suite-1", "databaseId": 1234 } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.UpdateCheckSuite(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-1"), res.GlobalID)
	assert.Equal(t, int64(1234), res.DatabaseID)
}

func TestUpdateCheckRun(t *testing.T) {
	start := time.Date(2016, time.May, 31, 16, 0, 0, 0, time.UTC)
	complete := time.Date(2016, time.May, 31, 16, 0, 0, 0, time.UTC)

	req := UpdateCheckRunRequest{
		RepositoryID: types.GlobalID("repo-1"),
		CheckRunID:   types.GlobalID("123f"),
		StartedAt:    &start,
		CompletedAt:  &complete,
		Conclusion:   "SUCCESS",
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationUpdateCheckRun, gql.Query)
		assertDig(t, "123f", gql.Variables, "update", "checkRunId")
		assertDig(t, "repo-1", gql.Variables, "update", "repositoryId")
		return `{ "data": { "updateCheckRun": { "checkRun": {"id": "check-run-1", "databaseId": 1234, "checkSuite": { "id": "check-suite-1" } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.UpdateCheckRun(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-1"), res.CheckSuiteIDPair.GlobalID)
	assert.Equal(t, types.GlobalID("check-run-1"), res.CheckRunIDPair.GlobalID)
	assert.Equal(t, int64(1234), res.CheckRunIDPair.DatabaseID)
}

func TestUpdateCheckRunWithoutCompletedAt(t *testing.T) {
	start := time.Date(2016, time.May, 31, 16, 0, 0, 0, time.UTC)

	req := UpdateCheckRunRequest{
		RepositoryID: types.GlobalID("repo-1"),
		CheckRunID:   types.GlobalID("123f"),
		StartedAt:    &start,
		Conclusion:   "SUCCESS",
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationUpdateCheckRun, gql.Query)
		assertDig(t, "123f", gql.Variables, "update", "checkRunId")
		assertDig(t, "repo-1", gql.Variables, "update", "repositoryId")
		assertDig(t, nil, gql.Variables, "update", "completedAt")
		assertDig(t, nil, gql.Variables, "update", "conclusion")
		assertDig(t, "2016-05-31T16:00:00Z", gql.Variables, "update", "startedAt")
		return `{ "data": { "updateCheckRun": { "checkRun": {"id": "check-run-1", "checkSuite": { "id": "check-suite-1" } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.UpdateCheckRun(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-1"), res.CheckSuiteIDPair.GlobalID)
	assert.Equal(t, types.GlobalID("check-run-1"), res.CheckRunIDPair.GlobalID)
}

func TestUpdateCheckRunWithoutConclusion(t *testing.T) {
	start := time.Date(2016, time.May, 31, 16, 0, 0, 0, time.UTC)
	complete := time.Date(2016, time.May, 31, 16, 0, 0, 0, time.UTC)

	req := UpdateCheckRunRequest{
		RepositoryID: types.GlobalID("repo-1"),
		CheckRunID:   types.GlobalID("123f"),
		StartedAt:    &start,
		CompletedAt:  &complete,
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationUpdateCheckRun, gql.Query)
		assertDig(t, "123f", gql.Variables, "update", "checkRunId")
		assertDig(t, "repo-1", gql.Variables, "update", "repositoryId")
		assertDig(t, nil, gql.Variables, "update", "completedAt")
		assertDig(t, nil, gql.Variables, "update", "conclusion")
		assertDig(t, "2016-05-31T16:00:00Z", gql.Variables, "update", "startedAt")
		return `{ "data": { "updateCheckRun": { "checkRun": {"id": "check-run-1", "checkSuite": { "id": "check-suite-1" } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.UpdateCheckRun(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-1"), res.CheckSuiteIDPair.GlobalID)
	assert.Equal(t, types.GlobalID("check-run-1"), res.CheckRunIDPair.GlobalID)
}

func TestUpdateCheckRunWithConcurrency(t *testing.T) {
	start := time.Date(2016, time.May, 31, 16, 0, 0, 0, time.UTC)
	complete := time.Date(2016, time.May, 31, 16, 0, 0, 0, time.UTC)

	req := UpdateCheckRunRequest{
		RepositoryID: types.GlobalID("repo-1"),
		CheckRunID:   types.GlobalID("123f"),
		StartedAt:    &start,
		CompletedAt:  &complete,
		Concurrency: &Concurrency{
			Group: "testGroup",
			WaitingOnResource: &WaitingOnResource{
				CheckSuiteID: types.GlobalID(testutils.EncodeGlobalID("CheckSuiteID", 18)),
				CheckRunID:   types.GlobalID(testutils.EncodeGlobalID("CheckRunID", 1088)),
				Identifier:   "test",
			},
		},
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationUpdateCheckRun, gql.Query)
		assertDig(t, "123f", gql.Variables, "update", "checkRunId")
		assertDig(t, "repo-1", gql.Variables, "update", "repositoryId")
		assertDig(t, nil, gql.Variables, "update", "completedAt")
		assertDig(t, nil, gql.Variables, "update", "conclusion")
		assertDig(t, "2016-05-31T16:00:00Z", gql.Variables, "update", "startedAt")

		updateData := gql.Variables["update"].(map[string]any)
		concurrencyData := updateData["concurrency"].(map[string]any)
		assertDig(t, "test", concurrencyData, "waitingOnResource", "identifier")
		return `{ "data": { "updateCheckRun": { "checkRun": {"id": "check-run-1", "checkSuite": { "id": "check-suite-1" } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.UpdateCheckRun(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-1"), res.CheckSuiteIDPair.GlobalID)
	assert.Equal(t, types.GlobalID("check-run-1"), res.CheckRunIDPair.GlobalID)
}

func TestCreateCheckRunWithConcurrency(t *testing.T) {
	req := CreateCheckRunRequest{
		CheckSuiteID: types.GlobalID("123f"),
		RepositoryID: types.GlobalID("repo-1"),
		HeadSHA:      "abc123",
		Name:         "check-run",
		Concurrency: &Concurrency{
			Group: "testGroup",
			WaitingOnResource: &WaitingOnResource{
				CheckSuiteID: types.GlobalID(testutils.EncodeGlobalID("CheckSuiteID", 18)),
				CheckRunID:   types.GlobalID(testutils.EncodeGlobalID("CheckRunID", 1088)),
				Identifier:   "test",
			},
		},
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationCreateCheckRun, gql.Query)
		assertDig(t, "123f", gql.Variables, "create", "checkSuiteId")
		assertDig(t, "repo-1", gql.Variables, "create", "repositoryId")
		assertDig(t, "abc123", gql.Variables, "create", "headSha")
		assertDig(t, "check-run", gql.Variables, "create", "name")

		createData := gql.Variables["create"].(map[string]any)
		conccData := createData["concurrency"].(map[string]any)
		assertDig(t, "test", conccData, "waitingOnResource", "identifier")
		refuteDig(t, gql.Variables, "create", "startedAt")
		refuteDig(t, gql.Variables, "create", "completedAt")
		return `{ "data": { "createCheckRun": { "checkRun": {"id": "check-run-1", "databaseId": 1234, "checkSuite": { "id": "check-suite-1", "databaseId": 5678 } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.CreateCheckRun(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-1"), res.CheckSuiteIDPair.GlobalID)
	assert.Equal(t, int64(5678), res.CheckSuiteIDPair.DatabaseID)
	assert.Equal(t, types.GlobalID("check-run-1"), res.CheckRunIDPair.GlobalID)
	assert.Equal(t, int64(1234), res.CheckRunIDPair.DatabaseID)
}

func TestReusePreviousWorkflowRunForPullRequest(t *testing.T) {
	req := ReusePreviousWorkflowRequest{
		RepositoryID:      types.GlobalID("repo-1"),
		CheckSuiteToClone: types.GlobalID("check-suite-1-clone-me"),
		Event:             "pull_request",
		CreatorID:         types.GlobalID("creator-1"),
		TriggerID:         types.GlobalID("trigger-1"),
		HeadSha:           types.CommitSha("abc123"),
		HeadBranch:        "monalisa-dev",
		TreeID:            types.CommitSha("tree123"),
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationReusePreviousWorkflowRun, gql.Query)
		assertDig(t, "repo-1", gql.Variables, "reuse", "repositoryId")
		assertDig(t, "check-suite-1-clone-me", gql.Variables, "reuse", "checkSuiteToClone")
		assertDig(t, "pull_request", gql.Variables, "reuse", "event")
		assertDig(t, "creator-1", gql.Variables, "reuse", "creatorId")
		assertDig(t, "trigger-1", gql.Variables, "reuse", "triggerId")
		assertDig(t, "abc123", gql.Variables, "reuse", "headSha")
		assertDig(t, "monalisa-dev", gql.Variables, "reuse", "headBranch")
		assertDig(t, "tree123", gql.Variables, "reuse", "treeId")
		return `{ "data": { "reusePreviousWorkflowRun": { "checkSuite": {"id": "check-suite-2", "databaseId": 2, "workflowRun": { "id": "workflow-run-2", "databaseId": 2 } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.ReusePreviousWorkflowRun(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-2"), res.CheckSuiteID)
	assert.Equal(t, int64(2), res.CheckSuiteDatabaseID)
	assert.Equal(t, types.GlobalID("workflow-run-2"), res.WorkflowRunID)
	assert.Equal(t, int64(2), res.WorkflowRunDatabaseID)
}

func TestReusePreviousWorkflowRunForPushEvent(t *testing.T) {
	req := ReusePreviousWorkflowRequest{
		RepositoryID:      types.GlobalID("repo-1"),
		CheckSuiteToClone: types.GlobalID("check-suite-1-clone-me"),
		Event:             "push",
		CreatorID:         types.GlobalID("creator-1"),
		TriggerID:         types.NilGlobalID,
		HeadSha:           types.CommitSha("abc123"),
		HeadBranch:        "main",
		TreeID:            types.CommitSha("tree123"),
	}

	c, teardown := createGraphqlEndpoint(t, func(gql graphQLRequest, r *http.Request) string {
		assert.Equal(t, mutationReusePreviousWorkflowRun, gql.Query)
		assertDig(t, "repo-1", gql.Variables, "reuse", "repositoryId")
		assertDig(t, "check-suite-1-clone-me", gql.Variables, "reuse", "checkSuiteToClone")
		assertDig(t, "push", gql.Variables, "reuse", "event")
		assertDig(t, "creator-1", gql.Variables, "reuse", "creatorId")
		assertDig(t, nil, gql.Variables, "reuse", "triggerId")
		assertDig(t, "abc123", gql.Variables, "reuse", "headSha")
		assertDig(t, "main", gql.Variables, "reuse", "headBranch")
		assertDig(t, "tree123", gql.Variables, "reuse", "treeId")
		return `{ "data": { "reusePreviousWorkflowRun": { "checkSuite": {"id": "check-suite-2", "databaseId": 2, "workflowRun": { "id": "workflow-run-2", "databaseId": 2 } } } } }`
	})
	defer teardown()

	ctx := context.Background()
	res, err := c.ReusePreviousWorkflowRun(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, types.GlobalID("check-suite-2"), res.CheckSuiteID)
	assert.Equal(t, int64(2), res.CheckSuiteDatabaseID)
	assert.Equal(t, types.GlobalID("workflow-run-2"), res.WorkflowRunID)
	assert.Equal(t, int64(2), res.WorkflowRunDatabaseID)
}

func createGraphqlEndpoint(t *testing.T, assertions func(gql graphQLRequest, r *http.Request) string) (Client, func()) {
	server, serverURL, teardown := newRemoteServer(t)

	server.handleGraphQLRequest(func(w http.ResponseWriter, r *http.Request) {
		server.handleGraphQL(w, r, func(w http.ResponseWriter, gql graphQLRequest) {
			resp := assertions(gql, r)
			w.Write([]byte(resp)) // nolint: errcheck
		})
	})

	c := createTestClient(t, serverURL, testGitHubToken, false)
	return c, teardown
}

func assertDig(t *testing.T, expectedValue any, actualMap map[string]any, keys ...any) bool {
	t.Helper()
	return assert.Equal(t, expectedValue, dig(actualMap, keys...), "req%s in %#v", describeDig(keys...), actualMap)
}

func refuteDig(t *testing.T, actualMap map[string]any, keys ...any) bool {
	t.Helper()
	return assert.Nil(t, dig(actualMap, keys...), "req%s in %#v", describeDig(keys...), actualMap)
}

func dig(coll any, keys ...any) any {
	if len(keys) == 0 {
		return coll
	}
	key := keys[0]
	rest := keys[1:]

	if m, ok := coll.(map[string]any); ok {
		if s, ok := key.(string); ok {
			return dig(m[s], rest...)
		}
	}

	if s, ok := coll.([]any); ok {
		if i, ok := key.(int); ok {
			if i < len(s) {
				return dig(s[i], rest...)
			}
		}
	}

	return fmt.Sprintf("Did not find key '%v' (%T) in (%T) %q", key, key, coll, coll)
}

func describeDig(keys ...any) string {
	if len(keys) == 0 {
		return ""
	}
	return fmt.Sprintf("[%q]", keys[0]) + describeDig(keys[1:]...)
}
