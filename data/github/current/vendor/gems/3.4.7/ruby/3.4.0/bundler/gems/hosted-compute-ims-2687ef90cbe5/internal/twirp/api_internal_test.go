package twirp

import (
	"context"
	"database/sql"
	"fmt"
	"testing"

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
		ctx                    = context.Background()
		actor                  = &sharedapi.Actor{GlobalId: featureflags.TEST_FeatureFlag_FakeUser_GlobalID}
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
			ImageSource:  "Unknown",
			ImageId:      curatedImageDefinition.Id,
			ImageVersion: "latest",
			Owner:        actor,
		})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("unsupported image type").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get image definition", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      curatedImageDefinition.Id,
			ImageVersion: "latest",
			Owner:        actor,
		})

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("image definition is not found", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, sql.ErrNoRows)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      curatedImageDefinition.Id,
			ImageVersion: "latest",
			Owner:        actor,
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("image definition is not found if image type doesn't match", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(1)).Times(1).Return(&models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated}, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(2)).Times(1).Return(&models.ImageDefinition{Id: 2, ImageType: models.ImageType_Customer}, nil)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      2,
			ImageVersion: "latest",
			Owner:        actor,
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)

		res, err = h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  ImageSource_Customer,
			ImageId:      1,
			ImageVersion: "latest",
			Owner:        actor,
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get exact image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      curatedImageDefinition.Id,
			ImageVersion: "latest",
			Owner:        actor,
		})

		assert.EqualError(t, err, twirp.Internal.Error("failed to get exact image version").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image details", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&imageVersion, nil)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      curatedImageDefinition.Id,
			ImageVersion: "latest",
			Owner:        actor,
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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(1)).Times(1).Return(&models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated, OsType: models.OsType_Linux, Architecture: models.Architecture_X64, FeatureFlag: utils.ToPtr("flag-1")}, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(2)).Times(1).Return(&models.ImageDefinition{Id: 2, ImageType: models.ImageType_Curated, OsType: models.OsType_Linux, Architecture: models.Architecture_X64, FeatureFlag: utils.ToPtr("flag-2")}, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), gomock.Any()).Times(2).Return(&imageVersion, nil)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      1,
			ImageVersion: "latest",
			Owner:        actor,
		})
		assert.NoError(t, err)
		assert.Equal(t, uint64(1), res.ImageDetails.Id)
		assert.Equal(t, res.ImageDetails.Enabled, true)

		res, err = h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      2,
			ImageVersion: "latest",
			Owner:        actor,
		})
		assert.NoError(t, err)
		assert.Equal(t, uint64(2), res.ImageDetails.Id)
		assert.Equal(t, res.ImageDetails.Enabled, false)
	})

	t.Run("successfully retrieved image details for marketplace image", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		featureflags.TEST_SetupFeatureFlagsClient(t).
			EnableFeatureFlagGlobally(featureflags.FeatureFlag("flag-1"))

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(1)).Times(1).Return(&models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated, OsType: models.OsType_Linux, Architecture: models.Architecture_X64, FeatureFlag: utils.ToPtr("flag-1")}, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), gomock.Any()).Times(1).Return(&imageVersion, nil)

		res, err := h.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{
			ImageSource:  "Marketplace",
			ImageId:      1,
			ImageVersion: "latest",
			Owner:        actor,
		})
		assert.NoError(t, err)
		assert.Equal(t, uint64(1), res.ImageDetails.Id)
		assert.Equal(t, res.ImageDetails.Enabled, true)
	})
}

func TestInternalImageApiHandler_GetImageReference(t *testing.T) {
	imageVersionResourceId := "/subscriptions/test-subscription/resourceGroups/hostedcomputeims-testdeveloperid/providers/Microsoft.Compute/galleries/imsgallerytestdeveloperid/images/image-1/versions/1.0.0"

	var (
		ctx             = context.Background()
		imageDefinition = &models.ImageDefinition{
			Id:        1,
			ImageType: models.ImageType_Curated,
			OsType:    models.OsType_Linux,
		}
		imageDefinitionMac = &models.ImageDefinition{
			Id:        1,
			ImageType: models.ImageType_Curated,
			OsType:    models.OsType_MacOS,
		}
		imageVersion = &models.ImageVersion{
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			SizeGB:            utils.ToPtr[int32](30),
			State:             models.ImageVersionState_Ready,
			OsState:           models.OsState_Generalized,
		}
		imageVersionMac = &models.ImageVersion{
			Version:           "2.0.0",
			ImageDefinitionId: 1,
			SizeGB:            utils.ToPtr[int32](0),
			State:             models.ImageVersionState_Ready,
			OsState:           models.OsState_Generalized,
			ResourceId:        "test-image",
		}
	)

	t.Run("unknown image source", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  "Unknown",
			ImageId:      1,
			ImageVersion: "latest",
		})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("unsupported image type").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get image definition", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "latest",
		})

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("image definition is not found", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(nil, sql.ErrNoRows)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "latest",
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("image definition is not found if image type doesn't match", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(1)).Times(1).Return(&models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated}, nil)
		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(2)).Times(1).Return(&models.ImageDefinition{Id: 2, ImageType: models.ImageType_Customer}, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      2,
			ImageVersion: "latest",
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)

		res, err = h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Customer,
			ImageId:      1,
			ImageVersion: "latest",
		})

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get exact image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), imageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "latest",
		})

		assert.EqualError(t, err, twirp.Internal.Error("failed to get exact image version").Error())
		assert.Nil(t, res)
	})

	t.Run("image version is not found for latest image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), imageDefinition.Id).Times(1).Return(nil, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "latest",
		})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("image definition does not have enabled versions in ready state").Error())
		assert.Nil(t, res)
	})

	t.Run("image version is not found for speficic image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), imageDefinition.Id, "1.0.0").Times(1).Return(nil, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "1.0.0",
		})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("image version is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("image version is not not in ready state", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), imageDefinition.Id, "1.0.0").Times(1).Return(&models.ImageVersion{State: models.ImageVersionState_Provisioning}, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "1.0.0",
		})

		assert.EqualError(t, err, twirp.InvalidArgument.Error("requested image version is not ready to use").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get image reference for linux image", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), imageDefinition.Id).Times(1).Return(imageVersion, nil)
		mockGalleryPromotionProvider.EXPECT().GetImageVersionResourceId(gomock.Any(), imageVersion).Times(1).Return("", fmt.Errorf("test"))

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "latest",
		})

		assert.ErrorContains(t, err, "failed to get image version resource id")
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image reference for linux image", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), imageDefinition.Id).Times(1).Return(imageVersion, nil)
		mockGalleryPromotionProvider.EXPECT().GetImageVersionResourceId(gomock.Any(), imageVersion).Times(1).Return(imageVersionResourceId, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "latest",
		})

		assert.NoError(t, err)
		assert.Equal(t, imageVersion.Version, res.ImageReference.ExactImageVersion)
		assert.Equal(t, imageVersionResourceId, res.ImageReference.ResourceId)
	})

	t.Run("successfully retrieved image reference for marketplace image", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(imageDefinition, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), imageDefinition.Id).Times(1).Return(imageVersion, nil)
		mockGalleryPromotionProvider.EXPECT().GetImageVersionResourceId(gomock.Any(), imageVersion).Times(1).Return(imageVersionResourceId, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  "Marketplace",
			ImageId:      1,
			ImageVersion: "latest",
		})

		assert.NoError(t, err)
		assert.Equal(t, imageVersion.Version, res.ImageReference.ExactImageVersion)
		assert.Equal(t, imageVersionResourceId, res.ImageReference.ResourceId)
	})

	t.Run("successfully retrieved image reference for macos image", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), imageDefinition.Id).Times(1).Return(imageDefinitionMac, nil)
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), imageDefinition.Id).Times(1).Return(imageVersionMac, nil)

		res, err := h.GetImageReference(ctx, &internalapi.GetImageReferenceRequest{
			ImageSource:  ImageSource_Curated,
			ImageId:      imageDefinition.Id,
			ImageVersion: "latest",
		})

		assert.NoError(t, err)
		assert.Equal(t, imageVersionMac.Version, res.ImageReference.ExactImageVersion)
		assert.Equal(t, imageVersionMac.ResourceId, res.ImageReference.ResourceId)
	})
}

func TestInternalImageApiHandler_ProtoValidate(t *testing.T) {
	testCases := []requestValidationTestCase{
		{
			requestName: "GetImageReference",
			testName:    "Valid request",
			request: &internalapi.GetImageReferenceRequest{
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "latest",
			},
			expectedError: "",
		},
		{
			requestName: "GetImageReference",
			testName:    "Missing fields",
			request:     &internalapi.GetImageReferenceRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_source: value is required [required]\n" +
				" - image_id: value is required [required]\n" +
				" - image_version: value is required [required]",
		},
		{
			requestName: "GetImageDetails",
			testName:    "Missing fields",
			request:     &internalapi.GetImageDetailsRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_source: value is required [required]\n" +
				" - image_id: value is required [required]\n" +
				" - image_version: value is required [required]",
		},
		{
			requestName: "GetImageDetails",
			testName:    "Valid request",
			request: &internalapi.GetImageDetailsRequest{
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "latest",
				Owner:        &sharedapi.Actor{GlobalId: "test-user"},
			},
			expectedError: "",
		},
	}

	for _, test := range testCases {
		testProtoValidate(t, test)
	}
}

func Test_GetExactImageVersion(t *testing.T) {
	ctrl, h := setupInternalImagesApiHandler(t)
	defer ctrl.Finish()

	var (
		ctx                        = context.Background()
		defaultImageId      uint64 = 1
		defaultImageVersion        = "1.0.0"
		latestImageVersion         = "latest"
		curatedImageVersion        = &models.ImageVersion{
			Id:                2,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Ready,
			StateDetails:      "enabled",
			Enabled:           true,
		}
	)

	t.Run("fail to resolve latest image version", func(t *testing.T) {
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), defaultImageId).Times(1).Return(nil, fmt.Errorf("test-error"))

		res, err := h.getExactImageVersion(ctx, defaultImageId, latestImageVersion)

		assert.ErrorContains(t, err, "failed to get latest image version: test-error")
		assert.Nil(t, res)
	})

	t.Run("latest image version is not found", func(t *testing.T) {
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), defaultImageId).Times(1).Return(nil, nil)

		res, err := h.getExactImageVersion(ctx, defaultImageId, latestImageVersion)

		assert.NoError(t, err)
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved latest version", func(t *testing.T) {
		mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), defaultImageId).Times(1).Return(curatedImageVersion, nil)

		res, err := h.getExactImageVersion(ctx, defaultImageId, latestImageVersion)

		assert.NoError(t, err)
		assert.Equal(t, curatedImageVersion.Id, res.Id)
	})

	t.Run("fail to get specific image version", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), defaultImageId, defaultImageVersion).Times(1).Return(nil, fmt.Errorf("test-error"))

		res, err := h.getExactImageVersion(ctx, defaultImageId, defaultImageVersion)

		assert.ErrorContains(t, err, "failed to get specific image version: test-error")
		assert.Nil(t, res)
	})

	t.Run("specific image version is not found", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), defaultImageId, defaultImageVersion).Times(1).Return(nil, nil)

		res, err := h.getExactImageVersion(ctx, defaultImageId, defaultImageVersion)

		assert.NoError(t, err)
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved specific image version", func(t *testing.T) {
		mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), defaultImageId, defaultImageVersion).Times(1).Return(curatedImageVersion, nil)

		res, err := h.getExactImageVersion(ctx, defaultImageId, defaultImageVersion)

		assert.NoError(t, err)
		assert.Equal(t, curatedImageVersion.Id, res.Id)
	})
}
