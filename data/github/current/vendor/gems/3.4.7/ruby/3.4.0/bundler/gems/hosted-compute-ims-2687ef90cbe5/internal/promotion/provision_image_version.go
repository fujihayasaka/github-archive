package promotion

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
)

func (c *ImagePromotionClient) ProvisionImageVersion(ctx context.Context, imageVersionId uint64, sourceVhdUrl string, workflowOwnerId string) *PromotionError {
	imageDefinition, imageVersion, err := c.utils.GetImageDefinitionAndVersionByVersionId(ctx, imageVersionId)
	if err != nil {
		return err
	}

	ctx = stash.WithLoggingFields(ctx,
		kvp.Uint64("image_definition_id", imageDefinition.Id),
		kvp.String("image_version", imageVersion.Version),
		kvp.String("image_type", string(imageDefinition.ImageType)),
		kvp.String("image_architecture", string(imageDefinition.Architecture)),
		kvp.String("image_os", string(imageDefinition.OsType)),
	)
	ctx = stash.WithStatterFields(ctx,
		kvp.String("image_type", string(imageDefinition.ImageType)),
		kvp.String("image_architecture", string(imageDefinition.Architecture)),
		kvp.String("image_os", string(imageDefinition.OsType)),
	)

	promotionStartTime := time.Now()
	statter.Increment(ctx, "promotion.provision_image_version.started")

	switch imageVersion.State {
	case models.ImageVersionState_Pending:
		if err := c.utils.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Pending, models.ImageVersionState_Provisioning, ""); err != nil {
			return &PromotionError{Err: fmt.Errorf("failed to update image version state: %w", err), UserErrorDetails: "failed to provision image", NonRetryable: false}
		}
	case models.ImageVersionState_Provisioning:
		// no need to update state if image version is already in provisioning state
		// it could happen if provision job was interrupted by restarting kube pod
		// after we had started but prior to completing the job.
	case models.ImageVersionState_Ready:
		// no need to update state if image version is already in ready state
		// it could happen if provision job was interrupted by restarting kube pod
		// after we had finished but prior to acknowledging the job.
	default:
		return &PromotionError{Err: fmt.Errorf("image version is in invalid state: %s, expected state: %v", imageVersion.State, []models.ImageVersionState{models.ImageVersionState_Pending, models.ImageVersionState_Provisioning}), UserErrorDetails: "Image version is in invalid state", NonRetryable: true}
	}

	var promErr *PromotionError
	if imageVersion.State != models.ImageVersionState_Ready {
		switch {
		case imageDefinition.IsGalleryImageDefinition():
			promErr = c.galleryProvider.ProvisionImageVersion(ctx, imageDefinition, imageVersion, sourceVhdUrl)
		case imageDefinition.OsType == models.OsType_MacOS:
			promErr = c.macOSProvider.ProvisionImageVersion(ctx, imageDefinition, imageVersion, sourceVhdUrl)
		default:
			promErr = &PromotionError{Err: fmt.Errorf("unknown image type for operation"), UserErrorDetails: "", NonRetryable: true}
		}
		if promErr == nil {
			if updateErr := c.utils.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Provisioning, models.ImageVersionState_Ready, ""); updateErr != nil {
				logger.ErrorWithReport(ctx, "failed to update image version state details", updateErr)
			}
		} else {
			// if image provision fails, put image version back to pending state. Worker will take care about retrying and reporting error
			if updateErr := c.utils.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Provisioning, models.ImageVersionState_Pending, ""); updateErr != nil {
				logger.ErrorWithReport(ctx, "failed to update image version state details", updateErr)
			}
		}

		ctx = stash.WithLoggingFields(ctx, kvp.Bool("result", promErr == nil))
		ctx = stash.WithStatterFields(ctx, kvp.Bool("result", promErr == nil))

		statter.Increment(ctx, "promotion.provision_image_version.finished")
		statter.DistributionMs(ctx, "promotion.provision_image_version.duration", time.Since(promotionStartTime))
		statter.DistributionMs(ctx, "promotion.provision_image_version_since_creation.duration", time.Since(imageVersion.CreatedAt))
		logger.Info(ctx, "image version provisioning finished",
			kvp.Duration("duration", time.Since(promotionStartTime)),
			kvp.Duration("duration_since_creation", time.Since(imageVersion.CreatedAt)),
		)
	} else {
		logger.Info(ctx, "image version was already ready")
	}

	if imageDefinition.ImageType == models.ImageType_Customer && workflowOwnerId != "" {
		// Publish notification about new image version ready to workflowOwnerId.
		logger.Info(ctx, "publish image version provisioning finished event")
	}

	return promErr
}

func (c *ImagePromotionClient) ProvisionImageVersionFailedAfterMaxRetries(ctx context.Context, imageVersionId uint64, failureDetails *PromotionError) error {
	stateDetails := failureDetails.UserErrorDetails

	if err := c.utils.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Pending, models.ImageVersionState_ProvisionFailed, stateDetails); err != nil {
		return fmt.Errorf("failed to update image version state to ProvisionFailed: %w", err)
	}

	imageDefinition, _, err := c.utils.GetImageDefinitionAndVersionByVersionId(ctx, imageVersionId)
	if err != nil {
		return err
	}

	if imageDefinition.IsGalleryImageDefinition() {
		if err := c.workerQueueClient.QueueProvisionCleanupJob(ctx, imageVersionId); err != nil {
			return fmt.Errorf("failed to queue provision clean up job: %w", err)
		}

		logger.Info(ctx, "queued provision cleanup job", kvp.Uint64("image_version_id", imageVersionId))
	}

	return nil
}
