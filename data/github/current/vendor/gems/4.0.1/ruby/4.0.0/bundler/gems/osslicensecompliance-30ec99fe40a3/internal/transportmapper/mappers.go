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
	case models.AlertStatusOpen:
		return proto.AlertStatus_ALERT_STATUS_OPEN
	case models.AlertStatusReviewRequested:
		return proto.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED
	case models.AlertStatusReviewDenied:
		return proto.AlertStatus_ALERT_STATUS_REVIEW_DENIED
	case models.AlertStatusClosed:
		return proto.AlertStatus_ALERT_STATUS_CLOSED
	default:
		return proto.AlertStatus_ALERT_STATUS_UNKNOWN
	}
}

// ModelToProtoAlertResolution converts a model AlertResolution to a proto AlertResolution.
func ModelToProtoAlertResolution(resolution models.AlertResolution) proto.AlertResolution {
	switch resolution {
	case models.AlertResolutionExceptionAdded:
		return proto.AlertResolution_ALERT_RESOLUTION_EXCEPTION_ADDED
	case models.AlertResolutionOutdated:
		return proto.AlertResolution_ALERT_RESOLUTION_OUTDATED
	case models.AlertResolutionLicensesAdded:
		return proto.AlertResolution_ALERT_RESOLUTION_LICENSES_ADDED
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
	case models.EventReviewExpired:
		return proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_EXPIRED
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

// ModelToProtoClosureReason converts a model ClosureReason to a proto ClosureReason.
func ModelToProtoClosureReason(reason *string) proto.ClosureReason {
	if reason == nil {
		return proto.ClosureReason_CLOSURE_REASON_UNKNOWN
	}
	switch *reason {
	case models.ClosureReasonAmendment:
		return proto.ClosureReason_CLOSURE_REASON_AMENDMENT
	case models.ClosureReasonPrivatePackage:
		return proto.ClosureReason_CLOSURE_REASON_PRIVATE_PACKAGE
	case models.ClosureReasonInaccurateLicense:
		return proto.ClosureReason_CLOSURE_REASON_INACCURATE_LICENSE
	case models.ClosureReasonPolicyEdited:
		return proto.ClosureReason_CLOSURE_REASON_POLICY_EDITED
	case models.ClosureReasonFixed:
		return proto.ClosureReason_CLOSURE_REASON_FIXED
	default:
		return proto.ClosureReason_CLOSURE_REASON_UNKNOWN
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
