package promotion

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestStartAsyncImageVersionDeletion(t *testing.T) {
	var (
		ctx                   = context.Background()
		imageVersionId uint64 = 1
	)

	t.Run("failed to update image version state", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting, "").Return(fmt.Errorf("test"))

		err := p.PromotionStartClient().StartAsyncImageVersionDeletion(ctx, imageVersionId)
		require.ErrorContains(t, err, "failed to update image version state to Deleting: test")
	})

	t.Run("failed to queue image version deletion job", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting, "").Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageVersionJob(ctx, imageVersionId).Return(fmt.Errorf("test")),
		)

		err := p.PromotionStartClient().StartAsyncImageVersionDeletion(ctx, imageVersionId)
		require.ErrorContains(t, err, "failed to queue deleting image version job: test")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().UpdateImageVersionState(ctx, imageVersionId, models.ImageVersionState_Deleting, "").Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageVersionJob(ctx, imageVersionId).Return(nil),
		)

		err := p.PromotionStartClient().StartAsyncImageVersionDeletion(ctx, imageVersionId)
		require.NoError(t, err)
	})
}

func TestStartAsyncImageDefinitionDeletion(t *testing.T) {
	var (
		ctx                      = context.Background()
		imageDefinitionId uint64 = 1
	)

	t.Run("failed to update image version state", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitionId, gomock.Any()).Return(fmt.Errorf("test"))

		err := p.PromotionStartClient().StartAsyncImageDefinitionDeletion(ctx, imageDefinitionId)
		require.ErrorContains(t, err, "failed to update image definition state to Deleting: test")
	})

	t.Run("failed to queue image version deletion job", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitionId, gomock.Any()).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageDefinitionJob(ctx, imageDefinitionId).Return(fmt.Errorf("test")),
		)

		err := p.PromotionStartClient().StartAsyncImageDefinitionDeletion(ctx, imageDefinitionId)
		require.ErrorContains(t, err, "failed to queue deleting image definition job: test")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitionId, gomock.Any()).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageDefinitionJob(ctx, imageDefinitionId).Return(nil),
		)

		err := p.PromotionStartClient().StartAsyncImageDefinitionDeletion(ctx, imageDefinitionId)
		require.NoError(t, err)
	})
}

func TestStartAsyncAllImageDefinitionsDeletion(t *testing.T) {
	var (
		ctx            = context.Background()
		ownerId string = "user1"
	)

	t.Run("failed to list customer image definitions for owner", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().ListCustomerImageDefinitionsByOwner(ctx, ownerId).Return(nil, fmt.Errorf("test"))

		err := p.PromotionStartClient().StartAsyncOwnerResourcesCleanup(ctx, ownerId)
		require.ErrorContains(t, err, "failed to list customer image definitions: test")
	})

	t.Run("failed if some image definitions are curated", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageDefinitions := []*models.ImageDefinition{
			{Id: 1, ImageType: models.ImageType_Customer},
			{Id: 2, ImageType: models.ImageType_Curated},
			{Id: 3, ImageType: models.ImageType_Customer},
		}

		mockImagesStore.EXPECT().ListCustomerImageDefinitionsByOwner(ctx, ownerId).Return(imageDefinitions, nil)

		err := p.PromotionStartClient().StartAsyncOwnerResourcesCleanup(ctx, ownerId)
		require.ErrorContains(t, err, "massive deletion of curated images is not allowed. Something goes wrong")
	})

	t.Run("failed if deletion of some image definitions failed", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageDefinitions := []*models.ImageDefinition{
			{Id: 1, ImageType: models.ImageType_Customer},
			{Id: 2, ImageType: models.ImageType_Customer},
			{Id: 3, ImageType: models.ImageType_Customer},
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCustomerImageDefinitionsByOwner(ctx, ownerId).Return(imageDefinitions, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitions[0].Id, gomock.Any()).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageDefinitionJob(ctx, imageDefinitions[0].Id).Return(nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitions[1].Id, gomock.Any()).Return(fmt.Errorf("test")),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitions[2].Id, gomock.Any()).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageDefinitionJob(ctx, imageDefinitions[2].Id).Return(nil),
		)

		err := p.PromotionStartClient().StartAsyncOwnerResourcesCleanup(ctx, ownerId)
		require.ErrorContains(t, err, "failed to start deletion of some image definitions:")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		imageDefinitions := []*models.ImageDefinition{
			{Id: 1, ImageType: models.ImageType_Customer},
			{Id: 2, ImageType: models.ImageType_Customer},
			{Id: 3, ImageType: models.ImageType_Customer},
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCustomerImageDefinitionsByOwner(ctx, ownerId).Times(1).Return(imageDefinitions, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitions[0].Id, gomock.Any()).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageDefinitionJob(ctx, imageDefinitions[0].Id).Return(nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitions[1].Id, gomock.Any()).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageDefinitionJob(ctx, imageDefinitions[1].Id).Return(nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, imageDefinitions[2].Id, gomock.Any()).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageDefinitionJob(ctx, imageDefinitions[2].Id).Return(nil),
		)

		err := p.PromotionStartClient().StartAsyncOwnerResourcesCleanup(ctx, ownerId)
		require.NoError(t, err)
	})
}
