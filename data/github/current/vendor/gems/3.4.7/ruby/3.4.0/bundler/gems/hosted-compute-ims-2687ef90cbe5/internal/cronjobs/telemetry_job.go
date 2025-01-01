package cronjobs

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
)

type TelemetryJob struct {
	BaseJob
}

func (j *TelemetryJob) GetName() string {
	return "TelemetryJob"
}

func (j *TelemetryJob) Perform(ctx context.Context) error {
	hasErrors := false

	if err := j.publishAzureSubscriptionsCapacity(ctx); err != nil {
		hasErrors = true
		logger.ErrorWithReport(ctx, "failed to publish azure subscriptions usage telemetry", err)
	}

	if err := j.publishImageVersionsSummary(ctx); err != nil {
		hasErrors = true
		logger.ErrorWithReport(ctx, "failed to publish image versions summary telemetry", err)
	}

	if hasErrors {
		return fmt.Errorf("telemetry job finished with errors")
	}

	return nil
}

func (j *TelemetryJob) publishAzureSubscriptionsCapacity(ctx context.Context) error {
	azureSubscriptions, err := j.ImagesStore.ListAzureSubscriptions(ctx)
	if err != nil {
		return fmt.Errorf("failed to list azure subscriptions: %w", err)
	}

	var (
		totalUsedCountMap  = map[models.ImageType]uint{}
		totalLimitCountMap = map[models.ImageType]uint{}
	)

	for _, subscription := range azureSubscriptions {
		logger.Info(ctx, "report azure subscription capacity",
			kvp.Uint64("subscription_id", subscription.Id),
			kvp.String("azure_subscription_id", subscription.SubscriptionId),
			kvp.String("image_type", string(subscription.ImageType)),
			kvp.Uint("image_versions_count", subscription.ImageVersionsCount),
			kvp.Uint("image_versions_limit", subscription.ImageVersionsLimit),
		)
		statterFields := []kvp.Field{
			kvp.Uint64("subscription_id", subscription.Id),
			kvp.String("azure_subscription_id", subscription.SubscriptionId),
			kvp.String("image_type", string(subscription.ImageType)),
		}
		statter.Distribution(ctx, "azure_subscriptions.capacity.subscription_used", float64(subscription.ImageVersionsCount), statterFields...)
		statter.Distribution(ctx, "azure_subscriptions.capacity.subscription_limit", float64(subscription.ImageVersionsLimit), statterFields...)

		totalUsedCountMap[subscription.ImageType] += subscription.ImageVersionsCount
		totalLimitCountMap[subscription.ImageType] += subscription.ImageVersionsLimit
	}

	for _, imageType := range []models.ImageType{models.ImageType_Curated, models.ImageType_Customer} {
		totalUsedCount := totalUsedCountMap[imageType]
		totalLimitCount := totalLimitCountMap[imageType]

		logger.Info(ctx, "report total usage across all azure subscriptions",
			kvp.String("image_type", string(imageType)),
			kvp.Uint("image_versions_count", totalUsedCount),
			kvp.Uint("image_versions_limit", totalLimitCount),
		)

		statter.Distribution(ctx, "azure_subscriptions.capacity.total_used", float64(totalUsedCount), kvp.String("image_type", string(imageType)))
		statter.Distribution(ctx, "azure_subscriptions.capacity.total_limit", float64(totalLimitCount), kvp.String("image_type", string(imageType)))
	}

	return nil
}

func (j *TelemetryJob) publishImageVersionsSummary(ctx context.Context) error {
	for _, imageType := range []models.ImageType{models.ImageType_Curated, models.ImageType_Customer} {
		summary, err := j.ImagesStore.GetAllImageVersionsSummary(ctx, imageType)
		if err != nil {
			return fmt.Errorf("failed to get all image versions summary: %w", err)
		}

		logger.Info(ctx, "report total image versions summary",
			kvp.String("image_type", string(imageType)),
			kvp.Int32("image_versions_count", summary.Count),
			kvp.Int32("image_versions_size_gb", summary.TotalImageVersionsSizeGB),
		)

		statter.Distribution(ctx, "image_versions.total_count", float64(summary.Count), kvp.String("image_type", string(imageType)))
		statter.Distribution(ctx, "image_versions.total_size_gb", float64(summary.TotalImageVersionsSizeGB), kvp.String("image_type", string(imageType)))
	}

	return nil
}
