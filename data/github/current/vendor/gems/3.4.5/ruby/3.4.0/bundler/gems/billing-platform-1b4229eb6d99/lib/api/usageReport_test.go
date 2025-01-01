package api

import (
	"context"
	"testing"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_QueueUsageReportExport_CallsKustoWhenNoOtherActiveExport(t *testing.T) {
	mockUsageReportEngine := fakes.NewMockUsageReportEngineInterface(pegomock.WithT(t))

	inputExportRequest := &proto.QueueUsageReportExportRequest{
		CustomerId: "customer-id",
		ActorId:    1234,
	}

	// return false to indicate that there are no active exports for the customer from the actor
	pegomock.When(mockUsageReportEngine.ActorHasActiveUsageReportExportForCustomer(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(inputExportRequest.CustomerId), pegomock.Eq(inputExportRequest.ActorId),
	)).ThenReturn(false, nil)

	vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
	api := NewUsageReportAPI(nil, nil, nil, nil, mockUsageReportEngine, log.NewNullLogger(), vexiClient)
	_, err := api.QueueUsageReportExport(context.Background(), inputExportRequest)
	assert.Nil(t, err)

	mockUsageReportEngine.VerifyWasCalledOnce().CreateUsageReportExport(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*proto.QueueUsageReportExportRequest]())
}

func Test_QueueUsageReportExport_DoesNotCallKustoWhenActiveExportExists(t *testing.T) {
	mockUsageReportEngine := fakes.NewMockUsageReportEngineInterface(pegomock.WithT(t))

	inputExportRequest := &proto.QueueUsageReportExportRequest{
		CustomerId: "customer-id",
		ActorId:    1234,
	}

	// return true to indicate that there are active exports for the customer from the actor
	pegomock.When(mockUsageReportEngine.ActorHasActiveUsageReportExportForCustomer(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(inputExportRequest.CustomerId), pegomock.Eq(inputExportRequest.ActorId),
	)).ThenReturn(true, nil)

	vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
	api := NewUsageReportAPI(nil, nil, nil, nil, mockUsageReportEngine, log.NewNullLogger(), vexiClient)
	_, err := api.QueueUsageReportExport(context.Background(), inputExportRequest)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "User already has an active usage report export")
}
