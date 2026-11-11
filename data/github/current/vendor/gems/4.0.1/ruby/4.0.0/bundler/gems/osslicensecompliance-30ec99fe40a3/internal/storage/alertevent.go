package storage

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/github/osslicensecompliance/internal/models"
)

// CreateAlertEventQuery is the SQL query to insert a new alert event.
const CreateAlertEventQuery = `
	INSERT INTO olc_alert_events (
		alert_id,
		event_type,
		user_id,
		occurred_at,
		event_body
	)
	VALUES (?, ?, ?, ?, ?)
`

// AlertEventStep is a storage step for creating an alert (timeline) event.
type AlertEventStep struct {
	models.AlertEvent

	rawEventBody any
}

// NewAlertEventStep creates a step to add an alert event to the timeline for the alert.
func NewAlertEventStep(alertID uint64, eventType models.AlertEventType, userID *uint64, eventBody any) *AlertEventStep {
	return &AlertEventStep{
		AlertEvent: models.AlertEvent{
			AlertID:   alertID,
			EventType: eventType,
			UserID:    userID,
		},
		rawEventBody: eventBody,
	}
}

// WithTimestamp allows setting a custom timestamp for when the event occurred. If not set, it defaults to the current time.
func (s *AlertEventStep) WithTimestamp(occurredAt time.Time) *AlertEventStep {
	s.OccurredAt = occurredAt
	return s
}

// Execute runs the step to insert the alert event into the database.
func (s *AlertEventStep) Execute(ctx context.Context, tx *sql.Tx) error {
	body := s.rawEventBody
	if body == nil {
		// Normalize a nil body to an empty JSON object so "empty body" events
		// are stored consistently as {} rather than null.
		body = struct{}{}
	}
	eventBodyBytes, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("failed to marshal alert event body: %w", err)
	}
	s.EventBody = eventBodyBytes
	if s.OccurredAt.IsZero() {
		s.OccurredAt = time.Now()
	}

	_, err = tx.ExecContext(ctx, CreateAlertEventQuery,
		s.AlertID,
		s.EventType.String(),
		s.UserID,
		s.OccurredAt,
		s.EventBody,
	)

	if err != nil {
		return fmt.Errorf("failed to insert alert event: %w", err)
	}

	return nil
}

// CreateAlertEvent inserts a new alert event into the database.
func (s *Storage) CreateAlertEvent(ctx context.Context, event models.AlertEvent) error {
	event.OccurredAt = time.Now()

	_, err := s.db.ExecContext(ctx, CreateAlertEventQuery,
		event.AlertID,
		event.EventType.String(),
		event.UserID,
		event.OccurredAt,
		event.EventBody,
	)

	if err != nil {
		return fmt.Errorf("failed to insert alert event: %w", err)
	}

	return nil
}

// GetAlertEvents retrieves all events for a given alert ID from the database.
func (s *Storage) GetAlertEvents(ctx context.Context, alertID uint64) ([]models.AlertEvent, error) {
	query := `
		SELECT
			id,
			alert_id,
			event_type,
			user_id,
			occurred_at,
			event_body
		FROM olc_alert_events
		WHERE alert_id = ?
		ORDER BY occurred_at ASC
	`

	rows, err := s.db.QueryContext(ctx, query, alertID)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch alert events for alert #%d: %w", alertID, err)
	}
	defer rows.Close()

	var events []models.AlertEvent
	for rows.Next() {
		var event models.AlertEvent
		var eventType string

		if err := rows.Scan(
			&event.ID,
			&event.AlertID,
			&eventType,
			&event.UserID,
			&event.OccurredAt,
			&event.EventBody,
		); err != nil {
			return nil, fmt.Errorf("failed to scan alert event row: %w", err)
		}

		event.EventType = models.AlertEventTypeFromString(eventType)
		events = append(events, event)
	}

	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("error during alert event rows iteration: %w", err)
	}

	return events, nil
}

// GetAlertEvent retrieves a single alert event by alert ID and event type.
func (s *Storage) GetAlertEvent(ctx context.Context, alertID uint64, eventType models.AlertEventType) (*models.AlertEvent, error) {
	query := `
		SELECT
			id,
			alert_id,
			event_type,
			user_id,
			occurred_at,
			event_body
		FROM olc_alert_events
		WHERE alert_id = ? AND event_type = ?
	`

	var event models.AlertEvent
	var eventTypeStr string

	err := s.db.QueryRowContext(ctx, query, alertID, eventType.String()).Scan(
		&event.ID,
		&event.AlertID,
		&eventTypeStr,
		&event.UserID,
		&event.OccurredAt,
		&event.EventBody,
	)

	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to fetch alert event for alert #%d with type %s: %w", alertID, eventType.String(), err)
	}

	event.EventType = models.AlertEventTypeFromString(eventTypeStr)
	return &event, nil
}
