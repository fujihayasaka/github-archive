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
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestImagesAdminApiHandler_GetImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                    = context.Background()
		curatedImageDefinition = models.ImageDefinition{
			Id:                         1,
			OwnerId:                    models.GithubOwnerId,
			ImageType:                  models.ImageType_Curated,
			Name:                       "test-image",
			Enabled:                    true,
			OsType:                     models.OsType_Linux,
			Architecture:               models.Architecture_X64,
			CreatedAt:                  fixedTime,
			UpdatedAt:                  &fixedTime,
			State:                      models.ImageDefinitionState_Ready,
			IsImageGenerationSupported: true,
		}

		customerImageDefinition = models.ImageDefinition{
			Id:                         2,
			OwnerId:                    models.GithubOwnerId,
			ImageType:                  models.ImageType_Customer,
			Name:                       "test-image",
			Enabled:                    true,
			OsType:                     models.OsType_Linux,
			Architecture:               models.Architecture_X64,
			CreatedAt:                  fixedTime,
			UpdatedAt:                  &fixedTime,
			State:                      models.ImageDefinitionState_Ready,
			IsImageGenerationSupported: false,
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
			State:        models.ImageDefinitionState_Ready,
		}
		latestImageVersion = models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
		}
		imageVersionsSummary = models.ImageVersionsSummary{Count: 5, TotalImageVersionsSizeGB: 100}
	)

	t.Run("failed to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve latest image version", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), curatedImageDefinition.Id).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image versions summary", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), curatedImageDefinition.Id).Return(&latestImageVersion, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), curatedImageDefinition.Id).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to map image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), invalidOsTypeSqlData.Id).Times(1).Return(&invalidOsTypeSqlData, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), invalidOsTypeSqlData.Id).Return(&latestImageVersion, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), invalidOsTypeSqlData.Id).Return(&imageVersionsSummary, nil),
		)

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: invalidOsTypeSqlData.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), curatedImageDefinition.Id).Return(&latestImageVersion, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), curatedImageDefinition.Id).Return(&imageVersionsSummary, nil),
		)

		req := adminapi.GetCuratedImageDefinitionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := h.GetCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		if assert.NotNil(t, res) {
			assert.Equal(t, curatedImageDefinition.Id, res.ImageDefinition.Id)
			assert.True(t, res.ImageDefinition.IsImageGenerationSupported)
		}
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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
			ResourceId:        "fake-resource-id",
		}
	)

	t.Run("failed to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageDefinition.Id, "bad-version").Times(1).Return(nil, fmt.Errorf("test")),
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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
		}
		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageDefinition.Id, badVersion.Version).Times(1).Return(&badVersion, nil),
		)

		req := adminapi.GetCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           badVersion.Version,
		}

		res, err := h.GetCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get image version").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageDefinition.Id, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), macOsCuratedImageDefinition.Id).Times(1).Return(&macOsCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), macOsCuratedImageDefinition.Id, macOsCuratedImageVersion.Version).Times(1).Return(&macOsCuratedImageVersion, nil),
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
				Enabled:                    true,
				Architecture:               models.Architecture_X64,
				CreatedAt:                  fixedTime,
				UpdatedAt:                  &fixedTime,
				State:                      models.ImageDefinitionState_Ready,
				IsImageGenerationSupported: false,
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
				State:        models.ImageDefinitionState_Ready,
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
				State:        models.ImageDefinitionState_Ready,
			},
		}
		latestVersionsMap = map[uint64]*models.ImageVersion{
			1: {
				Id:                1,
				Version:           "1.0.0",
				ImageDefinitionId: 1,
			},
			2: {
				Id:                2,
				Version:           "1.1.0",
				ImageDefinitionId: 2,
			},
		}
		versionsSummaryMap = map[uint64]*models.ImageVersionsSummary{
			1: {Count: 1, TotalImageVersionsSizeGB: 5},
			2: {Count: 1, TotalImageVersionsSizeGB: 10},
		}
	)

	t.Run("failed to list image definitions store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(nil, fmt.Errorf("test"))

		req := adminapi.ListCuratedImageDefinitionsRequest{}

		res, err := h.ListCuratedImageDefinitions(ctx, &req)

		assert.Error(t, err, twirp.Internal.Errorf("failed to list image definitions").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get latest versions for image definitions", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().GetLatestImageVersionsForImageDefinitions(gomock.Any(), []uint64{1, 2}).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.ListCuratedImageDefinitionsRequest{}

		res, err := h.ListCuratedImageDefinitions(ctx, &req)

		assert.Error(t, err, twirp.Internal.Errorf("failed to list image definitions").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get image versions summaries for image definitions", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().GetLatestImageVersionsForImageDefinitions(gomock.Any(), []uint64{1, 2}).Return(latestVersionsMap, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummariesForImageDefinitions(gomock.Any(), []uint64{1, 2}).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.ListCuratedImageDefinitionsRequest{}

		res, err := h.ListCuratedImageDefinitions(ctx, &req)

		assert.Error(t, err, twirp.Internal.Errorf("failed to list image definitions").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to map image definitions", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitionsWithInvalidData, nil),
			mockImagesStore.EXPECT().GetLatestImageVersionsForImageDefinitions(gomock.Any(), []uint64{1, 2}).Return(latestVersionsMap, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummariesForImageDefinitions(gomock.Any(), []uint64{1, 2}).Return(versionsSummaryMap, nil),
		)

		req := adminapi.ListCuratedImageDefinitionsRequest{}

		res, err := h.ListCuratedImageDefinitions(ctx, &req)

		assert.Error(t, err, twirp.Internal.Errorf("failed to map image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully list curated image definitions", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().GetLatestImageVersionsForImageDefinitions(gomock.Any(), []uint64{1, 2}).Return(latestVersionsMap, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummariesForImageDefinitions(gomock.Any(), []uint64{1, 2}).Return(versionsSummaryMap, nil),
		)

		req := adminapi.ListCuratedImageDefinitionsRequest{}

		res, err := h.ListCuratedImageDefinitions(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, 2, len(res.ImageDefinitions))

		for i, definition := range res.ImageDefinitions {
			assert.Equal(t, curatedImageDefinitions[i].Id, definition.Id)
			assert.Equal(t, curatedImageDefinitions[i].Name, definition.Name)
			assert.Equal(t, curatedImageDefinitions[i].Enabled, definition.Enabled)
			assert.Equal(t, curatedImageDefinitions[i].IsImageGenerationSupported, definition.IsImageGenerationSupported)
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
				VmGeneration:      models.VmGeneration_Gen1,
				OsState:           models.OsState_Generalized,
				AgentUser:         "",
				AzurePurchasePlan: "",
			},
			{
				Id:                3,
				Version:           "1.0.1",
				ImageDefinitionId: 1,
				State:             models.ImageVersionState_Pending,
				Enabled:           true,
				SizeGB:            &sizeGB,
				VmGeneration:      models.VmGeneration_Gen1,
				OsState:           models.OsState_Generalized,
				AgentUser:         "",
				AzurePurchasePlan: "",
			},
			{
				Id:                4,
				Version:           "1.0.2",
				ImageDefinitionId: 1,
				State:             models.ImageVersionState_Pending,
				Enabled:           false,
				SizeGB:            &sizeGB,
				VmGeneration:      models.VmGeneration_Gen1,
				OsState:           models.OsState_Generalized,
				AgentUser:         "",
				AzurePurchasePlan: "",
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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(invalidSqlDataCuratedImageVersions, nil),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(curatedImageVersions, nil),
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
		OwnerId:                    "github",
		Name:                       "test-image",
		ImageType:                  models.ImageType_Curated,
		Enabled:                    true,
		OsType:                     models.OsType_Linux,
		Architecture:               models.Architecture_X64,
		State:                      models.ImageDefinitionState_Ready,
		IsImageGenerationSupported: true,
	}

	imageDefinitionWithFeatureFlag := &models.ImageDefinition{
		OwnerId:                    "github",
		Name:                       "test-image",
		ImageType:                  models.ImageType_Curated,
		Enabled:                    true,
		FeatureFlag:                &featureFlag,
		OsType:                     models.OsType_Linux,
		Architecture:               models.Architecture_X64,
		State:                      models.ImageDefinitionState_Ready,
		IsImageGenerationSupported: false,
	}

	createdImageDefinition := &models.ImageDefinition{
		Id:                         1,
		OwnerId:                    "github",
		Name:                       "test-image",
		ImageType:                  models.ImageType_Curated,
		Enabled:                    true,
		OsType:                     models.OsType_Linux,
		Architecture:               models.Architecture_X64,
		CreatedAt:                  fixedTime,
		UpdatedAt:                  &fixedTime,
		State:                      models.ImageDefinitionState_Ready,
		IsImageGenerationSupported: true,
	}

	createdImageDefinitionWithFeatureFlag := &models.ImageDefinition{
		Id:                         1,
		OwnerId:                    "github",
		Name:                       "test-image",
		ImageType:                  models.ImageType_Curated,
		Enabled:                    true,
		FeatureFlag:                &featureFlag,
		OsType:                     models.OsType_Linux,
		Architecture:               models.Architecture_X64,
		CreatedAt:                  fixedTime,
		UpdatedAt:                  &fixedTime,
		State:                      models.ImageDefinitionState_Ready,
		IsImageGenerationSupported: false,
	}

	t.Run("failed to create curated image definition invalid os type", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AddImageDefinition(gomock.Any(), imageDefinition).Times(0)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         "test-image",
			Enabled:      true,
			OsType:       sharedapi.OsType(4), // Only 0/1 are valid mappings
			Architecture: sharedapi.Architecture_X64,
			OwnerId:      models.GithubOwnerId,
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("invalid os_type").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create curated image definition invalid architecture", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AddImageDefinition(gomock.Any(), imageDefinition).Times(0)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         "test-image",
			Enabled:      true,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture(4), // Only 0/1 are valid mappings
			OwnerId:      models.GithubOwnerId,
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("invalid architecture").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to create curated image definition db error", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().AddImageDefinition(gomock.Any(), imageDefinition).Times(1).Return(uint64(0), fmt.Errorf("test"))

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:                       "test-image",
			Enabled:                    true,
			OsType:                     sharedapi.OsType_Linux,
			Architecture:               sharedapi.Architecture_X64,
			OwnerId:                    models.GithubOwnerId,
			IsImageGenerationSupported: true,
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InternalError("failed to create a new image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully create image definition with github owner", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().AddImageDefinition(gomock.Any(), imageDefinition).Times(1).Return(uint64(1), nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(1)).Times(1).Return(createdImageDefinition, nil),
		)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:                       "test-image",
			Enabled:                    true,
			OsType:                     sharedapi.OsType_Linux,
			Architecture:               sharedapi.Architecture_X64,
			OwnerId:                    models.GithubOwnerId,
			IsImageGenerationSupported: true,
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		require.NoError(t, err)
		require.NotNil(t, res)
		require.NotNil(t, res.ImageDefinition)
		assert.Equal(t, uint64(1), res.ImageDefinition.Id)
		assert.Equal(t, imageDefinition.Name, res.ImageDefinition.Name)
		assert.Equal(t, sharedapi.Architecture_X64, res.ImageDefinition.Architecture)
		assert.Equal(t, sharedapi.OsType_Linux, res.ImageDefinition.OsType)
		assert.Equal(t, true, res.ImageDefinition.Enabled)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.CreatedAt)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.UpdatedAt)
		assert.True(t, res.ImageDefinition.IsImageGenerationSupported)
	})

	t.Run("successfully create image definition with partner owner", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		partnerImageDefinition := models.ImageDefinition{
			OwnerId:      models.PartnerOwnerId,
			Name:         "test-image",
			ImageType:    models.ImageType_Curated,
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			State:        models.ImageDefinitionState_Ready,
		}

		createdPartnerImageDefinition := partnerImageDefinition
		createdPartnerImageDefinition.Id = 1
		createdPartnerImageDefinition.CreatedAt = fixedTime
		createdPartnerImageDefinition.UpdatedAt = &fixedTime
		createdPartnerImageDefinition.IsImageGenerationSupported = false

		gomock.InOrder(
			mockImagesStore.EXPECT().AddImageDefinition(gomock.Any(), &partnerImageDefinition).Times(1).Return(uint64(1), nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(1)).Times(1).Return(&createdPartnerImageDefinition, nil),
		)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:         partnerImageDefinition.Name,
			Enabled:      true,
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
			OwnerId:      models.PartnerOwnerId,
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		require.NoError(t, err)
		require.NotNil(t, res)
		require.NotNil(t, res.ImageDefinition)
		assert.Equal(t, uint64(1), res.ImageDefinition.Id)
		assert.Equal(t, imageDefinition.Name, res.ImageDefinition.Name)
		assert.Equal(t, sharedapi.Architecture_X64, res.ImageDefinition.Architecture)
		assert.Equal(t, sharedapi.OsType_Linux, res.ImageDefinition.OsType)
		assert.Equal(t, true, res.ImageDefinition.Enabled)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.CreatedAt)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.UpdatedAt)
		assert.False(t, res.ImageDefinition.IsImageGenerationSupported)
	})

	t.Run("successfully create image definition with feature flag", func(t *testing.T) {
		ctrl, s := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().AddImageDefinition(gomock.Any(), imageDefinitionWithFeatureFlag).Times(1).Return(uint64(1), nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), uint64(1)).Times(1).Return(createdImageDefinitionWithFeatureFlag, nil),
		)

		req := adminapi.CreateCuratedImageDefinitionRequest{
			Name:                       "test-image",
			Enabled:                    true,
			OsType:                     sharedapi.OsType_Linux,
			Architecture:               sharedapi.Architecture_X64,
			FeatureFlag:                "test-feature-flag",
			OwnerId:                    models.GithubOwnerId,
			IsImageGenerationSupported: false,
		}

		res, err := s.CreateCuratedImageDefinition(ctx, &req)

		require.NoError(t, err)
		require.NotNil(t, res)
		require.NotNil(t, res.ImageDefinition)
		assert.Equal(t, uint64(1), res.ImageDefinition.Id)
		assert.Equal(t, imageDefinitionWithFeatureFlag.Name, res.ImageDefinition.Name)
		assert.Equal(t, sharedapi.Architecture_X64, res.ImageDefinition.Architecture)
		assert.Equal(t, sharedapi.OsType_Linux, res.ImageDefinition.OsType)
		assert.Equal(t, true, res.ImageDefinition.Enabled)
		assert.Equal(t, *imageDefinitionWithFeatureFlag.FeatureFlag, res.ImageDefinition.FeatureFlag)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.CreatedAt)
		assert.Equal(t, protoTimestamp, res.ImageDefinition.UpdatedAt)
		assert.False(t, res.ImageDefinition.IsImageGenerationSupported)
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(1).Return([]*models.ImageVersion{{}}, nil),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().DeleteImageDefinition(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(fmt.Errorf("test")),
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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), latestCuratedImageDefinition.Id).Times(1).Return(&latestCuratedImageDefinition, nil)

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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), curatedImageDefinition.Id).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().DeleteImageDefinition(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil),
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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil)
		mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Times(1).Return(curatedImageDefinitions, nil)

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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}
	)

	t.Run("failed to delete image version when unable to retrieve image version store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := h.DeleteCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.NotFound.Error("image definition is not found").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to start async image version deletion", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockPromotionStartClient.EXPECT().StartAsyncImageVersionDeletion(gomock.Any(), curatedImageVersion.Id).Return(fmt.Errorf("test")),
		)

		req := adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.DeleteCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to start image version deletion").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to get updated image version", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockPromotionStartClient.EXPECT().StartAsyncImageVersionDeletion(gomock.Any(), curatedImageVersion.Id).Return(nil),
			mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), curatedImageVersion.Id).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.DeleteCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := h.DeleteCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Error("failed to get updated image version").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully delete image version", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockPromotionStartClient.EXPECT().StartAsyncImageVersionDeletion(gomock.Any(), curatedImageVersion.Id).Return(nil),
			mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), curatedImageVersion.Id).Return(&curatedImageVersion, nil),
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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), latestCuratedImageDefinition.Id).Times(1).Return(&latestCuratedImageDefinition, nil),
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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(gomock.Any(), expectedVersion).Times(1).Return(uint64(0), fmt.Errorf("test")),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			Enabled:           true,
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.EqualError(t, err, twirp.InternalError("failed to create a new image version").Error())
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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(gomock.Any(), expectedVersion).Times(1).Return(uint64(0), &ent.ConstraintError{}),
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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}

		const c_sourceVhdUrl = "https://test.blob.core.windows.net/test/test.vhd"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(gomock.Any(), expectedReq).Times(1).Return(curatedImageVersion.Id, nil),
			mockPromotionStartClient.EXPECT().StartAsyncImageVersionProvision(gomock.Any(), curatedImageVersion.Id, c_sourceVhdUrl, "").Times(1).Return(fmt.Errorf("test")),
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
			VmGeneration:      models.VmGeneration_Gen2,
			OsState:           models.OsState_Specialized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}

		const c_sourceVhdUrl = "https://test.blob.core.windows.net/test/test.vhd"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().AddImageVersion(gomock.Any(), expectedReq).Times(1).Return(curatedImageVersion.Id, nil),
			mockPromotionStartClient.EXPECT().StartAsyncImageVersionProvision(gomock.Any(), curatedImageVersion.Id, c_sourceVhdUrl, "").Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), curatedImageVersion.Id).Times(1).Return(&curatedImageVersion, nil),
		)

		req := adminapi.CreateCuratedImageVersionRequest{
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
			SourceVhdUrl:      c_sourceVhdUrl,
			Enabled:           true,
			VmGeneration:      sharedapi.VmGeneration_Gen2,
			OsState:           sharedapi.OsState_Specialized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}

		res, err := h.CreateCuratedImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, curatedImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, curatedImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersion.State)
		assert.Equal(t, curatedImageVersion.Enabled, res.ImageVersion.Enabled)
	})
}

func TestImagesAdminApiHandler_UpdateCuratedImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	featureFlag := "Test-feature-flag"

	var (
		ctx                          = context.Background()
		githubCuratedImageDefinition = models.ImageDefinition{
			Id:                         1,
			OwnerId:                    models.GithubOwnerId,
			ImageType:                  models.ImageType_Curated,
			Name:                       "test-image-1",
			Enabled:                    false,
			OsType:                     models.OsType_Linux,
			Architecture:               models.Architecture_X64,
			FeatureFlag:                &featureFlag,
			CreatedAt:                  fixedTime,
			UpdatedAt:                  &fixedTime,
			State:                      models.ImageDefinitionState_Ready,
			IsImageGenerationSupported: false,
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
			State:                     models.ImageDefinitionState_Ready,
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
			State:        models.ImageDefinitionState_Ready,
		}
		latestImageVersion = models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
		}
		imageVersionsSummary = models.ImageVersionsSummary{Count: 5, TotalImageVersionsSizeGB: 25}
	)

	t.Run("fail rpc call when fail to retrieve image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

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

		mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), latestCuratedImageDefinition.Id).Times(1).Return(&latestCuratedImageDefinition, nil)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: latestCuratedImageDefinition.Id,
			Name:              "new-name",
			Enabled:           true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.InvalidArgument.Error("image definition pointer is not allowed for this operation").Error())
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when call to update fails", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &store.ImageDefinitionUpdatePayload{
			Name:                       wrapperspb.String("new-name"),
			Enabled:                    wrapperspb.Bool(true),
			FeatureFlag:                wrapperspb.String(""),
			IsImageGenerationSupported: wrapperspb.Bool(false),
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(gomock.Any(), githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(fmt.Errorf("test")),
		)

		res, err := h.UpdateCuratedImageDefinition(ctx, &adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId: githubCuratedImageDefinition.Id,
			Name:              "new-name",
			Enabled:           true,
		})

		assert.EqualError(t, err, twirp.Internal.Errorf("failed to update image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve updated definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &store.ImageDefinitionUpdatePayload{
			Name:                       wrapperspb.String("new-name"),
			Enabled:                    wrapperspb.Bool(true),
			FeatureFlag:                wrapperspb.String(""),
			IsImageGenerationSupported: wrapperspb.Bool(true),
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(gomock.Any(), githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId:          githubCuratedImageDefinition.Id,
			Name:                       "new-name",
			Enabled:                    true,
			IsImageGenerationSupported: true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Errorf("failed to get updated image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve latest version for updated image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &store.ImageDefinitionUpdatePayload{
			Name:                       wrapperspb.String("new-name"),
			Enabled:                    wrapperspb.Bool(true),
			FeatureFlag:                wrapperspb.String(""),
			IsImageGenerationSupported: wrapperspb.Bool(true),
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(gomock.Any(), githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), githubCuratedImageDefinition.Id).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId:          githubCuratedImageDefinition.Id,
			Name:                       "new-name",
			Enabled:                    true,
			IsImageGenerationSupported: true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Errorf("failed to get updated image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image versions summary for updated image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &store.ImageDefinitionUpdatePayload{
			Name:                       wrapperspb.String("new-name"),
			Enabled:                    wrapperspb.Bool(true),
			FeatureFlag:                wrapperspb.String(""),
			IsImageGenerationSupported: wrapperspb.Bool(true),
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(gomock.Any(), githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), githubCuratedImageDefinition.Id).Return(&latestImageVersion, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), githubCuratedImageDefinition.Id).Return(nil, fmt.Errorf("test")),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId:          githubCuratedImageDefinition.Id,
			Name:                       "new-name",
			Enabled:                    true,
			IsImageGenerationSupported: true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.EqualError(t, err, twirp.Internal.Errorf("failed to get updated image definition").Error())
		assert.Nil(t, res)
	})

	t.Run("successfully updated image definition", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		imageDefinitionUpdate := &store.ImageDefinitionUpdatePayload{
			Name:                       wrapperspb.String("new-name"),
			Enabled:                    wrapperspb.Bool(true),
			FeatureFlag:                wrapperspb.String(""),
			IsImageGenerationSupported: wrapperspb.Bool(true),
		}

		newName := "new-name"

		updatedImageDefinition := githubCuratedImageDefinition
		updatedImageDefinition.Name = newName
		updatedImageDefinition.Enabled = true
		updatedImageDefinition.IsImageGenerationSupported = true
		updatedImageDefinition.FeatureFlag = nil

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(gomock.Any(), githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&updatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), githubCuratedImageDefinition.Id).Return(&latestImageVersion, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), githubCuratedImageDefinition.Id).Return(&imageVersionsSummary, nil),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId:          githubCuratedImageDefinition.Id,
			Name:                       newName,
			Enabled:                    true,
			IsImageGenerationSupported: true,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.Equal(t, newName, res.ImageDefinition.Name)
		assert.True(t, res.ImageDefinition.Enabled)
		assert.True(t, res.ImageDefinition.IsImageGenerationSupported)
		assert.Empty(t, res.ImageDefinition.FeatureFlag)
	})

	t.Run("successfully updated image definition with feature flag", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		githubCuratedImageDefinition := githubCuratedImageDefinition
		githubCuratedImageDefinition.IsImageGenerationSupported = true
		newFeatureFlag := "test-feature-flag"
		newName := "new-name"

		imageDefinitionUpdate := &store.ImageDefinitionUpdatePayload{
			Name:                       wrapperspb.String(newName),
			Enabled:                    wrapperspb.Bool(false),
			FeatureFlag:                wrapperspb.String(newFeatureFlag),
			IsImageGenerationSupported: wrapperspb.Bool(false),
		}

		updatedImageDefinition := githubCuratedImageDefinition
		updatedImageDefinition.Name = newName
		updatedImageDefinition.Enabled = false
		updatedImageDefinition.IsImageGenerationSupported = false
		updatedImageDefinition.FeatureFlag = &newFeatureFlag

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&githubCuratedImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(gomock.Any(), githubCuratedImageDefinition.Id, imageDefinitionUpdate).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), githubCuratedImageDefinition.Id).Times(1).Return(&updatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(gomock.Any(), githubCuratedImageDefinition.Id).Return(&latestImageVersion, nil),
			mockImagesStore.EXPECT().GetImageVersionsSummary(gomock.Any(), githubCuratedImageDefinition.Id).Return(&imageVersionsSummary, nil),
		)

		req := adminapi.UpdateCuratedImageDefinitionRequest{
			ImageDefinitionId:          githubCuratedImageDefinition.Id,
			Name:                       newName,
			Enabled:                    false,
			FeatureFlag:                newFeatureFlag,
			IsImageGenerationSupported: false,
		}

		res, err := h.UpdateCuratedImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.Equal(t, newName, res.ImageDefinition.Name)
		assert.False(t, res.ImageDefinition.Enabled)
		assert.Equal(t, newFeatureFlag, res.ImageDefinition.FeatureFlag)
		assert.False(t, res.ImageDefinition.IsImageGenerationSupported)
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
			VmGeneration:      models.VmGeneration_Gen1,
			OsState:           models.OsState_Generalized,
			AgentUser:         "",
			AzurePurchasePlan: "",
		}
	)

	t.Run("failed to update image version when unable to retrieve image definition store error", func(t *testing.T) {
		ctrl, h := setupImagesAdminApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
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
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(nil, fmt.Errorf("test")),
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

		imageVersionUpdate := &store.ImageVersionUpdatePayload{
			Enabled: wrapperspb.Bool(true),
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersion(gomock.Any(), curatedImageDefinition.Id, imageVersionUpdate).Times(1).Return(fmt.Errorf("test")),
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

		imageVersionUpdate := &store.ImageVersionUpdatePayload{
			Enabled: wrapperspb.Bool(true),
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersion(gomock.Any(), curatedImageDefinition.Id, imageVersionUpdate).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), curatedImageVersion.Id).Times(1).Return(nil, fmt.Errorf("test")),
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

		imageVersionUpdate := &store.ImageVersionUpdatePayload{
			Enabled: wrapperspb.Bool(true),
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(gomock.Any(), curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(gomock.Any(), curatedImageVersion.ImageDefinitionId, curatedImageVersion.Version).Times(1).Return(&curatedImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersion(gomock.Any(), curatedImageDefinition.Id, imageVersionUpdate).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageVersionById(gomock.Any(), curatedImageVersion.Id).Times(1).Return(&curatedImageVersion, nil), // Return a valid result instead of an error
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
				" - name: value is required [required]\n" +
				" - owner_id: value is required [required]",
		},
		{
			requestName: "CreateCuratedImageDefinition",
			testName:    "Invalid name format",
			request: &adminapi.CreateCuratedImageDefinitionRequest{
				Name:         "invalid name!",
				OwnerId:      models.GithubOwnerId,
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
				OwnerId:      models.GithubOwnerId,
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
				OwnerId:      models.GithubOwnerId,
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
			expectedError: "twirp error invalid_argument: validation error:\n - version: value does not match regex pattern `^(\\d+\\.(\\d+|\\*)(|\\.(\\d+|\\*)))?$` [string.pattern]",
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
			testName:    "Invalid azure_purchase_plan",
			request: &adminapi.CreateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "http://example.com/image",
				Enabled:           true,
				AzurePurchasePlan: "invalid azure purchase plan",
			},
			expectedError: "twirp error invalid_argument: validation error:\n - azure_purchase_plan: value does not match regex pattern `^([a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+)?$` [string.pattern]",
		},
		{
			requestName: "CreateCuratedImageVersion",
			testName:    "Valid request without azure plan",
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
			testName:    "Valid request without azure plan",
			request: &adminapi.CreateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "http://example.com/image",
				Enabled:           true,
			},
			expectedError: "",
		},
		{
			requestName: "CreateCuratedImageVersion",
			testName:    "Valid request with azure plan",
			request: &adminapi.CreateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "http://example.com/image",
				Enabled:           true,
				AzurePurchasePlan: "Plan1:Plan2:Plan3",
			},
			expectedError: "",
		},
		{
			requestName: "CreateCuratedImageVersion",
			testName:    "Valid request with azure plan actual name",
			request: &adminapi.CreateCuratedImageVersionRequest{
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "http://example.com/image",
				Enabled:           true,
				AzurePurchasePlan: "arm:github_arm_windows11_runner:gh-windows-plan",
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
