package launcher

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/runnerlabels"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestActionsLauncher_ThirdPartyAgentDynamicWorkflow(t *testing.T) {
	copilotAppID := int64(100)
	copilotBotID := int64(101)
	claudeAppID := int64(200)
	claudeBotID := int64(201)

	copilot := agenticapp.NewCopilot(
		copilotAppID,
		"github-copilot",
		copilotBotID,
		"github-copilot-bot",
		"commit-login",
		"commit@email.com",
	)

	claudeApp := agenticapptest.NewTestAppWithDetails(claudeAppID, claudeBotID, "Claude", "claude")
	provider := agenticapp.NewProvider(copilot, claudeApp)

	newMockTwirp := func() *githubtwirp.NoopClient {
		mockTwirp := githubtwirp.NewNoopClient()
		mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
					HasPaidAccess: true,
				},
			}, nil
		}
		mockTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
			return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
				McpConfigurationJson: "{}",
				IsMcpEnabled:         false,
			}, nil
		}
		return mockTwirp
	}

	newLaunchOpts := func(agent sweagentd.AgenticApp) *LaunchAgentOpts {
		return &LaunchAgentOpts{
			JobID:             "test-job-123",
			SessionID:         "test-session-456",
			ActorLogin:        "test-actor",
			ActorID:           12345,
			GitHubToken:       "test-token",
			GitHubRepo:        "test-owner/test-repo",
			GitHubRepoOwner:   "test-owner",
			GitHubRepoName:    "test-repo",
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			BranchName:        "main",
			Agent:             agent,
		}
	}

	newLauncher := func(ffClient featureflags.Client, noopClient *github.NoopClient) *ActionsLauncher {
		clientFactory := &github.NoopClientFactory{
			GitHubAppLogin: "copilot-swe-agent",
			GitHubBotLogin: "copilot-swe-agent[bot]",
			MockNewClient: func(token string) github.ClientInterface {
				return noopClient
			},
		}
		return &ActionsLauncher{
			obsv:                observability.NewNoopExporters(),
			ffClient:            ffClient,
			githubClientFactory: clientFactory,
			ghTwirp:             newMockTwirp(),
			spokes:              spokestest.NewClient(t),
			appProvider:         provider,
			opts: ActionsLauncherOpts{
				ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL:     "https://api.githubcopilot.com",
					AgentCallbackURL:  "https://api.githubcopilot.com/agents/swe/agent",
					UploadsURL:        "https://uploads.github.com/user-attachments/assets",
					DownloadsURL:      "https://downloads.github.com",
					SecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
					Environment:       "production",
					AgentTimeoutMin:   60,
				},
			},
		}
	}

	findCreateDynamicWorkflowRunCall := func(t *testing.T, noopClient *github.NoopClient) *github.NewDynamicWorkflowRun {
		t.Helper()
		for _, call := range noopClient.MethodCalls {
			if call.Method == "CreateDynamicWorkflowRun" {
				return call.Args[4].(*github.NewDynamicWorkflowRun)
			}
		}
		t.Fatal("CreateDynamicWorkflowRun was not called")
		return nil
	}

	t.Run("third-party agent uses Copilot credentials and passes ActorID", func(t *testing.T) {
		ctx := context.Background()
		ffClient := featureflags.NewNoopClient(nil)

		noopClient := &github.NoopClient{
			GithubAppLogin: "copilot-swe-agent",
			GithubBotLogin: "copilot-swe-agent[bot]",
		}
		launcher := newLauncher(ffClient, noopClient)
		opts := newLaunchOpts(claudeApp)

		_, err := launcher.LaunchAgent(ctx, opts)
		require.NoError(t, err)

		workflowOpts := findCreateDynamicWorkflowRunCall(t, noopClient)
		require.NotNil(t, workflowOpts.ActorID, "ActorID should be set for third-party agent")
		assert.Equal(t, claudeBotID, *workflowOpts.ActorID, "ActorID should be the 3P agent's bot ID")
	})

	t.Run("third-party agent passes ActorID with empty feature flag client", func(t *testing.T) {
		ctx := context.Background()
		ffClient := featureflags.NewNoopClient(nil)

		noopClient := &github.NoopClient{
			GithubAppLogin: "copilot-swe-agent",
			GithubBotLogin: "copilot-swe-agent[bot]",
		}
		launcher := newLauncher(ffClient, noopClient)
		opts := newLaunchOpts(claudeApp)

		_, err := launcher.LaunchAgent(ctx, opts)
		require.NoError(t, err)

		workflowOpts := findCreateDynamicWorkflowRunCall(t, noopClient)
		require.NotNil(t, workflowOpts.ActorID, "ActorID should be set for third-party agent")
		assert.Equal(t, claudeBotID, *workflowOpts.ActorID, "ActorID should be the 3P agent's bot ID")
	})

	t.Run("copilot agent does not pass ActorID", func(t *testing.T) {
		ctx := context.Background()
		ffClient := featureflags.NewNoopClient(nil)

		noopClient := &github.NoopClient{
			GithubAppLogin: "copilot-swe-agent",
			GithubBotLogin: "copilot-swe-agent[bot]",
		}
		launcher := newLauncher(ffClient, noopClient)
		opts := newLaunchOpts(copilot)

		_, err := launcher.LaunchAgent(ctx, opts)
		require.NoError(t, err)

		workflowOpts := findCreateDynamicWorkflowRunCall(t, noopClient)
		assert.Nil(t, workflowOpts.ActorID, "ActorID should be nil for Copilot agent")
	})
}
