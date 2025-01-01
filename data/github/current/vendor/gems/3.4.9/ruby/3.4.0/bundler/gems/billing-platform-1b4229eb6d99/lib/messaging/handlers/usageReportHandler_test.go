package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log" //nolint:staticcheck
	stats "github.com/github/go-stats"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func TestNewUsageReportHandlerr_InitializedWithCorrectQueueName(t *testing.T) {
	handler := NewUsageReportHandler(&HandlerParams{}, nil, nil, nil)
	assert.NotNil(t, handler)
	assert.Equal(t, handler.queueName, "usage-report")
}

func TestUsageReportHandler_SkipMessageIfRequestNotActive(t *testing.T) {
	_, _, statter, logger, _ := helpers.SetupMocks(t)

	mockKustoService := fakes.NewMockKustoService(pegomock.WithT(t))
	mockUsageReportEngine := fakes.NewMockUsageReportEngineInterface(pegomock.WithT(t))

	pegomock.When(mockUsageReportEngine.UsageReportRequestActive(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Key](),
	)).ThenReturn(false, nil)

	handler := NewUsageReportHandler(&HandlerParams{statter: statter}, mockUsageReportEngine, mockKustoService, nil)

	model := &models.UsageReportExport{
		Key:    models.Key{},
		Status: models.UsageReportExportStatusPending,
	}
	payload, err := json.Marshal(model)
	assert.Nil(t, err)

	err = handler.ProcessMessage(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: payload}})
	assert.Nil(t, err)

	statter.AssertCalled(t, "Counter", "usage.report_handler.skip", stats.Tags{"status": string(model.Status)}, int64(1))
}

func TestUsageReportHandler_NoStatusErrorIf404ErrorDuringCompleteMigrationDelete(t *testing.T) {
	_, _, statter, logger, _ := helpers.SetupMocks(t)

	mockKustoService := fakes.NewMockKustoService(pegomock.WithT(t))
	mockUsageReportEngine := fakes.NewMockUsageReportEngineInterface(pegomock.WithT(t))

	azNotFoundError := &azcore.ResponseError{
		StatusCode: http.StatusNotFound,
	}

	pegomock.When(mockUsageReportEngine.UsageReportRequestActive(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Key](),
	)).ThenReturn(true, nil)
	pegomock.When(mockUsageReportEngine.MigrateLoadingUsageReportToCompleted(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.UsageReportExport](), pegomock.Any[[]string](),
	)).ThenReturn(nil, azNotFoundError)
	pegomock.When(mockUsageReportEngine.IsExportOperationAlreadyCompleted(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.UsageReportExport](),
	)).ThenReturn(true)
	pegomock.When(mockKustoService.GetExportStatus(
		pegomock.Any[context.Context](), pegomock.Any[*models.UsageReportExport](),
	)).ThenReturn(models.KustoOperationStatusCompleted, nil)

	handler := NewUsageReportHandler(&HandlerParams{statter: statter}, mockUsageReportEngine, mockKustoService, nil)

	model := &models.UsageReportExport{
		Key:    models.Key{},
		Status: models.UsageReportExportStatusLoading,
	}
	payload, err := json.Marshal(model)
	assert.Nil(t, err)

	err = handler.ProcessMessage(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: payload}})
	assert.Nil(t, err)

	statter.AssertNotCalled(t, "Counter", "usage.report_handler.error", stats.Tags{}, int64(1))
	statter.AssertCalled(t, "Counter", "usage.report_handler.skip", stats.Tags{"status": string(model.Status)}, int64(1))
}

func TestUsageReportHandler_NoStatusErrorIf409ErrorDuringCompleteMigrationDelete(t *testing.T) {
	_, _, statter, logger, _ := helpers.SetupMocks(t)

	mockKustoService := fakes.NewMockKustoService(pegomock.WithT(t))
	mockUsageReportEngine := fakes.NewMockUsageReportEngineInterface(pegomock.WithT(t))

	azConflictError := &azcore.ResponseError{
		StatusCode: http.StatusConflict,
	}

	pegomock.When(mockUsageReportEngine.UsageReportRequestActive(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Key](),
	)).ThenReturn(true, nil)
	pegomock.When(mockUsageReportEngine.MigrateLoadingUsageReportToCompleted(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.UsageReportExport](), pegomock.Any[[]string](),
	)).ThenReturn(nil, azConflictError)
	pegomock.When(mockUsageReportEngine.IsExportOperationAlreadyCompleted(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.UsageReportExport](),
	)).ThenReturn(true)
	pegomock.When(mockKustoService.GetExportStatus(
		pegomock.Any[context.Context](), pegomock.Any[*models.UsageReportExport](),
	)).ThenReturn(models.KustoOperationStatusCompleted, nil)

	handler := NewUsageReportHandler(&HandlerParams{statter: statter}, mockUsageReportEngine, mockKustoService, nil)

	model := &models.UsageReportExport{
		Key:    models.Key{},
		Status: models.UsageReportExportStatusLoading,
	}
	payload, err := json.Marshal(model)
	assert.Nil(t, err)

	err = handler.ProcessMessage(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: payload}})
	assert.Nil(t, err)

	statter.AssertNotCalled(t, "Counter", "usage.report_handler.error", stats.Tags{}, int64(1))
	statter.AssertCalled(t, "Counter", "usage.report_handler.skip", stats.Tags{"status": string(model.Status)}, int64(1))
}

func TestUsageReportHandler_StatusErrorIfNon404ErrorDuringCompleteMigrationDelete(t *testing.T) {
	_, _, statter, logger, _ := helpers.SetupMocks(t)

	mockKustoService := fakes.NewMockKustoService(pegomock.WithT(t))
	mockUsageReportEngine := fakes.NewMockUsageReportEngineInterface(pegomock.WithT(t))

	pegomock.When(mockUsageReportEngine.UsageReportRequestActive(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Key](),
	)).ThenReturn(true, nil)
	pegomock.When(mockUsageReportEngine.MigrateLoadingUsageReportToCompleted(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.UsageReportExport](), pegomock.Any[[]string](),
	)).ThenReturn(nil, errors.New("unexpected error"))
	pegomock.When(mockKustoService.GetExportStatus(
		pegomock.Any[context.Context](), pegomock.Any[*models.UsageReportExport](),
	)).ThenReturn(models.KustoOperationStatusCompleted, nil)

	handler := NewUsageReportHandler(&HandlerParams{statter: statter}, mockUsageReportEngine, mockKustoService, nil)

	model := &models.UsageReportExport{
		Key:    models.Key{},
		Status: models.UsageReportExportStatusLoading,
	}
	payload, err := json.Marshal(model)
	assert.Nil(t, err)

	err = handler.ProcessMessage(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: payload}})
	assert.Nil(t, err)

	statter.AssertCalled(t, "Counter", "usage.report_handler.error", stats.Tags{}, int64(1))
}

func TestUsageReportHandler_StatusErrorIf404DuringCompleteMigrationDeleteWithNoCompletedRecord(t *testing.T) {
	_, _, statter, logger, _ := helpers.SetupMocks(t)

	mockKustoService := fakes.NewMockKustoService(pegomock.WithT(t))
	mockUsageReportEngine := fakes.NewMockUsageReportEngineInterface(pegomock.WithT(t))

	azNotFoundError := &azcore.ResponseError{
		StatusCode: http.StatusNotFound,
	}

	pegomock.When(mockUsageReportEngine.UsageReportRequestActive(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Key](),
	)).ThenReturn(true, nil)
	pegomock.When(mockUsageReportEngine.MigrateLoadingUsageReportToCompleted(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.UsageReportExport](), pegomock.Any[[]string](),
	)).ThenReturn(nil, azNotFoundError)
	pegomock.When(mockUsageReportEngine.IsExportOperationAlreadyCompleted(
		pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.UsageReportExport](),
	)).ThenReturn(false)
	pegomock.When(mockKustoService.GetExportStatus(
		pegomock.Any[context.Context](), pegomock.Any[*models.UsageReportExport](),
	)).ThenReturn(models.KustoOperationStatusCompleted, nil)

	handler := NewUsageReportHandler(&HandlerParams{statter: statter}, mockUsageReportEngine, mockKustoService, nil)

	model := &models.UsageReportExport{
		Key:    models.Key{},
		Status: models.UsageReportExportStatusLoading,
	}
	payload, err := json.Marshal(model)
	assert.Nil(t, err)

	err = handler.ProcessMessage(context.Background(), logger, aqueduct.ReceiveResult{Job: aqueduct.Job{Payload: payload}})
	assert.Nil(t, err)

	statter.AssertCalled(t, "Counter", "usage.report_handler.error", stats.Tags{}, int64(1))
}
