package storage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/github/osslicensecompliance/internal/models"
)

// CreateAlertEventQuery is the SQL query to insert a new alert event.
var CreateAlertEventQuery = `
	INSERT INTO olc_alert_events (
		alert_id,
		event_type,
		user_id,
		occurred_at,
		event_body
	)
	VALUES (?, ?, ?, ?, ?)
`

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
