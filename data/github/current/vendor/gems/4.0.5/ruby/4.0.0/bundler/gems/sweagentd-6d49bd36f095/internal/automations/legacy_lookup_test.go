package automations

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestLegacyLookupWorkflowRunFailedRequiresFailureConclusion(t *testing.T) {
	lookup := &LegacyLookup{}
	event := EventMatchRequest{
		OwnerID:            1,
		RepoID:             2,
		EventName:          EventWorkflowRun,
		ActivityType:       ActivityWorkflowRunFailed,
		WorkflowConclusion: WorkflowConclusion("success"),
	}

	hasActive, err := lookup.HasActiveForEvent(context.Background(), event)
	require.NoError(t, err)
	require.False(t, hasActive)

	configs, err := lookup.ListForEvent(context.Background(), ListForEventRequest{Event: event})
	require.NoError(t, err)
	require.Empty(t, configs)
}
