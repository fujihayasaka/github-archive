package engines

import (
	"context"
	"testing"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_CreateUsageReportExport(t *testing.T) {
	mocker := pegomock.WithT(t)
	mockDB := fakes.NewMockDatabase(mocker)
	engine := NewUsageReportEngine(&EngineParams{
		db: mockDB,
	})
	StartDate := int64(1715003180)
	EndDate := int64(1715003180)
	LegacyReport := false

	input := &proto.QueueUsageReportExportRequest{
		CustomerId:   "1",
		StartDate:    StartDate,
		EndDate:      EndDate,
		LegacyReport: LegacyReport,
	}

	usageReportExport, err := engine.CreateUsageReportExport(context.Background(), log.NewNullLogger(), input)
	assert.Nil(t, err)

	mockDB.VerifyWasCalledOnce().CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.UsageReportExport](),
		pegomock.Any[*interfaces.QueryOptions](),
	)

	assert.Equal(t, input.CustomerId, usageReportExport.CustomerID)
	assert.Equal(t, input.ActorId, usageReportExport.ActorId)
	assert.Equal(t, input.StartDate, StartDate)
	assert.Equal(t, input.EndDate, EndDate)
	assert.Equal(t, input.LegacyReport, LegacyReport)
}

func Test_CreateLegacyUsageReportExport(t *testing.T) {
	mocker := pegomock.WithT(t)
	mockDB := fakes.NewMockDatabase(mocker)
	engine := NewUsageReportEngine(&EngineParams{
		db: mockDB,
	})
	StartDate := int64(1715003180)
	EndDate := int64(1715003180)
	LegacyReport := true

	input := &proto.QueueUsageReportExportRequest{
		CustomerId:        "1",
		StartDate:         StartDate,
		EndDate:           EndDate,
		LegacyReport:      LegacyReport,
		BillableOwnerType: proto.BillableOwnerType_Business,
		BillableOwnerId:   int64(5),
	}

	usageReportExport, err := engine.CreateUsageReportExport(context.Background(), log.NewNullLogger(), input)
	assert.Nil(t, err)

	mockDB.VerifyWasCalledOnce().CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.UsageReportExport](),
		pegomock.Any[*interfaces.QueryOptions](),
	)

	assert.Equal(t, input.CustomerId, usageReportExport.CustomerID)
	assert.Equal(t, input.ActorId, usageReportExport.ActorId)
	assert.Equal(t, input.StartDate, StartDate)
	assert.Equal(t, input.EndDate, EndDate)
	assert.Equal(t, input.LegacyReport, LegacyReport)
	assert.Equal(t, input.BillableOwnerType, usageReportExport.BillableOwnerType)
	assert.Equal(t, input.BillableOwnerId, usageReportExport.BillableOwnerID)
}

func Test_MigratePendingUsageReportToLoading(t *testing.T) {
	mocker := pegomock.WithT(t)
	mockDB := fakes.NewMockDatabase(mocker)
	engine := NewUsageReportEngine(&EngineParams{
		db: mockDB,
	})

	inputUsageReportExport := &models.UsageReportExport{}
	inputOperationUUID := "123"

	outputUsageReportExport, err := engine.MigratePendingUsageReportToLoading(context.Background(), log.NewNullLogger(), inputUsageReportExport, inputOperationUUID)
	assert.Nil(t, err)

	mockDB.VerifyWasCalledOnce().UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.UsageReportExport](),
		pegomock.Any[*interfaces.QueryOptions](),
	)

	assert.Equal(t, outputUsageReportExport.Status, models.UsageReportExportStatusLoading)
	assert.Equal(t, outputUsageReportExport.ExportOperationUUID, inputOperationUUID)
}

func Test_MigrateLoadingUsageReportToCompleted(t *testing.T) {
	mocker := pegomock.WithT(t)
	mockDB := fakes.NewMockDatabase(mocker)
	engine := NewUsageReportEngine(&EngineParams{
		db: mockDB,
	})

	inputUsageReportExport := &models.UsageReportExport{}
	inputBlobURLs := []string{"test-blob"}

	outputUsageReportExport, err := engine.MigrateLoadingUsageReportToCompleted(context.Background(), log.NewNullLogger(), inputUsageReportExport, inputBlobURLs)
	assert.Nil(t, err)

	mockDB.VerifyWasCalledOnce().DeleteWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.UsageReportExport](),
		pegomock.Any[*interfaces.QueryOptions](),
	)

	mockDB.VerifyWasCalledOnce().CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.UsageReportExport](),
		pegomock.Any[*interfaces.QueryOptions](),
	)

	assert.Equal(t, outputUsageReportExport.Status, models.UsageReportExportStatusCompleted)
	assert.Equal(t, outputUsageReportExport.ExportBlobs, inputBlobURLs)
}

func Test_MigrateLoadingUsageReportToFailed(t *testing.T) {
	mocker := pegomock.WithT(t)
	mockDB := fakes.NewMockDatabase(mocker)
	engine := NewUsageReportEngine(&EngineParams{
		db: mockDB,
	})

	inputUsageReportExport := &models.UsageReportExport{}

	outputUsageReportExport, err := engine.MigrateLoadingUsageReportToFailed(context.Background(), log.NewNullLogger(), inputUsageReportExport)
	assert.Nil(t, err)

	mockDB.VerifyWasCalledOnce().DeleteWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.UsageReportExport](),
		pegomock.Any[*interfaces.QueryOptions](),
	)

	mockDB.VerifyWasCalledOnce().CreateWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.UsageReportExport](),
		pegomock.Any[*interfaces.QueryOptions](),
	)

	assert.Equal(t, outputUsageReportExport.Status, models.UsageReportExportStatusFailed)
}

func Test_MigrateThrottledUsageReportToPending(t *testing.T) {
	mocker := pegomock.WithT(t)
	mockDB := fakes.NewMockDatabase(mocker)
	engine := NewUsageReportEngine(&EngineParams{
		db: mockDB,
	})

	inputUsageReportExport := &models.UsageReportExport{
		ExportOperationUUID: "123",
	}

	outputUsageReportExport, err := engine.MigrateThrottledUsageReportToPending(context.Background(), log.NewNullLogger(), inputUsageReportExport)
	assert.Nil(t, err)

	mockDB.VerifyWasCalledOnce().UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Any[*models.UsageReportExport](),
		pegomock.Any[*interfaces.QueryOptions](),
	)

	assert.Equal(t, outputUsageReportExport.Status, models.UsageReportExportStatusPending)
	assert.Equal(t, outputUsageReportExport.ExportOperationUUID, "")
}

func Test_PublishUsageReportRequestNotification(t *testing.T) {
	tests := []struct {
		name                   string
		inputUsageReportExport *models.UsageReportExport
		expectError            bool
	}{
		{
			name: "notification published successfully",
			inputUsageReportExport: &models.UsageReportExport{
				ActorId:             1,
				ExportBlobs:         []string{"test-blob1", "test-blob2"},
				CustomerID:          "1",
				StartDate:           time.Now(),
				EndDate:             time.Now().Add(24 * time.Hour),
				LegacyReport:        false,
				ExportOperationUUID: "123",
			},
			expectError: false,
		},
		{
			name: "returns error when publish fails",
			inputUsageReportExport: &models.UsageReportExport{
				ActorId:             1,
				ExportBlobs:         []string{"test-blob1", "test-blob2"},
				CustomerID:          "1",
				StartDate:           time.Now(),
				EndDate:             time.Now().Add(24 * time.Hour),
				LegacyReport:        false,
				ExportOperationUUID: "123",
			},
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mocker := pegomock.WithT(t)
			mockDB := fakes.NewMockDatabase(mocker)
			mockHydroPublisher := fakes.NewMockHydroPublisher(mocker)
			engine := NewUsageReportEngine(&EngineParams{
				db: mockDB,
			})

			expectedNotificaiton := &hydroSchema.UsageReportRequestNotification{
				ActorId:    tt.inputUsageReportExport.ActorId,
				BlobUrls:   tt.inputUsageReportExport.ExportBlobs,
				CustomerId: tt.inputUsageReportExport.CustomerID,
				Success:    true,
				StartDate:  tt.inputUsageReportExport.StartDate.Unix(),
				EndDate:    tt.inputUsageReportExport.EndDate.Unix(),
			}

			if tt.expectError {
				pegomock.When(mockHydroPublisher.Publish(pegomock.Any[*hydroSchema.UsageReportRequestNotification]())).ThenReturn(assert.AnError)
			}

			err := engine.PublishUsageReportRequestNotification(log.NewNullLogger(), mockHydroPublisher, tt.inputUsageReportExport, true)
			if tt.expectError {
				assert.NotNil(t, err)
			} else {
				assert.Nil(t, err)
			}

			mockHydroPublisher.VerifyWasCalledOnce().Publish(
				pegomock.Eq(expectedNotificaiton),
			)
		})
	}
}
