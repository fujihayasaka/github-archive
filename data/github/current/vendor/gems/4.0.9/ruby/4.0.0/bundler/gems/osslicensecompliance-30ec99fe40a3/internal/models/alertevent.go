package models

import (
	"encoding/json"
	"fmt"
	"time"
)

// AlertEventType represents the type of event that occurred on an alert.
type AlertEventType int

const (
	// EventReviewRequested indicates that a review was requested for the alert.
	EventReviewRequested AlertEventType = iota

	// EventReviewDenied indicates that a request for review was denied.
	EventReviewDenied

	// EventExceptionAdded indicates that an exception was added for the alert.
	EventExceptionAdded

	// EventLicensesAdded indicates that licenses were added to the policy to remediate the alert.
	EventLicensesAdded

	// EventClosed indicates that the alert was closed.
	EventClosed

	// EventReviewApproved indicates that a request for review was approved.
	EventReviewApproved

	// EventReviewExpired indicates that a review request expired.
	EventReviewExpired
)

// String provides a string representation of the AlertEventType.
func (a AlertEventType) String() string {
	switch a {
	case EventReviewRequested:
		return "review_requested"
	case EventReviewDenied:
		return "review_denied"
	case EventReviewApproved:
		return "review_approved"
	case EventReviewExpired:
		return "review_expired"
	case EventExceptionAdded:
		return "exception_added"
	case EventLicensesAdded:
		return "licenses_added"
	case EventClosed:
		return "closed"
	default:
		panic(fmt.Sprintf("invalid alert event type: %d", a))
	}
}

// AlertEventTypeFromString converts a string into an AlertEventType enum value.
func AlertEventTypeFromString(s string) AlertEventType {
	switch s {
	case "review_requested":
		return EventReviewRequested
	case "review_denied":
		return EventReviewDenied
	case "review_approved":
		return EventReviewApproved
	case "review_expired":
		return EventReviewExpired
	case "exception_added":
		return EventExceptionAdded
	case "licenses_added":
		return EventLicensesAdded
	case "closed":
		return EventClosed
	default:
		panic(fmt.Sprintf("invalid alert event type string: %s", s))
	}
}

// AlertEvent represents an event that occurred on a license compliance alert.
type AlertEvent struct {
	ID         uint64          `db:"id"`
	AlertID    uint64          `db:"alert_id"`
	EventType  AlertEventType  `db:"event_type"`
	UserID     *uint64         `db:"user_id"`
	OccurredAt time.Time       `db:"occurred_at"`
	EventBody  json.RawMessage `db:"event_body"`
}

// ExceptionAddedEventBody represents the event body for EventExceptionAdded.
type ExceptionAddedEventBody struct {
	PackageManager string `json:"package_manager"`
	PackageName    string `json:"package_name"`
	Level          string `json:"level"`
	Comment        string `json:"comment"` // TODO: ljones140 not using in FE can be removed after issue #8808 deployed
}

// ToJSON converts the ExceptionAddedEventBody to its JSON representation.
func (e ExceptionAddedEventBody) ToJSON() ([]byte, error) {
	return json.Marshal(e)
}

// LicensesAddedEventBody represents the event body for EventLicensesAdded.
type LicensesAddedEventBody struct {
	Licenses []string `json:"licenses"`
	Level    string   `json:"level"`
	Comment  string   `json:"comment"` // TODO: ljones140 not using in FE can be removed after issue #8808 deployed
}

// ToJSON converts the LicensesAddedEventBody to its JSON representation.
func (l LicensesAddedEventBody) ToJSON() ([]byte, error) {
	return json.Marshal(l)
}

// ReviewRequestedEventBody represents the event body for EventReviewRequested.
type ReviewRequestedEventBody struct {
	ClosureReason string `json:"closure_reason,omitempty"`
	Comment       string `json:"comment,omitempty"`
}

// ReviewDeniedEventBody represents the event body for EventReviewDenied.
type ReviewDeniedEventBody struct {
	Comment string `json:"comment,omitempty"`
}

// ReviewApprovedEventBody represents the event body for EventReviewApproved.
type ReviewApprovedEventBody struct {
	Comment string `json:"comment,omitempty"`
}

// AlertStatusChangeEventBody represents the event body for alert status
// changes. This is used for EventReviewRequested and
// EventReviewDenied.
type AlertStatusChangeEventBody struct {
	Comment string `json:"comment,omitempty"`
}

// CloseAlertEventBody represents the event body for EventClosed.
type CloseAlertEventBody struct {
	Comment string `json:"comment,omitempty"`
}
