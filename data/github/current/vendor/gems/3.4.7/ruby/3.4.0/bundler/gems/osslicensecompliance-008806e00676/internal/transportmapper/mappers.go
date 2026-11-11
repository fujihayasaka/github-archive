// Package transportmapper provides mapping from the model structs to the protobufs
// Used both for twirp transport and blob storage.
package transportmapper

import (
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// ModelToProtoAlertStatus converts a model AlertStatus to a proto AlertStatus.
func ModelToProtoAlertStatus(status models.AlertStatus) proto.AlertStatus {
	switch status {
	case models.Open:
		return proto.AlertStatus_ALERT_STATUS_OPEN
	case models.ReviewRequested:
		return proto.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED
	case models.Closed:
		return proto.AlertStatus_ALERT_STATUS_CLOSED
	default:
		return proto.AlertStatus_ALERT_STATUS_UNKNOWN
	}
}

// ModelToProtoAlertResolution converts a model AlertResolution pointer to a proto AlertResolution.
func ModelToProtoAlertResolution(resolution *models.AlertResolution) proto.AlertResolution {
	if resolution == nil {
		return proto.AlertResolution_ALERT_RESOLUTION_UNKNOWN
	}
	switch *resolution {
	case models.ExceptionAdded:
		return proto.AlertResolution_ALERT_RESOLUTION_EXCEPTION_ADDED
	case models.PolicyChanged:
		return proto.AlertResolution_ALERT_RESOLUTION_POLICY_CHANGED
	default:
		return proto.AlertResolution_ALERT_RESOLUTION_UNKNOWN
	}
}

// ModelToProtoAlertEventType converts a model AlertEventType to a proto AlertEventType.
func ModelToProtoAlertEventType(eventType models.AlertEventType) proto.AlertEventType {
	switch eventType {
	case models.EventReviewRequested:
		return proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_REQUESTED
	case models.EventReviewDenied:
		return proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_DENIED
	case models.EventReviewApproved:
		return proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_APPROVED
	case models.EventExceptionAdded:
		return proto.AlertEventType_ALERT_EVENT_TYPE_EXCEPTION_ADDED
	case models.EventLicensesAdded:
		return proto.AlertEventType_ALERT_EVENT_TYPE_LICENSES_ADDED
	case models.EventClosed:
		return proto.AlertEventType_ALERT_EVENT_TYPE_CLOSED
	default:
		return proto.AlertEventType_ALERT_EVENT_TYPE_UNKNOWN
	}
}

// ModelToProtoAlertEvent converts a model AlertEvent to a proto AlertEvent.
func ModelToProtoAlertEvent(event *models.AlertEvent) *proto.AlertEvent {
	if event == nil {
		return nil
	}
	return &proto.AlertEvent{
		Id:         event.ID,
		AlertId:    event.AlertID,
		EventType:  ModelToProtoAlertEventType(event.EventType),
		UserId:     pointers.ValueOrZero(event.UserID),
		OccurredAt: timestamppb.New(event.OccurredAt),
		EventBody:  string(event.EventBody),
	}
}
