package twirp

import (
	"context"
	"database/sql"
	"fmt"
	"testing"

	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"go.uber.org/mock/gomock"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
)

func TestInternalImageApiHandler_StartImageVersionGeneration(t *testing.T) {
	var (
		ctx             = context.Background()
		imageDefinition = models.ImageDefinition{
			Id:        1,
			OwnerId:   "test-owner",
			ImageType: models.ImageType_Customer,
		}
		imageVersion = models.ImageVersion{
			ImageDefinitionId: 1,
			Version:           "1.0.0",
			State:             models.ImageVersionState_Generating,
			Enabled:           true,
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}
		imageVersionsSummary = &models.ImageVersionsSummary{Count: 0, TotalImageVersionsSizeGB: 0}
		request              = &internalapi.StartImageVersionGenerationRequest{
			Owner:        &sharedapi.Actor{GlobalId: imageDefinition.OwnerId},
			ImageSource:  ImageSource_Customer,
			ImageId:      imageDefinition.Id,
			ImageVersion: "",
		}
	)

	t.Run("invalid owner", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		differentOwnerRequest := &internalapi.StartImageVersionGenerationRequest{
			Owner:        &sharedapi.Actor{GlobalId: "different-owner"},
			ImageSource:  ImageSource_Customer,
			ImageId:      imageDefinition.Id,
			ImageVersion: "",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
		)

		res, err := h.StartImageVersionGeneration(ctx, differentOwnerRequest)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "image definition is not found")
	})

	t.Run("failed to get image versions sumary", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), request.ImageId).Times(1).Return(nil, fmt.Errorf("test-error")),
		)

		res, err := h.StartImageVersionGeneration(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "failed to create image version")
	})

	t.Run("max image versions", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		versionsSummaryMaxImageVersions := &models.ImageVersionsSummary{Count: 100, TotalImageVersionsSizeGB: 0}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), request.ImageId).Times(1).Return(versionsSummaryMaxImageVersions, nil),
		)

		res, err := h.StartImageVersionGeneration(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "image definition already has maximum number of image versions")
	})

	t.Run("failed to list image versions", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), request.ImageId).Times(1).Return(imageVersionsSummary, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), request.ImageId).Times(1).Return(nil, fmt.Errorf("test-error")),
		)

		res, err := h.StartImageVersionGeneration(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "failed to auto-increment image version")
	})

	t.Run("failed to create image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), request.ImageId).Times(1).Return(imageVersionsSummary, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), request.ImageId).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().AddImageVersion(gomock.Any(), &imageVersion).Times(1).Return(uint64(0), fmt.Errorf("test-error")),
		)

		res, err := h.StartImageVersionGeneration(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "failed to create image version")
	})

	t.Run("failed to get created image version", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), request.ImageId).Times(1).Return(imageVersionsSummary, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), request.ImageId).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().AddImageVersion(gomock.Any(), &imageVersion).Times(1).Return(imageVersion.Id, nil),
			mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), imageVersion.Id).Return(nil, fmt.Errorf("test")),
		)

		res, err := h.StartImageVersionGeneration(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "failed to get newly created image version")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), request.ImageId).Times(1).Return(imageVersionsSummary, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), request.ImageId).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().AddImageVersion(gomock.Any(), &imageVersion).Times(1).Return(imageVersion.Id, nil),
			mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), imageVersion.Id).Return(&imageVersion, nil),
		)

		res, err := h.StartImageVersionGeneration(ctx, request)

		assert.Nil(t, err)
		assert.NotNil(t, res)
	})
}

func TestInternalImageApiHandler_UpdateImageVersionGenerationStatus(t *testing.T) {
	var (
		ctx             = context.Background()
		imageDefinition = models.ImageDefinition{
			Id:        1,
			OwnerId:   "test-owner",
			ImageType: models.ImageType_Customer,
		}
		imageVersion = models.ImageVersion{
			Id:                1,
			ImageDefinitionId: imageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_Generating,
			Enabled:           true,
		}
		request = &internalapi.UpdateImageVersionGenerationStatusRequest{
			Owner:        &sharedapi.Actor{GlobalId: imageDefinition.OwnerId},
			ImageSource:  ImageSource_Customer,
			ImageId:      imageDefinition.Id,
			ImageVersion: "1.0.0",
			StateDetails: "test-status",
		}
	)

	t.Run("invalid owner", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		differentOwnerRequest := &internalapi.UpdateImageVersionGenerationStatusRequest{
			Owner:        &sharedapi.Actor{GlobalId: "different-owner"},
			ImageSource:  ImageSource_Customer,
			ImageId:      imageDefinition.Id,
			ImageVersion: "1.0.0",
			StateDetails: "test-status",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
		)

		res, err := h.UpdateImageVersionGenerationStatus(ctx, differentOwnerRequest)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "image definition is not found")
	})

	t.Run("version not found", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), request.ImageId, request.ImageVersion).Times(1).Return(nil, sql.ErrNoRows),
		)

		res, err := h.UpdateImageVersionGenerationStatus(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "image version is not found")
	})

	t.Run("failed to update state details", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		proFailedimageVersion := models.ImageVersion{
			Id:                1,
			ImageDefinitionId: imageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_ProvisionFailed,
			Enabled:           true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), request.ImageId, request.ImageVersion).Times(1).Return(&proFailedimageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionStateDetailsForState(gomock.Any(), proFailedimageVersion.Id, models.ImageVersionState_Generating, request.StateDetails).Times(1).Return(fmt.Errorf("failed to update image version state details: %w", sql.ErrNoRows)),
		)

		res, err := h.UpdateImageVersionGenerationStatus(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "failed to update image version status")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, h := setupInternalImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), request.ImageId, request.ImageVersion).Times(1).Return(&imageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionStateDetailsForState(gomock.Any(), imageVersion.Id, models.ImageVersionState_Generating, request.StateDetails).Times(1).Return(nil),
		)

		res, err := h.UpdateImageVersionGenerationStatus(ctx, request)

		assert.Nil(t, err)
		assert.NotNil(t, res)
	})
}

func TestInternalImageApiHandler_FinishImageVersionGeneration(t *testing.T) {
	ctrl, h := setupInternalImagesApiHandler(t)
	defer ctrl.Finish()

	var (
		ctx             = context.Background()
		imageDefinition = models.ImageDefinition{
			Id:        1,
			OwnerId:   "test-owner",
			ImageType: models.ImageType_Customer,
		}
		preImageVersion = models.ImageVersion{
			Id:                1,
			ImageDefinitionId: imageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_Generating,
			StateDetails:      "test-status",
			Enabled:           true,
		}
		postImageVersion = models.ImageVersion{
			Id:                1,
			ImageDefinitionId: imageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_Pending,
			StateDetails:      "",
			Enabled:           true,
		}
		request = &internalapi.FinishImageVersionGenerationRequest{
			Owner:           &sharedapi.Actor{GlobalId: imageDefinition.OwnerId},
			ImageSource:     ImageSource_Customer,
			ImageId:         imageDefinition.Id,
			ImageVersion:    "1.0.0",
			Success:         true,
			SourceVhdUrl:    "test-source-vhd-url",
			WorkflowOwnerId: "test-workflow-owner-id",
		}
	)

	t.Run("invalid owner", func(t *testing.T) {
		differentOwnerRequest := &internalapi.FinishImageVersionGenerationRequest{
			Owner:           &sharedapi.Actor{GlobalId: "different-owner"},
			ImageSource:     ImageSource_Customer,
			ImageId:         imageDefinition.Id,
			ImageVersion:    "1.0.0",
			Success:         true,
			SourceVhdUrl:    "test-source-vhd-url",
			WorkflowOwnerId: "test-workflow-owner-id",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
		)

		res, err := h.FinishImageVersionGeneration(ctx, differentOwnerRequest)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "image definition is not found")
	})

	t.Run("version not found", func(t *testing.T) {
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), request.ImageId, request.ImageVersion).Times(1).Return(nil, sql.ErrNoRows),
		)

		res, err := h.FinishImageVersionGeneration(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "image version is not found")
	})

	t.Run("failed to update state", func(t *testing.T) {
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), request.ImageId, request.ImageVersion).Times(1).Return(&preImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), preImageVersion.Id, models.ImageVersionState_Pending, "").Times(1).Return(fmt.Errorf("test-error")),
		)

		res, err := h.FinishImageVersionGeneration(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "failed to finish image version generation")
	})

	t.Run("failed to queue job", func(t *testing.T) {
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), request.ImageId, request.ImageVersion).Times(1).Return(&preImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), preImageVersion.Id, models.ImageVersionState_Pending, "").Times(1).Return(nil),
			mockPromotionStartClient.EXPECT().StartAsyncImageVersionProvision(gomock.Any(), postImageVersion.Id, request.SourceVhdUrl, request.WorkflowOwnerId).Times(1).Return(fmt.Errorf("test-error")),
		)

		res, err := h.FinishImageVersionGeneration(ctx, request)

		assert.Nil(t, res)
		assert.NotNil(t, err)
		assert.ErrorContains(t, err, "failed to start image version provision")
	})

	t.Run("success", func(t *testing.T) {
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), request.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), request.ImageId, request.ImageVersion).Times(1).Return(&preImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), preImageVersion.Id, models.ImageVersionState_Pending, "").Times(1).Return(nil),
			mockPromotionStartClient.EXPECT().StartAsyncImageVersionProvision(gomock.Any(), postImageVersion.Id, request.SourceVhdUrl, request.WorkflowOwnerId).Times(1).Return(nil),
		)

		res, err := h.FinishImageVersionGeneration(ctx, request)

		assert.Nil(t, err)
		assert.NotNil(t, res)
	})

	t.Run("not success", func(t *testing.T) {
		requestFailed := &internalapi.FinishImageVersionGenerationRequest{
			Owner:           &sharedapi.Actor{GlobalId: imageDefinition.OwnerId},
			ImageSource:     ImageSource_Customer,
			ImageId:         imageDefinition.Id,
			ImageVersion:    "1.0.0",
			Success:         false,
			SourceVhdUrl:    "test-source-vhd-url",
			WorkflowOwnerId: "test-workflow-owner-id",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), requestFailed.ImageId).Times(1).Return(&imageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), requestFailed.ImageId, requestFailed.ImageVersion).Times(1).Return(&preImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(gomock.Any(), preImageVersion.Id, models.ImageVersionState_ProvisionFailed, "").Times(1).Return(nil),
		)

		res, err := h.FinishImageVersionGeneration(ctx, requestFailed)

		assert.Nil(t, err)
		assert.NotNil(t, res)
	})
}

func TestInternalImageApiHandler_ImageGeneration_ProtoValidate(t *testing.T) {
	imageOwner := &sharedapi.Actor{GlobalId: "github"}
	sourceVhdUrl := "https://test.blob.core.windows.net/test/test.vhd"

	testCases := []requestValidationTestCase{
		{
			requestName: "StartImageVersionGeneration",
			testName:    "Missing fields",
			request:     &internalapi.StartImageVersionGenerationRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_source: value is required [required]\n" +
				" - image_id: value is required [required]",
		},
		{
			requestName: "StartImageVersionGeneration",
			testName:    "Invalid azure plan",
			request: &internalapi.StartImageVersionGenerationRequest{
				Owner:             imageOwner,
				ImageSource:       "Curated",
				ImageId:           1,
				ImageVersion:      "1.0.0",
				AzurePurchasePlan: "invalid azure purchase plan",
			},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - azure_purchase_plan: value does not match regex pattern `^([a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+)?$` [string.pattern]",
		},
		{
			requestName: "StartImageVersionGeneration",
			testName:    "Invalid version format",
			request: &internalapi.StartImageVersionGenerationRequest{
				Owner:        imageOwner,
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "aa.bb.cc",
			},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_version: value does not match regex pattern `^(\\d+\\.(\\d+|\\*)(|\\.(\\d+|\\*)))?$` [string.pattern]",
		},
		{
			requestName: "StartImageVersionGeneration",
			testName:    "Valid request with actual name",
			request: &internalapi.StartImageVersionGenerationRequest{
				Owner:             imageOwner,
				ImageSource:       "Curated",
				ImageId:           1,
				ImageVersion:      "1.0.0",
				AzurePurchasePlan: "arm:github_arm_windows11_runner:gh-windows-plan",
			},
			expectedError: "",
		},
		{
			requestName: "StartImageVersionGeneration",
			testName:    "Valid request",
			request: &internalapi.StartImageVersionGenerationRequest{
				Owner:        imageOwner,
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "1.0.0",
			},
			expectedError: "",
		},
		{
			requestName: "StartImageVersionGeneration",
			testName:    "Valid request with version with wildcards",
			request: &internalapi.StartImageVersionGenerationRequest{
				Owner:        imageOwner,
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "1.*.*",
			},
			expectedError: "",
		},
		{
			requestName: "StartImageVersionGeneration",
			testName:    "Valid request with azure plan, agent user and vm generation",
			request: &internalapi.StartImageVersionGenerationRequest{
				Owner:             imageOwner,
				ImageSource:       "Curated",
				ImageId:           1,
				ImageVersion:      "1.0.0",
				AzurePurchasePlan: "Plan1:Plan2:Plan3",
				AgentUser:         "runner",
				VmGeneration:      sharedapi.VmGeneration_Gen2,
			},
			expectedError: "",
		},
		{
			requestName: "UpdateImageVersionGenerationStatus",
			testName:    "Missing fields",
			request:     &internalapi.UpdateImageVersionGenerationStatusRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_source: value is required [required]\n" +
				" - image_id: value is required [required]\n" +
				" - image_version: value is required [required]\n" +
				" - state_details: value is required [required]",
		},
		{
			requestName: "UpdateImageVersionGenerationStatus",
			testName:    "Invalid image version format",
			request: &internalapi.UpdateImageVersionGenerationStatusRequest{
				Owner:        imageOwner,
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "1.*.*",
				StateDetails: "update",
			},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_version: value does not match regex pattern `^\\d+\\.\\d+\\.\\d+$` [string.pattern]",
		},
		{
			requestName: "UpdateImageVersionGenerationStatus",
			testName:    "Valid request",
			request: &internalapi.UpdateImageVersionGenerationStatusRequest{
				Owner:        imageOwner,
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "1.0.0",
				StateDetails: "update",
			},
			expectedError: "",
		},
		{
			requestName: "FinishImageVersionGeneration",
			testName:    "Missing fields",
			request:     &internalapi.FinishImageVersionGenerationRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_source: value is required [required]\n" +
				" - image_id: value is required [required]\n" +
				" - image_version: value is required [required]\n" +
				" - source_vhd_url: value is required [required]",
		},
		{
			requestName: "FinishImageVersionGeneration",
			testName:    "Invalid image version format",
			request: &internalapi.FinishImageVersionGenerationRequest{
				Owner:        imageOwner,
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "1.*.*",
				Success:      true,
				SourceVhdUrl: sourceVhdUrl,
			},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_version: value does not match regex pattern `^\\d+\\.\\d+\\.\\d+$` [string.pattern]",
		},
		{
			requestName: "FinishImageVersionGeneration",
			testName:    "Invalid source vhd url",
			request: &internalapi.FinishImageVersionGenerationRequest{
				Owner:        imageOwner,
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "1.0.0",
				Success:      true,
				SourceVhdUrl: "invalidurl",
			},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - source_vhd_url: value must be a valid URI [string.uri]",
		},
		{
			requestName: "FinishImageVersionGeneration",
			testName:    "Valid request",
			request: &internalapi.FinishImageVersionGenerationRequest{
				Owner:        imageOwner,
				ImageSource:  "Curated",
				ImageId:      1,
				ImageVersion: "1.0.0",
				Success:      true,
				SourceVhdUrl: sourceVhdUrl,
			},
			expectedError: "",
		},
	}

	for _, test := range testCases {
		testProtoValidate(t, test)
	}
}
