package telemetry

import (
	"context"
	"testing"

	"github.com/github/feature-management-client-go/vexi/v2"
	copilotEntitiesv2 "github.com/github/hydro-schemas-go/hydro/schemas/github/copilot/v2/entities"
	sweagentEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0/entities"
	"github.com/stretchr/testify/assert"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/featureflags"
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
func (m *mockFeatureFlagClient) IsEnabledForOrganization(ctx context.Context, flag string, orgID int64) bool {
	return false
}
func (m *mockFeatureFlagClient) IsEnabledForOwner(ctx context.Context, flag string, ownerID int64) bool {
	return false
}
func (m *mockFeatureFlagClient) IsEnabledForRepoOrOwner(ctx context.Context, flag string, actors sweagentd.Repository) bool {
	return false
}
func (m *mockFeatureFlagClient) IsEnabledForRepoOrOwnerWithDefaultValue(_ context.Context, _ string, defaultValue bool, _ sweagentd.Repository) bool {
	return defaultValue
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

func (m *mockFeatureFlagClient) setFlagForUser(flag string, userID int64, enabled bool) {
	if m.enabledFlags[flag] == nil {
		m.enabledFlags[flag] = make(map[int64]bool)
	}
	m.enabledFlags[flag][userID] = enabled
}

func newMockTwirpClient(plan copilotUsersTwirp.CopilotPlan) githubtwirp.ClientInterface {
	client := githubtwirp.NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: plan,
			},
		}, nil
	}

	return client
}

func newMockTwirpClientWithAccessType(plan copilotUsersTwirp.CopilotPlan, accessType copilotUsersTwirp.AccessType) githubtwirp.ClientInterface {
	client := githubtwirp.NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:       plan,
				CopilotAccessType: accessType,
			},
		}, nil
	}

	return client
}

func newMockTwirpClientWithTelemetryConfig(plan copilotUsersTwirp.CopilotPlan, telemetryConfig copilotUsersTwirp.Telemetry) githubtwirp.ClientInterface {
	client := githubtwirp.NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:            plan,
				TelemetryConfiguration: telemetryConfig,
			},
		}, nil
	}

	return client
}

func newMockTwirpClientWithError() githubtwirp.ClientInterface {
	client := githubtwirp.NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return nil, assert.AnError
	}

	return client
}

// TestShouldPublishRestrictedTelemetry_EdgeCases tests the ShouldPublishRestrictedTelemetry logic
func TestShouldPublishRestrictedTelemetry_EdgeCases(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("telemetry_configuration ENABLED allows individual plan", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		job := &jobs.Job{ActorID: 123}
		twirp := newMockTwirpClientWithTelemetryConfig(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL, copilotUsersTwirp.Telemetry_TELEMETRY_ENABLED)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.True(t, result, "TELEMETRY_ENABLED should allow restricted telemetry")
	})

	t.Run("telemetry_configuration ENABLED allows even business plan", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		job := &jobs.Job{ActorID: 123}
		twirp := newMockTwirpClientWithTelemetryConfig(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, copilotUsersTwirp.Telemetry_TELEMETRY_ENABLED)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.True(t, result, "TELEMETRY_ENABLED should allow restricted telemetry even for business plan")
	})

	t.Run("telemetry_configuration DISABLED blocks even individual plan", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		job := &jobs.Job{ActorID: 123}
		twirp := newMockTwirpClientWithTelemetryConfig(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL, copilotUsersTwirp.Telemetry_TELEMETRY_DISABLED)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.False(t, result, "TELEMETRY_DISABLED should block restricted telemetry even for individual plan")
	})

	t.Run("telemetry_configuration INVALID is blocked (safe default)", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		job := &jobs.Job{ActorID: 123}
		twirp := newMockTwirpClientWithTelemetryConfig(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL, copilotUsersTwirp.Telemetry_TELEMETRY_INVALID)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.False(t, result, "TELEMETRY_INVALID should be blocked as a safe default")
	})

	t.Run("feature flag overrides TELEMETRY_DISABLED", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		ffClient.setFlagForUser(featureflags.CodingAgentForceRestrictedTelemetry, 123, true)
		job := &jobs.Job{ActorID: 123}
		twirp := newMockTwirpClientWithTelemetryConfig(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL, copilotUsersTwirp.Telemetry_TELEMETRY_DISABLED)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.True(t, result, "Feature flag should override TELEMETRY_DISABLED")
	})

	t.Run("feature flag overrides TELEMETRY_INVALID", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		ffClient.setFlagForUser(featureflags.CodingAgentForceRestrictedTelemetry, 123, true)
		job := &jobs.Job{ActorID: 123}
		twirp := newMockTwirpClientWithTelemetryConfig(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, copilotUsersTwirp.Telemetry_TELEMETRY_INVALID)
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.True(t, result, "Feature flag should override TELEMETRY_INVALID")
	})

	t.Run("user details unavailable is blocked (safe default)", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		job := &jobs.Job{ActorID: 123}
		twirp := newMockTwirpClientWithError()
		result := NewTelemetryPublisher(obsv, twirp, ffClient).ShouldPublishRestrictedTelemetry(ctx, job.ActorID)
		assert.False(t, result, "Should be blocked when user details cannot be fetched")
	})
}

// TestAddCopilotAccessTypeTag tests the core functionality of adding CopilotAccessType tags
func TestAddCopilotAccessTypeTag(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := newMockFeatureFlagClient()

	tests := []struct {
		name         string
		actorID      int64
		accessType   copilotUsersTwirp.AccessType
		expectedTag  string
		shouldAddTag bool
	}{
		{
			name:         "Individual monthly subscriber",
			actorID:      123,
			accessType:   copilotUsersTwirp.AccessType_ACCESS_TYPE_MONTHLY_SUBSCRIBER,
			expectedTag:  "ACCESS_TYPE_MONTHLY_SUBSCRIBER",
			shouldAddTag: true,
		},
		{
			name:         "Business seat",
			actorID:      456,
			accessType:   copilotUsersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT,
			expectedTag:  "ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT",
			shouldAddTag: true,
		},
		{
			name:         "Enterprise seat",
			actorID:      789,
			accessType:   copilotUsersTwirp.AccessType_ACCESS_TYPE_COPILOT_ENTERPRISE_SEAT,
			expectedTag:  "ACCESS_TYPE_COPILOT_ENTERPRISE_SEAT",
			shouldAddTag: true,
		},
		{
			name:         "Free OSS access",
			actorID:      101112,
			accessType:   copilotUsersTwirp.AccessType_ACCESS_TYPE_FREE_ENGAGED_OSS,
			expectedTag:  "ACCESS_TYPE_FREE_ENGAGED_OSS",
			shouldAddTag: true,
		},
		{
			name:         "Invalid access type",
			actorID:      131415,
			accessType:   copilotUsersTwirp.AccessType_ACCESS_TYPE_INVALID,
			expectedTag:  "ACCESS_TYPE_INVALID",
			shouldAddTag: true,
		},
		{
			name:         "Zero actor ID should not add tag",
			actorID:      0,
			accessType:   copilotUsersTwirp.AccessType_ACCESS_TYPE_MONTHLY_SUBSCRIBER,
			expectedTag:  "",
			shouldAddTag: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var twirp githubtwirp.ClientInterface
			if tt.actorID != 0 {
				twirp = newMockTwirpClientWithAccessType(
					copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
					tt.accessType,
				)
			} else {
				twirp = newMockTwirpClient(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL)
			}

			publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

			accessType := publisher.getCopilotAccessType(ctx, tt.actorID)

			if tt.shouldAddTag {
				assert.NotNil(t, accessType, "copilot access type should be returned")
				assert.Equal(t, *accessType, tt.accessType, "copilot access type should have correct value")
			} else {
				assert.Nil(t, accessType, "copilot access type should not be returned for zero actor ID")
			}
		})
	}
}

// TestShouldEmitCopilotAccessTypeStats tests the feature flag gating
func TestShouldEmitCopilotAccessTypeStats(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	tests := []struct {
		name           string
		actorID        int64
		featureFlagOn  bool
		expectedResult bool
	}{
		{
			name:           "Feature flag enabled should return true",
			actorID:        123,
			featureFlagOn:  true,
			expectedResult: true,
		},
		{
			name:           "Feature flag disabled should return false",
			actorID:        123,
			featureFlagOn:  false,
			expectedResult: false,
		},
		{
			name:           "Zero actor ID with feature flag on should return true",
			actorID:        0,
			featureFlagOn:  true,
			expectedResult: true,
		},
		{
			name:           "Zero actor ID with feature flag off should return false",
			actorID:        0,
			featureFlagOn:  false,
			expectedResult: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := newMockFeatureFlagClient()
			if tt.featureFlagOn {
				ffClient.setFlagForUser("sweagent_emit_copilot_access_type_stats", tt.actorID, true)
			}

			twirp := newMockTwirpClient(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL)
			publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

			result := publisher.shouldEmitCopilotAccessTypeStats(ctx, tt.actorID)
			assert.Equal(t, tt.expectedResult, result)
		})
	}
}

// TestTelemetryPublisherWithFeatureFlag tests the integration of feature flag with telemetry methods
func TestTelemetryPublisherWithFeatureFlag(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	// Create test job and command
	job := &jobs.Job{
		ID:      "test-job",
		ActorID: 123,
	}

	cmd := &command.Command{
		ID:      "test-command",
		ActorID: 123,
		Type:    command.TypeUserMessage,
		Status:  command.StatusPending,
	}

	t.Run("Methods work correctly when feature flag is enabled", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		ffClient.setFlagForUser("sweagent_emit_copilot_access_type_stats", 123, true)

		twirp := newMockTwirpClientWithAccessType(
			copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			copilotUsersTwirp.AccessType_ACCESS_TYPE_MONTHLY_SUBSCRIBER,
		)

		publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

		// These should not panic and should work correctly
		assert.NotPanics(t, func() {
			publisher.PublishJobStartedTelemetry(ctx, job)
		})

		assert.NotPanics(t, func() {
			publisher.PublishJobCompletedTelemetry(ctx, job)
		})

		assert.NotPanics(t, func() {
			publisher.PublishCommandCreatedTelemetry(ctx, cmd)
		})

		assert.NotPanics(t, func() {
			publisher.PublishCommandUpdatedTelemetry(ctx, cmd)
		})
	})

	t.Run("Methods work correctly when feature flag is disabled", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		// Don't enable the feature flag

		twirp := newMockTwirpClientWithAccessType(
			copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			copilotUsersTwirp.AccessType_ACCESS_TYPE_MONTHLY_SUBSCRIBER,
		)

		publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

		// These should still not panic and should work correctly (just without copilot access type)
		assert.NotPanics(t, func() {
			publisher.PublishJobStartedTelemetry(ctx, job)
		})

		assert.NotPanics(t, func() {
			publisher.PublishJobCompletedTelemetry(ctx, job)
		})

		assert.NotPanics(t, func() {
			publisher.PublishCommandCreatedTelemetry(ctx, cmd)
		})

		assert.NotPanics(t, func() {
			publisher.PublishCommandUpdatedTelemetry(ctx, cmd)
		})
	})
}

// TestErrorHandling tests error scenarios
func TestErrorHandling(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("API error should not add copilot access type tag", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		ffClient.setFlagForUser("sweagent_emit_copilot_access_type_stats", 123, true)

		twirp := newMockTwirpClientWithError()
		publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

		accessType := publisher.getCopilotAccessType(ctx, 123)

		assert.Nil(t, accessType, "copilot access type should be nil when API returns error")
	})

	t.Run("Nil UserDetails should not add copilot access type tag", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		ffClient.setFlagForUser("sweagent_emit_copilot_access_type_stats", 123, true)

		client := githubtwirp.NewNoopClient()
		client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: nil, // Nil user details
			}, nil
		}

		publisher := NewTelemetryPublisher(obsv, client, ffClient)

		accessType := publisher.getCopilotAccessType(ctx, 123)

		assert.Nil(t, accessType, "copilot access type should be nil when UserDetails is nil")
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
		twirp := newMockTwirpClient(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL)
		publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

		// Should not panic, even though it doesn't actually publish
		publisher.PublishCommandCreatedTelemetry(ctx, cmd)
	})

	t.Run("PublishCommandUpdatedTelemetry doesn't crash", func(t *testing.T) {
		ffClient := newMockFeatureFlagClient()
		twirp := newMockTwirpClient(copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL)
		publisher := NewTelemetryPublisher(obsv, twirp, ffClient)

		// Should not panic, even though it doesn't actually publish
		publisher.PublishCommandUpdatedTelemetry(ctx, cmd)
	})
}

func TestJobTelemetryConversion(t *testing.T) {
	t.Run("ToJob converts AgentID correctly for custom agent", func(t *testing.T) {
		job := &jobs.Job{
			AgentID: 123456,
			ID:      "test-job",
		}

		hydroJob := ToJob(job)

		assert.Equal(t, "123456", hydroJob.AgentId, "AgentID should be converted to string")
	})

	t.Run("ToJob converts AgentID correctly for default Copilot agent (zero value)", func(t *testing.T) {
		job := &jobs.Job{
			AgentID: 0,
			ID:      "test-job",
		}

		hydroJob := ToJob(job)

		assert.Equal(t, "0", hydroJob.AgentId, "Zero AgentID should be converted to '0'")
	})

	t.Run("ToJob includes model from job", func(t *testing.T) {
		job := &jobs.Job{
			ID:    "test-job",
			Model: "sweagent-capi:claude-sonnet-4.5",
		}

		hydroJob := ToJob(job)

		assert.Equal(t, "sweagent-capi:claude-sonnet-4.5", hydroJob.Model, "Model should be set from job")
	})

	t.Run("ToJob includes IsAutoMode from job", func(t *testing.T) {
		job := &jobs.Job{
			ID:         "test-job",
			Model:      "sweagent-capi:claude-sonnet-4.5",
			IsAutoMode: true,
		}

		hydroJob := ToJob(job)

		assert.Equal(t, true, hydroJob.IsAutoMode, "IsAutoMode should be set from job")
	})

	t.Run("ToJob includes compute fields and Actions workflow run ID", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "test-job",
			ComputeID: "12345",
			Launcher:  "actions",
		}

		hydroJob := ToJob(job)

		assert.Equal(t, "12345", hydroJob.ComputeId)
		assert.Equal(t, "actions", hydroJob.ComputeType)
		assert.Equal(t, "12345", hydroJob.WorkflowRunId)
	})

	t.Run("ToJob excludes workflow run ID for sandbox compute", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "test-job",
			ComputeID: "sb-abc-123",
			Launcher:  "sandbox",
		}

		hydroJob := ToJob(job)

		assert.Equal(t, "sb-abc-123", hydroJob.ComputeId)
		assert.Equal(t, "sandbox", hydroJob.ComputeType)
		assert.Empty(t, hydroJob.WorkflowRunId)
	})

	t.Run("ToJob includes error when present", func(t *testing.T) {
		job := &jobs.Job{
			ID: "test-job",
			Error: &jobs.JobError{
				Service:            "capi",
				ResponseStatusCode: "429",
				Message:            "Rate limited",
			},
		}

		hydroJob := ToJob(job)

		assert.NotNil(t, hydroJob.Error, "Error should be set")
		assert.Equal(t, "capi:429", hydroJob.Error.Code, "Error code should match summary")
		assert.Equal(t, "Rate limited", hydroJob.Error.Message, "Error message should match")
	})

	t.Run("ToJob excludes error when nil", func(t *testing.T) {
		job := &jobs.Job{
			ID:    "test-job",
			Error: nil,
		}

		hydroJob := ToJob(job)

		assert.Nil(t, hydroJob.Error, "Error should be nil")
	})

	t.Run("ToJobStarted includes AgentID in the event", func(t *testing.T) {
		job := &jobs.Job{
			AgentID: 789012,
			ID:      "test-job",
		}

		event := ToJobStarted(job)

		assert.Equal(t, "789012", event.Job.AgentId, "JobStarted event should include AgentID")
	})

	t.Run("ToJobCompleted includes AgentID in the event", func(t *testing.T) {
		job := &jobs.Job{
			AgentID:     345678,
			ID:          "test-job",
			CompletedAt: 1234567890,
			CreatedAt:   1234567800,
		}

		event := ToJobCompleted(job)

		assert.Equal(t, "345678", event.Job.AgentId, "JobCompleted event should include AgentID")
	})

	t.Run("ToJobCompleted includes terminal reason when job has error", func(t *testing.T) {
		job := &jobs.Job{
			AgentID:     345678,
			ID:          "test-job",
			CompletedAt: 1234567890,
			CreatedAt:   1234567800,
			Status:      jobs.JobStatusCancelled,
			Error: &jobs.JobError{
				Service:            "copilot",
				ResponseStatusCode: "cancelled",
				Message:            "Job was cancelled",
			},
		}

		event := ToJobCompleted(job)

		assert.Equal(t, "345678", event.Job.AgentId, "JobCompleted event should include AgentID")
		assert.NotNil(t, event.TerminalReason, "TerminalReason should be set")
		assert.Equal(t, "copilot:cancelled", *event.TerminalReason, "TerminalReason should match error summary")
	})

	t.Run("ToJobCompleted does not include terminal reason when no error", func(t *testing.T) {
		job := &jobs.Job{
			AgentID:     345678,
			ID:          "test-job",
			CompletedAt: 1234567890,
			CreatedAt:   1234567800,
			Status:      jobs.JobStatusCompleted,
		}

		event := ToJobCompleted(job)

		assert.Equal(t, "345678", event.Job.AgentId, "JobCompleted event should include AgentID")
		assert.Nil(t, event.TerminalReason, "TerminalReason should be nil when no error")
	})
}

func TestToJobError(t *testing.T) {
	tests := []struct {
		name     string
		input    *jobs.JobError
		expected *sweagentEntitiesv0.JobError
	}{
		{
			name:     "nil error returns nil",
			input:    nil,
			expected: nil,
		},
		{
			name: "error with service and status code",
			input: &jobs.JobError{
				Service:            "capi",
				ResponseStatusCode: "429",
				Message:            "Rate limited",
			},
			expected: &sweagentEntitiesv0.JobError{
				Code:    "capi:429",
				Message: "Rate limited",
			},
		},
		{
			name: "error with only service",
			input: &jobs.JobError{
				Service: "actions",
				Message: "Something failed",
			},
			expected: &sweagentEntitiesv0.JobError{
				Code:    "actions",
				Message: "Something failed",
			},
		},
		{
			name: "error with only status code",
			input: &jobs.JobError{
				ResponseStatusCode: "500",
				Message:            "Internal error",
			},
			expected: &sweagentEntitiesv0.JobError{
				Code:    "500",
				Message: "Internal error",
			},
		},
		{
			name: "error with only message",
			input: &jobs.JobError{
				Message: "Generic error",
			},
			expected: &sweagentEntitiesv0.JobError{
				Code:    "",
				Message: "Generic error",
			},
		},
		{
			name: "error with empty message",
			input: &jobs.JobError{
				Service:            "test",
				ResponseStatusCode: "400",
				Message:            "",
			},
			expected: &sweagentEntitiesv0.JobError{
				Code:    "test:400",
				Message: "",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ToJobError(tt.input)

			if tt.expected == nil {
				assert.Nil(t, result)
				return
			}

			assert.NotNil(t, result)
			assert.Equal(t, tt.expected.Code, result.Code)
			assert.Equal(t, tt.expected.Message, result.Message)
		})
	}
}

func TestToHydroCopilotPlan(t *testing.T) {
	tests := []struct {
		name     string
		input    copilotUsersTwirp.CopilotPlan
		expected copilotEntitiesv2.CopilotPlan
	}{
		{
			name:     "INDIVIDUAL maps to INDIVIDUAL",
			input:    copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			expected: copilotEntitiesv2.CopilotPlan_INDIVIDUAL,
		},
		{
			name:     "INDIVIDUAL_PRO maps to INDIVIDUAL_PRO_PLUS",
			input:    copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
			expected: copilotEntitiesv2.CopilotPlan_INDIVIDUAL_PRO_PLUS,
		},
		{
			name:     "BUSINESS maps to BUSINESS",
			input:    copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			expected: copilotEntitiesv2.CopilotPlan_BUSINESS,
		},
		{
			name:     "ENTERPRISE maps to ENTERPRISE",
			input:    copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
			expected: copilotEntitiesv2.CopilotPlan_ENTERPRISE,
		},
		{
			name:     "INVALID maps to INVALID",
			input:    copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INVALID,
			expected: copilotEntitiesv2.CopilotPlan_INVALID,
		},
		{
			name:     "unknown value maps to UNKNOWN",
			input:    copilotUsersTwirp.CopilotPlan(99),
			expected: copilotEntitiesv2.CopilotPlan_UNKNOWN,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := toHydroCopilotPlan(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}
