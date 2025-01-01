package twirp

import (
	"context"
	"database/sql"
	"fmt"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
	"go.uber.org/mock/gomock"
)

func TestInternalImageApiHandler_GetImageDetails(t *testing.T) {
	var (
		ctx             = context.Background()
		actor           = &sharedapi.Actor{GlobalId: "test-owner"}
		curatedImageKey = &internalapi.ImageKey{
			Source:  "Curated",
			Id:      1,
			Version: "latest",
		}

		curatedImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "valid-test-image",
			OsType:       models.OsType_Linux,
			Enabled:      true,
			Architecture: models.Architecture_X64,
		}

		imageVersion = models.ImageVersion{
			Version:           "1.0.0",
			ImageDefinitionId: 1,
		}
	)

	t.Run("unknown image source", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: &internalapi.ImageKey{Source: "Unknown", Id: 1, Version: "latest"},
			Owner:    actor,
		})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("unsupported image type").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get image definition", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageKey.Id).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: curatedImageKey,
			Owner:    actor,
		})

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("image definition is not found", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageKey.Id).Times(1).Return(nil, sql.ErrNoRows)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: curatedImageKey,
			Owner:    actor,
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("image definition is not found if image type doesn't match", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		curatedImageKey := &internalapi.ImageKey{Source: "Curated", Id: 1, Version: "latest"}
		customerImageKey := &internalapi.ImageKey{Source: "Customer", Id: 2, Version: "latest"}

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageKey.Id).Times(1).Return(&models.ImageDefinition{Id: 2, ImageType: models.ImageType_Customer}, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageKey.Id).Times(1).Return(&models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated}, nil)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: curatedImageKey,
			Owner:    actor,
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)

		res, err = h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: customerImageKey,
			Owner:    actor,
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get exact image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageKey.Id).Times(1).Return(&curatedImageDefinition, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, curatedImageKey).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: curatedImageKey,
			Owner:    actor,
		})

		assert.EqualError(t, err, twirp.Internal.Error("failed to get exact image version").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image details", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageKey.Id).Times(1).Return(&curatedImageDefinition, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, curatedImageKey).Times(1).Return(&imageVersion, nil)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: curatedImageKey,
			Owner:    actor,
		})

		assert.NoError(t, err)
		assert.Equal(t, res.ImageDetails.Id, curatedImageDefinition.Id)
		assert.Equal(t, res.ImageDetails.Enabled, curatedImageDefinition.Enabled)
	})

	t.Run("successfully retrieved image details if enabled under FF", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		featureflags.TEST_SetupFeatureFlagsClient(t).
			EnableFeatureFlagGlobally(featureflags.FeatureFlag("flag-1")).
			DisableFeatureFlagGlobally(featureflags.FeatureFlag("flag-2"))

		imageKeyWithEnabledFlag := &internalapi.ImageKey{Source: "Curated", Id: 1, Version: "latest"}
		imageKeyWithDisabledFlag := &internalapi.ImageKey{Source: "Curated", Id: 2, Version: "latest"}

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageKeyWithEnabledFlag.Id).Times(1).Return(&models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated, OsType: models.OsType_Linux, Architecture: models.Architecture_X64, FeatureFlag: utils.ToPtr("flag-1")}, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageKeyWithDisabledFlag.Id).Times(1).Return(&models.ImageDefinition{Id: 2, ImageType: models.ImageType_Curated, OsType: models.OsType_Linux, Architecture: models.Architecture_X64, FeatureFlag: utils.ToPtr("flag-2")}, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, gomock.Any()).Times(2).Return(&imageVersion, nil)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: imageKeyWithEnabledFlag,
			Owner:    actor,
		})
		assert.NoError(t, err)
		assert.Equal(t, uint64(1), res.ImageDetails.Id)
		assert.Equal(t, res.ImageDetails.Enabled, true)

		res, err = h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageKey: imageKeyWithDisabledFlag,
			Owner:    actor,
		})
		assert.NoError(t, err)
		assert.Equal(t, uint64(2), res.ImageDetails.Id)
		assert.Equal(t, res.ImageDetails.Enabled, false)
	})
}

func TestInternalImageApiHandler_GetImageReference(t *testing.T) {
	var (
		armRefId    = "/subscriptions/test-subscription/resourceGroups/hostedcomputeims-testdeveloperid/providers/Microsoft.Compute/galleries/imsgallerytestdeveloperid/images/image-1/versions/1.0.0"
		emptyString = ""
	)

	var (
		ctx            = context.Background()
		latestImageKey = &internalapi.ImageKey{
			Source:  "Curated",
			Id:      1,
			Version: "latest",
		}
		imageDefinition = &models.ImageDefinition{
			Id:        1,
			ImageType: models.ImageType_Curated,
		}
		imageVersion = &models.ImageVersion{
			ImageDefinitionId: 1,
			SizeGB:            utils.ToPtr[int32](30),
			State:             models.ImageVersionState_Ready,
		}
		armImageReference = armcompute.ImageReference{
			ID:        &armRefId,
			Offer:     &emptyString,
			Publisher: &emptyString,
			SKU:       &emptyString,
			Version:   &emptyString,
		}
	)

	t.Run("unknown image source", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageKey: &internalapi.ImageKey{Source: "Unknown", Id: 1, Version: "latest"},
		})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("unsupported image type").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get image definition", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, latestImageKey.Id).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{ImageKey: latestImageKey})

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("image definition is not found", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, latestImageKey.Id).Times(1).Return(nil, sql.ErrNoRows)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{ImageKey: latestImageKey})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("image definition is not found if image type doesn't match", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		curatedImageKey := &internalapi.ImageKey{Source: "Curated", Id: 1, Version: "latest"}
		customerImageKey := &internalapi.ImageKey{Source: "Customer", Id: 2, Version: "latest"}

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageKey.Id).Times(1).Return(&models.ImageDefinition{Id: 2, ImageType: models.ImageType_Customer}, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageKey.Id).Times(1).Return(&models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated}, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{ImageKey: curatedImageKey})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)

		res, err = h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{ImageKey: customerImageKey})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get exact image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, latestImageKey.Id).Times(1).Return(imageDefinition, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, latestImageKey).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{ImageKey: latestImageKey})

		assert.EqualError(t, err, twirp.Internal.Error("failed to get exact image version").Error())
		assert.Nil(t, res)
	})

	t.Run("image version is not found for latest image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		imageKey := &internalapi.ImageKey{
			Source:  "Curated",
			Id:      1,
			Version: "latest",
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageKey.Id).Times(1).Return(imageDefinition, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, imageKey).Times(1).Return(nil, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{ImageKey: imageKey})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("image definition does not have enabled versions in ready state").Error())
		assert.Nil(t, res)
	})

	t.Run("image version is not found for speficic image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		imageKey := &internalapi.ImageKey{
			Source:  "Curated",
			Id:      1,
			Version: "1.0.0",
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageKey.Id).Times(1).Return(imageDefinition, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, imageKey).Times(1).Return(nil, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{ImageKey: imageKey})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("image version is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("image version is not not in ready state", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		imageKey := &internalapi.ImageKey{
			Source:  "Curated",
			Id:      1,
			Version: "1.0.0",
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, imageKey.Id).Times(1).Return(imageDefinition, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, imageKey).Times(1).Return(&models.ImageVersion{State: models.ImageVersionState_Provisioning}, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{ImageKey: imageKey})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("requested image version is not ready to use").Error())
		assert.Nil(t, res)
	})

	t.Run("fail to get image reference", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, latestImageKey.Id).Times(1).Return(imageDefinition, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, latestImageKey).Times(1).Return(imageVersion, nil)
		mockManager.EXPECT().GetImageReference(ctx, imageVersion).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageKey: latestImageKey,
		})

		assert.ErrorContains(t, err, "failed to get image reference")
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image reference", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, latestImageKey.Id).Times(1).Return(imageDefinition, nil)
		mockManager.EXPECT().GetExactImageVersion(ctx, latestImageKey).Times(1).Return(imageVersion, nil)
		mockManager.EXPECT().GetImageReference(ctx, imageVersion).Times(1).Return(&armImageReference, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageKey: latestImageKey,
		})

		assert.NoError(t, err)
		assert.Equal(
			t,
			*armImageReference.ID,
			res.ImageReference.Id)
	})
}

func TestInternalImageApiHandler_ProtoValidate(t *testing.T) {
	testCases := []requestValidationTestCase{
		{
			requestName: "GetImageReference",
			testName:    "Missing image key",
			request:     &internalapi.GetImageReferenceRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_key: value is required [required]",
		},
		{
			requestName: "GetImageReference",
			testName:    "Missing fields",
			request: &internalapi.GetImageReferenceRequest{
				ImageKey: &internalapi.ImageKey{},
			},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_key.source: value is required [required]\n" +
				" - image_key.id: value is required [required]\n" +
				" - image_key.version: value is required [required]",
		},
		{
			requestName: "GetImageReference",
			testName:    "Valid request",
			request: &internalapi.GetImageReferenceRequest{
				ImageKey: &internalapi.ImageKey{
					Source:  "Curated",
					Id:      1,
					Version: "latest",
				},
			},
			expectedError: "",
		},
		{
			requestName: "GetImageDetails",
			testName:    "Missing image key",
			request:     &internalapi.GetImageDetailsRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_key: value is required [required]",
		},
		{
			requestName: "GetImageDetails",
			testName:    "Missing fields",
			request: &internalapi.GetImageDetailsRequest{
				ImageKey: &internalapi.ImageKey{},
			},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_key.source: value is required [required]\n" +
				" - image_key.id: value is required [required]\n" +
				" - image_key.version: value is required [required]",
		},
		{
			requestName: "GetImageDetails",
			testName:    "Valid request",
			request: &internalapi.GetImageDetailsRequest{
				ImageKey: &internalapi.ImageKey{
					Source:  "Curated",
					Id:      1,
					Version: "latest",
				},
				Owner: &sharedapi.Actor{GlobalId: "test-user"},
			},
			expectedError: "",
		},
	}

	for _, test := range testCases {
		testProtoValidate(t, test)
	}
}
