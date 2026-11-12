package telemetry

import (
	"context"
	"testing"

	"github.com/github/feature-management-client-go/vexi/v2"
	"github.com/stretchr/testify/assert"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

// mockFeatureFlagClient is a simple mock for testing
type mockFeatureFlagClient struct {
	enabledFlags map[string]map[int64]bool // flag name -> user ID -> enabled
}

func newMockFeatureFlagClient() *mockFeatureFlagClient {
	return &mockFeatureFlagClient{
		enabledFlags: make(map[string]map[int64]bool),
	}
}

func (m *mockFeatureFlagClient) setFlagForUser(flag string, userID int64, enabled bool) {
	if m.enabledFlags[flag] == nil {
		m.enabledFlags[flag] = make(map[int64]bool)
	}
	m.enabledFlags[flag][userID] = enabled
}

func (m *mockFeatureFlagClient) IsEnabledForUser(ctx context.Context, flag string, userID int64) bool {
	if userFlags, exists := m.enabledFlags[flag]; exists {
		return userFlags[userID]
	}
	return false
}

// Unused methods required by interface - minimal implementations
func (m *mockFeatureFlagClient) IsEnabled(ctx context.Context, flag string, actors ...vexi.Actor) bool {
	return false
}
func (m *mockFeatureFlagClient) IsEnabledForRepo(ctx context.Context, flag string, repoID int64) bool {
	return false
}
func (m *mockFeatureFlagClient) IsEnabledForUserOrRepo(ctx context.Context, flag string, userID, repoID int64) bool {
	return false
}
func (m *mockFeatureFlagClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, flag string, actors sweagentd.RepositoryWithActor) bool {
	return false
}
func (m *mockFeatureFlagClient) IsEnabledForGitHubApp(ctx context.Context, flag string, appID int64) bool {
	return false
}
func (m *mockFeatureFlagClient) IsEnabledForOAuthApp(ctx context.Context, flag string, appID int64) bool {
	return false
}

// TestIsRestrictedTelemetryAllowed tests the core SKU validation logic
func TestIsRestrictedTelemetryAllowed(t *testing.T) {
	tests := []struct {
		name string
		plan copilotUsersTwirp.CopilotPlan
		want bool
	}{
		{
			name: "Individual plan allowed",
			plan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			want: true,
		},
		{
			name: "Pro plan allowed",
			plan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
			want: true,
		},
		{
			name: "Business plan blocked",
			plan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			want: false,
		},
		{
			name: "Enterprise plan blocked",
			plan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
			want: false,
		},
		{
			name: "Invalid plan blocked (conservative default)",
			plan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INVALID,
			want: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isRestrictedTelemetryAllowed(tt.plan)
			assert.Equal(t, tt.want, got)
		})
	}
}

func newMockUserDetailsAPI(plan copilotUsersTwirp.CopilotPlan) copilotUsersTwirp.CopilotUserDetailAPI {
	client := githubtwirp.NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: plan,
			},
		}, nil
	}

	return client.UserDetailAPI()
}

// TestShouldPublishRestrictedTelemetry_EdgeCases tests the new feature flag logic
func TestShouldPublishRestrictedTelemetry_EdgeCases(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("user with allowed plan should be allowed", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		job := &jobs.Job{
			ActorID: 123,
		}
		twirp := newMockUserDetailsAPI(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.True(t, result, "Users with individual plan should be allowed")
	})

	t.Run("user with restricted plan but feature flag enabled should be allowed", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		ffClient.setFlagForUser("coding_agent_force_restricted_telemetry", 123, true)
		job := &jobs.Job{
			ActorID: 123,
		}
		twirp := newMockUserDetailsAPI(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.True(t, result, "Users with restricted plan but feature flag enabled should be allowed")
	})

	t.Run("user with restricted plan and no feature flag should be blocked", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		job := &jobs.Job{
			ActorID: 123,
		}
		twirp := newMockUserDetailsAPI(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.False(t, result, "Users with restricted plan and no feature flag should be blocked")
	})

	t.Run("user with pro plan should be allowed regardless of feature flag", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		// Don't set feature flag
		job := &jobs.Job{
			ActorID: 123,
		}
		twirp := newMockUserDetailsAPI(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.True(t, result, "Users with pro plan should be allowed regardless of feature flag")
	})
}

// TestCommandTelemetryConversion tests the command telemetry conversion functions
func TestCommandTelemetryConversion(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	cmd := &command.Command{
		ID:           "test-command-id",
		JobID:        "test-job-id",
		AssignmentID: "test-assignment-id",
		RepoID:       12345,
		OwnerID:      67890,
		SessionID:    "test-session-id",
		ExternalID:   "external-123",
		ActorID:      123,
		Type:         command.TypeUserMessage,
		Content:      "test command content",
		Status:       command.StatusPending,
		CreatedAt:    1640995200, // 2022-01-01 00:00:00 UTC
		DeliveredAt:  1640995260, // 2022-01-01 00:01:00 UTC
	}

	t.Run("ToCommand converts command correctly", func(t *testing.T) {
		result := ToCommand(cmd)

		assert.Equal(t, cmd.ID, result.Id)
		assert.Equal(t, cmd.JobID, result.JobId)
		assert.Equal(t, cmd.AssignmentID, result.AssignmentId)
		assert.Equal(t, cmd.RepoID, result.RepositoryId)
		assert.Equal(t, cmd.OwnerID, result.OwnerId)
		assert.Equal(t, cmd.SessionID, result.SessionId)
		assert.Equal(t, cmd.ExternalID, *result.ExternalId)
		assert.Equal(t, cmd.ActorID, result.ActorId)
		assert.Equal(t, "user_message", result.Type)
		assert.Equal(t, "pending", result.Status)
		assert.NotNil(t, result.CreatedAt)
	})

	t.Run("ToCommandCreated converts correctly", func(t *testing.T) {
		result := ToCommandCreated(cmd)

		assert.NotNil(t, result.Command)
		assert.Equal(t, cmd.ID, result.Command.Id)
	})

	t.Run("ToRestrictedCommandCreated converts correctly", func(t *testing.T) {
		result := ToRestrictedCommandCreated(cmd)

		assert.NotNil(t, result.Command)
		assert.Equal(t, cmd.ID, result.Command.Id)
		assert.Equal(t, cmd.Content, result.Content)
	})

	t.Run("ToCommandUpdated converts correctly", func(t *testing.T) {
		result := ToCommandUpdated(cmd)

		assert.NotNil(t, result.Command)
		assert.Equal(t, cmd.ID, result.Command.Id)
		assert.NotNil(t, result.UpdatedAt)
	})

	t.Run("PublishCommandCreatedTelemetry doesn't crash", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		twirp := newMockUserDetailsAPI(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL)
		publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

		// Should not panic, even though it doesn't actually publish
		publisher.PublishCommandCreatedTelemetry(ctx, cmd)
	})

	t.Run("PublishCommandUpdatedTelemetry doesn't crash", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		twirp := newMockUserDetailsAPI(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL)
		publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

		// Should not panic, even though it doesn't actually publish
		publisher.PublishCommandUpdatedTelemetry(ctx, cmd)
	})
}
