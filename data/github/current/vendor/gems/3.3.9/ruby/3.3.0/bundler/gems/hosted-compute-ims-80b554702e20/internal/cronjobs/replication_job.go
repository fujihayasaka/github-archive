package cronjobs

import (
	"context"
	"encoding/json"
	"fmt"
	"math"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
	"go.uber.org/zap/zapcore"
)

const VMsPerReplica float64 = 250

type ReplicationJob struct {
	BaseJob
}

func (j *ReplicationJob) GetName() string {
	return "ReplicationJob"
}

func (j *ReplicationJob) Perform(ctx context.Context) error {
	// Currently just curated are supported. This will need to iterate through all image definitions.
	allCuratedImages, err := j.ImagesStore.ListCuratedImageDefinitions(ctx)
	if err != nil {
		j.Logger.ErrorWithReport("replication job failed to list image definitions", err)
		return fmt.Errorf("replication job failed to list image definitions: %w", err)
	}

	hasImageDefinitionReplicationErrors := false
	for _, imageDefinition := range allCuratedImages {
		if j.shouldSkipImageDefinition(imageDefinition) {
			continue
		}

		loggerFields := []zapcore.Field{
			kvp.Uint64("image_definition_id", imageDefinition.Id),
			kvp.String("image_type", string(imageDefinition.ImageType)),
		}

		imagePointersForImageDefinition := j.getImagePointersForImageDefinition(imageDefinition, allCuratedImages)
		if hasImageVersionsReplicationErrors, err := j.handleReplicationForImageDefinition(ctx, imageDefinition, imagePointersForImageDefinition); err != nil {
			hasImageDefinitionReplicationErrors = true
			j.Logger.ErrorWithReport("replication job failed for image definition", err, loggerFields...)
		} else if hasImageVersionsReplicationErrors {
			hasImageDefinitionReplicationErrors = true
			j.Logger.Error("replication job failed for some image versions in image definition", loggerFields...)
		} else {
			j.Logger.Info("Replication job passed for all image versions in image definition successfully", loggerFields...)
		}
	}

	if hasImageDefinitionReplicationErrors {
		return fmt.Errorf("replication job failed for some image definitions")
	}

	return nil
}

func (j *ReplicationJob) handleReplicationForImageDefinition(ctx context.Context, imageDefinition *models.ImageDefinition, imagePointers []uint64) (bool, error) {
	imageVersions, err := j.ImagesStore.ListImageVersionsByDefinitionId(ctx, imageDefinition.Id)
	if err != nil {
		return false, fmt.Errorf("failed to list image versions for image definition: %w", err)
	}

	if len(imageVersions) == 0 {
		return false, nil
	}

	latestVersions := j.getLatestImageVersions(imageVersions)

	if err != nil {
		return false, fmt.Errorf("failed to get latest image version: %w", err)
	}

	runnerUsage, err := j.getAggregatedImagesUsage(ctx, append(imagePointers, imageDefinition.Id), latestVersions)
	if err != nil {
		return false, fmt.Errorf("failed to get aggregated images usage: %w", err)
	}

	hasImageVersionsReplicationErrors := false
	for _, imageVersion := range imageVersions {
		if j.shouldSkipImageVersion(imageVersion) {
			continue
		}

		loggerFields := []zapcore.Field{
			kvp.Uint64("image_definition_id", imageDefinition.Id),
			kvp.Uint64("image_version_id", imageVersion.Id),
			kvp.String("image_version", imageVersion.Version),
			kvp.String("image_type", string(imageDefinition.ImageType)),
		}

		err = j.handleReplicationForImageVersion(ctx, imageDefinition, runnerUsage.ImageVersions[imageVersion.Version], imageVersion)
		if err != nil {
			hasImageVersionsReplicationErrors = true
			j.Logger.ErrorWithReport("replication job failed for image version", err, loggerFields...)
		} else {
			j.Logger.Info("replication job passed for image version", loggerFields...)
		}
	}

	return hasImageVersionsReplicationErrors, nil
}

func (j *ReplicationJob) getLatestImageVersions(imageVersions []*models.ImageVersion) []*models.ImageVersion {
	models.SortImageVersionsByVersion(imageVersions)

	latestVersions := []*models.ImageVersion{}
	enabledCount := 0

	for i := 0; i < len(imageVersions)-1; i++ {
		if i == 0 || i == 1 {
			// Grab the latest two image versions, regardless of whether they are enabled or not.
			latestVersions = append(latestVersions, imageVersions[i])

			if imageVersions[i].Enabled {
				enabledCount++
			}

		} else if imageVersions[i].Enabled {
			// If we have one or two non-enabled version, we need to grab the latest enabled versions to at least have two enabled versions.
			latestVersions = append(latestVersions, imageVersions[i])
			enabledCount++
		}

		// We need at least 2 enabled versions.
		if enabledCount >= 2 {
			break
		}
	}
	return latestVersions
}

func (j *ReplicationJob) handleReplicationForImageVersion(ctx context.Context, imageDefinition *models.ImageDefinition, imageVersionUsage vssf_runner.ImageVersionUsage, imageVersion *models.ImageVersion) error {
	versionLogger := utils.NewLoggerWithFields(
		j.Logger,
		kvp.Uint64("image_definition_id", imageDefinition.Id),
		kvp.String("image_type", string(imageDefinition.ImageType)),
		kvp.Uint64("image_version_id", imageVersion.Id),
		kvp.String("image_version", imageVersion.Version),
	)

	localImageReplicationData, err := j.ImagesStore.GetImageReplicationsByImageIdAndVersion(ctx, imageDefinition.Id, imageVersion.Version)
	if err != nil {
		return fmt.Errorf("failed to get image replication data: %w", err)
	}

	var (
		shouldUpdateAzure                    = false
		imageVersionRegionsCalculationResult = imageVersionRegionsCalculationResult{}
	)

	for _, region := range j.Manager.GetSupportedImageRegions(imageDefinition) {
		// Get the current production usage.
		vmUsageInRegion, exists := imageVersionUsage.VMCountPerRegion[region]
		if !exists {
			vmUsageInRegion = 0
		}

		// Get the historical usage from the database to see if we need to update the number of replicas.
		historicalUsage, exists := localImageReplicationData.RegionReplicationData[region]

		if !exists {
			historicalUsage = models.ImageVersionRegionalReplicationData{VMCount: 0, ReplicaCount: 0}
		}

		// Calculate the expected VM count based on the current runner usage and the number of VMs per replica.
		replicaCountRequired := int32(math.Ceil(float64(vmUsageInRegion) / VMsPerReplica))
		replicaCountToSet := replicaCountRequired

		if replicaCountToSet < 1 {
			replicaCountToSet = 1
		}

		if replicaCountToSet > 100 {
			replicaCountToSet = 100
		}

		if replicaCountToSet != historicalUsage.ReplicaCount {
			shouldUpdateAzure = true
		}

		imageVersionRegionsCalculationResult = append(imageVersionRegionsCalculationResult, &imageVersionRegionCalculationResult{
			Region:               region,
			VMCount:              vmUsageInRegion,
			ReplicaCountRequired: replicaCountRequired,
			ReplicaCountToSet:    replicaCountToSet,
		})

		// Prepare for updating the database after we finish updating all of the regions.
		localImageReplicationData.RegionReplicationData[region] = models.ImageVersionRegionalReplicationData{
			ReplicaCount: replicaCountToSet,
			VMCount:      vmUsageInRegion,
		}

		j.Logger.Statter.Distribution("replication.image_version.calculation.vm_count", stats.Tags{"azure_region": region}, float64(vmUsageInRegion))
		j.Logger.Statter.Distribution("replication.image_version.calculation.replica_count_required", stats.Tags{"azure_region": region}, float64(replicaCountRequired))
		j.Logger.Statter.Distribution("replication.image_version.calculation.replica_count_to_set", stats.Tags{"azure_region": region}, float64(replicaCountToSet))
	}

	if replicationCalculationResultsSerialized, err := json.Marshal(imageVersionRegionsCalculationResult); err != nil {
		versionLogger.ErrorWithReport("failed to serialize replication calculation results", err)
	} else {
		versionLogger.Info("replication for image version is calculated", kvp.String("replications", string(replicationCalculationResultsSerialized)))
	}

	if shouldUpdateAzure {
		azureReplicationsToSet := imageVersionRegionsCalculationResult.ToAzureRegionReplication()

		if azureReplicationsToSetSerialized, err := json.Marshal(azureReplicationsToSet); err != nil {
			versionLogger.ErrorWithReport("failed to serialize azure replication data", err)
		} else {
			versionLogger.Info("updating image replication in Azure", kvp.String("image_version_replicas", string(azureReplicationsToSetSerialized)))
		}

		imageVersionKey, err := j.Manager.GetGalleryImageVersionKey(ctx, imageVersion)
		if err != nil {
			return fmt.Errorf("failed to get gallery image version key: %w", err)
		}

		// Update Azure prior to updating the database. We want to make sure that if we fail to update Azure, we don't update the database.
		err = j.AzureClient.UpdateImageVersionReplications(ctx, imageVersionKey, azureReplicationsToSet)
		if err != nil {
			return fmt.Errorf("failed to update image replication in Azure: %w", err)
		}

		j.Logger.Statter.Counter("replication.image_version.update_azure", nil, 1)
	} else {
		versionLogger.Info("skip updating image replication in Azure")
	}

	// Always update the database because we should always have new runner counts.
	err = j.ImagesStore.UpdateImageReplication(ctx, localImageReplicationData)
	if err != nil {
		return fmt.Errorf("failed to update image replication data: %w", err)
	}

	return nil
}

func (j *ReplicationJob) shouldSkipImageDefinition(imageDefinition *models.ImageDefinition) bool {
	// image pointers are processed by referenced images
	return imageDefinition.PointsToImageDefinitionId != nil
}

func (j *ReplicationJob) shouldSkipImageVersion(imageVersion *models.ImageVersion) bool {
	return imageVersion.State != models.ImageVersionState_Ready
}
