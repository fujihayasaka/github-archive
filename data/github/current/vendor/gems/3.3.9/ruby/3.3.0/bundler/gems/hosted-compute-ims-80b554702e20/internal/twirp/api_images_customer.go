package twirp

import (
	"context"

	"github.com/twitchtv/twirp"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/models"

	"github.com/github/hosted-compute-ims/gen/ent"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
)

const (
	maxCustomerImageDefinitions           = 100
	maxCustomerImageVersionsPerDefinition = 100
)

func (h *ImagesApiHandler) GetCustomerImageDefinition(ctx context.Context, req *imagesapi.GetCustomerImageDefinitionRequest) (*imagesapi.GetCustomerImageDefinitionResponse, error) {
	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	mappedImageDefinition, err := mapImageDefinition(imageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition", err, kvp.Uint64("image_definition_id", imageDefinition.Id))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	latestVersion, err := h.imageStore.GetLatestImageVersion(ctx, req.ImageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to get latest image version for image definition", err, kvp.Uint64("image_definition_id", imageDefinition.Id))
		return nil, twirp.Internal.Error("failed to get latest image version for image definition")
	}

	if latestVersion != nil {
		mappedImageDefinition.LatestVersion = latestVersion.Version
		if latestVersion.SizeGB != nil {
			mappedImageDefinition.SizeGb = *latestVersion.SizeGB
		}
	}

	return &imagesapi.GetCustomerImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) GetCustomerImageVersion(ctx context.Context, req *imagesapi.GetCustomerImageVersionRequest) (*imagesapi.GetCustomerImageVersionResponse, error) {
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
		h.logger.ErrorWithReport("failed to map image version", err,
			kvp.Uint64("image_definition_id", req.ImageDefinitionId),
			kvp.String("image_version", req.Version),
		)
		return nil, twirp.Internal.Error("failed to map image version")
	}

	return &imagesapi.GetCustomerImageVersionResponse{ImageVersion: mappedImageVersion}, nil
}

func (h *ImagesApiHandler) ListCustomerImageVersions(ctx context.Context, req *imagesapi.ListCustomerImageVersionsRequest) (*imagesapi.ListCustomerImageVersionsResponse, error) {
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
		h.logger.ErrorWithReport("failed to list image versions for image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to list image versions for image definition")
	}

	models.SortImageVersionsByVersion(imageVersions)

	mappedImageVersions, err := mapFunc(imageVersions, mapImageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map customer image versions", err)
		return nil, twirp.Internal.Error("failed to map image versions")
	}

	return &imagesapi.ListCustomerImageVersionsResponse{ImageVersions: mappedImageVersions}, nil
}

func (h *ImagesApiHandler) CreateCustomerImageVersion(ctx context.Context, req *imagesapi.CreateCustomerImageVersionRequest) (*imagesapi.CreateCustomerImageVersionResponse, error) {
	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	count, err := h.imageStore.GetImageVersionsCountByDefinitionId(ctx, req.ImageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to get count of existing image versions for definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to create image version")
	}

	if count >= maxCustomerImageVersionsPerDefinition {
		h.logger.Info("image definition already has maximum number of image versions",
			kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		)
		return nil, twirp.ResourceExhausted.Error("image definition already has maximum number of image versions")
	}

	imageVersionId, err := h.imageStore.AddImageVersion(ctx, &models.ImageVersion{
		ImageDefinitionId: req.ImageDefinitionId,
		Version:           req.Version,
		State:             models.ImageVersionState_Pending,
		Enabled:           true,
	})
	if err != nil {
		if ent.IsConstraintError(err) {
			h.logger.Info("image version with this version already exists")
			return nil, twirp.AlreadyExists.Error("image version with this version already exists")
		} else {
			h.logger.ErrorWithReport("failed to create image version", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
			return nil, twirp.Internal.Error("failed to create image version")
		}
	}

	if err = h.workerQueueClient.QueueProvisionImageVersionJob(ctx, imageVersionId, req.SourceVhdUrl); err != nil {
		h.logger.ErrorWithReport("failed to queue image version provision job", err, kvp.Uint64("image_version_id", imageVersionId))
		return nil, twirp.Internal.Error("failed to provision image version")
	}

	imageVersion, err := h.imageStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to get newly created image version", err, kvp.Uint64("image_version_id", imageVersionId))
		return nil, twirp.Internal.Error("failed to get newly created image version")
	}

	mappedImageVersion, err := mapImageVersion(imageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image version", err, kvp.Uint64("image_version_id", imageVersion.Id))
		return nil, twirp.Internal.Error("failed to map image version")
	}

	return &imagesapi.CreateCustomerImageVersionResponse{ImageVersion: mappedImageVersion}, nil
}

func (h *ImagesApiHandler) ListCustomerImageDefinitions(ctx context.Context, req *imagesapi.ListCustomerImageDefinitionsRequest) (*imagesapi.ListCustomerImageDefinitionsResponse, error) {
	imageDefinitions, err := h.imageStore.ListCustomerImageDefinitions(ctx, req.Owner.GlobalId)
	if err != nil {
		h.logger.ErrorWithReport("failed to list customer image definitions", err, kvp.String("owner_id", req.Owner.GlobalId))
		return nil, twirp.Internal.Error("failed to list image definitions")
	}

	mappedImageDefinitions, err := mapFunc(imageDefinitions, mapImageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map customer image definitions", err, kvp.String("owner_id", req.Owner.GlobalId))
		return nil, twirp.Internal.Error("failed to map image definitions")
	}

	// It will makes N + 1 calls to the DB. Currently, we limit the number of image versions per image definition is 100.
	// Need to optimize if we extend the limtation in the future.
	for _, mappedImageDefinition := range mappedImageDefinitions {
		latestVersion, err := h.imageStore.GetLatestImageVersion(ctx, mappedImageDefinition.Id)
		if err != nil {
			h.logger.ErrorWithReport("failed to get latest image version for image definition", err, kvp.Uint64("image_definition_id", mappedImageDefinition.Id))
			return nil, twirp.Internal.Error("failed to get latest image version for image definition")
		}

		if latestVersion != nil {
			mappedImageDefinition.LatestVersion = latestVersion.Version
			if latestVersion.SizeGB != nil {
				mappedImageDefinition.SizeGb = *latestVersion.SizeGB
			}
		}

	}

	return &imagesapi.ListCustomerImageDefinitionsResponse{
		ImageDefinitions: mappedImageDefinitions,
	}, nil
}

func (h *ImagesApiHandler) CreateCustomerImageDefinition(ctx context.Context, req *imagesapi.CreateCustomerImageDefinitionRequest) (*imagesapi.CreateCustomerImageDefinitionResponse, error) {
	osType, err := mapApiToOsType(req.OsType)
	if err != nil {
		h.logger.Info(
			"request has invalid os type",
			kvp.String("os_type", string(req.OsType)),
			kvp.String("error", err.Error()),
		)
		return nil, twirp.InvalidArgument.Error("invalid os_type")
	}

	architecture, err := mapApiToArchitecture(req.Architecture)
	if err != nil {
		h.logger.Info(
			"request has invalid architecture",
			kvp.String("architecture", string(req.Architecture)),
			kvp.String("error", err.Error()),
		)
		return nil, twirp.InvalidArgument.Error("invalid architecture")
	}

	count, err := h.imageStore.GetImageDefinitionsCountByOwnerId(ctx, req.Owner.GlobalId)
	if err != nil {
		h.logger.ErrorWithReport("failed to get count of existing customer image definitions", err, kvp.String("owner_id", req.Owner.GlobalId))
		return nil, twirp.Internal.Error("failed to create image definition")
	}

	if count >= maxCustomerImageDefinitions {
		h.logger.Info("owner has maximum number of image definitions", kvp.String("owner_id", req.Owner.GlobalId))
		return nil, twirp.ResourceExhausted.Error("owner has maximum number of image definitions")
	}

	imageDefinitionId, err := h.imageStore.AddImageDefinition(ctx, &models.ImageDefinition{
		OwnerId:             req.Owner.GlobalId,
		Name:                req.Name,
		ImageType:           models.ImageType_Customer,
		Enabled:             true, // Enabled on creation
		OsType:              osType,
		Architecture:        architecture,
		AzureSubscriptionId: nil, // Nil on creation
	})
	if err != nil {
		if ent.IsConstraintError(err) {
			h.logger.Info("image definition with this name already exists")
			return nil, twirp.AlreadyExists.Error("image definition with this name already exists")
		} else {
			h.logger.ErrorWithReport("failed to create customer image definition", err, kvp.String("owner_id", req.Owner.GlobalId))
			return nil, twirp.Internal.Error("failed to create new image definition")
		}
	}

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to get newly created customer image definition", err, kvp.Uint64("image_definition_id", imageDefinitionId))
		return nil, twirp.Internal.Error("failed to get newly created image definition")
	}

	mappedImageDefinition, err := mapImageDefinition(imageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition", err, kvp.Uint64("image_definition_id", imageDefinition.Id))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	return &imagesapi.CreateCustomerImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) UpdateCustomerImageDefinition(ctx context.Context, req *imagesapi.UpdateCustomerImageDefinitionRequest) (*imagesapi.UpdateCustomerImageDefinitionResponse, error) {
	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	_, err = h.imageStore.UpdateImageDefinition(ctx, req.GetImageDefinitionId(), &models.ImageDefinitionUpdate{
		Name:    req.GetName(),
		Enabled: imageDefinition.Enabled, // Prevent update to enabled for customer image definitions
	})
	if err != nil {
		if ent.IsConstraintError(err) {
			h.logger.Info("image definition with this name already exists")
			return nil, twirp.AlreadyExists.Error("image definition with this name already exists")
		} else {
			h.logger.ErrorWithReport("failed to update customer image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
			return nil, twirp.Internal.Error("failed to update image definition")
		}
	}

	imageDefinition, err = h.imageStore.GetImageDefinitionById(ctx, req.ImageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to get updated image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	mappedImageDefinition, err := mapImageDefinition(imageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	return &imagesapi.UpdateCustomerImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) DeleteCustomerImageDefinition(ctx context.Context, req *imagesapi.DeleteCustomerImageDefinitionRequest) (*imagesapi.DeleteCustomerImageDefinitionResponse, error) {
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
		h.logger.ErrorWithReport("failed to list image versions for image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to list image versions for image definition")
	}
	if len(imageVersions) > 0 {
		h.logger.Info("failed to delete image definition because it has image versions", kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.InvalidArgument.Error("failed to delete image definition because it has image versions")
	}

	if err = h.imageStore.DeleteImageDefinition(ctx, req.ImageDefinitionId); err != nil {
		h.logger.ErrorWithReport("failed to delete customer image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to delete image definition")
	}

	return &imagesapi.DeleteCustomerImageDefinitionResponse{}, nil
}

func (h *ImagesApiHandler) DeleteCustomerImageVersion(ctx context.Context, req *imagesapi.DeleteCustomerImageVersionRequest) (*imagesapi.DeleteCustomerImageVersionResponse, error) {
	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.imageStore.GetImageVersionByDefinitionIdAndVersion(ctx, req.ImageDefinitionId, req.Version)
	if err != nil {
		return nil, err
	}

	err = h.imageStore.UpdateImageVersionState(ctx, imageVersion.Id, models.ImageVersionState_Deleting, "")
	if err != nil {
		h.logger.ErrorWithReport("failed to change image version state", err,
			kvp.Uint64("image_definition_id", req.GetImageDefinitionId()),
			kvp.Uint64("image_version_id", imageVersion.Id),
			kvp.String("new_state", string(models.ImageVersionState_Deleting)),
		)
		return nil, twirp.Internal.Error("failed to delete image version")
	}

	if err = h.workerQueueClient.QueueDeleteImageVersionJob(ctx, imageVersion.Id); err != nil {
		h.logger.ErrorWithReport("failed to queue deleting image version job", err, kvp.Uint64("image_version_id", imageVersion.Id))
		return nil, twirp.Internal.Error("failed to delete image version")
	}

	mappedImageVersion, err := mapImageVersion(imageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image version", err, kvp.Uint64("image_version_id", imageVersion.Id))
		return nil, twirp.Internal.Error("failed to map image version")
	}

	return &imagesapi.DeleteCustomerImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}
