package layout

import (
	"fmt"
	"time"

	schemas "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/mobile/clients"
	"github.com/github/notifyd/internal/mobile/text"
)

// Message is a decorator around `schemas.DeliverMobilePush` to help us deal
// with some operations that we need to sanitize it, and handle some nil
// pointers
type Message struct {
	*schemas.DeliverMobilePush
}

// BuildNotification creates a notification from the message.
func (m Message) BuildNotification(username, notificationType string) (*clients.Notification, error) {
	notification, err := Render(m.GetLayoutData(), notificationType)
	if err != nil {
		return nil, fmt.Errorf("error rendering notification: %w", err)
	}

	notification.NotificationID = m.GetNotificationId()
	notification.UserID = int64(m.GetUserId())
	notification.Body = text.Sanitize(notification.Body)
	notification.Username = username

	return notification, nil
}

// GetSkipSAMLEnforcement returns a boolean indicating whether to skip enforcement.
func (m Message) GetSkipSAMLEnforcement() bool {
	return m.GetSamlEnforcement().GetSkipEnforcement()
}

// GetSAMLOrganizationID returns the organization ID for SAML enforcement.
func (m Message) GetSAMLOrganizationID() int32 {
	return m.GetSamlEnforcement().GetOrganizationId()
}

// GetTriggeredAtTime returns the time the notification was triggered.
func (m Message) GetTriggeredAtTime() time.Time {
	tracking := m.GetTracking()
	if tracking == nil {
		return time.Time{}
	}
	if tracking.TriggeredAt == nil {
		return time.Time{}
	}
	return m.GetTracking().TriggeredAt.AsTime()
}

// reasonMapping represents a mapping from a reason to type, where toType is
// the type that mobile.Notification should expect
type reasonMapping struct {
	reason string
	toType string
}

// prioritizedReasonMappings is the list of reason mappings sorted by priority
var prioritizedReasonMappings = []reasonMapping{
	{reason: "pull_request_reviewed", toType: "review"},
	{reason: "mention", toType: "mention"},
	{reason: "assign", toType: "assigned"},
	{reason: "review_requested", toType: "review_requested"},
	{reason: "approval_requested", toType: "approval_requested"},
	{reason: "mobile_auth_request", toType: "mobile_device_auth"},
	{reason: "ci_activity", toType: "ci_activity"},
}

// GetReasonAndType returns the reason and type of the message.
func (m Message) GetReasonAndType() (reason, notificationType string) {
	reasons := map[string]struct{}{}
	for _, reason := range m.GetReasons() {
		reasons[reason.GetName()] = struct{}{}
	}

	for _, mapping := range prioritizedReasonMappings {
		if _, ok := reasons[mapping.reason]; ok {
			return mapping.reason, mapping.toType
		}
	}
	return "", ""
}
