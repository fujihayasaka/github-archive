package cronjobs

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/require"
)

func Test_TelemetryJob_PublishAzureSubscriptionsCapacity(t *testing.T) {
	var (
		ctx                = context.Background()
		azureSubscriptions = []*models.AzureSubscription{
			{Id: 1, SubscriptionId: "sub-1", ImageType: models.ImageType_Curated, ImageVersionsCount: 100, ImageVersionsLimit: 10000},
			{Id: 2, SubscriptionId: "sub-2", ImageType: models.ImageType_Customer, ImageVersionsCount: 200, ImageVersionsLimit: 10000},
			{Id: 3, SubscriptionId: "sub-3", ImageType: models.ImageType("Mixed"), ImageVersionsCount: 400, ImageVersionsLimit: 10000},
		}
	)

	t.Run("failed to list azure subscriptions", func(t *testing.T) {
		ctrl, baseJob := setup(t)
		defer ctrl.Finish()

		job := &TelemetryJob{
			BaseJob: baseJob,
		}

		mockImagesStore.EXPECT().ListAzureSubscriptions(ctx).Return(nil, fmt.Errorf("test"))

		err := job.publishAzureSubscriptionsCapacity(ctx)
		require.ErrorContains(t, err, "failed to list azure subscriptions: test")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, baseJob := setup(t)
		defer ctrl.Finish()

		job := &TelemetryJob{
			BaseJob: baseJob,
		}

		mockImagesStore.EXPECT().ListAzureSubscriptions(ctx).Return(azureSubscriptions, nil)

		err := job.publishAzureSubscriptionsCapacity(ctx)
		require.NoError(t, err)
	})
}

func Test_TelemetryJob_PublishImageVersionsSummary(t *testing.T) {
	ctx := context.Background()

	t.Run("failed to get all image versions summary", func(t *testing.T) {
		ctrl, baseJob := setup(t)
		defer ctrl.Finish()

		job := &TelemetryJob{
			BaseJob: baseJob,
		}

		mockImagesStore.EXPECT().GetAllImageVersionsSummary(ctx, models.ImageType_Curated).Return(nil, fmt.Errorf("test"))

		err := job.publishImageVersionsSummary(ctx)
		require.ErrorContains(t, err, "failed to get all image versions summary: test")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, baseJob := setup(t)
		defer ctrl.Finish()

		job := &TelemetryJob{
			BaseJob: baseJob,
		}

		mockImagesStore.EXPECT().GetAllImageVersionsSummary(ctx, models.ImageType_Curated).Return(&models.ImageVersionsSummary{
			Count:                    100,
			TotalImageVersionsSizeGB: 500,
		}, nil)

		mockImagesStore.EXPECT().GetAllImageVersionsSummary(ctx, models.ImageType_Customer).Return(&models.ImageVersionsSummary{
			Count:                    200,
			TotalImageVersionsSizeGB: 1000,
		}, nil)

		err := job.publishImageVersionsSummary(ctx)
		require.NoError(t, err)
	})
}
