package cronjobs

import (
	"context"
	"testing"

	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
	"github.com/stretchr/testify/assert"
)

func TestReplicationJob_GetImageUsage(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	replicationJob := &ReplicationJob{
		BaseJob: baseJob,
		Kind:    models.ImageType_Curated,
	}
	imageDefinition := &models.ImageDefinition{
		Id:        123,
		ImageType: models.ImageType_Curated,
	}

	mockRunnerClient.EXPECT().KnownRunnerUrls().Return([]string{"http://test.net/runner1", "http://test.net/runner2"}).AnyTimes()

	call := mockRunnerClient.EXPECT().GetImageUsage(ctx, "http://test.net/runner1", imageDefinition).Return(
		&vssf_runner.ImageUsage{
			ImageVersions: map[string]vssf_runner.ImageVersionUsage{
				"1.0.0": {
					VMCountPerRegion: map[string]int32{
						"eastus": 1,
					},
				},
				"1.0.1": {
					VMCountPerRegion: map[string]int32{
						"eastus": 3,
					},
				},
			},
		},
		nil)

	mockRunnerClient.EXPECT().GetImageUsage(ctx, "http://test.net/runner2", imageDefinition).AnyTimes().After(call).Return(
		&vssf_runner.ImageUsage{
			ImageVersions: map[string]vssf_runner.ImageVersionUsage{
				"1.0.0": {
					VMCountPerRegion: map[string]int32{
						"eastus": 1,
						"westus": 1,
					},
				},
			},
		},
		nil)

	expectedUsage := &vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus": 2,
					"westus": 1,
				},
			},
			"1.0.1": {
				VMCountPerRegion: map[string]int32{
					"eastus": 3,
				},
			},
		},
	}

	actualUsage, err := replicationJob.getImageUsage(ctx, imageDefinition)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if actualUsage == nil {
		t.Error("Expected non-nil usage, but got nil")
	}

	assert.Equal(t, expectedUsage, actualUsage)
}

func TestReplicationJob_GetAggregatedImagesUsage(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	replicationJob := &ReplicationJob{
		BaseJob: baseJob,
		Kind:    models.ImageType_Curated,
	}
	imageDefinitions := []*models.ImageDefinition{
		{
			Id:        101,
			ImageType: models.ImageType_Curated,
		},
		{
			Id:        102,
			ImageType: models.ImageType_Curated,
		},
	}

	mockRunnerClient.EXPECT().KnownRunnerUrls().Return([]string{"http://test.net/runner1"}).AnyTimes()

	call := mockRunnerClient.EXPECT().GetImageUsage(ctx, "http://test.net/runner1", imageDefinitions[0]).Return(
		&vssf_runner.ImageUsage{
			ImageVersions: map[string]vssf_runner.ImageVersionUsage{
				"1.0.0": {
					VMCountPerRegion: map[string]int32{
						"eastus": 1,
						"westus": 2,
					},
				},
				"latest": {
					VMCountPerRegion: map[string]int32{
						"eastus": 3,
					},
				},
			},
		},
		nil)

	mockRunnerClient.EXPECT().GetImageUsage(ctx, "http://test.net/runner1", imageDefinitions[1]).AnyTimes().After(call).Return(
		&vssf_runner.ImageUsage{
			ImageVersions: map[string]vssf_runner.ImageVersionUsage{
				"1.0.0": {
					VMCountPerRegion: map[string]int32{
						"westus":  1,
						"westus2": 5,
					},
				},
				"1.0.1": {
					VMCountPerRegion: map[string]int32{
						"eastus": 3,
						"westus": 3,
					},
				},
				"latest": {
					VMCountPerRegion: map[string]int32{
						"westus2": 7,
					},
				},
			},
		},
		nil)

	expectedUsage := &vssf_runner.ImageUsage{
		ImageVersions: map[string]vssf_runner.ImageVersionUsage{
			"1.0.0": {
				VMCountPerRegion: map[string]int32{
					"eastus":  1,
					"westus":  3,
					"westus2": 5,
				},
			},
			"1.0.1": {
				VMCountPerRegion: map[string]int32{
					"eastus":  6,
					"westus":  3,
					"westus2": 7,
				},
			},
			"1.0.2": {
				VMCountPerRegion: map[string]int32{
					"eastus":  3,
					"westus2": 7,
				},
			},
		},
	}

	actualUsage, err := replicationJob.getAggregatedImagesUsage(ctx, imageDefinitions, []*models.ImageVersion{{Version: "1.0.2"}, {Version: "1.0.1"}})
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if actualUsage == nil {
		t.Error("Expected non-nil usage, but got nil")
	}

	assert.Equal(t, expectedUsage, actualUsage)
}

func TestReplicationJob_GetImagePointersForImageDefinition(t *testing.T) {
	allImageDefinitions := []*models.ImageDefinition{
		{Id: 1, ImageType: models.ImageType_Curated},
		{Id: 2, ImageType: models.ImageType_Curated},
		{Id: 3, ImageType: models.ImageType_Curated, PointsToImageDefinitionId: nil},
		{Id: 4, ImageType: models.ImageType_Curated, PointsToImageDefinitionId: utils.ToPtr[uint64](1)},
		{Id: 5, ImageType: models.ImageType_Customer},
		{Id: 6, ImageType: models.ImageType_Customer, PointsToImageDefinitionId: utils.ToPtr[uint64](5)},
	}

	replicationJob := &ReplicationJob{}
	actual := replicationJob.getImagePointersForImageDefinition(allImageDefinitions[0], allImageDefinitions)
	assert.Equal(t, 1, len(actual))
	assert.Equal(t, uint64(4), actual[0].Id)

	actual = replicationJob.getImagePointersForImageDefinition(allImageDefinitions[1], allImageDefinitions)
	assert.Equal(t, 0, len(actual))

	actual = replicationJob.getImagePointersForImageDefinition(allImageDefinitions[2], allImageDefinitions)
	assert.Equal(t, 0, len(actual))

	actual = replicationJob.getImagePointersForImageDefinition(allImageDefinitions[3], allImageDefinitions)
	assert.Equal(t, 0, len(actual))

	actual = replicationJob.getImagePointersForImageDefinition(allImageDefinitions[4], allImageDefinitions)
	assert.Equal(t, 0, len(actual))
}

func TestImageVersionRegionCalculationResultToAzureRegionReplication(t *testing.T) {
	calculationResults := imageVersionRegionsCalculationResult{
		&imageVersionRegionCalculationResult{
			Region:               "westus",
			VMCount:              100,
			ReplicaCountRequired: 50,
			ReplicaCountToSet:    30,
		},
		&imageVersionRegionCalculationResult{
			Region:               "eastus",
			VMCount:              1000,
			ReplicaCountRequired: 500,
			ReplicaCountToSet:    300,
		},
	}

	expectedAzureReplicas := azure.ImageVersionReplications{
		{
			Region:        "westus",
			ReplicasCount: 30,
		},
		{
			Region:        "eastus",
			ReplicasCount: 300,
		},
	}

	assert.Equal(t, expectedAzureReplicas, calculationResults.ToAzureRegionReplication())
}
