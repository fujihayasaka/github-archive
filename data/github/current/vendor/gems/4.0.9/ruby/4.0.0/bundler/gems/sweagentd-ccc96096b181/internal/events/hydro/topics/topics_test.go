package topics

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestServiceAndWorkerTopicsAreDisjoint(t *testing.T) {
	serviceTopics := make(map[string]struct{}, len(Service))
	for _, topic := range Service {
		serviceTopics[topic] = struct{}{}
	}

	for _, topic := range Worker {
		_, exists := serviceTopics[topic]
		require.False(t, exists, "topic %q should not be registered for both Service and Worker", topic)
	}
}

func TestTopicsAreAssigned(t *testing.T) {
	expectedTopics := []string{
		WorkflowRunExecution,
		PullRequestTimelineCommentCreate,
		PullRequestReviewSubmit,
		PullRequestReopen,
		PullRequestClose,
		PullRequestMerge,
		CodeScanningAlertAssignment,
		IssueCreateTemplate,
	}

	allTopics := append([]string{}, Service...)
	allTopics = append(allTopics, Worker...)

	require.ElementsMatch(t, expectedTopics, allTopics)
}

func TestPullRequestStateChangedTopics(t *testing.T) {
	for _, topic := range PullRequestStateChanged {
		require.Contains(t, Service, topic)
		require.NotContains(t, Worker, topic)
	}
}
