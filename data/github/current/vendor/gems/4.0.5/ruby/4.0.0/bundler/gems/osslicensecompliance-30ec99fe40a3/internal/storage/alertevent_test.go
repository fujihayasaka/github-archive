package storage_test

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/stretchr/testify/require"
)

func TestCreateAndGetAlertEvent_Success(t *testing.T) {
	s := newSqliteStorage(t)
	ctx := t.Context()

	userID := uint64(10)
	eventBodyKey := "matching_key"
	eventCount := 3
	alertID := uint64(100)

	for i := range eventCount {
		event := models.AlertEvent{
			AlertID:   alertID,
			EventType: models.EventReviewRequested,
			UserID:    &userID,
			EventBody: json.RawMessage(fmt.Sprintf(`{%q:%q}`, eventBodyKey, i)),
		}
		err := s.CreateAlertEvent(ctx, event)
		require.NoError(t, err)
	}

	// Create an event for a different alert to ensure filtering works
	otherEvent := models.AlertEvent{
		AlertID:   200,
		EventType: models.EventReviewRequested,
		UserID:    &userID,
		EventBody: json.RawMessage(`{"other_key":"is not going to match"}`),
	}
	err := s.CreateAlertEvent(ctx, otherEvent)
	require.NoError(t, err)

	retrievedEvents, err := s.GetAlertEvents(ctx, alertID)
	require.NoError(t, err)
	require.Len(t, retrievedEvents, eventCount)

	for _, retrievedEvent := range retrievedEvents {
		require.Equal(t, alertID, retrievedEvent.AlertID)
		require.Equal(t, models.EventReviewRequested, retrievedEvent.EventType)
		require.Equal(t, &userID, retrievedEvent.UserID)
		require.Contains(t, string(retrievedEvent.EventBody), eventBodyKey)
		require.WithinDuration(t, time.Now(), retrievedEvent.OccurredAt, 2*time.Second)
	}
}

func TestCreateAlertEvent_InOrder(t *testing.T) {
	s := newSqliteStorage(t)
	ctx := t.Context()

	userID := uint64(10)
	eventCount := 5
	alertID := uint64(100)

	for i := range eventCount {
		event := models.AlertEvent{
			AlertID:   alertID,
			EventType: models.EventReviewRequested,
			UserID:    &userID,
			EventBody: json.RawMessage(fmt.Sprintf(`{"sequence_number":%d}`, i)),
		}
		err := s.CreateAlertEvent(ctx, event)
		require.NoError(t, err)
	}

	retrievedEvents, err := s.GetAlertEvents(ctx, alertID)
	require.NoError(t, err)
	require.Len(t, retrievedEvents, eventCount)

	for i, retrievedEvent := range retrievedEvents {
		require.Contains(t, string(retrievedEvent.EventBody), fmt.Sprintf(`"sequence_number":%d`, i))
		if i > 0 {
			require.True(t, retrievedEvents[i-1].OccurredAt.Before(retrievedEvent.OccurredAt), "events are not in order")
		}
	}
}

func TestCreateAlertEvent_NilUserID(t *testing.T) {
	s := newSqliteStorage(t)
	ctx := t.Context()

	event := models.AlertEvent{
		AlertID:   100,
		EventType: models.EventClosed,
		UserID:    nil,
		EventBody: json.RawMessage(`{"reason":"test reason"}`),
	}

	err := s.CreateAlertEvent(ctx, event)
	require.NoError(t, err)

	retrievedEvents, err := s.GetAlertEvents(ctx, event.AlertID)
	require.NoError(t, err)
	require.Len(t, retrievedEvents, 1)

	retrievedEvent := retrievedEvents[0]
	require.Nil(t, retrievedEvent.UserID) // Ensure UserID is nil
}

func TestGetAlertEvents_NoEvents(t *testing.T) {
	s := newSqliteStorage(t)
	ctx := t.Context()

	event := models.AlertEvent{
		AlertID:   100,
		EventType: models.EventClosed,
		UserID:    nil,
		EventBody: json.RawMessage(`{"reason":"test reason"}`),
	}

	err := s.CreateAlertEvent(ctx, event)
	require.NoError(t, err)

	events, err := s.GetAlertEvents(ctx, 9999)
	require.NoError(t, err)
	require.Empty(t, events)
}
