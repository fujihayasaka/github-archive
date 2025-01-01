package azp

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/services/auth/hkdf"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
	"github.com/github/launch/workflowbuild/build"
)

func TestBuildsQueue(t *testing.T, clp func(string) RepositoryClient) {
	s := new(queueSuite)
	s.clp = clp
	suite.Run(t, s)
}

type queueSuite struct {
	suite.Suite

	clp          func(string) RepositoryClient
	wfb          *build.WorkflowBuild
	secretSource string
	secrets      map[string]string
	variables    map[string]string
	featureFlags map[string]bool
}

func (s *queueSuite) SetupTest() {
	s.wfb = &build.WorkflowBuild{
		SigningKey: &hkdf.DerivedKey{
			WorkflowID: "test-id",
			Timestamp:  time.Now(),
		},
		WorkflowFilePath: ".github/workflows/one.yml",
		ResolvedFiles: []types.ResolvedFile{
			{
				Path: ".github/workflows/one.yml",
				Text: "build-file-content",
				SHA:  "bbcc",
			},
		},
		EventPayload: []byte("{}"),
	}

	s.secretSource = "Actions"
	s.secrets = map[string]string{"VERY_SECRET": "shhhh"}
	s.variables = map[string]string{"PLAIN_TEXT_VARIABLE": "variable_value"}
}

//revive:disable-next-line:var-naming
func (s *queueSuite) TestClient_Queue_ReusesE2EIDs() {
	// tests that
	// - the client uses same E2EID across retries, by calling a server
	//   that always 502s and collecting all E2E IDs seen
	// - if context has been prepared with JCVs, we send the correct UA header
	// - the body exists on retries

	ctx := context.Background()
	e2eIDs := make([]string, 0)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		e2eIDs = append(e2eIDs, req.Header.Get(azpcorrelation.VSSE2EIDHeaderName))

		ua := req.Header.Get(azpcorrelation.UserAgentHeaderName)
		s.Equal("GitHubServices service:actions", ua)

		body, err := io.ReadAll(req.Body)
		s.NoError(err)
		s.True(len(body) > 0)

		w.WriteHeader(502)
		fmt.Fprint(w, "Naughty Gateway")
	}))
	defer server.Close()

	client := s.newClient(server.URL)

	resp, err := client.Queue(ctx, s.wfb, "https://ruri.localhost", "https://res-ruri.locahost", s.secretSource, s.secrets, s.variables, nil, nil, s.featureFlags, launchconfig.TestAppEnv)

	s.EqualError(err, "failed to queue build: Naughty Gateway (status code: 502)")
	s.Nil(resp)
	first := ""
	for i, id := range e2eIDs {
		if first == "" {
			first = id
		}
		s.Equal(first, id, fmt.Sprintf("E2EID for all retries should be equal, request %d wasn't", i))
	}
}

//revive:disable-next-line:var-naming
func (s *queueSuite) TestClient_Queue_WithRerunInfo() {
	// tests that RerunInfo is passed over to azp in the payload
	ctx := context.Background()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		body, err := io.ReadAll(req.Body)
		s.NoError(err)
		s.True(len(body) > 0)

		s.Contains(string(body), "\"rerunContext\":{\"previousPlanId\":\"rerun-plan-id\",\"jobIds\":[\"a-job-id\"]}")

		w.WriteHeader(201)
		fmt.Fprintf(w, "{}")
	}))
	defer server.Close()

	client := s.newClient(server.URL)

	s.wfb.RerunInfo = &types.RerunInfo{
		PlanID: "rerun-plan-id",
		JobIDs: types.JobIDs{"a-job-id"},
	}

	_, err := client.Queue(ctx, s.wfb, "https://ruri.localhost", "https://res-ruri.locahost", s.secretSource, s.secrets, s.variables, nil, nil, s.featureFlags, launchconfig.TestAppEnv)
	s.NoError(err)
}

//revive:disable-next-line:var-naming
func (s *queueSuite) TestClient_Queue_Handle429() {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.WriteHeader(429)
	}))
	defer server.Close()

	client := s.newClient(server.URL)
	_, err := client.Queue(context.Background(), s.wfb, "https://ruri.localhost", "https://res-ruri.locahost", s.secretSource, s.secrets, s.variables, nil, nil, s.featureFlags, launchconfig.TestAppEnv)

	want := &azperrors.TooManyBuildsError{}
	s.ErrorAs(err, &want)
}

//revive:disable-next-line:var-naming
func (s *queueSuite) TestClient_Queue_HandlePipelineValidationException() {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.WriteHeader(400)
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		fmt.Fprint(w, "{\"$id\":\"1\",\"innerException\":null,\"message\":\"The workflow is not valid. .github/workflows/ci.yml (Line: 29, Col: 9): 'run' is already defined\",\"typeName\":\"Microsoft.TeamFoundation.DistributedTask.Pipelines.PipelineValidationException, Microsoft.TeamFoundation.DistributedTask.WebApi\",\"typeKey\":\"PipelineValidationException\",\"errorCode\":0,\"eventId\":3000}")
	}))
	defer server.Close()

	client := s.newClient(server.URL)
	_, err := client.Queue(context.Background(), s.wfb, "https://ruri.localhost", "https://res-ruri.locahost", s.secretSource, s.secrets, s.variables, nil, nil, s.featureFlags, launchconfig.TestAppEnv)

	s.IsType(&azperrors.AZPSyntaxError{}, err)
	s.EqualError(err, "The workflow is not valid. .github/workflows/ci.yml (Line: 29, Col: 9): 'run' is already defined")
}

//revive:disable-next-line:var-naming
func (s *queueSuite) TestClient_Queue_WithWorkflowTemplate() {
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wfText := `
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: echo Hello World`
	workflowFilePath := ".github/workflows/workflow.yml"
	resolvedFiles := []wfparser.WorkflowReferencedFile{
		{
			Path: workflowFilePath,
			Text: wfText,
		},
	}

	wft, err := wfparser.LoadWorkflow(ctx, obs, workflowFilePath, wfparser.NewFileProvider(ctx, obs, resolvedFiles), types.LimitedReadWorkflowPermissions)
	s.NoError(err)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		body, err := io.ReadAll(req.Body)
		s.NoError(err)
		s.True(len(body) > 0)

		s.Contains(string(body), "\"workflowTemplate\":{\"jobs\":[{\"type\":\"job\",\"id\":{\"type\":0,\"file\":1,\"line\":4,\"col\":3,\"lit\":\"build\"},\"name\":{\"type\":0,\"file\":1,\"line\":4,\"col\":3,\"lit\":\"build\"},\"if\":{\"type\":3,\"expr\":\"success()\"},\"runs-on\":{\"type\":0,\"file\":1,\"line\":5,\"col\":14,\"lit\":\"ubuntu-latest\"},\"steps\":[{\"id\":\"__actions_checkout\",\"if\":{\"type\":3,\"expr\":\"success()\"},\"uses\":{\"type\":0,\"file\":1,\"line\":7,\"col\":15,\"lit\":\"actions/checkout@v3\"}},{\"id\":\"__run\",\"if\":{\"type\":3,\"expr\":\"success()\"},\"run\":{\"type\":0,\"file\":1,\"line\":8,\"col\":14,\"lit\":\"echo Hello World\"}}]}],\"file-table\":[\".github/workflows/workflow.yml\"],\"file-info\":[{\"path\":\".github/workflows/workflow.yml\"}]}")

		w.WriteHeader(201)
		fmt.Fprintf(w, "{}")
	}))
	defer server.Close()

	client := s.newClient(server.URL)

	_, err = client.Queue(ctx, s.wfb, "https://ruri.localhost", "https://res-ruri.locahost", s.secretSource, s.secrets, s.variables, wft, nil, s.featureFlags, launchconfig.TestAppEnv)
	s.NoError(err)
}

//revive:disable-next-line:var-naming
func (s *queueSuite) TestClient_Queue_UnmarshalAZPExceptions() {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.WriteHeader(400)
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		fmt.Fprint(w, "{\"message\":\"Oops\",\"typeKey\":\"OopsException\"}")
	}))
	defer server.Close()

	client := s.newClient(server.URL)
	_, err := client.Queue(context.Background(), s.wfb, "https://ruri.localhost", "https://res-ruri.locahost", s.secretSource, s.secrets, s.variables, nil, nil, s.featureFlags, launchconfig.TestAppEnv)

	s.EqualError(err, "failed to queue build: OopsException: Oops (status code: 400)")

	azpErr := azperrors.GetAZPError(err)
	s.NotNil(azpErr, "Cause should be an AZPError.")
	if azpErr != nil {
		s.Equal("OopsException", azpErr.ExceptionType)
		s.Equal("Oops", azpErr.Message)
		s.Equal(400, azpErr.StatusCode)
	}
}

func (s *queueSuite) newClient(serverURL string) RepositoryClient {
	return s.clp(serverURL)
}

func TestRunnerGroups(t *testing.T, clp func(string) RepositoryClient) {
	tests := map[string]func(*testing.T, func(string) RepositoryClient){
		"UpdateGroupTargets": TestUpdateGroupTargets,
		"RemoveTarget":       TestRemoveTarget,
		"AddTarget":          TestAddTarget,
		"UpdateGroupRunners": TestUpdateGroupRunners,
		"RemoveRunner":       TestRemoveRunner,
		"UpdateGroup":        TestUpdateGroupRunners,
		"CreateGroup":        TestCreateRunnerGroup,
		"DeleteGroup":        TestRemoveRunner,
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			test(t, clp)
		})
	}
}

func TestCreateRunnerGroup(t *testing.T, clp func(string) RepositoryClient) {
	var createReq string
	var updateRunnersReq string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		b, err := io.ReadAll(r.Body)
		require.NoError(t, err)

		switch r.URL.Path {
		case "/testTenant/_apis/runtime/runnergroups":
			createReq = string(b)
		case "/testTenant/_apis/runtime/runnergroups/1":
			updateRunnersReq = string(b)
		default:
			require.Fail(t, fmt.Sprintf("unexpected request %s", r.URL.Path))
		}
		fmt.Fprintln(w, runnerGroupJSON)
	}))
	defer ts.Close()

	client := clp(ts.URL)
	runnerIDs := []int64{2}
	_, err := client.CreateGroup(context.Background(), runnerIDs, "test", []*pbtypes.Identity{}, "all", AllowPublicDeny, []string{}, RestrictedToWorkflowsUnrestricted)
	require.NoError(t, err)
	assert.JSONEq(t, `{"name":"test","visibility":{"approvedChildren":[],"visibilityType":"all","allowPublic":"false","restrictedToWorkflows":false,"selectedWorkflowRefs":[]}}`, createReq)
	assert.JSONEq(t, `[{"op":"replace","path":"/runners","value":[2]}]`, updateRunnersReq)
}

//revive:disable-next-line:var-naming
func TestCreateRunnerGroup_CannotMoveRunnerIntoOrOutOfVirtualGroupException(t *testing.T, clp func(string) RepositoryClient) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/testTenant/_apis/runtime/runnergroups":
			fmt.Fprintln(w, runnerGroupJSON)
		case "/testTenant/_apis/runtime/runnergroups/1":
			w.WriteHeader(http.StatusInternalServerError)
		default:
			require.Fail(t, fmt.Sprintf("unexpected request %s", r.URL.Path))
		}
	}))
	defer ts.Close()

	client := clp(ts.URL)
	runnerIDs := []int64{2}
	resp, err := client.CreateGroup(context.Background(), runnerIDs, "test", []*pbtypes.Identity{}, "all", AllowPublicDeny, []string{}, RestrictedToWorkflowsUnrestricted)
	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestAddRunner(t *testing.T, clp func(string) RepositoryClient) {
	var req string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		b, err := io.ReadAll(r.Body)
		require.NoError(t, err)
		req = string(b)
		fmt.Fprintln(w, "{}")
	}))
	defer ts.Close()

	client := clp(ts.URL)
	_, err := client.AddRunners(context.Background(), 0, []int64{1, 2, 3})
	require.NoError(t, err)
	assert.JSONEq(t, `[{"op":"add","path":"/runners","value":[1, 2, 3]}]`, req)
}

func TestUpdateGroupRunners(t *testing.T, clp func(string) RepositoryClient) {
	var req string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			fmt.Fprintln(w, runnerGroupJSON)
		case http.MethodPatch:
			defer r.Body.Close()
			b, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			req = string(b)
			fmt.Fprintln(w, runnerGroupJSON)
		}
	}))
	defer ts.Close()

	client := clp(ts.URL)
	var groupID int64 = 1
	runnerIDs := []int64{2}
	_, err := client.UpdateGroupRunners(context.Background(), groupID, runnerIDs)
	require.NoError(t, err)
	assert.JSONEq(t, `[{"op":"replace","path":"/runners","value":[2]}]`, req)
}

func TestRemoveRunner(t *testing.T, clp func(string) RepositoryClient) {
	var req string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		b, err := io.ReadAll(r.Body)
		require.NoError(t, err)
		req = string(b)
		fmt.Fprintln(w, "{}")
	}))
	defer ts.Close()

	client := clp(ts.URL)
	_, err := client.RemoveRunner(context.Background(), 0, 1)
	require.NoError(t, err)
	assert.JSONEq(t, `[{"op":"remove","path":"/runners","value":[1]}]`, req)
}

func TestAddTarget(t *testing.T, clp func(string) RepositoryClient) {
	var req string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		b, err := io.ReadAll(r.Body)
		require.NoError(t, err)
		req = string(b)
		fmt.Fprintln(w, "{}")
	}))
	defer ts.Close()

	client := clp(ts.URL)
	_, err := client.AddTarget(context.Background(), 0, repoID)
	require.NoError(t, err)
	assert.JSONEq(t, `[{"op":"add","path":"/approvedChildren","value":["R_kgDNA-c"]}]`, req)
}

func TestRemoveTarget(t *testing.T, clp func(string) RepositoryClient) {
	var req string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		b, err := io.ReadAll(r.Body)
		require.NoError(t, err)
		req = string(b)
		fmt.Fprintln(w, "{}")
	}))
	defer ts.Close()

	client := clp(ts.URL)
	_, err := client.RemoveTarget(context.Background(), 0, repoID)
	require.NoError(t, err)
	assert.JSONEq(t, `[{"op":"remove","path":"/approvedChildren","value":["R_kgDNA-c"]}]`, req)
}

func TestUpdateGroupTargets(t *testing.T, clp func(string) RepositoryClient) {
	var req string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			fmt.Fprintln(w, runnerGroupJSON)
		case http.MethodPatch:
			defer r.Body.Close()
			b, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			req = string(b)
			fmt.Fprintln(w, runnerGroupJSON)
		}
	}))
	defer ts.Close()

	client := clp(ts.URL)
	var groupID int64 = 1
	runnerIDs := []*pbtypes.Identity{{GlobalId: "repositoryB"}}
	_, err := client.UpdateGroupTargets(context.Background(), groupID, runnerIDs)
	require.NoError(t, err)
	assert.JSONEq(t, `[{"op":"replace","path":"/approvedChildren","value":["repositoryB"]}]`, req)
}

var (
	repoID = &pbtypes.Identity{
		GlobalId: "R_kgDNA-c",
	}
	runnerGroupJSON = `{
		"id": 1,
		"name": "TestGroup",
		"size": 1,
		"isHosted": false,
		"visibility": {
			"visibilityType": "selected",
			"approvedChildren": [ "R_kgDNA-c" ]
		},
		"runners": [{
			"id": 1,
			"name": "TestRunner",
			"version": 1,
			"runnerGroupId": 1,
			"osDescription": "ubuntu-latest",
			"enabled": true,
			"status": "online",
			"currentParallelism": 0,
			"maxParallelism": 1,
			"labels": []
		}]
	}`
)
