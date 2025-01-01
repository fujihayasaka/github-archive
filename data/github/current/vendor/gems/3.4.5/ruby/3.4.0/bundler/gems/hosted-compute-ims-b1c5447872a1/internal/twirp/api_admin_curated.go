package twirp

import (
	"context"

	"github.com/twitchtv/twirp"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/gen/ent"
	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	"github.com/github/hosted-compute-ims/internal/models"
)

func (h *ImagesAdminApiHandler) GetCuratedImageDefinition(ctx context.Context, req *adminapi.GetCuratedImageDefinitionRequest) (*adminapi.GetCuratedImageDefinitionResponse, error) {
	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		),
	)
	if err != nil {
		return nil, err
	}

	mappedImageDefinition, err := mapAdminImageDefinition(imageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	return &adminapi.GetCuratedImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) GetCuratedImageVersion(ctx context.Context, req *adminapi.GetCuratedImageVersionRequest) (*adminapi.GetCuratedImageVersionResponse, error) {
	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, imageDefinition.ResolveImageDefinitionId(), req.Version, nil)
	if err != nil {
		return nil, err
	}

	mappedImageVersion, err := mapAdminImageVersion(imageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image version", err,
			kvp.Uint64("image_definition_id", req.ImageDefinitionId),
			kvp.String("image_version", req.Version),
		)
		return nil, twirp.Internal.Error("failed to map image version")
	}

	return &adminapi.GetCuratedImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}

func (h *ImagesAdminApiHandler) ListCuratedImageDefinitions(ctx context.Context, req *adminapi.ListCuratedImageDefinitionsRequest) (*adminapi.ListCuratedImageDefinitionsResponse, error) {
	imageDefinitions, err := h.imageStore.ListCuratedImageDefinitions(ctx)
	if err != nil {
		h.logger.ErrorWithReport("failed to list curated image definitions", err)
		return nil, twirp.Internal.Error("failed to list image definitions")
	}

	mappedImageDefinitions, err := mapFunc(imageDefinitions, mapAdminImageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definitions", err)
		return nil, twirp.Internal.Error("failed to map image definitions")
	}

	return &adminapi.ListCuratedImageDefinitionsResponse{
		ImageDefinitions: mappedImageDefinitions,
	}, nil
}

func (h *ImagesAdminApiHandler) ListCuratedImageVersions(ctx context.Context, req *adminapi.ListCuratedImageVersionsRequest) (*adminapi.ListCuratedImageVersionsResponse, error) {
	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withImageOwnerValidation(models.GithubOwnerId),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersions, err := h.imageStore.ListImageVersionsByDefinitionId(ctx, imageDefinition.ResolveImageDefinitionId())
	if err != nil {
		h.logger.ErrorWithReport("failed to list curated image versions", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to list image versions")
	}

	models.SortImageVersionsByVersion(imageVersions)

	mappedImageVersions, err := mapFunc(imageVersions, mapAdminImageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map curated image versions", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to map image versions")
	}

	return &adminapi.ListCuratedImageVersionsResponse{
		ImageVersions: mappedImageVersions,
	}, nil
}

func (h *ImagesAdminApiHandler) CreateCuratedImageDefinition(ctx context.Context, req *adminapi.CreateCuratedImageDefinitionRequest) (*adminapi.CreateCuratedImageDefinitionResponse, error) {
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

	var featureFlag *string
	if req.FeatureFlag != "" {
		featureFlag = &req.FeatureFlag
	}

	id, err := h.imageStore.AddImageDefinition(ctx, &models.ImageDefinition{
		OwnerId:             models.GithubOwnerId,
		Name:                req.Name,
		ImageType:           models.ImageType_Curated,
		Enabled:             req.Enabled,
		FeatureFlag:         featureFlag,
		OsType:              osType,
		Architecture:        architecture,
		AzureSubscriptionId: nil,
	})
	if err != nil {
		if ent.IsConstraintError(err) {
			h.logger.Info("image definition with this name already exists")
			return nil, twirp.AlreadyExists.Error("image definition with this name already exists")
		} else {
			h.logger.ErrorWithReport("failed to create new curated image definition", err)
			return nil, twirp.Internal.Error("failed to create new image definition")
		}
	}

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, id)
	if err != nil {
		h.logger.ErrorWithReport("failed to get newly created image definition", err, kvp.Uint64("image_definition_id", id))
		return nil, twirp.Internal.Error("failed to get newly created image definition")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(imageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition", err, kvp.Uint64("image_definition_id", id))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	return &adminapi.CreateCuratedImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) DeleteCuratedImageDefinition(ctx context.Context, req *adminapi.DeleteCuratedImageDefinitionRequest) (*adminapi.DeleteCuratedImageDefinitionResponse, error) {
	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withImageOwnerValidation(models.GithubOwnerId),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	isReferenced, err := h.isImageDefinitionReferencedByPointer(ctx, req.ImageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to list curated image definitions", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to get image definition")
	}
	if isReferenced {
		h.logger.Info("failed to delete image definition because it is referenced by pointer", kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.InvalidArgument.Error("failed to delete image definition because it is referenced by pointer. Delete pointer first.")
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

	err = h.imageStore.DeleteImageDefinition(ctx, req.ImageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to delete image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to delete image definition")
	}

	return &adminapi.DeleteCuratedImageDefinitionResponse{}, nil
}

func (h *ImagesAdminApiHandler) DeleteCuratedImageVersion(ctx context.Context, req *adminapi.DeleteCuratedImageVersionRequest) (*adminapi.DeleteCuratedImageVersionResponse, error) {
	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withImageOwnerValidation(models.GithubOwnerId),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, req.ImageDefinitionId, req.Version, nil)
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

	apiImageVersion, err := mapAdminImageVersion(imageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image version", err, kvp.Uint64("image_version_id", imageVersion.Id))
		return nil, twirp.Internal.Error("failed to map image version")
	}

	return &adminapi.DeleteCuratedImageVersionResponse{
		ImageVersion: apiImageVersion,
	}, nil
}

func (h *ImagesAdminApiHandler) UpdateCuratedImageVersion(ctx context.Context, req *adminapi.UpdateCuratedImageVersionRequest) (*adminapi.UpdateCuratedImageVersionResponse, error) {
	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withImageOwnerValidation(models.GithubOwnerId),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, req.ImageDefinitionId, req.Version, nil)
	if err != nil {
		return nil, err
	}

	_, err = h.imageStore.UpdateImageVersion(ctx, imageVersion.Id, &models.ImageVersionUpdate{
		Enabled:    req.Enabled,
		ResourceId: imageVersion.ResourceId,
	})
	if err != nil {
		h.logger.ErrorWithReport("failed to update image version", err, kvp.Uint64("image_version_id", imageVersion.Id))
		return nil, twirp.Internal.Error("failed to update image version")
	}

	updatedImageVersion, err := h.imageStore.GetImageVersionById(ctx, imageVersion.Id)
	if err != nil {
		h.logger.ErrorWithReport("failed to get updated image version", err, kvp.Uint64("image_version_id", imageVersion.Id))
		return nil, twirp.Internal.Error("failed to get updated image version")
	}

	mappedImageVersion, err := mapAdminImageVersion(updatedImageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image version", err, kvp.Uint64("image_version_id", imageVersion.Id))
		return nil, twirp.Internal.Error("failed to map image version")
	}

	return &adminapi.UpdateCuratedImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}

func (h *ImagesAdminApiHandler) CreateCuratedImageVersion(ctx context.Context, req *adminapi.CreateCuratedImageVersionRequest) (*adminapi.CreateCuratedImageVersionResponse, error) {
	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withImageOwnerValidation(models.GithubOwnerId),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	newImageVersion := &models.ImageVersion{
		Version:           req.GetVersion(),
		ImageDefinitionId: req.GetImageDefinitionId(),
		Enabled:           req.GetEnabled(),
		State:             models.ImageVersionState_Pending,
	}

	id, err := h.imageStore.AddImageVersion(ctx, newImageVersion)
	if err != nil {
		if ent.IsConstraintError(err) {
			h.logger.Info("image version with this version already exists")
			return nil, twirp.AlreadyExists.Error("image version with this version already exists")
		} else {
			h.logger.ErrorWithReport("failed to create curated image version", err,
				kvp.Uint64("image_definition_id", req.GetImageDefinitionId()),
				kvp.String("image_version", req.GetVersion()),
			)
			return nil, twirp.Internal.Error("failed to create new image version")
		}
	}

	if err = h.workerQueueClient.QueueProvisionImageVersionJob(ctx, id, req.GetSourceVhdUrl()); err != nil {
		h.logger.ErrorWithReport("failed to queue image provision job", err, kvp.Uint64("image_version_id", id))
		return nil, twirp.Internal.Error("failed to start image version provision")
	}

	imageVersion, err := h.imageStore.GetImageVersionById(ctx, id)
	if err != nil {
		h.logger.ErrorWithReport("failed to get newly created image version", err, kvp.Uint64("image_version_id", id))
		return nil, twirp.Internal.Error("failed to get newly created image version")
	}

	mappedImageVersion, err := mapAdminImageVersion(imageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image version", err, kvp.Uint64("image_version_id", id))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	return &adminapi.CreateCuratedImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}

func (h *ImagesAdminApiHandler) UpdateCuratedImageDefinition(ctx context.Context, req *adminapi.UpdateCuratedImageDefinitionRequest) (*adminapi.UpdateCuratedImageDefinitionResponse, error) {
	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withImageOwnerValidation(models.GithubOwnerId),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	var featureFlag *string

	if req.FeatureFlag != "" {
		featureFlag = &req.FeatureFlag
	}
	_, err = h.imageStore.UpdateImageDefinition(ctx, req.GetImageDefinitionId(), &models.ImageDefinitionUpdate{
		Name:                      req.GetName(),
		Enabled:                   req.GetEnabled(),
		FeatureFlag:               featureFlag,
		PointsToImageDefinitionId: nil,
	})
	if err != nil {
		if ent.IsConstraintError(err) {
			h.logger.Info("image definition with this name already exists")
			return nil, twirp.AlreadyExists.Error("image definition with this name already exists")
		} else {
			h.logger.ErrorWithReport("failed to update curated image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
			return nil, twirp.Internal.Error("failed to update image definition")
		}
	}

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, req.ImageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to get updated image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(imageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	return &adminapi.UpdateCuratedImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) isImageDefinitionReferencedByPointer(ctx context.Context, imageDefinitionId uint64) (bool, error) {
	imageDefinitions, err := h.imageStore.ListCuratedImageDefinitions(ctx)
	if err != nil {
		return false, err
	}

	for _, imageDefinition := range imageDefinitions {
		if imageDefinition.PointsToImageDefinitionId != nil && *imageDefinition.PointsToImageDefinitionId == imageDefinitionId {
			return true, nil
		}
	}

	return false, nil
}
