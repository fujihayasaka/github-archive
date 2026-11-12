package jobapi

import (
	"context"
	"errors"
	"testing"

	authd "github.com/github/authnd/client"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestHydrateFullJobResponse_WorkflowRun verifies that WorkflowRun is only
// populated for Actions-launcher jobs (where ComputeID is the numeric workflow
// run ID), and that sandbox-launcher jobs with non-numeric ComputeIDs do not
// cause the response to fail.
func TestHydrateFullJobResponse_WorkflowRun(t *testing.T) {
	h := &Handler{obsv: observability.NewNoopExporters()}

	tests := []struct {
		name           string
		job            *jobs.Job
		expectWorkflow bool
	}{
		{
			name: "actions launcher with numeric compute ID populates workflow run",
			job: &jobs.Job{
				ID:        "job-1",
				ComputeID: "12345",
				Launcher:  launcher.TypeActions,
			},
			expectWorkflow: true,
		},
		{
			name: "empty launcher (legacy) with numeric compute ID populates workflow run",
			job: &jobs.Job{
				ID:        "job-2",
				ComputeID: "12345",
			},
			expectWorkflow: true,
		},
		{
			name: "sandbox launcher with non-numeric compute ID skips workflow run",
			job: &jobs.Job{
				ID:        "job-3",
				ComputeID: "sb-abc-123",
				Launcher:  launcher.TypeSandbox,
			},
			expectWorkflow: false,
		},
		{
			name: "empty compute ID skips workflow run",
			job: &jobs.Job{
				ID: "job-4",
			},
			expectWorkflow: false,
		},
		{
			name: "actions launcher with invalid compute ID skips workflow run",
			job: &jobs.Job{
				ID:        "job-5",
				ComputeID: "not-a-number",
				Launcher:  launcher.TypeActions,
			},
			expectWorkflow: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp := &FullJobResponse{}
			err := h.hydrateFullJobResponse(context.Background(), nil, tt.job, resp)
			require.NoError(t, err)
			if tt.expectWorkflow {
				require.NotNil(t, resp.WorkflowRun)
				assert.Equal(t, int64(12345), resp.WorkflowRun.GetID())
			} else {
				assert.Nil(t, resp.WorkflowRun)
			}
		})
	}
}

func newOwnerRepo() *gg.Repository {
	return &gg.Repository{
		ID:    gg.Ptr(int64(99)),
		Name:  gg.Ptr("repo"),
		Owner: &gg.User{Login: gg.Ptr("owner")},
	}
}

// resolveTestOpts configures the handler+user fixture used by the
// resolveWorkflowAccess tests below.
type resolveTestOpts struct {
	ffOn           bool
	tokenType      authd.CredentialType // defaults to UserToServerToken
	privileged     bool                 // privileged-app capability result (S2S tokens only)
	privilegedErr  error                // error from the privileged-app checker
	hasAccess      bool                 // BatchControlAccess Decision when the call is reached
	twirpErr       error                // BatchControlAccess error
	twirpForbidden bool                 // assert BatchControlAccess is NOT called
}

func newResolveTestHandler(t *testing.T, opts resolveTestOpts) (*Handler, *requestctx.UserInfo) {
	t.Helper()

	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopAuthorizationAPI.MockBatchControlAccess = func(_ context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
		if opts.twirpForbidden {
			t.Fatal("BatchControlAccess must not be called for this case")
		}
		if opts.twirpErr != nil {
			return nil, opts.twirpErr
		}
		require.Len(t, req.AuthorizationRequests, 1, "resolveWorkflowAccess must issue exactly one access check")
		require.Equal(t, writeWorkflowsAccessAction, req.AuthorizationRequests[0].Action)
		require.Equal(t, "Repository", req.AuthorizationRequests[0].ResourceType)
		require.Equal(t, "owner/repo", req.AuthorizationRequests[0].RepositoryNwo)
		return &coreTwirp.BatchControlAccessResponse{
			Decisions: []*coreTwirp.AuthorizationDecision{{Id: "wf", Decision: opts.hasAccess}},
		}, nil
	}

	tokenType := opts.tokenType
	if tokenType == "" {
		tokenType = authd.CredentialTypeUserToServerToken
	}

	h := &Handler{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentScopeGitTokenWorkflows: opts.ffOn}),
		ghTwirp:  noopClient,
		privilegedAppChecker: &github.MockPrivilegedAppChecker{
			MockHasCapabilityResult: opts.privileged,
			MockHasCapabilityError:  opts.privilegedErr,
		},
	}

	user := &requestctx.UserInfo{
		ID:    42,
		Login: "actor",
		TokenInfo: &requestctx.TokenInfo{
			Type:            string(tokenType),
			Token:           "ghu_xxx",
			ApplicationID:   1,
			ApplicationType: "GithubApp",
		},
	}
	return h, user
}

// FF off: no check is performed and the launcher omits the new input.
// This is the byte-identical no-op behavior we rely on for safe rollout.
func TestResolveWorkflowAccess_FFOff_ReturnsNil(t *testing.T) {
	h, user := newResolveTestHandler(t, resolveTestOpts{ffOn: false, twirpForbidden: true})

	got := h.resolveWorkflowAccess(context.Background(), user, newOwnerRepo())
	assert.Nil(t, got, "FF off must return nil so the launcher omits the new dynamic-workflow input")
}

// Happy path: credential is allowed.
func TestResolveWorkflowAccess_FFOn_Allowed(t *testing.T) {
	h, user := newResolveTestHandler(t, resolveTestOpts{ffOn: true, hasAccess: true})

	got := h.resolveWorkflowAccess(context.Background(), user, newOwnerRepo())
	require.NotNil(t, got)
	assert.True(t, *got)
}

// Denied path: credential lacks workflows:write.
func TestResolveWorkflowAccess_FFOn_Denied(t *testing.T) {
	h, user := newResolveTestHandler(t, resolveTestOpts{ffOn: true, hasAccess: false})

	got := h.resolveWorkflowAccess(context.Background(), user, newOwnerRepo())
	require.NotNil(t, got)
	assert.False(t, *got)
}

// Fail-closed contract: a Twirp error returns &false rather than nil so
// the launcher drops workflows:write rather than silently falling back to
// the legacy permissions.
func TestResolveWorkflowAccess_FFOn_TwirpError_FailsClosed(t *testing.T) {
	h, user := newResolveTestHandler(t, resolveTestOpts{ffOn: true, twirpErr: errors.New("twirp unavailable")})

	got := h.resolveWorkflowAccess(context.Background(), user, newOwnerRepo())
	require.NotNil(t, got, "must not return nil on error — that would silently use legacy permissions")
	assert.False(t, *got, "fail-closed: drop workflows:write rather than risk over-scoping")
}

// Privileged apps (platform-trusted carve-out) short-circuit to &true
// without invoking Twirp. Mirrors the requiredAccessActionsPrivileged
// carve-out in verifyTokenAccess.
func TestResolveWorkflowAccess_FFOn_PrivilegedApp_ShortCircuits(t *testing.T) {
	h, user := newResolveTestHandler(t, resolveTestOpts{ffOn: true, privileged: true, twirpForbidden: true})

	got := h.resolveWorkflowAccess(context.Background(), user, newOwnerRepo())
	require.NotNil(t, got)
	assert.True(t, *got, "privileged apps must short-circuit to allowed without calling Twirp")
}

// Privileged-app checker errors must fail closed (the user-to-server
// token is treated as denied rather than over-granting workflows:write).
func TestResolveWorkflowAccess_FFOn_PrivilegedCheckError_FailsClosed(t *testing.T) {
	h, user := newResolveTestHandler(t, resolveTestOpts{ffOn: true, privilegedErr: errors.New("checker down"), twirpForbidden: true})

	got := h.resolveWorkflowAccess(context.Background(), user, newOwnerRepo())
	require.NotNil(t, got)
	assert.False(t, *got, "checker failure must fail closed — denied")
}

// For credential types other than UserToServerToken (e.g. PATs), the
// privileged-app capability check is skipped and Twirp is invoked
// directly. If we incorrectly invoked the privileged checker for a PAT,
// MockHasCapabilityError would surface.
func TestResolveWorkflowAccess_FFOn_NonS2SToken_SkipsPrivilegedCheck(t *testing.T) {
	h, user := newResolveTestHandler(t, resolveTestOpts{
		ffOn:          true,
		tokenType:     authd.CredentialTypeFineGrainedPersonalAccessToken,
		privilegedErr: errors.New("must not be called for non-S2S tokens"),
		hasAccess:     true,
	})

	got := h.resolveWorkflowAccess(context.Background(), user, newOwnerRepo())
	require.NotNil(t, got)
	assert.True(t, *got)
}
