package jobs

import (
	"testing"

	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/stretchr/testify/require"
)

func TestEventJob_QueueName(t *testing.T) {
	tests := []struct {
		name     string
		trigger  string
		topic    string
		expected string
	}{
		{
			name:     "trigger field routes to trigger queue",
			trigger:  "workflow_run_failed",
			topic:    topics.WorkflowRunExecution,
			expected: EventJobTriggerQueueName,
		},
		{
			name:     "issue_created trigger routes to trigger queue",
			trigger:  "issue_created",
			topic:    topics.IssueCreateTemplate,
			expected: EventJobTriggerQueueName,
		},
		{
			name:     "trigger field takes precedence over topic",
			trigger:  "some_trigger",
			topic:    topics.PullRequestClose,
			expected: EventJobTriggerQueueName,
		},
		{
			name:     "IssueCreateTemplate topic routes to trigger queue",
			topic:    topics.IssueCreateTemplate,
			expected: EventJobTriggerQueueName,
		},
		{
			name:     "PullRequestClose routes to background queue",
			topic:    topics.PullRequestClose,
			expected: EventJobBackgroundQueueName,
		},
		{
			name:     "PullRequestMerge routes to background queue",
			topic:    topics.PullRequestMerge,
			expected: EventJobBackgroundQueueName,
		},
		{
			name:     "WorkflowRunExecution without trigger routes to default queue",
			topic:    topics.WorkflowRunExecution,
			expected: EventJobQueueName,
		},
		{
			name:     "default topic routes to default queue",
			topic:    topics.PullRequestReviewSubmit,
			expected: EventJobQueueName,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			job := EventJob{Trigger: tc.trigger, Topic: tc.topic}
			require.Equal(t, tc.expected, job.QueueName())
		})
	}
}
