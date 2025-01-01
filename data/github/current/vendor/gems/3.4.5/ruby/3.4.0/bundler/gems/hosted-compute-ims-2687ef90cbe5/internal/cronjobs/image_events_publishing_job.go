package cronjobs

import (
	"context"
	"fmt"
	"math"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	actionsHydroSchemas "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
)

type ImageEventsPublishingJob struct {
	BaseJob
}

func (j *ImageEventsPublishingJob) GetName() string {
	return "ImageEventsPublishingJob"
}

// This job publishes image snapshot-to-runner-group mappings grouped by owner ID
// as Hydro events for broker worker to enforce image name ownership policy.
// Issue for reference: https://github.com/github/actions-larger-runners/issues/3618
func (j *ImageEventsPublishingJob) Perform(ctx context.Context) error {
	if !featureflags.IsFeatureFlagEnabledGlobally(ctx, featureflags.FeatureFlag_ImsImageEventsPublishingJobEnable) {
		logger.Info(ctx, "Image events pubishing job is disabled, skipping job")
		return nil
	}

	hasErrors := false

	if err := j.publishRunnerGroupOwnershipHydroEvents(ctx); err != nil {
		hasErrors = true
		logger.ErrorWithReport(ctx, "failed to publish snapshot names to runner group mapping hydro events", err)
	}

	if hasErrors {
		return fmt.Errorf("customer image events publishing job finished with errors")
	}

	return nil
}

func (j *ImageEventsPublishingJob) publishRunnerGroupOwnershipHydroEvents(ctx context.Context) error {
	ownerIds, err := j.ImagesStore.ListAllCustomerImageOwners(ctx)
	if err != nil {
		return fmt.Errorf("failed to fetch all customer image definition owners: %w", err)
	}

	if len(ownerIds) == 0 {
		logger.Info(ctx, "no customer image owners found, skipping event publishing")
		return nil
	}

	for _, ownerId := range ownerIds {
		images, err := j.ImagesStore.ListCustomerImageDefinitionsByOwner(ctx, ownerId)
		if err != nil {
			return fmt.Errorf("failed to fetch customer image definitions for owner %s: %w", ownerId, err)
		}

		if len(images) == 0 {
			continue
		}

		err = j.publishImageNameToRunnerGroupHydroEvents(ctx, ownerId, images)
		if err != nil {
			// trace and exit the loop
			logger.ErrorWithReport(ctx, "failed to publish snapshot to runner group id hydro events", err)
			break
		}

		statter.Increment(ctx, "events.snapshots_to_runner_group", kvp.String("image_type", string(models.ImageType_Customer)))
	}

	return nil
}

func (j *ImageEventsPublishingJob) publishImageNameToRunnerGroupHydroEvents(ctx context.Context, ownerId string, images []*models.ImageDefinition) error {
	snapshotNamesToRunnerGroupMapping := make(map[string]int64)

	for _, image := range images {
		if image.RunnerGroupId != nil && *image.RunnerGroupId > 0 {
			// Ensure uint64 runner group ID can be safely converted to int64
			if *image.RunnerGroupId <= uint64(math.MaxInt64) {
				snapshotNamesToRunnerGroupMapping[image.Name] = int64(*image.RunnerGroupId)
			} else {
				logger.Warn(ctx, "runner group ID exceeds maximum int64 value",
					kvp.String("image_name", image.Name),
					kvp.Uint64("runner_group_id", *image.RunnerGroupId),
				)
			}
		}
	}

	if len(snapshotNamesToRunnerGroupMapping) == 0 {
		logger.Info(ctx, "no eligible snapshot names to publish")
		return nil
	}

	event := actionsHydroSchemas.RunnerGroupSnapshotNamesMappingUpdateEvent{
		OwnerId:                           ownerId,
		SnapshotNamesToRunnerGroupMapping: snapshotNamesToRunnerGroupMapping,
	}

	// TODO: Publish the event to hydro.
	logger.Info(ctx, "published snapshots to runner group event to hydro", kvp.String("event", event.String()))

	return nil
}
