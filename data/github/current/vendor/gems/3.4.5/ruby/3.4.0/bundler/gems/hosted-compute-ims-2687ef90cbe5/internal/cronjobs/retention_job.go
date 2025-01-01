package cronjobs

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

const defaultVersionsToKeep int = 20

type RetentionJob struct {
	BaseJob
	Kind           models.ImageType
	VersionsToKeep int
}

func (j *RetentionJob) GetName() string {
	return "RetentionJob"
}

func (j *RetentionJob) Perform(ctx context.Context) error {
	if !featureflags.IsFeatureFlagEnabledGlobally(ctx, featureflags.FeatureFlag_ImsRetentionJobEnable) {
		logger.Info(ctx, "Retention job is disabled, skipping job")
		return nil
	}

	var imageDefinitions []*models.ImageDefinition

	switch j.Kind {
	case models.ImageType_Curated:
		allCuratedImages, err := j.ImagesStore.ListCuratedImageDefinitions(ctx)
		if err != nil {
			logger.ErrorWithReport(ctx, "retention job failed to list image definitions", err)
			return fmt.Errorf("retention job failed to list image definitions: %w", err)
		}
		imageDefinitions = allCuratedImages
	case models.ImageType_Customer:
		allCustomerImages, err := j.ImagesStore.ListAllCustomerImageDefinitions(ctx)
		if err != nil {
			logger.ErrorWithReport(ctx, "retention job failed to list image definitions", err)
			return fmt.Errorf("retention job failed to list image definitions: %w", err)
		}
		imageDefinitions = allCustomerImages
	}

	hasImageDefinitionsRetentionErrors := false
	for _, imageDefinition := range imageDefinitions {
		imageDefCtx := stash.WithLoggingFields(ctx,
			kvp.String("image_type", string(imageDefinition.ImageType)),
			kvp.Uint64("image_definition_id", imageDefinition.Id),
		)

		if j.shouldSkipImageDefinition(imageDefinition) {
			continue
		}

		if hasImageVersionsRetentionErrors, err := j.cleanUpImageVersions(imageDefCtx, imageDefinition); err != nil {
			hasImageDefinitionsRetentionErrors = true
			logger.ErrorWithReport(imageDefCtx, "retention job failed for image definition", err)
		} else if hasImageVersionsRetentionErrors {
			hasImageDefinitionsRetentionErrors = true
			logger.Error(imageDefCtx, "retention job failed for some image versions in image definition")
		} else {
			logger.Info(imageDefCtx, "Retention job passed for all image versions in image definition successfully")
		}
	}

	if hasImageDefinitionsRetentionErrors {
		return fmt.Errorf("retention job failed for some image definitions")
	}

	return nil
}

func (j *RetentionJob) cleanUpImageVersions(ctx context.Context, imageDefinition *models.ImageDefinition) (bool, error) {
	imageVersions, err := j.ImagesStore.ListImageVersionsByDefinitionId(ctx, imageDefinition.Id)
	if err != nil {
		return false, fmt.Errorf("failed to list image versions for image definition: %w", err)
	}

	versionsToKeep := j.VersionsToKeep
	if versionsToKeep == 0 {
		versionsToKeep = defaultVersionsToKeep
	}

	versionsToDelete := getVersionsToDelete(imageVersions, versionsToKeep)

	if len(versionsToDelete) > 0 {
		versions := make([]string, len(versionsToDelete))
		for i, version := range versionsToDelete {
			versions[i] = version.Version
		}
		logger.Info(ctx, fmt.Sprintf("Image versions to be removed: %s", strings.Join(versions, ", ")))
	}

	switch j.Kind {
	case models.ImageType_Curated:
		if !featureflags.IsFeatureFlagEnabledGlobally(ctx, featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages) {
			logger.Info(ctx, "Retention job delete curated images is disabled, skipping deletion")
			return false, nil
		}
	case models.ImageType_Customer:
		if !featureflags.IsFeatureFlagEnabledGlobally(ctx, featureflags.FeatureFlag_ImsRetentionJobDeleteCustomerImages) {
			logger.Info(ctx, "Retention job delete customer images is disabled, skipping deletion")
			return false, nil
		}
	}

	hasImageVersionsRetentionErrors := false
	for _, imageVersion := range versionsToDelete {
		if err := j.processImageVersionDeletion(ctx, imageDefinition, imageVersion); err != nil {
			hasImageVersionsRetentionErrors = true
		}
	}
	return hasImageVersionsRetentionErrors, nil
}

func (j *RetentionJob) processImageVersionDeletion(ctx context.Context, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion) error {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(imageDefinition.ImageType)),
		kvp.Uint64("image_definition_id", imageDefinition.Id),
		kvp.Uint64("image_version_id", imageVersion.Id),
		kvp.String("image_version", imageVersion.Version),
	)

	// Skip deletion if the image version is already in "Deleting" state
	if imageVersion.State == models.ImageVersionState_Deleting {
		logger.Info(ctx, "Skipping deletion for image version as it is already in 'Deleting' state")
		return nil
	}

	err := j.PromotionStartClient.StartAsyncImageVersionDeletion(ctx, imageVersion.Id)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to start image version deletion", err, kvp.Uint64("image_version_id", imageVersion.Id))
		return err
	}
	logger.Info(ctx, "successfully queue deleting image version job")

	return nil
}

func getVersionsToDelete(imageVersions []*models.ImageVersion, versionsToKeep int) []*models.ImageVersion {
	if len(imageVersions) <= versionsToKeep {
		return nil
	}

	// Sort image versions by its version number
	models.SortImageVersionsByVersion(imageVersions)

	// Collect IDs of versions to delete
	return imageVersions[versionsToKeep:]
}

func (j *RetentionJob) shouldSkipImageDefinition(imageDefinition *models.ImageDefinition) bool {
	// skip pointer
	return imageDefinition.PointsToImageDefinitionId != nil
}
