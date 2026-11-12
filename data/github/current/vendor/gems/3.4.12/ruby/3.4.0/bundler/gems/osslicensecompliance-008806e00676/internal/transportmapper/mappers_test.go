package transportmapper_test

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/transportmapper"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
)

func TestStatusToProto(t *testing.T) {
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_OPEN, transportmapper.ModelToProtoAlertStatus(models.Open))
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED, transportmapper.ModelToProtoAlertStatus(models.ReviewRequested))
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_CLOSED, transportmapper.ModelToProtoAlertStatus(models.Closed))
}

func TestResolutionToProto(t *testing.T) {
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_UNKNOWN, transportmapper.ModelToProtoAlertResolution(nil))

	exceptionAdded := models.ExceptionAdded
	policyChanged := models.PolicyChanged

	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_EXCEPTION_ADDED, transportmapper.ModelToProtoAlertResolution(&exceptionAdded))
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_POLICY_CHANGED, transportmapper.ModelToProtoAlertResolution(&policyChanged))

	unknownResolution := models.AlertResolution(999)
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_UNKNOWN, transportmapper.ModelToProtoAlertResolution(&unknownResolution))
}

func TestModelToProtoAlertEventType(t *testing.T) {
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_REQUESTED, transportmapper.ModelToProtoAlertEventType(models.EventReviewRequested))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_DENIED, transportmapper.ModelToProtoAlertEventType(models.EventReviewDenied))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_APPROVED, transportmapper.ModelToProtoAlertEventType(models.EventReviewApproved))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_EXCEPTION_ADDED, transportmapper.ModelToProtoAlertEventType(models.EventExceptionAdded))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_LICENSES_ADDED, transportmapper.ModelToProtoAlertEventType(models.EventLicensesAdded))
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_CLOSED, transportmapper.ModelToProtoAlertEventType(models.EventClosed))

	unknownEventType := models.AlertEventType(999)
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_UNKNOWN, transportmapper.ModelToProtoAlertEventType(unknownEventType))
}
