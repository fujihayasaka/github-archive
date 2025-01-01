package cronjobs

import (
	"context"
	"encoding/json"
	"fmt"
	"math"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
	"go.uber.org/zap/zapcore"
)

const VMsPerReplica float64 = 250

type ReplicationJob struct {
	BaseJob
	Kind models.ImageType
}

func (j *ReplicationJob) GetName() string {
	return "ReplicationJob"
}

func (j *ReplicationJob) Perform(ctx context.Context) error {
	var imageDefinitions []*models.ImageDefinition

	switch j.Kind {
	case models.ImageType_Curated:
		// Iterate through all curated image definitions.
		allCuratedImages, err := j.ImagesStore.ListCuratedImageDefinitions(ctx)
		if err != nil {
			logger.ErrorWithReport(ctx, "replication job failed to list image definitions", err)
			return fmt.Errorf("replication job failed to list image definitions: %w", err)
		}
		imageDefinitions = allCuratedImages
	case models.ImageType_Customer:
		// Iterate through all customer image definitions.
		allCustomerImages, err := j.ImagesStore.ListAllCustomerImageDefinitions(ctx)
		if err != nil {
			logger.ErrorWithReport(ctx, "replication job failed to list image definitions", err)
			return fmt.Errorf("replication job failed to list image definitions: %w", err)
		}
		imageDefinitions = allCustomerImages
	}

	hasImageDefinitionReplicationErrors := false
	for _, imageDefinition := range imageDefinitions {
		if j.shouldSkipImageDefinition(imageDefinition) {
			continue
		}

		loggerFields := []zapcore.Field{
			kvp.Uint64("image_definition_id", imageDefinition.Id),
			kvp.String("image_type", string(imageDefinition.ImageType)),
		}

		imagePointersForImageDefinition := j.getImagePointersForImageDefinition(imageDefinition, imageDefinitions)
		if hasImageVersionsReplicationErrors, err := j.handleReplicationForImageDefinition(ctx, imageDefinition, imagePointersForImageDefinition); err != nil {
			hasImageDefinitionReplicationErrors = true
			logger.ErrorWithReport(ctx, "replication job failed for image definition", err, loggerFields...)
		} else if hasImageVersionsReplicationErrors {
			hasImageDefinitionReplicationErrors = true
			logger.Error(ctx, "replication job failed for some image versions in image definition", loggerFields...)
		} else {
			logger.Info(ctx, "Replication job passed for all image versions in image definition successfully", loggerFields...)
		}
	}

	if hasImageDefinitionReplicationErrors {
		return fmt.Errorf("replication job failed for some image definitions")
	}

	return nil
}

func (j *ReplicationJob) handleReplicationForImageDefinition(ctx context.Context, imageDefinition *models.ImageDefinition, imagePointers []*models.ImageDefinition) (bool, error) {
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

	runnerUsage, err := j.getAggregatedImagesUsage(ctx, append(imagePointers, imageDefinition), latestVersions)
	if err != nil {
		return false, fmt.Errorf("failed to get aggregated images usage: %w", err)
	}

	hasImageVersionsReplicationErrors := false
	for _, imageVersion := range imageVersions {
		if j.shouldSkipImageVersion(imageVersion) {
			continue
		}

		imageVersionCtx := stash.WithLoggingFields(ctx,
			kvp.Uint64("image_definition_id", imageDefinition.Id),
			kvp.Uint64("image_version_id", imageVersion.Id),
			kvp.String("image_version", imageVersion.Version),
			kvp.String("image_type", string(imageDefinition.ImageType)),
		)

		err = j.handleReplicationForImageVersion(ctx, imageDefinition, runnerUsage.ImageVersions[imageVersion.Version], imageVersion)
		if err != nil {
			hasImageVersionsReplicationErrors = true
			logger.ErrorWithReport(imageVersionCtx, "replication job failed for image version", err)
		} else {
			logger.Info(imageVersionCtx, "replication job passed for image version")
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
	ctx = stash.WithLoggingFields(ctx,
		kvp.Uint64("image_definition_id", imageDefinition.Id),
		kvp.String("image_type", string(imageDefinition.ImageType)),
		kvp.Uint64("image_version_id", imageVersion.Id),
		kvp.String("image_version", imageVersion.Version),
	)

	galleryPromotionProvider := j.PromotionClient.GalleryProvider()

	localImageReplicationData, err := j.ImagesStore.GetImageReplicationsByImageIdAndVersion(ctx, imageDefinition.Id, imageVersion.Version)
	if err != nil {
		return fmt.Errorf("failed to get image replication data: %w", err)
	}

	var (
		shouldUpdateAzure                    = false
		imageVersionRegionsCalculationResult = imageVersionRegionsCalculationResult{}
	)

	for _, region := range galleryPromotionProvider.GetAzureRegionsForReplication(imageDefinition) {
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

		statter.Distribution(ctx, "replication.image_version.calculation.vm_count", float64(vmUsageInRegion), kvp.String("azure_region", region))
		statter.Distribution(ctx, "replication.image_version.calculation.replica_count_required", float64(replicaCountRequired), kvp.String("azure_region", region))
		statter.Distribution(ctx, "replication.image_version.calculation.replica_count_to_set", float64(replicaCountToSet), kvp.String("azure_region", region))
	}

	if replicationCalculationResultsSerialized, err := json.Marshal(imageVersionRegionsCalculationResult); err != nil {
		logger.ErrorWithReport(ctx, "failed to serialize replication calculation results", err)
	} else {
		logger.Info(ctx, "replication for image version is calculated", kvp.String("replications", string(replicationCalculationResultsSerialized)))
	}

	if shouldUpdateAzure {
		azureReplicationsToSet := imageVersionRegionsCalculationResult.ToAzureRegionReplication()

		if azureReplicationsToSetSerialized, err := json.Marshal(azureReplicationsToSet); err != nil {
			logger.ErrorWithReport(ctx, "failed to serialize azure replication data", err)
		} else {
			logger.Info(ctx, "updating image replication in Azure", kvp.String("image_version_replicas", string(azureReplicationsToSetSerialized)))
		}

		// Update Azure prior to updating the database. We want to make sure that if we fail to update Azure, we don't update the database.
		if err := galleryPromotionProvider.UpdateImageVersionReplications(ctx, imageVersion, azureReplicationsToSet); err != nil {
			return err
		}

		statter.Increment(ctx, "replication.image_version.update_azure")
	} else {
		logger.Info(ctx, "skip updating image replication in Azure")
	}

	// Always update the database because we should always have new runner counts.
	err = j.ImagesStore.UpdateImageReplication(ctx, localImageReplicationData)
	if err != nil {
		return fmt.Errorf("failed to update image replication data: %w", err)
	}

	return nil
}

func (j *ReplicationJob) shouldSkipImageDefinition(imageDefinition *models.ImageDefinition) bool {
	if !imageDefinition.IsGalleryImageDefinition() {
		// replication management is only required for images hosted in Azure Gallery
		return true
	}

	if imageDefinition.PointsToImageDefinitionId != nil {
		// image pointers are processed by referenced images
		return true
	}

	if imageDefinition.ImageType == models.ImageType_Curated && imageDefinition.OwnerId == models.AzureDevOpsOwnerId {
		// skip replication for Azure DevOps images for now because we can't use Runner service as a source of usage data
		return true
	}

	return false
}

func (j *ReplicationJob) shouldSkipImageVersion(imageVersion *models.ImageVersion) bool {
	return imageVersion.State != models.ImageVersionState_Ready
}
