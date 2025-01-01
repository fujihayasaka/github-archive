package twirp

import (
	"context"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/github/hosted-compute-ims/internal/utils"

	"github.com/github/hosted-compute-ims/gen/ent"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
)

func (h *ImagesApiHandler) GetCustomerImageDefinition(ctx context.Context, req *imagesapi.GetCustomerImageDefinitionRequest) (*imagesapi.GetCustomerImageDefinitionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	latestVersion, err := h.imageStore.GetLatestImageVersion(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get latest image version for image definition", err)
		return nil, twirp.Internal.Error("failed to get image definition")
	}

	versionsSummary, err := h.imageStore.GetImageVersionsSummary(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get image versions summary for definition", err)
		return nil, twirp.Internal.Error("failed to get image definition")
	}

	mappedImageDefinition, err := mapImageDefinition(imageDefinition, latestVersion, versionsSummary)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err)
		return nil, twirp.Internal.Error("failed to get image definition")
	}

	return &imagesapi.GetCustomerImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) GetCustomerImageVersion(ctx context.Context, req *imagesapi.GetCustomerImageVersionRequest) (*imagesapi.GetCustomerImageVersionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		kvp.String("image_version", req.Version),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, req.ImageDefinitionId, req.Version, nil)
	if err != nil {
		return nil, err
	}

	mappedImageVersion, err := mapImageVersion(imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image version", err)
		return nil, twirp.Internal.Error("failed to get image version")
	}

	return &imagesapi.GetCustomerImageVersionResponse{ImageVersion: mappedImageVersion}, nil
}

func (h *ImagesApiHandler) ListCustomerImageVersions(ctx context.Context, req *imagesapi.ListCustomerImageVersionsRequest) (*imagesapi.ListCustomerImageVersionsResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersions, err := h.imageStore.ListImageVersionsByDefinitionId(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to list image versions for image definition", err)
		return nil, twirp.Internal.Error("failed to list image versions")
	}

	models.SortImageVersionsByVersion(imageVersions)

	mappedImageVersions, err := utils.MapFunc(imageVersions, mapImageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map customer image versions", err)
		return nil, twirp.Internal.Error("failed to list image versions")
	}

	return &imagesapi.ListCustomerImageVersionsResponse{ImageVersions: mappedImageVersions}, nil
}

func (h *ImagesApiHandler) CreateCustomerImageVersion(ctx context.Context, req *imagesapi.CreateCustomerImageVersionRequest) (*imagesapi.CreateCustomerImageVersionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		kvp.String("image_version", req.Version),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	var versionsCount int32 = 0
	if versionsSummary, err := h.imageStore.GetImageVersionsSummary(ctx, req.ImageDefinitionId); err != nil {
		logger.ErrorWithReport(ctx, "failed to get image versions summary for image definition", err)
		return nil, twirp.Internal.Error("failed to create image version")
	} else if versionsSummary != nil {
		versionsCount = versionsSummary.Count
	}

	if versionsCount >= h.getCustomerImageVersionsLimitForActor(ctx, req.Owner) {
		logger.Info(ctx, "image definition already has maximum number of image versions")
		return nil, twirp.ResourceExhausted.Error("image definition already has maximum number of image versions")
	}

	version, err := h.getNextImageVersionAsNeeded(ctx, req.ImageDefinitionId, req.Version)
	if err != nil {
		return nil, err
	}
	logger.Info(ctx, "resolved next image version", kvp.String("resolved_to_image_version", version))

	imageVersionId, err := h.imageStore.AddImageVersion(ctx, &models.ImageVersion{
		ImageDefinitionId: req.ImageDefinitionId,
		Version:           version,
		State:             models.ImageVersionState_Pending,
		Enabled:           true,
		VmGeneration:      models.VmGeneration_Gen1,
		AgentUser:         "",
		AzurePurchasePlan: "",
		OsState:           models.OsState_Generalized,
	})
	if err != nil {
		if ent.IsConstraintError(err) {
			logger.Info(ctx, "image version with this version already exists")
			return nil, twirp.AlreadyExists.Error("image version with this version already exists")
		} else {
			logger.ErrorWithReport(ctx, "failed to create image version", err)
			return nil, twirp.Internal.Error("failed to create image version")
		}
	}

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_version_id", imageVersionId))
	logger.Info(ctx, "created image version")

	if err = h.promotionStartClient.StartAsyncImageVersionProvision(ctx, imageVersionId, req.SourceVhdUrl, ""); err != nil {
		logger.ErrorWithReport(ctx, "failed to queue image version provision job", err)
		return nil, twirp.Internal.Error("failed to start image version provision")
	}

	imageVersion, err := h.imageStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get newly created image version", err)
		return nil, twirp.Internal.Error("failed to get newly created image version")
	}

	mappedImageVersion, err := mapImageVersion(imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map newly created image version", err)
		return nil, twirp.Internal.Error("failed to get newly created image version")
	}

	return &imagesapi.CreateCustomerImageVersionResponse{ImageVersion: mappedImageVersion}, nil
}

func (h *ImagesApiHandler) ListCustomerImageDefinitions(ctx context.Context, req *imagesapi.ListCustomerImageDefinitionsRequest) (*imagesapi.ListCustomerImageDefinitionsResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
	)

	imageDefinitions, err := h.imageStore.ListCustomerImageDefinitionsByOwner(ctx, req.Owner.GlobalId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to list customer image definitions", err)
		return nil, twirp.Internal.Error("failed to list image definitions")
	}

	var imageDefinitionIds []uint64
	for _, imageDefinition := range imageDefinitions {
		imageDefinitionIds = append(imageDefinitionIds, imageDefinition.Id)
	}

	latestVersionsMap, err := h.imageStore.GetLatestImageVersionsForImageDefinitions(ctx, imageDefinitionIds)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get latest image versions for image definitions", err)
		return nil, twirp.Internal.Error("failed to list image definitions")
	}

	versionsSummariesMap, err := h.imageStore.GetImageVersionsSummariesForImageDefinitions(ctx, imageDefinitionIds)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get image versions summaries for image definitions", err)
		return nil, twirp.Internal.Error("failed to list image definitions")
	}

	mappedImageDefinitions := make([]*imagesapi.ImageDefinition, len(imageDefinitions))
	for index, imageDefinition := range imageDefinitions {
		mappedImageDefinitions[index], err = mapImageDefinition(imageDefinition, latestVersionsMap[imageDefinition.Id], versionsSummariesMap[imageDefinition.Id])
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to map image definitions", err)
			return nil, twirp.Internal.Error("failed to list image definitions")
		}
	}

	return &imagesapi.ListCustomerImageDefinitionsResponse{
		ImageDefinitions: mappedImageDefinitions,
	}, nil
}

func (h *ImagesApiHandler) CreateCustomerImageDefinition(ctx context.Context, req *imagesapi.CreateCustomerImageDefinitionRequest) (*imagesapi.CreateCustomerImageDefinitionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
	)

	osType, err := mapApiToOsType(req.OsType)
	if err != nil {
		logger.Info(ctx, "request has invalid os type", kvp.String("os_type", string(req.OsType)))
		return nil, twirp.InvalidArgument.Error("invalid os_type")
	}

	if osType == models.OsType_MacOS {
		logger.Info(ctx, "macos is not supported for customer image")
		return nil, twirp.InvalidArgument.Error("macos is not supported for customer image")
	}

	architecture, err := mapApiToArchitecture(req.Architecture)
	if err != nil {
		logger.Info(ctx, "request has invalid architecture", kvp.String("architecture", string(req.Architecture)))
		return nil, twirp.InvalidArgument.Error("invalid architecture")
	}

	// Check for duplicate image name
	exists, err := h.imageStore.CheckImageDefinitionNameAlreadyUsed(ctx, req.Owner.GlobalId, req.Name)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to check for duplicate image name", err)
		return nil, twirp.Internal.Error("failed to create image definition")
	}
	if exists {
		logger.Info(ctx, "image definition with this name already exists")
		return nil, twirp.AlreadyExists.Error("image definition with this name already exists")
	}

	count, err := h.imageStore.GetImageDefinitionsCountByOwnerId(ctx, req.Owner.GlobalId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get count of existing customer image definitions", err)
		return nil, twirp.Internal.Error("failed to create image definition")
	}

	if count >= h.getCustomerImageDefinitionsLimitForActor(ctx, req.Owner) {
		logger.Info(ctx, "owner has maximum number of image definitions")
		return nil, twirp.ResourceExhausted.Error("owner has maximum number of image definitions")
	}

	var runnerGroupId *uint64
	if req.RunnerGroupId != nil {
		runnerGroupId = &req.RunnerGroupId.Value
	}

	imageDefinitionId, err := h.imageStore.AddImageDefinition(ctx, &models.ImageDefinition{
		OwnerId:       req.Owner.GlobalId,
		Name:          req.Name,
		ImageType:     models.ImageType_Customer,
		Enabled:       true,
		OsType:        osType,
		Architecture:  architecture,
		State:         models.ImageDefinitionState_Ready,
		RunnerGroupId: runnerGroupId,
	})
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to create customer image definition", err)
		return nil, twirp.Internal.Error("failed to create a new image definition")
	}

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_definition_id", imageDefinitionId))
	logger.Info(ctx, "created image definition")

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get newly created customer image definition", err)
		return nil, twirp.Internal.Error("failed to get newly created image definition")
	}

	// No image version metadata for a new image definition since it doesn't have any image versions.
	mappedImageDefinition, err := mapImageDefinition(imageDefinition, nil, nil)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err)
		return nil, twirp.Internal.Error("failed to get newly created image definition")
	}

	return &imagesapi.CreateCustomerImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) UpdateCustomerImageDefinition(ctx context.Context, req *imagesapi.UpdateCustomerImageDefinitionRequest) (*imagesapi.UpdateCustomerImageDefinitionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	dbUpdatePayload := &store.ImageDefinitionUpdatePayload{}

	if req.Name != nil && req.Name.Value != "" {
		// Check for duplicate image name
		exists, err := h.imageStore.CheckImageDefinitionNameAlreadyUsed(ctx, req.Owner.GlobalId, req.Name.Value)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to check for duplicate image name", err)
			return nil, twirp.Internal.Error("failed to create image definition")
		}
		if exists {
			logger.Info(ctx, "image definition with this name already exists")
			return nil, twirp.AlreadyExists.Error("image definition with this name already exists")
		}

		dbUpdatePayload.Name = wrapperspb.String(req.Name.Value)
	}

	if req.RunnerGroupId != nil {
		dbUpdatePayload.RunnerGroupId = wrapperspb.UInt64(req.RunnerGroupId.Value)
	}

	err = h.imageStore.UpdateImageDefinition(ctx, req.ImageDefinitionId, dbUpdatePayload)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to update customer image definition", err)
		return nil, twirp.Internal.Error("failed to update image definition")
	}

	logger.Info(ctx, "updated image definition")

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get updated image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	latestVersion, err := h.imageStore.GetLatestImageVersion(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get latest image version for updated image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	versionsSummary, err := h.imageStore.GetImageVersionsSummary(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get image versions summary for updated image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	mappedImageDefinition, err := mapImageDefinition(imageDefinition, latestVersion, versionsSummary)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	return &imagesapi.UpdateCustomerImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) DeleteCustomerImageDefinition(ctx context.Context, req *imagesapi.DeleteCustomerImageDefinitionRequest) (*imagesapi.DeleteCustomerImageDefinitionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	if err := h.promotionStartClient.StartAsyncImageDefinitionDeletion(ctx, req.ImageDefinitionId); err != nil {
		logger.ErrorWithReport(ctx, "failed to start image definition deletion", err)
		return nil, twirp.Internal.Error("failed to start image definition deletion")
	}

	logger.Info(ctx, "started image definition deletion")

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get updated image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition after deletion")
	}

	latestVersion, err := h.imageStore.GetLatestImageVersion(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get latest image version for updated image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition after deletion")
	}

	versionsSummary, err := h.imageStore.GetImageVersionsSummary(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get image versions summaries for image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition after deletion")
	}

	mappedImageDefinition, err := mapImageDefinition(imageDefinition, latestVersion, versionsSummary)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition after deletion")
	}

	return &imagesapi.DeleteCustomerImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) DeleteCustomerImageVersion(ctx context.Context, req *imagesapi.DeleteCustomerImageVersionRequest) (*imagesapi.DeleteCustomerImageVersionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Customer)),
		kvp.String("owner_id", req.Owner.GlobalId),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		kvp.String("image_version", req.Version),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, req.ImageDefinitionId, req.Version, nil)
	if err != nil {
		return nil, err
	}

	imageVersionId := imageVersion.Id
	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_version_id", imageVersionId))

	if err := h.promotionStartClient.StartAsyncImageVersionDeletion(ctx, imageVersionId); err != nil {
		logger.ErrorWithReport(ctx, "failed to start image version deletion", err)
		return nil, twirp.Internal.Error("failed to start image version deletion")
	}

	logger.Info(ctx, "started image version deletion")

	imageVersion, err = h.imageStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get updated image version", err)
		return nil, twirp.Internal.Error("failed to get updated image version after deletion")
	}

	mappedImageVersion, err := mapImageVersion(imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map updated image version", err)
		return nil, twirp.Internal.Error("failed to get updated image version after deletion")
	}

	return &imagesapi.DeleteCustomerImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}

func (h *ImagesApiHandler) HandleAdminEvent(ctx context.Context, req *imagesapi.HandleAdminEventRequest) (*imagesapi.HandleAdminEventResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("owner_id", req.Owner.GlobalId),
		kvp.String("event_name", req.EventName),
	)

	statter.Increment(ctx, "adminevents.received", kvp.String("event_name", req.EventName))

	if req.EventName == models.AdminEventTypes_BillingOwnerDeleted {
		logger.Info(ctx, "start processing admin event")

		if err := h.promotionStartClient.StartAsyncOwnerResourcesCleanup(ctx, req.Owner.GlobalId); err != nil {
			// don't fail API request even if image definition clean up fails because it is async admin event
			logger.ErrorWithReport(ctx, "failed to process admin event", err)
		} else {
			logger.Info(ctx, "finished processing admin event without errors")
		}

	} else {
		logger.Info(ctx, "skipped admin event")
	}

	return &imagesapi.HandleAdminEventResponse{}, nil
}
