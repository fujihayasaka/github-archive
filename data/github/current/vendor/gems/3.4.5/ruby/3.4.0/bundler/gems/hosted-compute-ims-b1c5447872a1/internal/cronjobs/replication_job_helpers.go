package cronjobs

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
)

type imageVersionRegionCalculationResult struct {
	Region               string
	VMCount              int32
	ReplicaCountRequired int32
	ReplicaCountToSet    int32
}

type imageVersionRegionsCalculationResult []*imageVersionRegionCalculationResult

func (r imageVersionRegionsCalculationResult) ToAzureRegionReplication() azure.ImageVersionReplications {
	result := azure.ImageVersionReplications{}
	for _, regionData := range r {
		result = append(result, azure.ImageVersionRegionReplication{
			Region:        regionData.Region,
			ReplicasCount: regionData.ReplicaCountToSet,
		})
	}
	return result
}

func (j ReplicationJob) getImagePointersForImageDefinition(imageDefinition *models.ImageDefinition, allImageDefinitions []*models.ImageDefinition) []uint64 {
	imagePointers := make([]uint64, 0)

	if imageDefinition.ImageType != models.ImageType_Curated {
		return imagePointers
	}

	for _, image := range allImageDefinitions {
		if image.PointsToImageDefinitionId != nil && *image.PointsToImageDefinitionId == imageDefinition.Id {
			imagePointers = append(imagePointers, image.Id)
		}
	}

	return imagePointers
}

func (j ReplicationJob) getAggregatedImagesUsage(ctx context.Context, imageDefinitionIds []uint64, latestVersions []*models.ImageVersion) (*vssf_runner.ImageUsage, error) {
	aggregatedImagesUsage := &vssf_runner.ImageUsage{}

	for _, imageDefinitionId := range imageDefinitionIds {
		imageUsage, err := j.getImageUsage(ctx, imageDefinitionId)
		if err != nil {
			return nil, err
		}

		if usage, ok := imageUsage.ImageVersions["latest"]; ok {

			// Share the usage of the "latest" version to all of the latest versions in order to be able to change
			// the "latest" version without requiring a large scale up operation.
			for _, latestVersion := range latestVersions {

				// If we don't have any image usage for a latest image version, we need to initialize it
				if _, ok := imageUsage.ImageVersions[latestVersion.Version]; !ok {
					imageUsage.ImageVersions[latestVersion.Version] = vssf_runner.ImageVersionUsage{
						VMCountPerRegion: make(map[string]int32),
					}
				}

				for region, vmCount := range usage.VMCountPerRegion {
					imageUsage.ImageVersions[latestVersion.Version].VMCountPerRegion[region] += vmCount
				}
			}

			delete(imageUsage.ImageVersions, "latest")
		}

		aggregatedImagesUsage = vssf_runner.MergeImagesUsage(aggregatedImagesUsage, imageUsage)
	}

	return aggregatedImagesUsage, nil
}

func (j *ReplicationJob) getImageUsage(ctx context.Context, imageDefinitionId uint64) (*vssf_runner.ImageUsage, error) {
	totalImageUsage := &vssf_runner.ImageUsage{}

	for _, runnerInstance := range j.RunnerClient.KnownRunnerUrls() {
		requestLogger := utils.NewLoggerWithFields(
			j.Logger,
			kvp.String("runner_instance", runnerInstance),
			kvp.Uint64("image_definition_id", imageDefinitionId),
		)

		requestLogger.Info("Getting image usage")

		imageUsage, err := j.RunnerClient.GetImageUsage(ctx, runnerInstance, imageDefinitionId)
		if err != nil {
			return nil, fmt.Errorf("failed to get image usage: %w", err)
		}

		totalImageUsage = vssf_runner.MergeImagesUsage(totalImageUsage, imageUsage)
	}

	return totalImageUsage, nil
}
