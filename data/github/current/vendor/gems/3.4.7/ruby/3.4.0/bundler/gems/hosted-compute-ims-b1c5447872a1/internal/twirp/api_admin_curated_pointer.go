package twirp

import (
	"context"

	"github.com/twitchtv/twirp"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/gen/ent"
	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	"github.com/github/hosted-compute-ims/internal/models"
)

func (h *ImagesAdminApiHandler) CreateCuratedImageDefinitionPointer(ctx context.Context, req *adminapi.CreateCuratedImageDefinitionPointerRequest) (*adminapi.CreateCuratedImageDefinitionPointerResponse, error) {
	// retrieve image definition with ID req.PointsToImageDefinitionId
	// set allowPointerValidation to false to check existing ImageDefintion is NOT a pointer record.
	targetImageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.PointsToImageDefinitionId,
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

	id, err := h.imageStore.AddImageDefinition(ctx, &models.ImageDefinition{
		OwnerId:                   models.GithubOwnerId,
		Name:                      req.Name,
		ImageType:                 models.ImageType_Curated,
		Enabled:                   req.Enabled,
		FeatureFlag:               featureFlag,
		OsType:                    targetImageDefinition.OsType,
		Architecture:              targetImageDefinition.Architecture,
		AzureSubscriptionId:       nil,
		PointsToImageDefinitionId: &req.PointsToImageDefinitionId,
	})
	if err != nil {
		if ent.IsConstraintError(err) {
			h.logger.Info("image definition with this name already exists")
			return nil, twirp.AlreadyExists.Error("image definition with this name already exists")
		} else {
			h.logger.ErrorWithReport("failed to create new curated image definition pointer", err)
			return nil, twirp.Internal.Error("failed to create new image definition pointer")
		}
	}

	pointerImageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, id)
	if err != nil {
		h.logger.ErrorWithReport("failed to get newly created image definition pointer", err, kvp.Uint64("image_definition_id", id))
		return nil, twirp.Internal.Error("failed to get newly created image definition pointer")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(pointerImageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition", err, kvp.Uint64("image_definition_id", id))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	return &adminapi.CreateCuratedImageDefinitionPointerResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) UpdateCuratedImageDefinitionPointer(ctx context.Context, req *adminapi.UpdateCuratedImageDefinitionPointerRequest) (*adminapi.UpdateCuratedImageDefinitionPointerResponse, error) {
	existingImageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withImageOwnerValidation(models.GithubOwnerId),
			allowPointerValidation(true),
		),
	)
	if err != nil {
		return nil, err
	}

	if existingImageDefinition.PointsToImageDefinitionId == nil {
		h.logger.Info("image definition is not a pointer",
			kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		)
		return nil, twirp.InvalidArgument.Error("image definition is not a pointer")
	}

	// The server will validate points_to_image_definition_id is an existing ImageDefinition and NOT a pointer record
	newImageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.PointsToImageDefinitionId,
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

	if existingImageDefinition.Architecture != newImageDefinition.Architecture {
		h.logger.Info("architecture of new pointer target is not equal to previous pointer target",
			kvp.Uint64("image_definition_id", req.ImageDefinitionId),
			kvp.Uint64("previous_target", *existingImageDefinition.PointsToImageDefinitionId),
			kvp.Uint64("new_target", req.PointsToImageDefinitionId),
		)
		return nil, twirp.InvalidArgument.Error("architecture of new pointer target is not equal to previous pointer target")
	}

	if existingImageDefinition.OsType != newImageDefinition.OsType {
		h.logger.Info("os_type of new pointer target is not equal to previous pointer target",
			kvp.Uint64("image_definition_id", req.ImageDefinitionId),
			kvp.Uint64("previous_target", *existingImageDefinition.PointsToImageDefinitionId),
			kvp.Uint64("new_target", req.PointsToImageDefinitionId),
		)
		return nil, twirp.InvalidArgument.Error("os_type of new pointer target is not equal to previous pointer target")
	}

	_, err = h.imageStore.UpdateImageDefinition(ctx, req.GetImageDefinitionId(), &models.ImageDefinitionUpdate{
		Name:                      req.GetName(),
		Enabled:                   req.GetEnabled(),
		FeatureFlag:               featureFlag,
		PointsToImageDefinitionId: &req.PointsToImageDefinitionId,
	})
	if err != nil {
		if ent.IsConstraintError(err) {
			h.logger.Info("image definition with this name already exists")
			return nil, twirp.AlreadyExists.Error("image definition with this name already exists")
		} else {
			h.logger.ErrorWithReport("failed to update image definition pointer", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
			return nil, twirp.Internal.Error("failed to update image definition pointer")
		}
	}

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, req.ImageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to get updated image definition pointer", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(imageDefinition)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition pointer", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to map image definition pointer")
	}

	return &adminapi.UpdateCuratedImageDefinitionPointerResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) DeleteCuratedImageDefinitionPointer(ctx context.Context, req *adminapi.DeleteCuratedImageDefinitionPointerRequest) (*adminapi.DeleteCuratedImageDefinitionPointerResponse, error) {
	latestImageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withImageOwnerValidation(models.GithubOwnerId),
			allowPointerValidation(true),
		),
	)
	if err != nil {
		return nil, err
	}

	if latestImageDefinition.PointsToImageDefinitionId == nil {
		h.logger.Info("image definition is not a pointer",
			kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		)
		return nil, twirp.InvalidArgument.Error("image definition is not a pointer")
	}

	err = h.imageStore.DeleteImageDefinition(ctx, req.ImageDefinitionId)
	if err != nil {
		h.logger.ErrorWithReport("failed to delete image definition pointer", err, kvp.Uint64("image_definition_id", req.GetImageDefinitionId()))
		return nil, twirp.Internal.Error("failed to delete image definition pointer")
	}

	return &adminapi.DeleteCuratedImageDefinitionPointerResponse{}, nil
}
