package actions_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/turbocassette/recorder"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/twirp/clients/actions"
	"github.com/stretchr/testify/require"
)

func TestRunDynamicWorkflow(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)
	ctx := context.Background()

	r, err := recorder.New("./testdata/launch.yml")
	require.NoError(t, err)
	defer require.NoError(t, r.Stop())

	launch, err := actions.New(cfg, actions.WithDebugClient(r))
	require.NoError(t, err)

	// TODO : This test is not checking that we are sending the correct arguments,
	// as the recorder is not doing request matching.
	// Therefore we are fine using an empty run object
	run := &ts.CodeqlRun{}

	err = launch.RunDynamicWorkflow(ctx, run)
	require.NoError(t, err)
	require.Equal(t, ts.WorkflowRunEID(5), run.WorkflowRunID)
	require.Equal(t, "sweet-potato", run.ExecutionID)
	require.Equal(t, ts.CodeqlRunStatus_INPROGRESS, run.Status)
}

type requestChecker struct {
	t *testing.T
}

func (r *requestChecker) RoundTrip(req *http.Request) (*http.Response, error) {
	slug := req.Header.Get(headers.Tenant)
	require.Equal(r.t, "avocado-corp", slug)
	return &http.Response{StatusCode: 418}, nil
}

func TestRunDynamicWorkflow_IncludeTenant(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)
	ctx := context.Background()
	ctx = tenant.TenantContext(ctx, "avocado-corp")

	r := &requestChecker{t: t}
	launch, err := actions.New(cfg, actions.WithDebugClient(r))
	require.NoError(t, err)

	err = launch.RunDynamicWorkflow(ctx, &ts.CodeqlRun{})
	// Return an error so we do not need to build a valid response
	// Use a specific error code to avoid confusion
	require.Error(t, err)
	require.Contains(t, err.Error(), "418")
}

func TestRunDynamicWorkflow_RequireTenant(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)
	ctx := context.Background()

	// On Proxima we require the tenant information to be present
	// before making a request to Launch
	cfg.Environment = "proxima"
	launch, err := actions.New(cfg)
	require.NoError(t, err)

	err = launch.RunDynamicWorkflow(ctx, &ts.CodeqlRun{})
	require.Error(t, err)
	require.ErrorIs(t, err, actions.ErrMissingTenant)
}

type packsChecker struct {
	t *testing.T
}

type body struct {
	Inputs map[string]string `json:"inputs"`
}

func (r *packsChecker) RoundTrip(req *http.Request) (*http.Response, error) {
	var b body
	require.NoError(r.t, json.NewDecoder(req.Body).Decode(&b))
	require.Equal(r.t, "myorg/mypack@1.2.3,myorg/myotherpack", b.Inputs["code_scanning_codeql_packs"])
	return &http.Response{StatusCode: 418}, nil
}

func TestRunDynamicWorkflow_IncludePacks(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)
	ctx := context.Background()
	ctx = tenant.TenantContext(ctx, "avocado-corp")

	r := &packsChecker{t: t}
	launch, err := actions.New(cfg, actions.WithDebugClient(r))
	require.NoError(t, err)

	packs := ts.CodeqlPacks("\nmyorg/mypack@1.2.3 \n myorg/myotherpack\n")
	err = launch.RunDynamicWorkflow(ctx, &ts.CodeqlRun{CodeqlPacks: &packs})
	// Return an error so we do not need to build a valid response
	// Use a specific error code to avoid confusion
	require.Error(t, err)
	require.Contains(t, err.Error(), "418")
}
