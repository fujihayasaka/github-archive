package store

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestTriggerKey(t *testing.T) {
	record := &IntervalTriggerRecord{
		AgentID:      "agent-abc-123",
		IntervalType: IntervalTypeDaily,
	}
	assert.Equal(t, "agent-abc-123:daily", record.TriggerKey())

	record.IntervalType = IntervalTypeWeekly
	assert.Equal(t, "agent-abc-123:weekly", record.TriggerKey())
}

func TestSetTimestamps(t *testing.T) {
	record := &IntervalTriggerRecord{}
	record.SetTimestamps()
	assert.NotZero(t, record.CreatedAt)
	// UpdatedAt (_ts) is managed by Cosmos server-side and should not be set.
	assert.Zero(t, record.UpdatedAt)

	// Second call should not overwrite CreatedAt.
	originalCreatedAt := record.CreatedAt
	record.SetTimestamps()
	assert.Equal(t, originalCreatedAt, record.CreatedAt)
}

func TestValidIntervalTypes(t *testing.T) {
	assert.True(t, ValidIntervalTypes[IntervalTypeHourly])
	assert.True(t, ValidIntervalTypes[IntervalTypeDaily])
	assert.True(t, ValidIntervalTypes[IntervalTypeWeekly])
	assert.False(t, ValidIntervalTypes["monthly"])
}
