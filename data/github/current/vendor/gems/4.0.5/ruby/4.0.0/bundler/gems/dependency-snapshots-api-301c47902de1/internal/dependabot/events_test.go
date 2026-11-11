package dependabot_test

import (
	"testing"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/stretchr/testify/assert"
)

func TestDependabotEvent_EvaluateReadiness(t *testing.T) {
	tests := []struct {
		name           string
		event          *interfaces.DependabotEvent
		expectedReady  bool
		expectedReason interfaces.ReadinessReason
	}{
		{
			name:           "no requested snapshots",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 0, Received: 0, Expired: 0}},
			expectedReady:  true,
			expectedReason: interfaces.ReadinessReasonSnapshotComplete,
		},
		{
			name:           "all received",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 2, Received: 2, Expired: 0}},
			expectedReady:  true,
			expectedReason: interfaces.ReadinessReasonSnapshotComplete,
		},
		{
			name:           "all expired",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 2, Received: 0, Expired: 2}},
			expectedReady:  true,
			expectedReason: interfaces.ReadinessReasonDeadlinePastNoSnapshot,
		},
		{
			name:           "mixed received and expired",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 2, Received: 1, Expired: 1}},
			expectedReady:  true,
			expectedReason: interfaces.ReadinessReasonDeadlinePastPartialSnapshot,
		},
		{
			name:           "one received one pending",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 2, Received: 1, Expired: 0}},
			expectedReady:  false,
			expectedReason: interfaces.ReadinessReasonPending,
		},
		{
			name:           "mixed with one still pending",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 3, Received: 1, Expired: 1}},
			expectedReady:  false,
			expectedReason: interfaces.ReadinessReasonPending,
		},
		{
			name:           "single received",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 1, Received: 1, Expired: 0}},
			expectedReady:  true,
			expectedReason: interfaces.ReadinessReasonSnapshotComplete,
		},
		{
			name:           "single pending",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 1, Received: 0, Expired: 0}},
			expectedReady:  false,
			expectedReason: interfaces.ReadinessReasonPending,
		},
		{
			name:           "all expired with some received",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 2, Received: 1, Expired: 1}},
			expectedReady:  true,
			expectedReason: interfaces.ReadinessReasonDeadlinePastPartialSnapshot,
		},
		{
			name:           "single expired",
			event:          &interfaces.DependabotEvent{ID: 1, EventType: interfaces.EventTypePush, Readiness: interfaces.EventReadinessCounts{Total: 1, Received: 0, Expired: 1}},
			expectedReady:  true,
			expectedReason: interfaces.ReadinessReasonDeadlinePastNoSnapshot,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			result := tt.event.EvaluateReadiness()
			assert.Equal(t, tt.expectedReady, result.Ready, "unexpected readiness")
			assert.Equal(t, tt.expectedReason, result.Reason, "unexpected reason")
			assert.Equal(t, tt.event.Readiness.Total, result.Requested, "unexpected requested")
		})
	}
}

func TestDependabotEvent_EvaluateReadiness_Counters(t *testing.T) {
	event := &interfaces.DependabotEvent{
		ID:        1,
		EventType: interfaces.EventTypePush,
		Readiness: interfaces.EventReadinessCounts{
			Total:    3,
			Received: 1,
			Expired:  2,
		},
	}

	result := event.EvaluateReadiness()

	assert.True(t, result.Ready)
	assert.Equal(t, interfaces.ReadinessReasonDeadlinePastPartialSnapshot, result.Reason)
	assert.Equal(t, 3, result.Requested)
	assert.Equal(t, 1, result.Received)
	assert.Equal(t, 2, result.Expired)
	assert.Equal(t, 0, result.Pending)
}
