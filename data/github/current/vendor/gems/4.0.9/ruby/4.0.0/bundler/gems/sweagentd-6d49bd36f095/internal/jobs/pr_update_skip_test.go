package jobs

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/stretchr/testify/require"
)

func TestShouldSkipMidSessionPRUpdate(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name     string
		flags    map[string]bool
		job      *Job
		expected bool
	}{
		{
			name:     "nil job returns false",
			flags:    map[string]bool{},
			job:      nil,
			expected: false,
		},
		{
			name:  "skips for non-agent-authored pull request comment",
			flags: map[string]bool{},
			job: &Job{
				EventType: EventTypePullRequestCommentNonCopilotPullRequest,
			},
			expected: true,
		},
		{
			name:  "skips for non-agent-authored pull request review",
			flags: map[string]bool{},
			job: &Job{
				EventType: EventTypePullRequestReviewNonCopilotPullRequest,
			},
			expected: true,
		},
		{
			name:  "skips for fix-pr-comment action with subsequent-jobs flag enabled",
			flags: map[string]bool{featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs: true},
			job: &Job{
				Action:    AgentActionFixPRComment,
				EventType: EventTypeAPICallReceived,
			},
			expected: true,
		},
		{
			name:  "does not skip for fix action even with subsequent-jobs flag enabled",
			flags: map[string]bool{featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs: true},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypeAPICallReceived,
			},
			expected: false,
		},
		{
			name:  "does not skip for fix-pr-comment when subsequent-jobs flag disabled",
			flags: map[string]bool{},
			job: &Job{
				Action:    AgentActionFixPRComment,
				EventType: EventTypeAPICallReceived,
			},
			expected: false,
		},
		{
			name: "skips for fix_failed_workflow with skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: true,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypeFixFailedWorkflow,
			},
			expected: true,
		},
		{
			name: "does not skip for fix_failed_workflow when skip flag disabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: false,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypeFixFailedWorkflow,
			},
			expected: false,
		},
		{
			name: "skips for code_review_fix_with_copilot with skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs: true,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypeCodeReviewFixWithCopilot,
			},
			expected: true,
		},
		{
			name: "does not skip for code_review_fix_with_copilot when skip flag disabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs: false,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypeCodeReviewFixWithCopilot,
			},
			expected: false,
		},
		{
			name: "does not skip for code_review_fix_with_copilot with only failed-workflow skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: true,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypeCodeReviewFixWithCopilot,
			},
			expected: false,
		},
		{
			name: "skips for pull_request_opened with pull request trigger skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs: true,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypePullRequestOpened,
			},
			expected: true,
		},
		{
			name: "skips for pull_request_synchronize with pull request trigger skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs: true,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypePullRequestSynchronize,
			},
			expected: true,
		},
		{
			name: "does not skip for pull_request_opened when pull request trigger skip flag disabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs: false,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypePullRequestOpened,
			},
			expected: false,
		},
		{
			name: "does not skip for pull_request_opened with only failed-workflow skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: true,
			},
			job: &Job{
				Action:    AgentActionFix,
				EventType: EventTypePullRequestOpened,
			},
			expected: false,
		},
		{
			name:  "does not skip for ordinary task with no flags",
			flags: map[string]bool{},
			job: &Job{
				Action:    AgentActionTask,
				EventType: EventTypeAPICallReceived,
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ff := featureflags.NewNoopClient(tt.flags)
			require.Equal(t, tt.expected, ShouldSkipMidSessionPRUpdate(ctx, ff, tt.job))
		})
	}

	t.Run("nil ff client does not panic and returns false for fix_failed_workflow", func(t *testing.T) {
		require.False(t, ShouldSkipMidSessionPRUpdate(ctx, nil, &Job{EventType: EventTypeFixFailedWorkflow}))
	})
}

func TestShouldSkipPostSessionPRUpdate(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name     string
		flags    map[string]bool
		job      *Job
		expected bool
	}{
		{
			name:     "nil job returns false",
			flags:    map[string]bool{},
			job:      nil,
			expected: false,
		},
		{
			name: "skips for fix_failed_workflow with skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: true,
			},
			job:      &Job{EventType: EventTypeFixFailedWorkflow},
			expected: true,
		},
		{
			name: "does not skip for fix_failed_workflow when skip flag disabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: false,
			},
			job:      &Job{EventType: EventTypeFixFailedWorkflow},
			expected: false,
		},
		{
			name: "skips for code_review_fix_with_copilot with skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs: true,
			},
			job:      &Job{EventType: EventTypeCodeReviewFixWithCopilot},
			expected: true,
		},
		{
			name: "does not skip for code_review_fix_with_copilot when skip flag disabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForCodeReviewFixJobs: false,
			},
			job:      &Job{EventType: EventTypeCodeReviewFixWithCopilot},
			expected: false,
		},
		{
			name: "does not skip for code_review_fix_with_copilot with only failed-workflow skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: true,
			},
			job:      &Job{EventType: EventTypeCodeReviewFixWithCopilot},
			expected: false,
		},
		{
			name: "skips for pull_request_opened with pull request trigger skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs: true,
			},
			job:      &Job{EventType: EventTypePullRequestOpened},
			expected: true,
		},
		{
			name: "skips for pull_request_synchronize with pull request trigger skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs: true,
			},
			job:      &Job{EventType: EventTypePullRequestSynchronize},
			expected: true,
		},
		{
			name: "does not skip for pull_request_opened when pull request trigger skip flag disabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForPullRequestTriggerJobs: false,
			},
			job:      &Job{EventType: EventTypePullRequestOpened},
			expected: false,
		},
		{
			name: "does not skip for pull_request_opened with only failed-workflow skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: true,
			},
			job:      &Job{EventType: EventTypePullRequestOpened},
			expected: false,
		},
		{
			name: "does not skip for non-workflow event even with skip flag enabled",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRUpdatesForFixFailedWorkflowJobs: true,
			},
			job:      &Job{EventType: EventTypePullRequestComment},
			expected: false,
		},
		{
			name: "does not skip for fix-pr-comment action (mid-session-only signal)",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentSkipPRBodyUpdateForSubsequentJobs: true,
			},
			job: &Job{
				Action:    AgentActionFixPRComment,
				EventType: EventTypeAPICallReceived,
			},
			expected: false,
		},
		{
			name:  "does not skip for non-agent-authored PR event (mid-session-only signal)",
			flags: map[string]bool{},
			job: &Job{
				EventType: EventTypePullRequestCommentNonCopilotPullRequest,
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ff := featureflags.NewNoopClient(tt.flags)
			require.Equal(t, tt.expected, ShouldSkipPostSessionPRUpdate(ctx, ff, tt.job))
		})
	}

	t.Run("nil ff client does not panic and returns false for fix_failed_workflow", func(t *testing.T) {
		require.False(t, ShouldSkipPostSessionPRUpdate(ctx, nil, &Job{EventType: EventTypeFixFailedWorkflow}))
	})
}
