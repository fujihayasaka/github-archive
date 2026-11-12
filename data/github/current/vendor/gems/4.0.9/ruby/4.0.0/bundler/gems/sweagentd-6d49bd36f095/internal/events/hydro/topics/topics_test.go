package topics

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestServiceAndWorkerTopicsAreDisjoint(t *testing.T) {
	// WorkflowRunExecution intentionally appears in both Service and Worker:
	// Service handles agent run completions, Worker handles trigger evaluation.
	// PullRequestMerge intentionally appears in both: Service handles job
	// cancellation when a PR is merged, Worker fires pull_request.merged
	// automation triggers. See the Worker topic list comment for details.
	allowedOverlap := map[string]bool{
		WorkflowRunExecution: true,
		PullRequestMerge:     true,
	}

	serviceTopics := make(map[string]struct{}, len(Service))
	for _, topic := range Service {
		serviceTopics[topic] = struct{}{}
	}

	for _, topic := range Worker {
		if allowedOverlap[topic] {
			continue
		}
		_, exists := serviceTopics[topic]
		require.False(t, exists, "topic %q should not be registered for both Service and Worker", topic)
	}
}

func TestTopicsAreAssigned(t *testing.T) {
	// All is deduplicated, so WorkflowRunExecution appears once even though
	// it's in both Service and Worker.
	expectedTopics := []string{
		WorkflowRunExecution,
		PullRequestTimelineCommentCreate,
		PullRequestReviewSubmit,
		PullRequestClose,
		PullRequestMerge,
		CodeScanningAlertAssignment,
		IssueCreateTemplate,
		PullRequestMergeConflict,
		PullRequestCreate,
		AutomationRunRequested,
		PullRequestSynchronize,
	}

	require.ElementsMatch(t, expectedTopics, All)
}
