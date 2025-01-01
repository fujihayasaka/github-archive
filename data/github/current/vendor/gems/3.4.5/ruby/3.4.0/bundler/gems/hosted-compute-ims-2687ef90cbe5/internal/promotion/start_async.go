package promotion

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/utils"
)

func (c *ImagePromotionStartClient) StartAsyncImageVersionProvision(ctx context.Context, imageVersionId uint64, sourceVhdUrl string, workflowOwnerId string) error {
	if err := c.workerQueueClient.QueueProvisionImageVersionJob(ctx, imageVersionId, sourceVhdUrl, workflowOwnerId); err != nil {
		return fmt.Errorf("failed to queue provision image version job: %w", err)
	}

	return nil
}

func (c *ImagePromotionStartClient) StartAsyncImageVersionDeletion(ctx context.Context, imageVersionId uint64) error {
	if err := c.imagesStore.UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting, ""); err != nil {
		return fmt.Errorf("failed to update image version state to Deleting: %w", err)
	}

	if err := c.workerQueueClient.QueueDeleteImageVersionJob(ctx, imageVersionId); err != nil {
		return fmt.Errorf("failed to queue deleting image version job: %w", err)
	}

	return nil
}

func (c *ImagePromotionStartClient) StartAsyncImageDefinitionDeletion(ctx context.Context, imageDefinitionId uint64) error {
	if err := c.imagesStore.UpdateImageDefinition(ctx, imageDefinitionId, &store.ImageDefinitionUpdatePayload{
		State: utils.ToPtr(models.ImageDefinitionState_Deleting),
	}); err != nil {
		return fmt.Errorf("failed to update image definition state to Deleting: %w", err)
	}

	if err := c.workerQueueClient.QueueDeleteImageDefinitionJob(ctx, imageDefinitionId); err != nil {
		return fmt.Errorf("failed to queue deleting image definition job: %w", err)
	}

	return nil
}

func (c *ImagePromotionStartClient) StartAsyncOwnerResourcesCleanup(ctx context.Context, ownerId string) error {
	allImages, err := c.imagesStore.ListCustomerImageDefinitionsByOwner(ctx, ownerId)
	if err != nil {
		return fmt.Errorf("failed to list customer image definitions: %w", err)
	}

	for _, imageDefinition := range allImages {
		if imageDefinition.ImageType == models.ImageType_Curated {
			// it must never happen but adding this validation just in case.
			return fmt.Errorf("massive deletion of curated images is not allowed. Something goes wrong")
		}
	}

	var aggregatedError error = nil
	for _, imageDefinition := range allImages {
		if err := c.StartAsyncImageDefinitionDeletion(ctx, imageDefinition.Id); err != nil {
			aggregatedError = errors.Join(aggregatedError, err)
		}
	}

	if aggregatedError != nil {
		return fmt.Errorf("failed to start deletion of some image definitions: %w", aggregatedError)
	}

	return nil
}
