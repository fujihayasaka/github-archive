package twirp

import (
	"context"
	"fmt"
	"testing"
	"time"

	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"go.uber.org/mock/gomock"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
)

func TestImageManagementServer_GetCuratedImageVersion(t *testing.T) {
	var (
		ctx                 = context.Background()
		sizeGB              = int32(10)
		imageOwner          = &sharedapi.Actor{GlobalId: "github"}
		curatedImageVersion = models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
			SizeGB:            &sizeGB,
		}
		curatedImageDefinition = models.ImageDefinition{
			Id:        1,
			OwnerId:   models.GithubOwnerId,
			ImageType: models.ImageType_Curated,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
			Enabled:   true,
		}
		customerImageVersion = models.ImageVersion{
			Id:                2,
			Version:           "1.0.0",
			ImageDefinitionId: 3,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
			SizeGB:            &sizeGB,
		}
		customerImageDefinition = models.ImageDefinition{
			Id:        3,
			OwnerId:   "test",
			ImageType: models.ImageType_Customer,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
			Enabled:   true,
		}
	)

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageDefinition.Id, curatedImageVersion.Version).Times(0),
		)

		req := imagesapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error internal: failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version because image is not curated", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), customerImageDefinition.Id, customerImageVersion.Version).Times(0),
		)

		req := imagesapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version because db failed", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageDefinition.Id, curatedImageVersion.Version).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error internal: failed to get image version")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version because version is disabled", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		disabledImageVersion := models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Provisioning,
			Enabled:           false,
			SizeGB:            &sizeGB,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageDefinition.Id, disabledImageVersion.Version).Times(1).Return(&disabledImageVersion, nil),
		)

		req := imagesapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           disabledImageVersion.Version,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image version is not found")
		assert.Nil(t, res)
	})

	t.Run("successfully retrieve image version", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageDefinition.Id, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
		)

		req := imagesapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, curatedImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, curatedImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersion.State)
		assert.Equal(t, *curatedImageVersion.SizeGB, res.ImageVersion.SizeGb)
	})

	t.Run("successfully retrieve image version with null SizeGB", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		nullSizeGBCuratedImageVersion := models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Provisioning,
			Enabled:           true,
			SizeGB:            nil,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageDefinition.Id, nullSizeGBCuratedImageVersion.Version).Times(1).Return(&nullSizeGBCuratedImageVersion, nil),
		)

		req := imagesapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           nullSizeGBCuratedImageVersion.Version,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, nullSizeGBCuratedImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, nullSizeGBCuratedImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Provisioning, res.ImageVersion.State)
		assert.Equal(t, int32(0), res.ImageVersion.SizeGb)
	})
}

func TestImageManagementServer_ListCuratedImageVersions(t *testing.T) {
	var (
		ctx                    = context.Background()
		sizeGB                 = int32(10)
		imageOwner             = &sharedapi.Actor{GlobalId: "github"}
		curatedImageDefinition = models.ImageDefinition{
			Id:        1,
			OwnerId:   models.GithubOwnerId,
			ImageType: models.ImageType_Curated,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
			Enabled:   true,
		}
		customerImageDefinition = models.ImageDefinition{
			Id:        3,
			OwnerId:   "test",
			ImageType: models.ImageType_Customer,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
			Enabled:   true,
		}
		curatedImageVersions = []*models.ImageVersion{
			{
				Id:                2,
				Version:           "1.0.2",
				ImageDefinitionId: 1,
				State:             models.ImageVersionState_Provisioning,
				Enabled:           true,
				SizeGB:            &sizeGB,
			},
			{
				Id:                3,
				Version:           "1.0.1",
				ImageDefinitionId: 1,
				State:             models.ImageVersionState_Provisioning,
				Enabled:           true,
				SizeGB:            &sizeGB,
			},
			{
				Id:                4,
				Version:           "1.0.0",
				ImageDefinitionId: 1,
				State:             models.ImageVersionState_Provisioning,
				Enabled:           false,
				SizeGB:            &sizeGB,
			},
		}
	)

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Owner:             imageOwner,
		}

		res, err := s.ListCuratedImageVersions(ctx, &req)

		assert.ErrorContains(t, err, "twirp error internal: failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions because type is not curated", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(0),
		)

		req := imagesapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: customerImageDefinition.Id,
			Owner:             imageOwner,
		}

		res, err := s.ListCuratedImageVersions(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		disabledCuratedImageDefinition := models.ImageDefinition{
			Id:        2,
			OwnerId:   models.GithubOwnerId,
			ImageType: models.ImageType_Curated,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
			Enabled:   false,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), disabledCuratedImageDefinition.Id).Times(1).Return(&disabledCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(0),
		)

		req := imagesapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: disabledCuratedImageDefinition.Id,
			Owner:             imageOwner,
		}

		res, err := s.ListCuratedImageVersions(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		res, err := s.ListCuratedImageVersions(ctx, &imagesapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Owner:             imageOwner,
		})

		assert.ErrorContains(t, err, "twirp error internal: failed to list image versions")
		assert.Nil(t, res)
	})

	t.Run("successfully to list curated image versions excluded disabled versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(curatedImageVersions, nil),
		)

		req := imagesapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Owner:             imageOwner,
		}

		res, err := s.ListCuratedImageVersions(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, 2, len(res.ImageVersions))

		assert.Equal(t, curatedImageVersions[0].ImageDefinitionId, res.ImageVersions[0].ImageDefinitionId)
		assert.Equal(t, curatedImageVersions[0].Version, res.ImageVersions[0].Version)
		assert.Equal(t, sharedapi.ImageVersionState_Provisioning, res.ImageVersions[0].State)
		assert.Equal(t, sizeGB, res.ImageVersions[0].SizeGb)

		assert.Equal(t, curatedImageVersions[1].ImageDefinitionId, res.ImageVersions[1].ImageDefinitionId)
		assert.Equal(t, curatedImageVersions[1].Version, res.ImageVersions[1].Version)
		assert.Equal(t, sharedapi.ImageVersionState_Provisioning, res.ImageVersions[1].State)
		assert.Equal(t, sizeGB, res.ImageVersions[1].SizeGb)
	})
}

func TestImageManagementServer_GetCuratedImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	imageOwner := &sharedapi.Actor{GlobalId: "github"}

	var (
		ctx                    = context.Background()
		sizeGB                 = int32(10)
		curatedImageDefinition = models.ImageDefinition{
			Id:                         1,
			OwnerId:                    models.GithubOwnerId,
			ImageType:                  models.ImageType_Curated,
			Name:                       "test-image",
			OsType:                     models.OsType_Linux,
			Architecture:               models.Architecture_X64,
			CreatedAt:                  fixedTime,
			UpdatedAt:                  &fixedTime,
			Enabled:                    true,
			State:                      models.ImageDefinitionState_Ready,
			IsImageGenerationSupported: true,
		}
		curatedImageVersion = models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
			SizeGB:            &sizeGB,
		}
	)

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "twirp error internal: failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve latest image version", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "twirp error internal: failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageVersion, nil),
		)

		req := imagesapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Owner:             imageOwner,
		}

		res, err := s.GetCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.Equal(t, curatedImageDefinition.Id, res.ImageDefinition.Id)
		assert.True(t, res.ImageDefinition.IsImageGenerationSupported)
	})
}

func TestImageManagementServer_ListCuratedImageDefinitions(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                     = context.Background()
		imageOwner              = &sharedapi.Actor{GlobalId: "github"}
		curatedImageDefinitions = []*models.ImageDefinition{
			{
				Id:                         1,
				OwnerId:                    models.GithubOwnerId,
				ImageType:                  models.ImageType_Curated,
				Name:                       "test-image",
				OsType:                     models.OsType_Linux,
				Enabled:                    true,
				Architecture:               models.Architecture_X64,
				CreatedAt:                  fixedTime,
				UpdatedAt:                  &fixedTime,
				State:                      models.ImageDefinitionState_Ready,
				IsImageGenerationSupported: true,
			},
			{
				Id:                         2,
				OwnerId:                    models.GithubOwnerId,
				ImageType:                  models.ImageType_Curated,
				Name:                       "test-image2",
				OsType:                     models.OsType_Linux,
				Enabled:                    false,
				Architecture:               models.Architecture_X64,
				CreatedAt:                  fixedTime,
				UpdatedAt:                  &fixedTime,
				State:                      models.ImageDefinitionState_Ready,
				IsImageGenerationSupported: false,
			},
			{
				Id:           3,
				OwnerId:      models.GithubOwnerId,
				ImageType:    models.ImageType_Curated,
				Name:         "test-image3",
				OsType:       models.OsType_MacOS,
				Architecture: models.Architecture_X64,
				Enabled:      true,
				State:        models.ImageDefinitionState_Ready,
			},
			{
				Id:           4,
				OwnerId:      models.AzureDevOpsOwnerId,
				ImageType:    models.ImageType_Curated,
				Name:         "test-image4",
				OsType:       models.OsType_Linux,
				Architecture: models.Architecture_X64,
				Enabled:      true,
				State:        models.ImageDefinitionState_Ready,
			},
		}
		latestImageVersions = map[uint64]*models.ImageVersion{
			1: {Id: 1, Version: "1.0.0", ImageDefinitionId: 1},
			2: {Id: 2, Version: "1.0.0", ImageDefinitionId: 2},
		}
	)

	t.Run("failed to list image definitions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(nil, fmt.Errorf("test")),
		)

		res, err := s.ListCuratedImageDefinitions(ctx, &imagesapi.ListCuratedImageDefinitionsRequest{})

		assert.ErrorContains(t, err, "twirp error internal: failed to list image definitions")
		assert.Nil(t, res)
	})

	t.Run("failed to get latest image versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().GetLatestImageVersionsForImageDefinitions(gomock.Any(), []uint64{1, 2}).Return(nil, fmt.Errorf("test")),
		)
		res, err := s.ListCuratedImageDefinitions(ctx, &imagesapi.ListCuratedImageDefinitionsRequest{})

		assert.ErrorContains(t, err, "twirp error internal: failed to list image definitions")
		assert.Nil(t, res)
	})

	t.Run("successfully list curated image definitions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().GetLatestImageVersionsForImageDefinitions(gomock.Any(), []uint64{1, 2}).Times(1).Return(latestImageVersions, nil),
		)

		res, err := s.ListCuratedImageDefinitions(ctx, &imagesapi.ListCuratedImageDefinitionsRequest{Owner: imageOwner})

		assert.NoError(t, err)
		assert.Equal(t, 1, len(res.ImageDefinitions))

		for i, definition := range res.ImageDefinitions {
			assert.Equal(t, curatedImageDefinitions[i].Id, definition.Id)
			assert.Equal(t, curatedImageDefinitions[i].Name, definition.Name)
			assert.Equal(t, sharedapi.Architecture_X64, definition.Architecture)
			assert.Equal(t, curatedImageDefinitions[i].IsImageGenerationSupported, definition.IsImageGenerationSupported)
		}
	})

	t.Run("successfully to list curated image definitions include disabled true", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().GetLatestImageVersionsForImageDefinitions(gomock.Any(), []uint64{1, 2}).Times(1).Return(latestImageVersions, nil),
		)

		res, err := s.ListCuratedImageDefinitions(ctx, &imagesapi.ListCuratedImageDefinitionsRequest{IncludeDisabled: true, Owner: imageOwner})

		assert.NoError(t, err)
		assert.Equal(t, 2, len(res.ImageDefinitions))

		for i, definition := range res.ImageDefinitions {
			assert.Equal(t, curatedImageDefinitions[i].Id, definition.Id)
			assert.Equal(t, curatedImageDefinitions[i].Name, definition.Name)
			assert.Equal(t, sharedapi.Architecture_X64, definition.Architecture)
			assert.Equal(t, curatedImageDefinitions[i].IsImageGenerationSupported, definition.IsImageGenerationSupported)
		}
	})

	t.Run("successfully to list curated image definitions include disabled false", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().GetLatestImageVersionsForImageDefinitions(gomock.Any(), []uint64{1, 2}).Times(1).Return(latestImageVersions, nil),
		)

		res, err := s.ListCuratedImageDefinitions(ctx, &imagesapi.ListCuratedImageDefinitionsRequest{IncludeDisabled: false, Owner: imageOwner})

		assert.NoError(t, err)
		assert.Equal(t, 1, len(res.ImageDefinitions))

		for i, definition := range res.ImageDefinitions {
			assert.Equal(t, curatedImageDefinitions[i].Id, definition.Id)
			assert.Equal(t, curatedImageDefinitions[i].Name, definition.Name)
			assert.Equal(t, sharedapi.Architecture_X64, definition.Architecture)
			assert.Equal(t, curatedImageDefinitions[i].IsImageGenerationSupported, definition.IsImageGenerationSupported)
		}
	})
}

func TestImageManagementServer_Curated_ProtoValidate(t *testing.T) {
	testCases := []requestValidationTestCase{
		{
			requestName: "ListCuratedImageDefinitions",
			testName:    "Missing fields",
			request:     &imagesapi.ListCuratedImageDefinitionsRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]",
		},
		{
			requestName: "ListCuratedImageDefinitions",
			testName:    "Valid request",
			request: &imagesapi.ListCuratedImageDefinitionsRequest{
				Owner:           &sharedapi.Actor{GlobalId: "user1"},
				IncludeDisabled: false,
			},
			expectedError: "",
		},
		{
			requestName: "GetCuratedImageDefinition",
			testName:    "Missing fields",
			request:     &imagesapi.GetCuratedImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]",
		},
		{
			requestName: "GetCuratedImageDefinition",
			testName:    "Valid request",
			request: &imagesapi.GetCuratedImageDefinitionRequest{
				ImageDefinitionId: 8,
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
			},
			expectedError: "",
		},
		{
			requestName: "ListCuratedImageVersions",
			testName:    "Missing fields",
			request:     &imagesapi.ListCuratedImageVersionsRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]",
		},
		{
			requestName: "ListCuratedImageVersions",
			testName:    "Valid request",
			request: &imagesapi.ListCuratedImageVersionsRequest{
				ImageDefinitionId: 8,
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
			},
			expectedError: "",
		},
		{
			requestName: "GetCuratedImageVersion",
			testName:    "Missing fields",
			request:     &imagesapi.GetCuratedImageVersionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]\n" +
				" - version: value is required [required]",
		},
		{
			requestName: "GetCuratedImageVersion",
			testName:    "Invalid version format",
			request: &imagesapi.GetCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "a.bc",
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
			},
			expectedError: "twirp error invalid_argument: validation error:\n - version: value does not match regex pattern `^\\d+\\.\\d+\\.\\d+$` [string.pattern]",
		},
		{
			requestName: "GetCuratedImageVersion",
			testName:    "Valid request",
			request: &imagesapi.GetCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
			},
			expectedError: "",
		},
	}

	for _, test := range testCases {
		testProtoValidate(t, test)
	}
}
