package promotion

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
)

func (c *ImagePromotionClient) ProvisionImageVersion(ctx context.Context, logger *telemetry.ReportingLogger, imageVersionId uint64, sourceVhdUrl string) *PromotionError {
	imageVersion, err := c.imagesStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to get image version by id: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     true,
		}
	}

	imageDefinition, err := c.imagesStore.GetImageDefinitionById(ctx, imageVersion.ImageDefinitionId)
	if err != nil {
		return &PromotionError{
			Err:              fmt.Errorf("failed to get image definition by id: %w", err),
			UserErrorDetails: "failed to provision image",
			NonRetryable:     true,
		}
	}

	promotionStartTime := time.Now()
	logger = utils.NewLoggerWithFields(logger, append(c.utils.GetLoggerFieldsForImageDefinition(imageDefinition), kvp.String("image_version", imageVersion.Version))...)
	logger.Statter.Counter("promotion.provision_image_version.started", c.utils.GetStatterTagsForImageDefinition(imageDefinition), 1)

	switch imageVersion.State {
	case models.ImageVersionState_Pending:
		if err = c.utils.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Pending, models.ImageVersionState_Provisioning, ""); err != nil {
			return &PromotionError{Err: fmt.Errorf("failed to update image version state: %w", err), UserErrorDetails: "failed to provision image", NonRetryable: false}
		}
	case models.ImageVersionState_Provisioning:
		// no need to update state if image version is already in provisioning state
		// it could happen if provision job was interrupted by restarting kube pod
	default:
		return &PromotionError{Err: fmt.Errorf("image version is in invalid state: %s, expected state: %v", imageVersion.State, []models.ImageVersionState{models.ImageVersionState_Pending, models.ImageVersionState_Provisioning}), UserErrorDetails: "Image version is in invalid state", NonRetryable: true}
	}

	var promErr *PromotionError
	switch {
	case imageDefinition.OsType == models.OsType_Linux || imageDefinition.OsType == models.OsType_Windows:
		promErr = c.galleryProvider.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, sourceVhdUrl)
	case imageDefinition.OsType == models.OsType_MacOS:
		promErr = c.macOSProvider.ProvisionImageVersion(ctx, logger, imageDefinition, imageVersion, sourceVhdUrl)
	default:
		promErr = &PromotionError{Err: fmt.Errorf("unknown image type for operation"), UserErrorDetails: "", NonRetryable: true}
	}
	if promErr == nil {
		if updateErr := c.utils.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Provisioning, models.ImageVersionState_Ready, ""); err != nil {
			logger.ErrorWithReport("failed to update image version state details", updateErr)
		}
	} else {
		// if image provision fails, put image version back to pending state. Worker will take care about retrying and reporting error
		if updateErr := c.utils.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Provisioning, models.ImageVersionState_Pending, ""); updateErr != nil {
			logger.ErrorWithReport("failed to update image version state details", updateErr)
		}
	}

	statsWithResult := c.utils.GetStatterTagsForImageDefinition(imageDefinition).Merge(stats.Tags{"result": fmt.Sprint(promErr == nil)})
	logger.Statter.Counter("promotion.provision_image_version.finished", statsWithResult, 1)
	logger.Statter.DistributionMs("promotion.provision_image_version.duration", statsWithResult, time.Since(promotionStartTime))
	logger.Info("image version provisioning finished", kvp.Duration("duration", time.Since(promotionStartTime)), kvp.Bool("result", promErr == nil))

	return promErr
}

func (c *ImagePromotionClient) ProvisionImageVersionFailedAfterMaxRetries(ctx context.Context, logger *telemetry.ReportingLogger, imageVersionId uint64, failureDetails *PromotionError) error {
	stateDetails := failureDetails.UserErrorDetails

	if err := c.utils.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Pending, models.ImageVersionState_ProvisionFailed, stateDetails); err != nil {
		return fmt.Errorf("failed to update image version state to ProvisionFailed: %w", err)
	}

	if err := c.workerQueueClient.QueueProvisionCleanupJob(ctx, imageVersionId); err != nil {
		return fmt.Errorf("failed to queue provision clean up job: %w", err)
	}

	return nil
}
