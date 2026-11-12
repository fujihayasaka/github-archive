package transportmapper_test

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/transportmapper"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
)

func TestStatusToProto(t *testing.T) {
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_OPEN, transportmapper.ModelToProtoAlertStatus(models.AlertStatusOpen))
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED, transportmapper.ModelToProtoAlertStatus(models.AlertStatusReviewRequested))
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_CLOSED, transportmapper.ModelToProtoAlertStatus(models.AlertStatusClosed))
}

func TestResolutionToProto(t *testing.T) {
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_UNKNOWN, transportmapper.ModelToProtoAlertResolution(models.AlertResolutionUnknown))
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_EXCEPTION_ADDED, transportmapper.ModelToProtoAlertResolution(models.AlertResolutionExceptionAdded))
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_OUTDATED, transportmapper.ModelToProtoAlertResolution(models.AlertResolutionOutdated))
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_LICENSES_ADDED, transportmapper.ModelToProtoAlertResolution(models.AlertResolutionLicensesAdded))

	unknownResolution := models.AlertResolution(999)
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_UNKNOWN, transportmapper.ModelToProtoAlertResolution(unknownResolution))
}

func TestModelToProtoAlertEventType(t *testing.T) {
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_REQUESTED, transportmapper.ModelToProtoAlertEventType(models.EventReviewRequested))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_DENIED, transportmapper.ModelToProtoAlertEventType(models.EventReviewDenied))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_APPROVED, transportmapper.ModelToProtoAlertEventType(models.EventReviewApproved))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_EXPIRED, transportmapper.ModelToProtoAlertEventType(models.EventReviewExpired))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_EXCEPTION_ADDED, transportmapper.ModelToProtoAlertEventType(models.EventExceptionAdded))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_LICENSES_ADDED, transportmapper.ModelToProtoAlertEventType(models.EventLicensesAdded))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_CLOSED, transportmapper.ModelToProtoAlertEventType(models.EventClosed))

	unknownEventType := models.AlertEventType(999)
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_UNKNOWN, transportmapper.ModelToProtoAlertEventType(unknownEventType))
}

func TestModelToProtoClosureReason(t *testing.T) {
	amendment := models.ClosureReasonAmendment
	assert.Equal(t, proto.ClosureReason_CLOSURE_REASON_AMENDMENT, transportmapper.ModelToProtoClosureReason(&amendment))
	privatePackage := models.ClosureReasonPrivatePackage
	assert.Equal(t, proto.ClosureReason_CLOSURE_REASON_PRIVATE_PACKAGE, transportmapper.ModelToProtoClosureReason(&privatePackage))
	inaccurateLicense := models.ClosureReasonInaccurateLicense
	assert.Equal(t, proto.ClosureReason_CLOSURE_REASON_INACCURATE_LICENSE, transportmapper.ModelToProtoClosureReason(&inaccurateLicense))
	policyEdited := models.ClosureReasonPolicyEdited
	assert.Equal(t, proto.ClosureReason_CLOSURE_REASON_POLICY_EDITED, transportmapper.ModelToProtoClosureReason(&policyEdited))
	fixed := models.ClosureReasonFixed
	assert.Equal(t, proto.ClosureReason_CLOSURE_REASON_FIXED, transportmapper.ModelToProtoClosureReason(&fixed))

	unknownClosureReason := (*string)(nil)
	assert.Equal(t, proto.ClosureReason_CLOSURE_REASON_UNKNOWN, transportmapper.ModelToProtoClosureReason(unknownClosureReason))
}
