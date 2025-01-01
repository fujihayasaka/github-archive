package twirp

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/hosted-compute-ims/gen/ent"
	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/twitchtv/twirp"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
)

func TestImagesAdminApiHandler_CreateCuratedImageDefinitionPointer(t *testing.T) {
	ctx := context.Background()

	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	protoTimestamp := timestamppb.New(fixedTime)
	pointer := uint64(1)
	featureFlag := "test-feature-flag"

	imageDefinition := &models.ImageDefinition{
		OwnerId:                   "github",
		Name:                      "test-image",
		ImageType:                 models.ImageType_Curated,
		Enabled:                   true,
		OsType:                    models.OsType_Linux,
		Architecture:              models.Architecture_X64,
		PointsToImageDefinitionId: &pointer,
		FeatureFlag:               &featureFlag,
	}

	existedImageDefinition := &models.ImageDefinition{
		Id:           1,
		OwnerId:      "github",
		Name:         "test-image",
		ImageType:    models.ImageType_Curated,
		Enabled:      true,
		OsType:       models.OsType_Linux,
		Architecture: models.Architecture_X64,
		CreatedAt:    fixedTime,
		UpdatedAt:    &fixedTime,
	}

	createdLatestImageDefinition := &models.ImageDefinition{
		Id:                        3,
		OwnerId:                   "github",
		Name:                      "test-image",
		ImageType:                 models.ImageType_Curated,
		Enabled:                   true,
		OsType:                    models.OsType_Linux,
		Architecture:              models.Architecture_X64,
		PointsToImageDefinitionId: &pointer,
		CreatedAt:                 fixedTime,
		UpdatedAt:                 &fixedTime,
		FeatureFlag:               &featureFlag,
	}

	t.Run("failed to create curated image definition pointer because of db error", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			// Get
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, uint64(1)).Times(1).Return(existedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(0), fmt.Errorf("test")),
		)

		req := adminapi.CreateCuratedImageDefinitionPointerRequest{
			Name:                      "test-image",
			Enabled:                   true,
			PointsToImageDefinitionId: pointer,
			FeatureFlag:               featureFlag,
		}

		res, err := s.CreateCuratedImageDefinitionPointer(ctx, &req)

		assert.EqualError(t, err, twirp.InternalError("failed to create new image definition pointer").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create image definition pointer because already exists", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, uint64(1)).Times(1).Return(existedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(0), &ent.ConstraintError{}),
		)

		req := adminapi.CreateCuratedImageDefinitionPointerRequest{
			Name:                      "test-image",
			Enabled:                   true,
			PointsToImageDefinitionId: pointer,
			FeatureFlag:               featureFlag,
		}

		_, err := s.CreateCuratedImageDefinitionPointer(ctx, &req)

		assert.ErrorContains(t, err, "image definition with this name already exists")
	})

	t.Run("successfully create image definition pointer", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, uint64(1)).Times(1).Return(existedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(3), nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, uint64(3)).Times(1).Return(createdLatestImageDefinition, nil),
		)

		req := adminapi.CreateCuratedImageDefinitionPointerRequest{
			Name:                      "test-image",
			Enabled:                   true,
			PointsToImageDefinitionId: pointer,
			FeatureFlag:               featureFlag,
		}

		res, err := s.CreateCuratedImageDefinitionPointer(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.NotNil(t, res.ImageDefinition)
		assert.Equal(t, uint64(3), res.ImageDefinition.Id)
		assert.Equal(t, imageDefinition.Name, res.ImageDefinition.Name)
		assert.Equal(t, sharedapi.Architecture_X64, res.ImageDefinition.Architecture)
		assert.Equal(t, sharedapi.OsType_Linux, res.ImageDefinition.OsType)
		assert.Equal(t, true, res.ImageDefinition.Enabled)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.CreatedAt)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.UpdatedAt)
		assert.Equal(t, featureFlag, res.ImageDefinition.FeatureFlag)
	})
}

func TestImagesAdminApiHandler_UpdateCuratedImageDefinitionPointer(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	existedPointer := uint64(1)
	newPointer := uint64(3)
	featureFlag := "test-feature-flag"

	var (
		ctx                = context.Background()
		newImageDefinition = models.ImageDefinition{
			Id:           3,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image-1",
			Enabled:      false,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}
		existedLatestImageDefinition = models.ImageDefinition{
			Id:                        2,
			OwnerId:                   models.GithubOwnerId,
			ImageType:                 models.ImageType_Curated,
			Name:                      "test-image-1",
			Enabled:                   false,
			OsType:                    models.OsType_Linux,
			Architecture:              models.Architecture_X64,
			PointsToImageDefinitionId: &existedPointer,
			CreatedAt:                 fixedTime,
			UpdatedAt:                 &fixedTime,
			FeatureFlag:               &featureFlag,
		}
		newLatestImageDefinition = models.ImageDefinition{
			Id:                        2,
			OwnerId:                   models.GithubOwnerId,
			ImageType:                 models.ImageType_Curated,
			Name:                      "test-image-1",
			Enabled:                   false,
			OsType:                    models.OsType_Linux,
			Architecture:              models.Architecture_X64,
			PointsToImageDefinitionId: &newPointer,
			CreatedAt:                 fixedTime,
			UpdatedAt:                 &fixedTime,
			FeatureFlag:               &featureFlag,
		}
	)

	t.Run("fail rpc call when fail to retrieve image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, existedLatestImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		req := adminapi.UpdateCuratedImageDefinitionPointerRequest{
			ImageDefinitionId:         existedLatestImageDefinition.Id,
			Name:                      "new-name",
			Enabled:                   true,
			PointsToImageDefinitionId: newPointer,
			FeatureFlag:               featureFlag,
		}

		res, err := h.UpdateCuratedImageDefinitionPointer(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to update image definition pointer", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &models.ImageDefinitionUpdate{
			Name:                      "new-name",
			Enabled:                   true,
			PointsToImageDefinitionId: &newPointer,
			FeatureFlag:               &featureFlag,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, existedLatestImageDefinition.Id).Times(1).Return(&existedLatestImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, newPointer).Times(1).Return(&newImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, existedLatestImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(uint64(0), &ent.ConstraintError{}),
		)

		req := adminapi.UpdateCuratedImageDefinitionPointerRequest{
			ImageDefinitionId:         existedLatestImageDefinition.Id,
			Name:                      "new-name",
			Enabled:                   true,
			PointsToImageDefinitionId: newPointer,
			FeatureFlag:               featureFlag,
		}

		_, err := h.UpdateCuratedImageDefinitionPointer(ctx, &req)

		assert.ErrorContains(t, err, "image definition with this name already exists")
	})

	t.Run("successfully updated image definition pointer", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &models.ImageDefinitionUpdate{
			Name:                      "new-name",
			Enabled:                   true,
			PointsToImageDefinitionId: &newPointer,
			FeatureFlag:               &featureFlag,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, existedLatestImageDefinition.Id).Times(1).Return(&existedLatestImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, newPointer).Times(1).Return(&newImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, existedLatestImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(existedLatestImageDefinition.Id, nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, existedLatestImageDefinition.Id).Times(1).Return(&newLatestImageDefinition, nil),
		)

		req := adminapi.UpdateCuratedImageDefinitionPointerRequest{
			ImageDefinitionId:         existedLatestImageDefinition.Id,
			Name:                      "new-name",
			Enabled:                   true,
			PointsToImageDefinitionId: newPointer,
			FeatureFlag:               featureFlag,
		}

		res, err := h.UpdateCuratedImageDefinitionPointer(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})
}

func TestImagesAdminApiHandler_DeleteCuratedImageDefinitionPointer(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	pointer := uint64(6)

	var (
		ctx = context.Background()

		existedLatestImageDefinition = models.ImageDefinition{
			Id:                        1,
			OwnerId:                   models.GithubOwnerId,
			ImageType:                 models.ImageType_Curated,
			Name:                      "test-image",
			Enabled:                   true,
			OsType:                    models.OsType_Linux,
			Architecture:              models.Architecture_X64,
			PointsToImageDefinitionId: &pointer,
			CreatedAt:                 fixedTime,
			UpdatedAt:                 &fixedTime,
		}
	)

	t.Run("failed delete image definition when unable to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, existedLatestImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.DeleteCuratedImageDefinitionPointerRequest{
			ImageDefinitionId: existedLatestImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinitionPointer(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully delete image definition pointer", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, existedLatestImageDefinition.Id).Times(1).Return(&existedLatestImageDefinition, nil)
		mockImagesStore.EXPECT().DeleteImageDefinition(ctx, existedLatestImageDefinition.Id).Times(1).Return(nil)

		req := adminapi.DeleteCuratedImageDefinitionPointerRequest{
			ImageDefinitionId: existedLatestImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinitionPointer(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})
}

func TestImagesAdminApiHandler_Pointers_ProtoValidate(t *testing.T) {
	testCases := []requestValidationTestCase{
		{
			requestName: "CreateCuratedImageDefinitionPointer",
			testName:    "Missing fields",
			request:     &adminapi.CreateCuratedImageDefinitionPointerRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - name: value is required [required]\n" +
				" - points_to_image_definition_id: value is required [required]",
		},
		{
			requestName: "CreateCuratedImageDefinitionPointer",
			testName:    "Invalid name format",
			request: &adminapi.CreateCuratedImageDefinitionPointerRequest{
				Name:                      "invalid name!",
				Enabled:                   true,
				PointsToImageDefinitionId: 8,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - name: value does not match regex pattern `^[a-zA-Z0-9()._ -]{1,100}$` [string.pattern]",
		},
		{
			requestName: "CreateCuratedImageDefinitionPointer",
			testName:    "Valid request",
			request: &adminapi.CreateCuratedImageDefinitionPointerRequest{
				Name:                      "Ubuntu Latest (22.04)",
				Enabled:                   true,
				PointsToImageDefinitionId: 8,
			},
			expectedError: "",
		},
		{
			requestName: "CreateCuratedImageDefinitionPointer",
			testName:    "Valid request",
			request: &adminapi.CreateCuratedImageDefinitionPointerRequest{
				Name:                      "Ubuntu Latest (22.04)",
				Enabled:                   true,
				PointsToImageDefinitionId: 8,
			},
			expectedError: "",
		},
		{
			requestName: "UpdateCuratedImageDefinitionPointer",
			testName:    "Missing fields",
			request:     &adminapi.UpdateCuratedImageDefinitionPointerRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_definition_id: value is required [required]\n" +
				" - name: value is required [required]\n" +
				" - points_to_image_definition_id: value is required [required]",
		},
		{
			requestName: "UpdateCuratedImageDefinitionPointer",
			testName:    "Invalid name format",
			request: &adminapi.UpdateCuratedImageDefinitionPointerRequest{
				ImageDefinitionId:         3,
				Name:                      "invalid name!",
				Enabled:                   true,
				PointsToImageDefinitionId: 8,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - name: value does not match regex pattern `^[a-zA-Z0-9()._ -]{1,100}$` [string.pattern]",
		},
		{
			requestName: "DeleteCuratedImageDefinitionPointer",
			testName:    "Missing fields",
			request:     &adminapi.DeleteCuratedImageDefinitionPointerRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_definition_id: value is required [required]",
		},
		{
			requestName: "DeleteCuratedImageDefinitionPointer",
			testName:    "Valid request",
			request: &adminapi.DeleteCuratedImageDefinitionPointerRequest{
				ImageDefinitionId: 8,
			},
			expectedError: "",
		},
	}

	for _, test := range testCases {
		testProtoValidate(t, test)
	}
}
