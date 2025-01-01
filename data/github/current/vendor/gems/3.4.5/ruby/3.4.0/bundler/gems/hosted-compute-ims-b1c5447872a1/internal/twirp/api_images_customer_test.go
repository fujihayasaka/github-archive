package twirp

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/hosted-compute-ims/gen/ent"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"go.uber.org/mock/gomock"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
)

func TestImageManagementServer_GetCustomerImageVersion(t *testing.T) {
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
			Enabled:   true,
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
		customerImageDefinition = models.ImageDefinition{
			Id:        3,
			OwnerId:   "test",
			ImageType: models.ImageType_Customer,
			Name:      "test-image",
			Enabled:   true,
			OsType:    models.OsType_Linux,
		}
	)

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, customerImageDefinition.Id, customerImageVersion.Version).Times(0),
		)

		req := imagesapi.GetCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.GetCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version because image type in image definition is not customer", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionById(ctx, curatedImageVersion.Version).Times(0),
		)

		req := imagesapi.GetCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := s.GetCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version because image doesn't belong to customer", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, customerImageDefinition.Id, customerImageVersion.Version).Times(0),
		)

		req := imagesapi.GetCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: "test2"},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.GetCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, customerImageDefinition.Id, customerImageVersion.Version).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.GetCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.GetCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error internal: failed to get image version")
		assert.Nil(t, res)
	})

	t.Run("successfully retrieve image version", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, customerImageDefinition.Id, customerImageVersion.Version).Times(1).Return(&customerImageVersion, nil),
		)

		req := imagesapi.GetCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.GetCustomerImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, customerImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, customerImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersion.State)
		assert.Equal(t, *customerImageVersion.SizeGB, res.ImageVersion.SizeGb)
	})

	t.Run("successfully retrieve image version with null SizeGB", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		nullSizeGBCustomerImageVersion := models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
			SizeGB:            nil,
		}
		nullSizeGBCustomerImageDefinition := models.ImageDefinition{
			Id:        1,
			OwnerId:   models.GithubOwnerId,
			ImageType: models.ImageType_Customer,
			Name:      "test-image",
			Enabled:   true,
			OsType:    models.OsType_Linux,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, nullSizeGBCustomerImageDefinition.Id).Times(1).Return(&nullSizeGBCustomerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, nullSizeGBCustomerImageVersion.Id, nullSizeGBCustomerImageVersion.Version).Times(1).Return(&nullSizeGBCustomerImageVersion, nil),
		)

		req := imagesapi.GetCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: nullSizeGBCustomerImageDefinition.OwnerId},
			ImageDefinitionId: nullSizeGBCustomerImageDefinition.Id,
			Version:           nullSizeGBCustomerImageVersion.Version,
		}

		res, err := s.GetCustomerImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, nullSizeGBCustomerImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, nullSizeGBCustomerImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersion.State)
		assert.Equal(t, int32(0), res.ImageVersion.SizeGb)
	})
}

func TestImageManagementServer_CreateCustomerImageVersion(t *testing.T) {
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
		customerNoExistingVersionsMetadata = map[uint64]*models.ImageVersionsStorageMetadata{
			customerImageDefinition.Id: {
				ImageDefinitionId:        customerImageDefinition.Id,
				Count:                    0,
				TotalImageVersionsSizeGB: 0,
			},
		}
	)

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test"))

		req := imagesapi.CreateCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.CreateCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version because image definition type is not customer", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil)

		req := imagesapi.CreateCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           curatedImageVersion.Version,
		}

		res, err := s.CreateCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image version because image doesn't belong to customer", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil)

		req := imagesapi.CreateCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: "test2"},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.CreateCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to create image version in store due to db error", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		expectedVersion := &models.ImageVersion{
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsStorageMetadataForDefinitionIds(ctx, []uint64{customerImageDefinition.Id}).Times(1).Return(customerNoExistingVersionsMetadata, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedVersion).Times(1).Return(uint64(1), fmt.Errorf("test")),
		)

		req := imagesapi.CreateCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.CreateCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "failed to create image version")
		assert.Nil(t, res)
	})

	t.Run("failed to create image version already exists", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		expectedVersion := &models.ImageVersion{
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsStorageMetadataForDefinitionIds(ctx, []uint64{customerImageDefinition.Id}).Times(1).Return(customerNoExistingVersionsMetadata, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedVersion).Times(1).Return(uint64(1), &ent.ConstraintError{}),
		)

		req := imagesapi.CreateCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.CreateCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "image version with this version already exists")
		assert.Nil(t, res)
	})

	t.Run("failed to create image version due to max image versions reached", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		fullOnImageVersions := map[uint64]*models.ImageVersionsStorageMetadata{
			customerImageDefinition.Id: {
				ImageDefinitionId:        customerImageDefinition.Id,
				Count:                    100,
				TotalImageVersionsSizeGB: 0,
			},
		}

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsStorageMetadataForDefinitionIds(ctx, []uint64{customerImageDefinition.Id}).Times(1).Return(fullOnImageVersions, nil),
		)

		req := imagesapi.CreateCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.CreateCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "image definition already has maximum number of image versions")
		assert.Nil(t, res)
	})

	t.Run("failed to queue provision image version job", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		expectedReq := &models.ImageVersion{
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		const c_sourceVhdUrl = "https://test.blob.core.windows.net/test/test.vhd"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsStorageMetadataForDefinitionIds(ctx, []uint64{customerImageDefinition.Id}).Times(1).Return(customerNoExistingVersionsMetadata, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedReq).Times(1).Return(customerImageVersion.Id, nil),
			mockWorkerQueueClient.EXPECT().QueueProvisionImageVersionJob(ctx, customerImageVersion.Id, c_sourceVhdUrl).Times(1).Return(fmt.Errorf("test")),
		)

		req := imagesapi.CreateCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
			SourceVhdUrl:      c_sourceVhdUrl,
		}

		res, err := s.CreateCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "failed to provision image version")
		assert.Nil(t, res)
	})

	t.Run("successfully created image version", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		expectedReq := &models.ImageVersion{
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
			State:             models.ImageVersionState_Pending,
			Enabled:           true,
		}

		const c_sourceVhdUrl = "https://test.blob.core.windows.net/test/test.vhd"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsStorageMetadataForDefinitionIds(ctx, []uint64{customerImageDefinition.Id}).Times(1).Return(customerNoExistingVersionsMetadata, nil),
			mockImagesStore.EXPECT().AddImageVersion(ctx, expectedReq).Times(1).Return(customerImageVersion.Id, nil),
			mockWorkerQueueClient.EXPECT().QueueProvisionImageVersionJob(ctx, customerImageVersion.Id, c_sourceVhdUrl).Times(1).Return(nil),
			mockImagesStore.EXPECT().GetImageVersionById(ctx, customerImageVersion.Id).Times(1).Return(&customerImageVersion, nil),
		)

		req := imagesapi.CreateCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
			SourceVhdUrl:      c_sourceVhdUrl,
		}

		res, err := s.CreateCustomerImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, customerImageVersion.ImageDefinitionId, res.ImageVersion.ImageDefinitionId)
		assert.Equal(t, customerImageVersion.Version, res.ImageVersion.Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersion.State)
	})
}

func TestImageManagementServer_ListCustomerImageVersions(t *testing.T) {
	var (
		ctx                    = context.Background()
		sizeGB                 = int32(10)
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
		customerImageVersions = []*models.ImageVersion{
			{
				Id:                2,
				Version:           "1.0.0",
				ImageDefinitionId: 3,
				State:             models.ImageVersionState_Pending,
				Enabled:           true,
				SizeGB:            &sizeGB,
			},
			{
				Id:                3,
				Version:           "1.0.1",
				ImageDefinitionId: 3,
				State:             models.ImageVersionState_Pending,
				Enabled:           true,
				SizeGB:            &sizeGB,
			},
			{
				Id:                4,
				Version:           "1.0.2",
				ImageDefinitionId: 3,
				State:             models.ImageVersionState_Pending,
				Enabled:           false,
				SizeGB:            &sizeGB,
			},
		}
	)

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.ListCustomerImageVersionsRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.ListCustomerImageVersions(ctx, &req)

		assert.ErrorContains(t, err, "failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions because type is not customer", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, customerImageDefinition.Id).Times(0),
		)

		req := imagesapi.ListCustomerImageVersionsRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := s.ListCustomerImageVersions(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions because owner doesn't own the image", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, customerImageDefinition.Id).Times(0),
		)

		req := imagesapi.ListCustomerImageVersionsRequest{
			Owner:             &sharedapi.Actor{GlobalId: "wrongOwner"},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.ListCustomerImageVersions(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("failed to list image versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, customerImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.ListCustomerImageVersionsRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.ListCustomerImageVersions(ctx, &req)

		assert.ErrorContains(t, err, "failed to list image versions")
		assert.Nil(t, res)
	})

	t.Run("successfully to list customer image versions including enabled + disabled versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, customerImageDefinition.Id).Times(1).Return(customerImageVersions, nil),
		)

		req := imagesapi.ListCustomerImageVersionsRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.ListCustomerImageVersions(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, 3, len(res.ImageVersions))

		assert.Equal(t, customerImageVersions[0].ImageDefinitionId, res.ImageVersions[0].ImageDefinitionId)
		assert.Equal(t, customerImageVersions[0].Version, res.ImageVersions[0].Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersions[0].State)
		assert.Equal(t, sizeGB, res.ImageVersions[0].SizeGb)

		assert.Equal(t, customerImageVersions[1].ImageDefinitionId, res.ImageVersions[1].ImageDefinitionId)
		assert.Equal(t, customerImageVersions[1].Version, res.ImageVersions[1].Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersions[1].State)
		assert.Equal(t, sizeGB, res.ImageVersions[1].SizeGb)

		assert.Equal(t, customerImageVersions[2].ImageDefinitionId, res.ImageVersions[2].ImageDefinitionId)
		assert.Equal(t, customerImageVersions[2].Version, res.ImageVersions[2].Version)
		assert.Equal(t, sharedapi.ImageVersionState_Pending, res.ImageVersions[2].State)
		assert.Equal(t, sizeGB, res.ImageVersions[2].SizeGb)
	})
}

func TestImageManagementServer_GetCustomerImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                     = context.Background()
		customerImageDefinition = models.ImageDefinition{
			Id:           3,
			OwnerId:      "test",
			Name:         "test-image",
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_Arm64,
			ImageType:    models.ImageType_Customer,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
			Enabled:      true,
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
			Id:                1,
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_Ready,
			StateDetails:      "state details",
			Enabled:           true,
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
		}
		customerNoExistingVersionsMetadata = map[uint64]*models.ImageVersionsStorageMetadata{
			customerImageDefinition.Id: {
				ImageDefinitionId:        customerImageDefinition.Id,
				Count:                    0,
				TotalImageVersionsSizeGB: 0,
			},
		}
	)

	t.Run("failed to retrieve image definition because image definition type is not customer", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
		)

		req := imagesapi.GetCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: curatedImageDefinition.OwnerId},
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := s.GetCustomerImageDefinition(ctx, &req)

		expectedError := "twirp error not_found: image definition is not found"
		assert.ErrorContains(t, err, expectedError)
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image definition because it does not belong to this owner", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		// Assume that the image definition belongs to a different owner
		differentOwner := "differentOwnerId"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := imagesapi.GetCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: differentOwner},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.GetCustomerImageDefinition(ctx, &req)

		expectedError := "twirp error not_found: image definition is not found"
		assert.ErrorContains(t, err, expectedError)
		assert.Nil(t, res)
	})

	t.Run("failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.GetCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.GetCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("successfully retrieved image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsStorageMetadataForDefinitionIds(ctx, []uint64{customerImageDefinition.Id}).Times(1).Return(customerNoExistingVersionsMetadata, nil),
			mockImagesStore.EXPECT().GetLatestImageVersion(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageVersion, nil),
		)

		req := imagesapi.GetCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.GetCustomerImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.Equal(t, customerImageDefinition.Id, res.ImageDefinition.Id)
	})
}

func TestImageManagementServer_ListCustomerImageDefinitions(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                      = context.Background()
		customerImageDefinitions = []*models.ImageDefinition{
			{
				Id:           1,
				OwnerId:      "test",
				ImageType:    models.ImageType_Customer,
				Name:         "test-image",
				OsType:       models.OsType_Linux,
				Enabled:      true,
				Architecture: models.Architecture_X64,
				CreatedAt:    fixedTime,
				UpdatedAt:    &fixedTime,
			},
			{
				Id:           2,
				OwnerId:      "test",
				ImageType:    models.ImageType_Customer,
				Name:         "test-image2",
				OsType:       models.OsType_Linux,
				Enabled:      true,
				Architecture: models.Architecture_X64,
				CreatedAt:    fixedTime,
				UpdatedAt:    &fixedTime,
			},
		}
		latestImageVersions = map[uint64]*models.ImageVersion{
			customerImageDefinitions[0].Id: {
				Version: "1.0.0",
			},
			customerImageDefinitions[1].Id: {
				Version: "1.0.0",
			},
		}
		customerNoExistingVersionsMetadata = map[uint64]*models.ImageVersionsStorageMetadata{
			customerImageDefinitions[0].Id: {
				ImageDefinitionId:        customerImageDefinitions[0].Id,
				Count:                    0,
				TotalImageVersionsSizeGB: 0,
			},
			customerImageDefinitions[1].Id: {
				ImageDefinitionId:        customerImageDefinitions[1].Id,
				Count:                    0,
				TotalImageVersionsSizeGB: 0,
			},
		}
	)

	t.Run("failed to list image definitions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCustomerImageDefinitions(ctx, "test").Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.ListCustomerImageDefinitionsRequest{
			Owner: &sharedapi.Actor{GlobalId: "test"},
		}

		res, err := s.ListCustomerImageDefinitions(ctx, &req)

		assert.ErrorContains(t, err, "failed to list image definitions")
		assert.Nil(t, res)
	})

	t.Run("successfully to list customer image definitions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().ListCustomerImageDefinitions(ctx, customerImageDefinitions[0].OwnerId).Times(1).Return(customerImageDefinitions, nil),
			mockImagesStore.EXPECT().GetImageVersionsStorageMetadataForDefinitionIds(ctx, []uint64{customerImageDefinitions[0].Id, customerImageDefinitions[1].Id}).Times(1).Return(customerNoExistingVersionsMetadata, nil),
			mockImagesStore.EXPECT().GetLatestImageVersions(ctx, gomock.Any()).Times(1).Return(latestImageVersions, nil),
		)

		req := imagesapi.ListCustomerImageDefinitionsRequest{
			Owner: &sharedapi.Actor{GlobalId: "test"},
		}

		res, err := s.ListCustomerImageDefinitions(ctx, &req)

		assert.NoError(t, err)
		assert.Equal(t, 2, len(res.ImageDefinitions))

		for i, definition := range res.ImageDefinitions {
			assert.Equal(t, customerImageDefinitions[i].Id, definition.Id)
			assert.Equal(t, customerImageDefinitions[i].Name, definition.Name)
			assert.Equal(t, sharedapi.Architecture_X64, definition.Architecture)
		}
	})
}

func TestImageManagementServer_UpdateCustomerImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                     = context.Background()
		customerImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      "testOwner",
			ImageType:    models.ImageType_Customer,
			Name:         "test-image",
			Enabled:      true,
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
		}
		imageVersionsMetadata = map[uint64]*models.ImageVersionsStorageMetadata{
			customerImageDefinition.Id: {
				ImageDefinitionId:        customerImageDefinition.Id,
				Count:                    0,
				TotalImageVersionsSizeGB: 0,
			},
		}
	)

	t.Run("fail rpc call when failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.UpdateCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Name:              "new-name",
		}

		res, err := s.UpdateCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when image definition does not belong to owner", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		// Assume that the image definition belongs to a different owner
		differentOwner := "differentOwnerId"

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := imagesapi.UpdateCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: differentOwner},
			ImageDefinitionId: customerImageDefinition.Id,
			Name:              "new-name",
		}

		res, err := s.UpdateCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when already exists", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, customerImageDefinition.Id, &models.ImageDefinitionUpdate{
				Name:    "new-name",
				Enabled: true,
			}).Times(1).Return(uint64(0), &ent.ConstraintError{}),
		)

		req := imagesapi.UpdateCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Name:              "new-name",
		}

		res, err := s.UpdateCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "image definition with this name already exists")
		assert.Nil(t, res)
	})

	t.Run("successfully updated image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		updatedDefinition := customerImageDefinition
		updatedDefinition.Name = "new-name"
		updatedDefinition.Enabled = true

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().UpdateImageDefinition(ctx, customerImageDefinition.Id, &models.ImageDefinitionUpdate{
				Name:    "new-name",
				Enabled: true,
			}).Times(1).Return(uint64(1), nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&updatedDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionsStorageMetadataForDefinitionIds(ctx, []uint64{customerImageDefinition.Id}).Times(1).Return(imageVersionsMetadata, nil),
		)

		req := imagesapi.UpdateCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Name:              "new-name",
		}

		res, err := s.UpdateCustomerImageDefinition(ctx, &req)
		assert.NoError(t, err)
		assert.NotNil(t, res)

		updatedImageDef := res.ImageDefinition

		assert.Equal(t, customerImageDefinition.Id, updatedImageDef.Id)
		assert.Equal(t, "new-name", updatedImageDef.Name)
	})
}

func TestImageManagementServer_DeleteCustomerImageDefinition(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                     = context.Background()
		customerImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      "testOwner",
			ImageType:    models.ImageType_Customer,
			Name:         "test-image",
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
			Enabled:      true,
		}
	)

	t.Run("fail rpc call when failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.DeleteCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.DeleteCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when deleting curated image definition from invalid owner", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := imagesapi.DeleteCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: "invalid owner"},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.DeleteCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when deleting curated image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		curatedImageDefinition := customerImageDefinition
		curatedImageDefinition.ImageType = models.ImageType_Curated

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
		)

		req := imagesapi.DeleteCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: curatedImageDefinition.Id,
		}

		res, err := s.DeleteCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when returning error on delete image definition in DB", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, customerImageDefinition.Id).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().DeleteImageDefinition(ctx, customerImageDefinition.Id).Times(1).Return(fmt.Errorf("test")),
		)

		req := imagesapi.DeleteCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.DeleteCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "failed to delete image definition")
		assert.Nil(t, res)
	})

	t.Run("fail rpc call when returning error on delete image definition if it has image versions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, customerImageDefinition.Id).Times(1).Return([]*models.ImageVersion{{}}, nil),
		)

		req := imagesapi.DeleteCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.DeleteCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "failed to delete image definition because it has image versions")
		assert.Nil(t, res)
	})

	t.Run("successfully deleted image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(ctx, customerImageDefinition.Id).Times(1).Return([]*models.ImageVersion{}, nil),
			mockImagesStore.EXPECT().DeleteImageDefinition(ctx, customerImageDefinition.Id).Times(1).Return(nil),
		)

		req := imagesapi.DeleteCustomerImageDefinitionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
		}

		res, err := s.DeleteCustomerImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})
}

// let's test same test cases as for DeleteCustomerImageDefinition but for DeleteCustomerImageVersion
func TestImageManagementServer_DeleteCustomerImageVersions(t *testing.T) {
	fixedTime := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

	var (
		ctx                     = context.Background()
		customerImageDefinition = models.ImageDefinition{
			Id:           1,
			OwnerId:      "testOwner",
			ImageType:    models.ImageType_Customer,
			Name:         "test-image",
			OsType:       models.OsType_Linux,
			Architecture: models.Architecture_X64,
			CreatedAt:    fixedTime,
			UpdatedAt:    &fixedTime,
			Enabled:      true,
		}
		customerImageVersion = models.ImageVersion{
			Id:                1,
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           "1.0.0",
			State:             models.ImageVersionState_Ready,
			StateDetails:      "state details",
			Enabled:           true,
			CreatedAt:         fixedTime,
			UpdatedAt:         &fixedTime,
		}
	)

	t.Run("fail delete image version rpc call when failed to retrieve image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(nil, fmt.Errorf("test")),
		)

		req := imagesapi.DeleteCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.DeleteCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "failed to get image definition")
		assert.Nil(t, res)
	})

	t.Run("fail delete image version rpc call when deleting image version from invalid owner", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
		)

		req := imagesapi.DeleteCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: "invalid owner"},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.DeleteCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("fail delete image version rpc call when version belongs to curated image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		curatedImageDefinition := customerImageDefinition
		curatedImageDefinition.ImageType = models.ImageType_Curated

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, curatedImageDefinition.Id).Times(1).Return(&curatedImageDefinition, nil),
		)

		req := imagesapi.DeleteCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: curatedImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.DeleteCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "twirp error not_found: image definition is not found")
		assert.Nil(t, res)
	})

	t.Run("fail delete image version rpc call when failed to queue delete image version", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, customerImageVersion.ImageDefinitionId, customerImageVersion.Version).Times(1).Return(&customerImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(ctx, customerImageVersion.Id, models.ImageVersionState_Deleting, "").Times(1).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageVersionJob(ctx, customerImageVersion.Id).Times(1).Return(fmt.Errorf("test")),
		)

		req := imagesapi.DeleteCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.DeleteCustomerImageVersion(ctx, &req)

		assert.ErrorContains(t, err, "failed to delete image version")
		assert.Nil(t, res)
	})

	t.Run("successfully deleted image version", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, customerImageDefinition.Id).Times(1).Return(&customerImageDefinition, nil),
			mockImagesStore.EXPECT().GetImageVersionByDefinitionIdAndVersion(ctx, customerImageVersion.ImageDefinitionId, customerImageVersion.Version).Times(1).Return(&customerImageVersion, nil),
			mockImagesStore.EXPECT().UpdateImageVersionState(ctx, customerImageVersion.Id, models.ImageVersionState_Deleting, "").Times(1).Return(nil),
			mockWorkerQueueClient.EXPECT().QueueDeleteImageVersionJob(ctx, customerImageDefinition.Id).Times(1).Return(nil),
		)

		req := imagesapi.DeleteCustomerImageVersionRequest{
			Owner:             &sharedapi.Actor{GlobalId: customerImageDefinition.OwnerId},
			ImageDefinitionId: customerImageDefinition.Id,
			Version:           customerImageVersion.Version,
		}

		res, err := s.DeleteCustomerImageVersion(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
	})
}

func TestImageManagementServer_CreateCustomerImageDefinition(t *testing.T) {
	ctx := context.Background()

	const ownerId = "test"

	imageDefinition := &models.ImageDefinition{
		OwnerId:      ownerId,
		Name:         "test-image",
		ImageType:    models.ImageType_Customer,
		Enabled:      true,
		OsType:       models.OsType_Linux,
		Architecture: models.Architecture_X64,
	}

	t.Run("failed to create macos image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		req := imagesapi.CreateCustomerImageDefinitionRequest{
			Owner:        &sharedapi.Actor{GlobalId: ownerId},
			Name:         "test-image",
			OsType:       sharedapi.OsType_MacOS,
			Architecture: sharedapi.Architecture_X64,
		}

		res, err := s.CreateCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "macos is not supported for customer image")
		assert.Nil(t, res)
	})

	t.Run("failed to create image definition due to store error", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionsCountByOwnerId(ctx, ownerId).Times(1).Return(0, nil),
			mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(0), fmt.Errorf("test")),
		)

		req := imagesapi.CreateCustomerImageDefinitionRequest{
			Owner:        &sharedapi.Actor{GlobalId: ownerId},
			Name:         "test-image",
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}

		res, err := s.CreateCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "failed to create new image definition")
		assert.Nil(t, res)
	})

	t.Run("failed to create image definition exceeded max definitions", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().GetImageDefinitionsCountByOwnerId(ctx, ownerId).Times(1).Return(100, nil)

		req := imagesapi.CreateCustomerImageDefinitionRequest{
			Owner:        &sharedapi.Actor{GlobalId: ownerId},
			Name:         "test-image",
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}

		res, err := s.CreateCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "owner has maximum number of image definitions")
		assert.Nil(t, res)
	})

	t.Run("failed to create image definition because already exists", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionsCountByOwnerId(ctx, ownerId).Times(1).Return(0, nil),
			mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(0), &ent.ConstraintError{}),
		)

		req := imagesapi.CreateCustomerImageDefinitionRequest{
			Owner:        &sharedapi.Actor{GlobalId: ownerId},
			Name:         "test-image",
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}

		res, err := s.CreateCustomerImageDefinition(ctx, &req)

		assert.ErrorContains(t, err, "image definition with this name already exists")
		assert.Nil(t, res)
	})

	t.Run("successfully create image definition", func(t *testing.T) {
		ctrl, s := setupImagesApiHandler(t)
		defer ctrl.Finish()

		gomock.InOrder(
			mockImagesStore.EXPECT().GetImageDefinitionsCountByOwnerId(ctx, ownerId).Times(1).Return(0, nil),
			mockImagesStore.EXPECT().AddImageDefinition(ctx, imageDefinition).Times(1).Return(uint64(0), nil),
			mockImagesStore.EXPECT().GetImageDefinitionById(ctx, uint64(0)).Times(1).Return(imageDefinition, nil),
		)

		req := imagesapi.CreateCustomerImageDefinitionRequest{
			Owner:        &sharedapi.Actor{GlobalId: ownerId},
			Name:         "test-image",
			OsType:       sharedapi.OsType_Linux,
			Architecture: sharedapi.Architecture_X64,
		}

		res, err := s.CreateCustomerImageDefinition(ctx, &req)

		assert.NoError(t, err)
		assert.NotNil(t, res)
		assert.NotNil(t, res.ImageDefinition)
		assert.Equal(t, uint64(0), res.ImageDefinition.Id)
		assert.Equal(t, imageDefinition.Name, res.ImageDefinition.Name)
		assert.Equal(t, sharedapi.Architecture_X64, res.ImageDefinition.Architecture)
	})
}

func TestImageManagementServer_Customer_ProtoValidate(t *testing.T) {
	testCases := []requestValidationTestCase{
		{
			requestName:   "ListCustomerImageDefinitions",
			testName:      "Missing fields",
			request:       &imagesapi.ListCustomerImageDefinitionsRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n - owner: value is required [required]",
		},
		{
			requestName: "ListCustomerImageDefinitions",
			testName:    "Valid request",
			request: &imagesapi.ListCustomerImageDefinitionsRequest{
				Owner: &sharedapi.Actor{GlobalId: "user1"},
			},
			expectedError: "",
		},
		{
			requestName: "GetCustomerImageDefinition",
			testName:    "Missing fields",
			request:     &imagesapi.GetCustomerImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]",
		},
		{
			requestName: "GetCustomerImageDefinition",
			testName:    "Valid request",
			request: &imagesapi.GetCustomerImageDefinitionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
			},
			expectedError: "",
		},
		{
			requestName: "ListCustomerImageVersions",
			testName:    "Missing fields",
			request:     &imagesapi.ListCustomerImageVersionsRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]",
		},
		{
			requestName: "ListCustomerImageVersions",
			testName:    "Valid request",
			request: &imagesapi.ListCustomerImageVersionsRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
			},
			expectedError: "",
		},
		{
			requestName: "GetCustomerImageVersion",
			testName:    "Missing fields",
			request:     &imagesapi.GetCustomerImageVersionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]\n" +
				" - version: value is required [required]",
		},
		{
			requestName: "GetCustomerImageVersion",
			testName:    "Invalid version format",
			request: &imagesapi.GetCustomerImageVersionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
				Version:           "a.b.c",
			},
			expectedError: "twirp error invalid_argument: validation error:\n - version: value does not match regex pattern `^\\d+\\.\\d+\\.\\d+$` [string.pattern]",
		},
		{
			requestName: "GetCustomerImageVersion",
			testName:    "Valid request",
			request: &imagesapi.GetCustomerImageVersionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
				Version:           "1.0.0",
			},
			expectedError: "",
		},
		{
			requestName: "CreateCustomerImageDefinition",
			testName:    "Missing fields",
			request:     &imagesapi.CreateCustomerImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - name: value is required [required]",
		},
		{
			requestName: "CreateCustomerImageDefinition",
			testName:    "Invalid name format",
			request: &imagesapi.CreateCustomerImageDefinitionRequest{
				Owner:        &sharedapi.Actor{GlobalId: "user1"},
				Name:         "invalid name!",
				OsType:       sharedapi.OsType_Linux,
				Architecture: sharedapi.Architecture_X64,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - name: value does not match regex pattern `^[a-zA-Z0-9._-]{1,100}$` [string.pattern]",
		},
		{
			requestName: "CreateCustomerImageDefinition",
			testName:    "Unknown os_type",
			request: &imagesapi.CreateCustomerImageDefinitionRequest{
				Owner:        &sharedapi.Actor{GlobalId: "user1"},
				Name:         "valid-name",
				OsType:       157,
				Architecture: sharedapi.Architecture_X64,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - os_type: value must be one of the defined enum values [enum.defined_only]",
		},

		{
			requestName: "CreateCustomerImageDefinition",
			testName:    "Unknown architecture",
			request: &imagesapi.CreateCustomerImageDefinitionRequest{
				Owner:        &sharedapi.Actor{GlobalId: "user1"},
				Name:         "valid-name",
				OsType:       sharedapi.OsType_Linux,
				Architecture: 157,
			},
			expectedError: "twirp error invalid_argument: validation error:\n - architecture: value must be one of the defined enum values [enum.defined_only]",
		},
		{
			requestName: "CreateCustomerImageDefinition",
			testName:    "Valid request",
			request: &imagesapi.CreateCustomerImageDefinitionRequest{
				Owner:        &sharedapi.Actor{GlobalId: "user1"},
				Name:         "valid-name",
				OsType:       sharedapi.OsType_Linux,
				Architecture: sharedapi.Architecture_X64,
			},
			expectedError: "",
		},
		{
			requestName: "CreateCustomerImageVersion",
			testName:    "Missing fields",
			request:     &imagesapi.CreateCustomerImageVersionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]\n" +
				" - version: value is required [required]\n" +
				" - source_vhd_url: value is required [required]",
		},
		{
			requestName: "CreateCustomerImageVersion",
			testName:    "Invalid version format",
			request: &imagesapi.CreateCustomerImageVersionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
				Version:           "a.b.c",
				SourceVhdUrl:      "https://example.com",
			},
			expectedError: "twirp error invalid_argument: validation error:\n - version: value does not match regex pattern `^\\d+\\.\\d+\\.\\d+$` [string.pattern]",
		},
		{
			requestName: "CreateCustomerImageVersion",
			testName:    "Invalid source_vhd_url format",
			request: &imagesapi.CreateCustomerImageVersionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "invalid-url",
			},
			expectedError: "twirp error invalid_argument: validation error:\n - source_vhd_url: value must be a valid URI [string.uri]",
		},
		{
			requestName: "CreateCustomerImageVersion",
			testName:    "Valid request",
			request: &imagesapi.CreateCustomerImageVersionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
				Version:           "1.0.0",
				SourceVhdUrl:      "https://example.com",
			},
			expectedError: "",
		},
		{
			requestName: "UpdateCustomerImageDefinition",
			testName:    "Missing fields",
			request:     &imagesapi.UpdateCustomerImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]\n" +
				" - name: value is required [required]",
		},
		{
			requestName: "UpdateCustomerImageDefinition",
			testName:    "Invalid name format",
			request: &imagesapi.UpdateCustomerImageDefinitionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
				Name:              "invalid name!",
			},
			expectedError: "twirp error invalid_argument: validation error:\n - name: value does not match regex pattern `^[a-zA-Z0-9._-]{1,100}$` [string.pattern]",
		},
		{
			requestName: "UpdateCustomerImageDefinition",
			testName:    "Valid request",
			request: &imagesapi.UpdateCustomerImageDefinitionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
				Name:              "valid-name",
			},
			expectedError: "",
		},
		{
			requestName: "DeleteCustomerImageDefinition",
			testName:    "Missing fields",
			request:     &imagesapi.DeleteCustomerImageDefinitionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]",
		},
		{
			requestName: "DeleteCustomerImageDefinition",
			testName:    "Valid request",
			request: &imagesapi.DeleteCustomerImageDefinitionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
				ImageDefinitionId: 8,
			},
			expectedError: "",
		},
		{
			requestName: "DeleteCustomerImageVersion",
			testName:    "Missing fields",
			request:     &imagesapi.DeleteCustomerImageVersionRequest{},
			expectedError: "twirp error invalid_argument: validation error:\n" +
				" - owner: value is required [required]\n" +
				" - image_definition_id: value is required [required]\n" +
				" - version: value is required [required]",
		},
		{
			requestName: "DeleteCustomerImageVersion",
			testName:    "Valid request",
			request: &imagesapi.DeleteCustomerImageVersionRequest{
				Owner:             &sharedapi.Actor{GlobalId: "user1"},
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
