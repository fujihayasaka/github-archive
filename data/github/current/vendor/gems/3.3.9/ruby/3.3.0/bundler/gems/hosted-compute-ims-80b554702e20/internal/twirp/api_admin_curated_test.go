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

func TestImagesAdminApiHandler_GetImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                    = context.Background()
		curatedImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}

		customerImageDefinition = models.ImageDefinition{
			Id:           2,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Customer,
			Name:         "test-image",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}

		invalidOsTypeSqlData = models.ImageDefinition{
			Id:           3,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image",
			Enabled:      true,
			OsType:       "invalid",
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}
	)

	t.Run("failed to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image definition invalid image type error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image definition mapping error on os type", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, invalidOsTypeSqlData.Id).Times(1).Return(&invalidOsTypeSqlData, nil)

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: invalidOsTypeSqlData.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to map image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil)

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.Equal(t, curatedImageDefinition.Id, res.ImageDefinition.Id)
	})
}

func TestImagesAdminApiHandler_GetImageVersion(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	sizeGB := int32(10)

	var (
		ctx                    = context.Background()
		curatedImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}

		customerImageDefinition = models.ImageDefinition{
			Id:           2,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Customer,
			Name:         "test-image",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}

		curatedImageVersion = models.ImageVersion{
			Id:                3,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Ready,
			StateDetails:      "",
			SizeGB:            &sizeGB,
			Enabled:           true,
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
		}
	)

	t.Run("failed to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		req := adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.GetCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image definition invalid image type error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

		req := adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.GetCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageDefinition.Id, "bad-version").Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           "bad-version",
		}

		res, err := h.GetCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image version").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version mapping error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		badVersion := models.ImageVersion{
			Id:                5,
			Version:           "1.0.6",
			ImageDefinitionId: 1,
			State:             "invalid",
			StateDetails:      "",
			SizeGB:            &sizeGB,
			Enabled:           true,
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
		}
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageDefinition.Id, badVersion.Version).Times(1).Return(&badVersion, nil),
		)

		req := adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           badVersion.Version,
		}

		res, err := h.GetCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to map image version").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageDefinition.Id, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
		)

		req := adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.GetCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.Equal(t, curatedImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, curatedImageVersion.Version, res.ImageVersion.Version)
	})

	t.Run("successfully retrieve image version with ResourceId", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		macOsCuratedImageDefinition := models.ImageDefinition{
			Id:        3,
			OwnerId:   models.GithubOwnerId,
			ImageType: models.ImageType_Curated,
			Name:      "macos-test-image",
			OsType:    models.OsType_MacOS,
			Enabled:   true,
		}

		macOsCuratedImageVersion := models.ImageVersion{
			Id:                3,
			Version:           "0000.0101.1",
			ImageDefinitionId: 3,
			State:             models.ImageVersionState_Pending,
			ResourceId:        "os://f986c249-d5db-424a-a0a7-7a64345d21b4",
			Enabled:           true,
			SizeGB:            &sizeGB,
			StateDetails:      "",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, macOsCuratedImageDefinition.Id).Times(1).Return(&macOsCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, macOsCuratedImageDefinition.Id, macOsCuratedImageVersion.Version).Times(1).Return(&macOsCuratedImageVersion, nil),
		)

		req := adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: macOsCuratedImageDefinition.Id,
			Version:           macOsCuratedImageVersion.Version,
		}

		res, err := h.GetCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, macOsCuratedImageDefinition.Id, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, macOsCuratedImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersion.State)
		assert.Equal(t, *macOsCuratedImageVersion.SizeGB, res.ImageVersion.SizeGb)
		assert.Equal(t, macOsCuratedImageVersion.ResourceId, res.ImageVersion.ResourceId)
	})
}

func TestImagesAdminApiHandler_ListImageDefinitions(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                     = context.Background()
		curatedImageDefinitions = []*models.ImageDefinition{
			{
				Id:           1,
				OwnerId:      models.GithubOwnerId,
				ImageType:    models.ImageType_Curated,
				Name:         "test-image",
				OsType:       models.OsType_Linux,
				Enabled:      true,
				Architecture: models.Architecture_X64,
				CreatedAt:    fixedTime,
				UpdatedAt:    &fixedTime,
			},
			{
				Id:           2,
				OwnerId:      models.GithubOwnerId,
				ImageType:    models.ImageType_Curated,
				Name:         "test-image2",
				OsType:       models.OsType_Linux,
				Enabled:      true,
				Architecture: models.Architecture_X64,
				CreatedAt:    fixedTime,
				UpdatedAt:    &fixedTime,
			},
		}
		curatedImageDefinitionsWithInvalidData = []*models.ImageDefinition{
			{
				Id:           1,
				OwnerId:      models.GithubOwnerId,
				ImageType:    models.ImageType_Curated,
				Name:         "valid-test-image",
				OsType:       models.OsType_Linux,
				Enabled:      true,
				Architecture: models.Architecture_X64,
				CreatedAt:    fixedTime,
				UpdatedAt:    &fixedTime,
			},
			{
				Id:           2,
				OwnerId:      models.GithubOwnerId,
				ImageType:    models.ImageType_Curated,
				Name:         "invalid",
				OsType:       models.OsType_Linux,
				Enabled:      true,
				Architecture: "unknown",
				CreatedAt:    fixedTime,
				UpdatedAt:    &fixedTime,
			},
		}
	)

	t.Run("failed to list image definitions store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().ListCuratedImageDefinitions(ctx).Times(1).Return(nil, fmt.Errorf("test"))

		req := adminapi.ListCuratedImageDefinitionsRequest{}

		res, err := h.ListCuratedImageDefinitions(ctx, &req)

		assert.Error(t, err, twirp.Internal.Errorf("failed to list image definitions").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to list image definitions mapping error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().ListCuratedImageDefinitions(ctx).Times(1).Return(curatedImageDefinitionsWithInvalidData, nil)

		req := adminapi.ListCuratedImageDefinitionsRequest{}

		res, err := h.ListCuratedImageDefinitions(ctx, &req)

		assert.Error(t, err, twirp.Internal.Errorf("failed to map image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully list curated image definitions", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().ListCuratedImageDefinitions(ctx).Times(1).Return(curatedImageDefinitions, nil)

		req := adminapi.ListCuratedImageDefinitionsRequest{}

		res, err := h.ListCuratedImageDefinitions(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, 2, len(res.ImageDefinitions))

		for i, definition := range res.ImageDefinitions {
			assert.Equal(t, curatedImageDefinitions[i].Id, definition.Id)
			assert.Equal(t, curatedImageDefinitions[i].Name, definition.Name)
			assert.Equal(t, curatedImageDefinitions[i].Enabled, definition.Enabled)
			assert.Equal(t, sharedapi.Architecture_X64, definition.Architecture)
		}
	})
}

func TestImagesAdminApiHandler_ListCuratedImageVersions(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	sizeGB := int32(10)

	var (
		ctx                    = context.Background()
		curatedImageDefinition = &models.ImageDefinition{
			Id:           1,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image",
			OsType:       models.OsType_Linux,
			Enabled:      true,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}

		customerImageDefinition = models.ImageDefinition{
			Id:           2,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Customer,
			Name:         "test-image2",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}

		curatedImageVersions = []*models.ImageVersion{
			{
				Id:                2,
				Version:           "1.0.0",
				ImageDefinitionId: 1,
				State:             models.ImageVersionState_Pending,
				Enabled:           true,
				SizeGB:            &sizeGB,
			},
			{
				Id:                3,
				Version:           "1.0.1",
				ImageDefinitionId: 1,
				State:             models.ImageVersionState_Pending,
				Enabled:           true,
				SizeGB:            &sizeGB,
			},
			{
				Id:                4,
				Version:           "1.0.2",
				ImageDefinitionId: 1,
				State:             models.ImageVersionState_Pending,
				Enabled:           false,
				SizeGB:            &sizeGB,
			},
		}

		invalidSqlDataCuratedImageVersions = []*models.ImageVersion{
			{
				Id:                2,
				Version:           "1.0.0",
				ImageDefinitionId: 1,
				State:             "",
				Enabled:           true,
				SizeGB:            &sizeGB,
			},
		}
	)

	t.Run("failed list image versions when unable to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		req := adminapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.ListCuratedImageVersions(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions when request provides invalid image type error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

		req := adminapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := h.ListCuratedImageVersions(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.ListCuratedImageVersions(ctx, &req)

		assert.Error(t, err, twirp.Internal.Errorf("failed to list image versions").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions mapping error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, curatedImageDefinition.Id).Times(1).Return(invalidSqlDataCuratedImageVersions, nil),
		)

		req := adminapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.ListCuratedImageVersions(ctx, &req)

		assert.Error(t, err, twirp.Internal.Errorf("failed to map image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully list curated image versions", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, curatedImageDefinition.Id).Times(1).Return(curatedImageVersions, nil),
		)

		req := adminapi.ListCuratedImageVersionsRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.ListCuratedImageVersions(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, 3, len(res.ImageVersions))

		for i, version := range res.ImageVersions {
			assert.Equal(t, curatedImageVersions[i].ImageDefinitionId, version.ImageDefinitionId)
			assert.Equal(t, curatedImageVersions[i].Version, version.Version)
			assert.Equal(t, curatedImageVersions[i].Enabled, version.Enabled)
			assert.Equal(t, sharedapi.ImageVersionState_Pending, version.State)
			assert.Equal(t, sizeGB, version.SizeGb)
		}
	})
}

func TestImagesAdminApiHandler_CreateCuratedImageDefinition(t *testing.T) {
	ctx := context.Background()

	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	protoTimestamp := timestamppb.New(fixedTime)
	featureFlag := "test-feature-flag"

	imageDefinition := &models.ImageDefinition{
		OwnerId:      "github",
		Name:         "test-image",
		ImageType:    models.ImageType_Curated,
		Enabled:      true,
		OsType:       models.OsType_Linux,
		Architecture: models.Architecture_X64,
	}

	imageDefinitionWithFeatureFlag := &models.ImageDefinition{
		OwnerId:      "github",
		Name:         "test-image",
		ImageType:    models.ImageType_Curated,
		Enabled:      true,
		FeatureFlag:  &featureFlag,
		OsType:       models.OsType_Linux,
		Architecture: models.Architecture_X64,
	}

	createdImageDefinition := &models.ImageDefinition{
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

	createdImageDefinitionWithFeatureFlag := &models.ImageDefinition{
		Id:           1,
		OwnerId:      "github",
		Name:         "test-image",
		ImageType:    models.ImageType_Curated,
		Enabled:      true,
		FeatureFlag:  &featureFlag,
		OsType:       models.OsType_Linux,
		Architecture: models.Architecture_X64,
		CreatedAt:    fixedTime,
		UpdatedAt:    &fixedTime,
	}

	t.Run("failed to create curated image definition invalid os type", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(0)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         "test-image",
			Enabled:      true,
			OsType:       sharedapi.OsType(4), // Only 0/1 are valid mappings
			Architecture: sharedapi.Architecture_X64,
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("invalid os_type").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create curated image definition invalid architecture", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(0)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         "test-image",
			Enabled:      true,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture(4), // Only 0/1 are valid mappings
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("invalid architecture").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create curated image definition db error", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(0), fmt.Errorf("test"))

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         "test-image",
			Enabled:      true,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64, // Only 0/1 are valid mappings
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InternalError("failed to create new image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create curated image definition already exists", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(0), &ent.ConstraintError{})

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         "test-image",
			Enabled:      true,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64, // Only 0/1 are valid mappings
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.AlreadyExists.Error("image definition with this name already exists").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully create image definition", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(1), nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, uint64(1)).Times(1).Return(createdImageDefinition, nil),
		)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         "test-image",
			Enabled:      true,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.NotNil(t, res.ImageDefinition)
		assert.Equal(t, uint64(1), res.ImageDefinition.Id)
		assert.Equal(t, imageDefinition.Name, res.ImageDefinition.Name)
		assert.Equal(t, sharedapi.Architecture_X64, res.ImageDefinition.Architecture)
		assert.Equal(t, sharedapi.OsType_Linux, res.ImageDefinition.OsType)
		assert.Equal(t, true, res.ImageDefinition.Enabled)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.CreatedAt)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.UpdatedAt)
	})

	t.Run("successfully create image definition with feature flag", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinitionWithFeatureFlag).Times(1).Return(uint64(1), nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, uint64(1)).Times(1).Return(createdImageDefinitionWithFeatureFlag, nil),
		)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         "test-image",
			Enabled:      true,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			FeatureFlag:  "test-feature-flag",
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.NotNil(t, res.ImageDefinition)
		assert.Equal(t, uint64(1), res.ImageDefinition.Id)
		assert.Equal(t, imageDefinitionWithFeatureFlag.Name, res.ImageDefinition.Name)
		assert.Equal(t, sharedapi.Architecture_X64, res.ImageDefinition.Architecture)
		assert.Equal(t, sharedapi.OsType_Linux, res.ImageDefinition.OsType)
		assert.Equal(t, true, res.ImageDefinition.Enabled)
		assert.Equal(t, *imageDefinitionWithFeatureFlag.FeatureFlag, res.ImageDefinition.FeatureFlag)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.CreatedAt)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.UpdatedAt)
	})
}

func TestImagesAdminApiHandler_DeleteCuratedImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                    = context.Background()
		curatedImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}
		latestCuratedImageDefinition = models.ImageDefinition{
			Id:                        2,
			OwnerId:                   models.GithubOwnerId,
			ImageType:                 models.ImageType_Curated,
			Name:                      "test-image-latest",
			Enabled:                   true,
			OsType:                    models.OsType_Linux,
			Architecture:              models.Architecture_X64,
			PointsToImageDefinitionId: &curatedImageDefinition.Id,
			CreatedAt:                 fixedTime,
			UpdatedAt:                 &fixedTime,
		}
		customerImageDefinition = models.ImageDefinition{
			Id:           2,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Customer,
			Name:         "test-image2",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}
		curatedImageDefinitions = []*models.ImageDefinition{
			&curatedImageDefinition,
		}
	)

	t.Run("failed delete image definition when unable to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image definition when request provides invalid image type error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to delete admin curated image definition when it has image versions", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(ctx).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, curatedImageDefinition.Id).Times(1).Return([]*models.ImageVersion{{}}, nil),
		)

		req := adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("failed to delete image definition because it has image versions").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to delete admin curated image definition when store returns an error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(ctx).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, curatedImageDefinition.Id).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().DeleteImageDefinition(ctx, curatedImageDefinition.Id).Times(1).Return(fmt.Errorf("test")),
		)

		req := adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to delete image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to delete admin curated image definition when it is a pointer", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, latestCuratedImageDefinition.Id).Times(1).Return(&latestCuratedImageDefinition, nil)

		req := adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: latestCuratedImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("image definition pointer is not allowed for this operation").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully delete admin curated image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(ctx).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, curatedImageDefinition.Id).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().DeleteImageDefinition(ctx, curatedImageDefinition.Id).Times(1).Return(nil),
		)

		req := adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})

	t.Run("failed to delete admin curated image definition when there is a pointer referenced", func(t *testing.T) {
		curatedImageDefinitions = append(curatedImageDefinitions, &latestCuratedImageDefinition)
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil)
		mockImagesStore.EXPECT().ListCuratedImageDefinitions(ctx).Times(1).Return(curatedImageDefinitions, nil)

		req := adminapi.DeleteCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.DeleteCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("failed to delete image definition because it is referenced by pointer. Delete pointer first.").Error())
		assert.Nil(t, res)
	})
}

func TestImagesAdminApiHandler_DeleteCuratedImageVersion(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                    = context.Background()
		curatedImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}
		curatedImageVersion = models.ImageVersion{
			Id:                2,
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_ProvisionFailed,
			StateDetails:      "",
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
		}
	)

	t.Run("failed to delete image version when unable to retrieve image version store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.DeleteCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to delete image version when request provides invalid image type error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		customerImageDefinition := curatedImageDefinition
		customerImageDefinition.ImageType = models.ImageType_Customer

		customerImageVersion := models.ImageVersion{
			Id:                2,
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_ProvisionFailed,
			StateDetails:      "",
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := h.DeleteCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to delete image version when unable to mark image version state as deleting", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(ctx, curatedImageVersion.Id, models.ImageVersionState_Deleting, "").Times(1).Return(fmt.Errorf("test")),
		)

		req := adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.DeleteCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to delete image version").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to delete image version when unable to queue image definition delete operation", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(ctx, curatedImageVersion.Id, models.ImageVersionState_Deleting, "").Times(1).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageVersionJob(ctx, curatedImageVersion.Id).Times(1).Return(fmt.Errorf("test")),
		)

		req := adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.DeleteCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to delete image version").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully delete image version", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(ctx, curatedImageVersion.Id, models.ImageVersionState_Deleting, "").Times(1).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageVersionJob(ctx, curatedImageVersion.Id).Times(1).Return(nil),
		)

		req := adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.DeleteCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})
}

func TestImagesAdminApiHandler_CreateCuratedImageVersion(t *testing.T) {
	var (
		ctx                 = context.Background()
		sizeGB              = int32(10)
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
		}
		latestCuratedImageDefinition = models.ImageDefinition{
			Id:                        4,
			OwnerId:                   models.GithubOwnerId,
			ImageType:                 models.ImageType_Curated,
			Name:                      "test-image-latest",
			OsType:                    models.OsType_Linux,
			PointsToImageDefinitionId: &curatedImageDefinition.Id,
		}
		customerImageDefinition = models.ImageDefinition{
			Id:        3,
			OwnerId:   "test",
			ImageType: models.ImageType_Customer,
			Name:      "test-image",
			OsType:    models.OsType_Linux,
		}
		customerImageVersion = models.ImageVersion{
			Id:                2,
			Version:           "1.0.0",
			ImageDefinitionId: 3,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
			SizeGB:            &sizeGB,
		}
	)

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version because image definition type is not curated", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create image version because image definition is pointer", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, latestCuratedImageDefinition.Id).Times(1).Return(&latestCuratedImageDefinition, nil),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: latestCuratedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("image definition pointer is not allowed for this operation").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create image version in store", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		expectedVersion := &models.ImageVersion{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedVersion).Times(1).Return(uint64(0), fmt.Errorf("test")),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.InternalError("failed to create new image version").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create image version already exists", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		expectedVersion := &models.ImageVersion{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedVersion).Times(1).Return(uint64(0), &ent.ConstraintError{}),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.AlreadyExists.Error("image version with this version already exists").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to queue provision image version job", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		expectedReq := &models.ImageVersion{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		const c_sourceVhdUrl = "https://test.blob.core.windows.net/test/test.vhd"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedReq).Times(1).Return(curatedImageVersion.Id, nil),
			mockWorkerQueueClient.EXPECT().QueueProvisionImageVersionJob(ctx, curatedImageVersion.Id, c_sourceVhdUrl).Times(1).Return(fmt.Errorf("test")),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			SourceVhdUrl:      c_sourceVhdUrl,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.InternalError("failed to start image version provision").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully created image version", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		expectedReq := &models.ImageVersion{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		const c_sourceVhdUrl = "https://test.blob.core.windows.net/test/test.vhd"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedReq).Times(1).Return(curatedImageVersion.Id, nil),
			mockWorkerQueueClient.EXPECT().QueueProvisionImageVersionJob(ctx, curatedImageVersion.Id, c_sourceVhdUrl).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageVersionById(ctx, curatedImageVersion.Id).Times(1).Return(&curatedImageVersion, nil),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			SourceVhdUrl:      c_sourceVhdUrl,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, curatedImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, curatedImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersion.State)
		assert.Equal(t, curatedImageVersion.Enabled, res.ImageVersion.Enabled)
	})

	t.Run("successfully created macOS image version and saved ResourceId", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		macOsCuratedImageDefinition := models.ImageDefinition{
			Id:           3,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "macos-test-image",
			Enabled:      true,
			OsType:       models.OsType_MacOS,
			Architecture: models.Architecture_X64,
		}

		macOsCuratedImageVersion := models.ImageVersion{
			Id:                3,
			Version:           "0000.0101.1",
			ImageDefinitionId: 3,
			State:             models.ImageVersionState_Pending,
			ResourceId:        "os://f986c249-d5db-424a-a0a7-7a64345d21b4",
			Enabled:           true,
		}

		expectedReq := &models.ImageVersion{
			ImageDefinitionId: macOsCuratedImageDefinition.Id,
			Version:           macOsCuratedImageVersion.Version,
			ResourceId:        macOsCuratedImageVersion.ResourceId,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		const c_sourceVhdUrl = "os://f986c249-d5db-424a-a0a7-7a64345d21b4"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, macOsCuratedImageDefinition.Id).Times(1).Return(&macOsCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedReq).Times(1).Return(curatedImageVersion.Id, nil),
			mockWorkerQueueClient.EXPECT().QueueProvisionImageVersionJob(ctx, curatedImageVersion.Id, c_sourceVhdUrl).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageVersionById(ctx, curatedImageVersion.Id).Times(1).Return(&macOsCuratedImageVersion, nil),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: macOsCuratedImageDefinition.Id,
			Version:           macOsCuratedImageVersion.Version,
			SourceVhdUrl:      macOsCuratedImageVersion.ResourceId,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, macOsCuratedImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, macOsCuratedImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersion.State)
		assert.Equal(t, macOsCuratedImageVersion.ResourceId, res.ImageVersion.ResourceId)
		assert.Equal(t, macOsCuratedImageVersion.Enabled, res.ImageVersion.Enabled)
	})
}

func TestImagesAdminApiHandler_UpdateCuratedImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	featureFlag := "Test-feature-flag"

	var (
		ctx                          = context.Background()
		githubCuratedImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image-1",
			Enabled:      false,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			FeatureFlag:  &featureFlag,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}

		latestCuratedImageDefinition = models.ImageDefinition{
			Id:                        2,
			OwnerId:                   models.GithubOwnerId,
			ImageType:                 models.ImageType_Curated,
			Name:                      "test-image-1",
			Enabled:                   false,
			OsType:                    models.OsType_Linux,
			Architecture:              models.Architecture_X64,
			PointsToImageDefinitionId: &githubCuratedImageDefinition.Id,
			CreatedAt:                 fixedTime,
			UpdatedAt:                 &fixedTime,
		}

		customerImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      "x0v3",
			ImageType:    models.ImageType_Customer,
			Name:         "test-image-3",
			Enabled:      false,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}
	)

	t.Run("fail rpc call when fail to retrieve image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              "new-name",
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Errorf("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when image definition has invalid type", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              "new-name",
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when image definition is pointer record", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, latestCuratedImageDefinition.Id).Times(1).Return(&latestCuratedImageDefinition, nil)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: latestCuratedImageDefinition.Id,
			Name:              "new-name",
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("image definition pointer is not allowed for this operation").Error())
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when image definition has valid type but owner is incorrect", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		dodgeySqlData := models.ImageDefinition{
			Id:           1,
			OwnerId:      "x0v3",
			ImageType:    models.ImageType_Curated,
			Name:         "test-image-2",
			Enabled:      false,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&dodgeySqlData, nil)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              "new-name",
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when call to update fails", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &models.ImageDefinitionUpdate{
			Name:    "new-name",
			Enabled: true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(uint64(0), fmt.Errorf("test")),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              imageDefinitionUpdate.Name,
			Enabled:           imageDefinitionUpdate.Enabled,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Errorf("failed to update image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when new name already exists", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &models.ImageDefinitionUpdate{
			Name:    "new-name",
			Enabled: true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(uint64(0), &ent.ConstraintError{}),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              imageDefinitionUpdate.Name,
			Enabled:           imageDefinitionUpdate.Enabled,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.AlreadyExists.Error("image definition with this name already exists").Error())
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when call to retrieve updated definition fails", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &models.ImageDefinitionUpdate{
			Name:    "new-name",
			Enabled: true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(githubCuratedImageDefinition.Id, nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              imageDefinitionUpdate.Name,
			Enabled:           imageDefinitionUpdate.Enabled,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Errorf("failed to get updated image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully updated image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &models.ImageDefinitionUpdate{
			Name:    "new-name",
			Enabled: true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(githubCuratedImageDefinition.Id, nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              "new-name",
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})

	t.Run("successfully updated image definition with feature flag", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		featureFlag = "test-feature-flag"
		imageDefinitionUpdate := &models.ImageDefinitionUpdate{
			Name:        "new-name",
			Enabled:     true,
			FeatureFlag: &featureFlag,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(githubCuratedImageDefinition.Id, nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              "new-name",
			Enabled:           true,
			FeatureFlag:       "test-feature-flag",
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})
}

func TestImagesAdminApiHandler_UpdateCuratedImageVersion(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                    = context.Background()
		curatedImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      models.GithubOwnerId,
			ImageType:    models.ImageType_Curated,
			Name:         "test-image",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}
		curatedImageVersion = models.ImageVersion{
			Id:                1,
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_Ready,
			StateDetails:      "",
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
		}
	)

	t.Run("failed to update image version when unable to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.UpdateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.UpdateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to update image version when request provides invalid image type error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		customerImageDefinition := curatedImageDefinition
		customerImageDefinition.ImageType = models.ImageType_Customer

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := adminapi.UpdateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.UpdateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to update image version when unable to get image version by image definition id and version", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.UpdateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image version").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to update image version when unable to update image version field enabled", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageVersionUpdate := &models.ImageVersionUpdate{
			Enabled: true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, curatedImageDefinition.Id, imageVersionUpdate).Times(1).Return(uint64(1), fmt.Errorf("1")),
		)

		req := adminapi.UpdateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to update image version").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to update image version when unable to get image version by image id and version error after update", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageVersionUpdate := &models.ImageVersionUpdate{
			Enabled: true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, curatedImageDefinition.Id, imageVersionUpdate).Times(1).Return(uint64(1), nil),
			mockImagesStore.EXPECT().GetImageVersionById(ctx, curatedImageVersion.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.UpdateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get updated image version").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully update image version", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageVersionUpdate := &models.ImageVersionUpdate{
			Enabled: true,
		}
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersion(ctx, curatedImageDefinition.Id, imageVersionUpdate).Times(1).Return(uint64(1), nil),
			mockImagesStore.EXPECT().GetImageVersionById(ctx, curatedImageVersion.Id).Times(1).Return(&curatedImageVersion, nil), // Return a valid result instead of an error
		)

		req := adminapi.UpdateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})
}

func TestImagesAdminApiHandler_ProtoValidate(t *testing.T) {
	testCases := []requestValidationTestCase{
		{
			requestName:   "ListCuratedImageDefinitions",
			testName:      "Valid request",
			request:       &adminapi.ListCuratedImageDefinitionsRequest{},
			expectedError: "",
		},
		{
			requestName:   "GetCuratedImageDefinition",
			testName:      "Missing fields",
			request:       &adminapi.GetCuratedImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n - image_definition_id: value is required [required]",
		},
		{
			requestName: "GetCuratedImageDefinition",
			testName:    "Valid request",
			request: &adminapi.GetCuratedImageDefinitionRequest{
				ImageDefinitionId: 8,
			},
			expectedError: "",
		},
		{
			requestName:   "ListCuratedImageVersions",
			testName:      "Missing fields",
			request:       &adminapi.ListCuratedImageVersionsRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n - image_definition_id: value is required [required]",
		},
		{
			requestName: "ListCuratedImageVersions",
			testName:    "Valid request",
			request: &adminapi.ListCuratedImageVersionsRequest{
				ImageDefinitionId: 8,
			},
			expectedError: "",
		},
		{
			requestName: "GetCuratedImageVersion",
			testName:    "Missing fields",
			request:     &adminapi.GetCuratedImageVersionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_definition_id: value is required [required]\n" +
				" - version: value is required [required]",
		},
		{
			requestName: "GetCuratedImageVersion",
			testName:    "Invalid version format",
			request: &adminapi.GetCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "a.b.c",
			},
			expectedError: "twirp error invalid_argument: validation error:\n - version: value does not match regex pattern `^\\d+\\.\\d+\\.\\d+$` [string.pattern]",
		},
		{
			requestName: "GetCuratedImageVersion",
			testName:    "Valid request",
			request: &adminapi.GetCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
			},
			expectedError: "",
		},
		{
			requestName: "CreateCuratedImageDefinition",
			testName:    "Missing fields",
			request:     &adminapi.CreateCuratedImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - name: value is required [required]",
		},
		{
			requestName: "CreateCuratedImageDefinition",
			testName:    "Invalid name format",
			request: &adminapi.CreateCuratedImageDefinitionRequest{
				Name:         "invalid name!",
				Enabled:      true,
				OsType:       sharedapi.OsType_Linux,
				Architecture: sharedapi.Architecture_X64,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - name: value does not match regex pattern `^[a-zA-Z0-9()._ -]{1,100}$` [string.pattern]",
		},
		{
			requestName: "CreateCuratedImageDefinition",
			testName:    "Valid request",
			request: &adminapi.CreateCuratedImageDefinitionRequest{
				Name:         "Ubuntu 22.04",
				Enabled:      false,
				OsType:       sharedapi.OsType_Linux,
				Architecture: sharedapi.Architecture_X64,
			},
			expectedError: "",
		},
		{
			requestName: "CreateCuratedImageDefinition",
			testName:    "Valid request",
			request: &adminapi.CreateCuratedImageDefinitionRequest{
				Name:         "Ubuntu 22.04",
				Enabled:      true,
				OsType:       sharedapi.OsType_Linux,
				Architecture: sharedapi.Architecture_X64,
			},
			expectedError: "",
		},
		{
			requestName: "CreateCuratedImageVersion",
			testName:    "Missing fields",
			request:     &adminapi.CreateCuratedImageVersionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_definition_id: value is required [required]\n" +
				" - version: value is required [required]\n" +
				" - source_vhd_url: value is required [required]",
		},
		{
			requestName: "CreateCuratedImageVersion",
			testName:    "Invalid version format",
			request: &adminapi.CreateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "a.b.c",
				SourceVhdUrl:      "http://example.com/image",
				Enabled:           true,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - version: value does not match regex pattern `^\\d+\\.\\d+\\.\\d+$` [string.pattern]",
		},
		{
			requestName: "CreateCuratedImageVersion",
			testName:    "Invalid image URL format",
			request: &adminapi.CreateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "invalid url",
				Enabled:           true,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - source_vhd_url: value must be a valid URI [string.uri]",
		},
		{
			requestName: "CreateCuratedImageVersion",
			testName:    "Valid request",
			request: &adminapi.CreateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "http://example.com/image",
				Enabled:           false,
			},
			expectedError: "",
		},
		{
			requestName: "CreateCuratedImageVersion",
			testName:    "Valid request",
			request: &adminapi.CreateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "http://example.com/image",
				Enabled:           true,
			},
			expectedError: "",
		},
		{
			requestName: "UpdateCuratedImageDefinition",
			testName:    "Missing fields",
			request:     &adminapi.UpdateCuratedImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_definition_id: value is required [required]\n" +
				" - name: value is required [required]",
		},
		{
			requestName: "UpdateCuratedImageDefinition",
			testName:    "Invalid name format",
			request: &adminapi.UpdateCuratedImageDefinitionRequest{
				ImageDefinitionId: 8,
				Name:              "invalid name!",
				Enabled:           true,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - name: value does not match regex pattern `^[a-zA-Z0-9()._ -]{1,100}$` [string.pattern]",
		},
		{
			requestName: "UpdateCuratedImageDefinition",
			testName:    "Valid request",
			request: &adminapi.UpdateCuratedImageDefinitionRequest{
				ImageDefinitionId: 8,
				Name:              "Ubuntu 22.04",
				Enabled:           false,
			},
			expectedError: "",
		},
		{
			requestName: "UpdateCuratedImageDefinition",
			testName:    "Valid request",
			request: &adminapi.UpdateCuratedImageDefinitionRequest{
				ImageDefinitionId: 8,
				Name:              "Ubuntu 22.04",
				Enabled:           true,
			},
			expectedError: "",
		},
		{
			requestName: "UpdateCuratedImageVersion",
			testName:    "Missing fields",
			request:     &adminapi.UpdateCuratedImageVersionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_definition_id: value is required [required]\n" +
				" - version: value is required [required]",
		},
		{
			requestName: "UpdateCuratedImageVersion",
			testName:    "Valid request",
			request: &adminapi.UpdateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				Enabled:           false,
			},
			expectedError: "",
		},
		{
			requestName: "UpdateCuratedImageVersion",
			testName:    "Valid request",
			request: &adminapi.UpdateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				Enabled:           true,
			},
			expectedError: "",
		},
		{
			requestName: "DeleteCuratedImageDefinition",
			testName:    "Missing fields",
			request:     &adminapi.DeleteCuratedImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_definition_id: value is required [required]",
		},
		{
			requestName: "DeleteCuratedImageDefinition",
			testName:    "Valid request",
			request: &adminapi.DeleteCuratedImageDefinitionRequest{
				ImageDefinitionId: 8,
			},
			expectedError: "",
		},
		{
			requestName: "DeleteCuratedImageVersion",
			testName:    "Missing fields",
			request:     &adminapi.DeleteCuratedImageVersionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - image_definition_id: value is required [required]\n" +
				" - version: value is required [required]",
		},
		{
			requestName: "DeleteCuratedImageVersion",
			testName:    "Valid request",
			request: &adminapi.DeleteCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
			},
			expectedError: "",
		},
	}

	for _, test := range testCases {
		testProtoValidate(t, test)
	}
}
