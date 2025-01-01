package cronjobs

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestReplicationJob_Perform(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// Create a replication job instance
	replicationJob := &ReplicationJob{
		BaseJob: baseJob,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux}
	image2 := &models.ImageDefinition{Id: 2, OsType: models.OsType_Linux}
	imageVersions1 := []*models.ImageVersion{
		{Version: "1.0.0", State: models.ImageVersionState_Ready},
		{Version: "1.0.1", State: models.ImageVersionState_Ready},
	}
	imageVersions2 := []*models.ImageVersion{
		{Version: "2.0.0", State: models.ImageVersionState_Ready},
	}
	azureImageVersionKey1 := azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", "1.0.0")
	azureImageVersionKey2 := azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", "1.0.1")
	azureImageVersionKey3 := azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-2", "1.0.0")

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1, image2}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions1, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image2.Id).Return(imageVersions2, nil)

	// Set up the expectations for the mock RunnerClient
	mockRunnerClient.EXPECT().KnownRunnerUrls().Return([]string{"http://test.net/runner1"}).AnyTimes()
	mockRunnerClient.EXPECT().GetImageUsage(ctx, gomock.Any(), image1.Id).Return(&vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 300,
				},
			},
			"1.0.1": {
				VMCountPerRegion: map[string]int32{
					"eastus": 250,
				},
			},
		},
	}, nil)
	mockRunnerClient.EXPECT().GetImageUsage(ctx, gomock.Any(), image2.Id).Return(&vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"2.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 700,
					"westus": 1500,
				},
			},
		},
	}, nil)

	mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(gomock.Any(), image1.Id, "1.0.0").Return(&models.ImageVersionReplicationData{
		Id:                    5,
		ImageDefinitionId:     1,
		ImageVersion:          "1.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{},
	}, nil).Times(1)

	mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(gomock.Any(), image1.Id, "1.0.1").Return(&models.ImageVersionReplicationData{
		Id:                    6,
		ImageDefinitionId:     1,
		ImageVersion:          "1.0.1",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{},
	}, nil).Times(1)

	// No data in the database should be the expected case for new image versions will return an id of 0.
	mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(gomock.Any(), image2.Id, "2.0.0").Return(&models.ImageVersionReplicationData{
		Id:                    0,
		ImageDefinitionId:     image2.Id,
		ImageVersion:          "2.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{},
	}, nil).Times(1)

	mockManager.EXPECT().GetSupportedImageRegions(gomock.Any()).Return([]string{"eastus", "westus"}).Times(3)

	mockManager.EXPECT().GetGalleryImageVersionKey(gomock.Any(), imageVersions1[0]).Return(azureImageVersionKey1, nil).Times(1)
	mockManager.EXPECT().GetGalleryImageVersionKey(gomock.Any(), imageVersions1[1]).Return(azureImageVersionKey2, nil).Times(1)
	mockManager.EXPECT().GetGalleryImageVersionKey(gomock.Any(), imageVersions2[0]).Return(azureImageVersionKey3, nil).Times(1)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		Id:                5,
		ImageDefinitionId: image1.Id,
		ImageVersion:      "1.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      300,
				ReplicaCount: 2,
			},
			"westus": {
				VMCount:      0,
				ReplicaCount: 1,
			},
		},
	}).Return(nil)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		Id:                6,
		ImageDefinitionId: image1.Id,
		ImageVersion:      "1.0.1",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      250,
				ReplicaCount: 1,
			},
			"westus": {
				VMCount:      0,
				ReplicaCount: 1,
			},
		},
	}).Return(nil)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		Id:                0,
		ImageDefinitionId: image2.Id,
		ImageVersion:      "2.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      700,
				ReplicaCount: 3,
			},
			"westus": {
				VMCount:      1500,
				ReplicaCount: 6,
			},
		},
	}).Return(nil)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azureImageVersionKey1, azure.ImageVersionReplications{
		{
			Region:        "eastus",
			ReplicasCount: 2,
		},
		{
			Region:        "westus",
			ReplicasCount: 1,
		},
	}).Return(nil)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azureImageVersionKey2, azure.ImageVersionReplications{
		{
			Region:        "eastus",
			ReplicasCount: 1,
		},
		{
			Region:        "westus",
			ReplicasCount: 1,
		},
	}).Return(nil)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azureImageVersionKey3, azure.ImageVersionReplications{
		{
			Region:        "eastus",
			ReplicasCount: 3,
		},
		{
			Region:        "westus",
			ReplicasCount: 6,
		},
	}).Return(nil)

	// Call the Perform method
	err := replicationJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestReplicationJob_Perform_ImagePointers(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// Create a replication job instance
	replicationJob := &ReplicationJob{
		BaseJob: baseJob,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, ImageType: models.ImageType_Curated, OsType: models.OsType_Linux}
	image2 := &models.ImageDefinition{Id: 2, ImageType: models.ImageType_Curated, OsType: models.OsType_Linux, PointsToImageDefinitionId: nil}
	image3 := &models.ImageDefinition{Id: 3, ImageType: models.ImageType_Curated, OsType: models.OsType_Linux, PointsToImageDefinitionId: &image1.Id}
	imageVersionsForImage1 := []*models.ImageVersion{{Version: "1.0.0", ImageDefinitionId: image1.Id, State: models.ImageVersionState_Ready}}
	imageVersionsForImage2 := []*models.ImageVersion{{Version: "1.0.0", ImageDefinitionId: image2.Id, State: models.ImageVersionState_Ready}}
	azureImageVersionKey1 := azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", "1.0.0")
	azureImageVersionKey2 := azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-2", "1.0.0")

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1, image2, image3}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersionsForImage1, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image2.Id).Return(imageVersionsForImage2, nil)

	// Set up the expectations for the mock RunnerClient
	mockRunnerClient.EXPECT().KnownRunnerUrls().Return([]string{"http://test.net/runner1"}).AnyTimes()
	mockRunnerClient.EXPECT().GetImageUsage(ctx, gomock.Any(), image1.Id).Return(&vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 5000,
					"westus": 2000,
				},
			},
		},
	}, nil)
	mockRunnerClient.EXPECT().GetImageUsage(ctx, gomock.Any(), image2.Id).Return(&vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 250,
					"westus": 251,
				},
			},
		},
	}, nil)
	mockRunnerClient.EXPECT().GetImageUsage(ctx, gomock.Any(), image3.Id).Return(&vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 5000,
					"westus": 3000,
				},
			},
		},
	}, nil)

	mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(gomock.Any(), image1.Id, "1.0.0").Return(&models.ImageVersionReplicationData{
		ImageDefinitionId:     image1.Id,
		ImageVersion:          "1.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{},
	}, nil)
	mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(gomock.Any(), image2.Id, "1.0.0").Return(&models.ImageVersionReplicationData{
		ImageDefinitionId:     image2.Id,
		ImageVersion:          "1.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{},
	}, nil)

	mockManager.EXPECT().GetGalleryImageVersionKey(gomock.Any(), imageVersionsForImage1[0]).Return(azureImageVersionKey1, nil).Times(1)
	mockManager.EXPECT().GetGalleryImageVersionKey(gomock.Any(), imageVersionsForImage2[0]).Return(azureImageVersionKey2, nil).Times(1)
	mockManager.EXPECT().GetSupportedImageRegions(gomock.Any()).Return([]string{"eastus", "westus"}).Times(2)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		ImageDefinitionId: image1.Id,
		ImageVersion:      "1.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      10000,
				ReplicaCount: 40,
			},
			"westus": {
				VMCount:      5000,
				ReplicaCount: 20,
			},
		},
	}).Return(nil)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		ImageDefinitionId: image2.Id,
		ImageVersion:      "1.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      250,
				ReplicaCount: 1,
			},
			"westus": {
				VMCount:      251,
				ReplicaCount: 2,
			},
		},
	}).Return(nil)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azureImageVersionKey1, azure.ImageVersionReplications{
		{
			Region:        "eastus",
			ReplicasCount: 40,
		},
		{
			Region:        "westus",
			ReplicasCount: 20,
		},
	}).Return(nil)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azureImageVersionKey2, azure.ImageVersionReplications{
		{
			Region:        "eastus",
			ReplicasCount: 1,
		},
		{
			Region:        "westus",
			ReplicasCount: 2,
		},
	}).Return(nil)

	err := replicationJob.Perform(ctx)
	assert.NoError(t, err)
}

func TestReplicationJob_Perform_SkipNonReadyImageVersions(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// Create a replication job instance
	replicationJob := &ReplicationJob{
		BaseJob: baseJob,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux}
	image2 := &models.ImageDefinition{Id: 2, OsType: models.OsType_Linux}
	imageVersions1 := []*models.ImageVersion{
		{Version: "1.0.0", State: models.ImageVersionState_ProvisionFailed},
		{Version: "1.0.1", State: models.ImageVersionState_Ready},
	}
	imageVersions2 := []*models.ImageVersion{
		{Version: "2.0.0", State: models.ImageVersionState_Provisioning},
	}
	azureImageVersionKey2 := azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", "1.0.1")

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1, image2}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions1, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image2.Id).Return(imageVersions2, nil)

	// Set up the expectations for the mock RunnerClient
	mockRunnerClient.EXPECT().KnownRunnerUrls().Return([]string{"http://test.net/runner1"}).AnyTimes()
	mockRunnerClient.EXPECT().GetImageUsage(ctx, gomock.Any(), image1.Id).Return(&vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 300,
				},
			},
			"1.0.1": {
				VMCountPerRegion: map[string]int32{
					"eastus": 250,
				},
			},
		},
	}, nil)
	mockRunnerClient.EXPECT().GetImageUsage(ctx, gomock.Any(), image2.Id).Return(&vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"2.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 700,
					"westus": 1500,
				},
			},
		},
	}, nil)

	mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(gomock.Any(), image1.Id, "1.0.1").Return(&models.ImageVersionReplicationData{
		Id:                    6,
		ImageDefinitionId:     1,
		ImageVersion:          "1.0.1",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{},
	}, nil).Times(1)

	mockManager.EXPECT().GetSupportedImageRegions(gomock.Any()).Return([]string{"eastus", "westus"}).Times(1)

	mockManager.EXPECT().GetGalleryImageVersionKey(gomock.Any(), imageVersions1[1]).Return(azureImageVersionKey2, nil).Times(1)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		Id:                6,
		ImageDefinitionId: image1.Id,
		ImageVersion:      "1.0.1",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      250,
				ReplicaCount: 1,
			},
			"westus": {
				VMCount:      0,
				ReplicaCount: 1,
			},
		},
	}).Return(nil)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azureImageVersionKey2, azure.ImageVersionReplications{
		{
			Region:        "eastus",
			ReplicasCount: 1,
		},
		{
			Region:        "westus",
			ReplicasCount: 1,
		},
	}).Return(nil)

	// Call the Perform method
	err := replicationJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestReplicationJob_Perform_Latest(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// Create a replication job instance
	replicationJob := &ReplicationJob{
		BaseJob: baseJob,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux}
	imageVersions := []*models.ImageVersion{
		{Version: "1.0.0", State: models.ImageVersionState_Ready, Enabled: true},
		{Version: "1.0.1", State: models.ImageVersionState_Ready, Enabled: true},
		{Version: "1.1.1", State: models.ImageVersionState_Ready, Enabled: false},
		{Version: "2.0.0", State: models.ImageVersionState_Ready, Enabled: true},
	}

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions, nil)

	// Set up the expectations for the mock RunnerClient
	mockRunnerClient.EXPECT().KnownRunnerUrls().Return([]string{"http://test.net/runner1"}).AnyTimes()
	mockRunnerClient.EXPECT().GetImageUsage(ctx, gomock.Any(), image1.Id).Return(&vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"latest": {
				VMCountPerRegion: map[string]int32{
					"eastus": 300,
				},
			},
		},
	}, nil)

	mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(gomock.Any(), image1.Id, gomock.Any()).DoAndReturn(
		func(ctx context.Context, imageID uint64, version string) (*models.ImageVersionReplicationData, error) {
			// Create a new ImageVersionReplicationData with the last version
			replicationData := &models.ImageVersionReplicationData{
				Id:                    6,
				ImageDefinitionId:     1,
				ImageVersion:          version,
				RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{},
			}

			return replicationData, nil
		},
	).Times(4)

	mockManager.EXPECT().GetSupportedImageRegions(gomock.Any()).Return([]string{"eastus"}).Times(4)

	mockManager.EXPECT().GetGalleryImageVersionKey(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, v *models.ImageVersion) (*azure.GalleryImageVersionKey, error) {
			return azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", v.Version), nil
		},
	).Times(4)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		Id:                6,
		ImageDefinitionId: image1.Id,
		ImageVersion:      "2.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      300,
				ReplicaCount: 2,
			},
		},
	}).Return(nil)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		Id:                6,
		ImageDefinitionId: image1.Id,
		ImageVersion:      "1.1.1",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      300,
				ReplicaCount: 2,
			},
		},
	}).Return(nil)

	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		Id:                6,
		ImageDefinitionId: image1.Id,
		ImageVersion:      "1.0.1",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      300,
				ReplicaCount: 2,
			},
		},
	}).Return(nil)

	// Scale down to 0 for the non-latest image version.
	mockImagesStore.EXPECT().UpdateImageReplication(gomock.Any(), &models.ImageVersionReplicationData{
		Id:                6,
		ImageDefinitionId: image1.Id,
		ImageVersion:      "1.0.0",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      0,
				ReplicaCount: 1,
			},
		},
	}).Return(nil)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", "2.0.0"), []azure.ImageVersionRegionReplication{
		{
			Region:        "eastus",
			ReplicasCount: 2,
		},
	}).Return(nil).Times(1)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", "1.1.1"), []azure.ImageVersionRegionReplication{
		{
			Region:        "eastus",
			ReplicasCount: 2,
		},
	}).Return(nil).Times(1)

	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", "1.0.1"), []azure.ImageVersionRegionReplication{
		{
			Region:        "eastus",
			ReplicasCount: 2,
		},
	}).Return(nil).Times(1)

	// Non-latest should scale down to 1.
	mockAzureClient.EXPECT().UpdateImageVersionReplications(gomock.Any(), azure.NewGalleryImageVersionKey("subId", "rgName", "ims-gallery", "ims-gallery-image-definition-1", "1.0.0"), []azure.ImageVersionRegionReplication{
		{
			Region:        "eastus",
			ReplicasCount: 1,
		},
	}).Return(nil).Times(1)

	// Call the Perform method
	err := replicationJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestReplicationJob_Perform_ImagesStoreError(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// Create a replication job instance
	replicationJob := &ReplicationJob{
		BaseJob: baseJob,
	}

	// Set up the expectation for the mock ImagesStore
	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return(nil, fmt.Errorf("test"))

	// Call the Perform method
	err := replicationJob.Perform(ctx)

	// Assert that the error matches the expected error
	assert.ErrorContains(t, err, "replication job failed to list image definitions: test")
}

func TestReplicationJob_Perform_RunnerClientError(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// Create a replication job instance
	replicationJob := &ReplicationJob{
		BaseJob: baseJob,
	}

	// Define the test data
	image := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux}
	imageVersions := []*models.ImageVersion{
		{Version: "1.0.0"},
		{Version: "1.0.1"},
	}

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image.Id).Return(imageVersions, nil)

	// Set up the expectation for the mock RunnerClient
	mockRunnerClient.EXPECT().KnownRunnerUrls().Return([]string{"http://test.net/runner1"}).AnyTimes()
	mockRunnerClient.EXPECT().GetImageUsage(gomock.Any(), gomock.Any(), image.Id).Return(nil, errors.New("failed to get runner usage"))

	// Should never be called
	mockImagesStore.EXPECT().GetImageReplicationsByImageIdAndVersion(gomock.Any(), gomock.Any(), gomock.Any()).Return(nil, nil).Times(0)

	// Call the Perform method
	err := replicationJob.Perform(ctx)

	// Assert that the error matches the expected error
	assert.EqualError(t, err, "replication job failed for some image definitions")
}

func TestShouldSkipImageDefinition(t *testing.T) {
	tests := []struct {
		testName        string
		imageDefinition *models.ImageDefinition
		expectedOutput  bool
	}{
		{
			testName: "skip image pointer",
			imageDefinition: &models.ImageDefinition{
				Id:                        5,
				PointsToImageDefinitionId: utils.ToPtr[uint64](5),
				OsType:                    models.OsType_Linux,
				Architecture:              models.Architecture_X64,
			},
			expectedOutput: true,
		},
		{
			testName: "skip macos image",
			imageDefinition: &models.ImageDefinition{
				Id:                        5,
				PointsToImageDefinitionId: nil,
				OsType:                    models.OsType_MacOS,
				Architecture:              models.Architecture_X64,
			},
			expectedOutput: true,
		},
		{
			testName: "process linux image",
			imageDefinition: &models.ImageDefinition{
				Id:                        5,
				PointsToImageDefinitionId: nil,
				OsType:                    models.OsType_Linux,
				Architecture:              models.Architecture_X64,
			},
			expectedOutput: false,
		},
		{
			testName: "process windows image",
			imageDefinition: &models.ImageDefinition{
				Id:                        5,
				PointsToImageDefinitionId: nil,
				OsType:                    models.OsType_Windows,
				Architecture:              models.Architecture_X64,
			},
			expectedOutput: false,
		},
	}

	replicationJob := &ReplicationJob{}

	for _, test := range tests {
		t.Run(test.testName, func(t *testing.T) {
			actualOutput := replicationJob.shouldSkipImageDefinition(test.imageDefinition)
			assert.Equal(t, test.expectedOutput, actualOutput)
		})
	}
}

func TestShouldSkipImageVersion(t *testing.T) {
	tests := []struct {
		testName       string
		imageVersion   *models.ImageVersion
		expectedOutput bool
	}{
		{
			testName: "image version in incorrect state",
			imageVersion: &models.ImageVersion{
				Id:    5,
				State: models.ImageVersionState_ProvisionFailed,
			},
			expectedOutput: true,
		},
		{
			testName: "correct image version",
			imageVersion: &models.ImageVersion{
				Id:    5,
				State: models.ImageVersionState_Ready,
			},
			expectedOutput: false,
		},
	}

	replicationJob := &ReplicationJob{}

	for _, test := range tests {
		t.Run(test.testName, func(t *testing.T) {
			actualOutput := replicationJob.shouldSkipImageVersion(test.imageVersion)
			assert.Equal(t, test.expectedOutput, actualOutput)
		})
	}
}
