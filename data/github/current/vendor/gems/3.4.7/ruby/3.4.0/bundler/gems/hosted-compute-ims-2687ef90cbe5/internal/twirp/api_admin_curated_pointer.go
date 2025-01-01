package twirp

import (
	"context"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/github-telemetry-go/kvp"
	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

func (h *ImagesAdminApiHandler) CreateCuratedImageDefinitionPointer(ctx context.Context, req *adminapi.CreateCuratedImageDefinitionPointerRequest) (*adminapi.CreateCuratedImageDefinitionPointerResponse, error) {
	ctx = stash.WithLoggingFields(ctx, kvp.String("image_type", string(models.ImageType_Curated)))

	// retrieve image definition with ID req.PointsToImageDefinitionId
	// set allowPointerValidation to false to check existing ImageDefintion is NOT a pointer record.
	targetImageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.PointsToImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
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

	imageDefinitionId, err := h.imageStore.AddImageDefinition(ctx, &models.ImageDefinition{
		OwnerId:                   req.OwnerId,
		Name:                      req.Name,
		ImageType:                 models.ImageType_Curated,
		Enabled:                   req.Enabled,
		FeatureFlag:               featureFlag,
		OsType:                    targetImageDefinition.OsType,
		Architecture:              targetImageDefinition.Architecture,
		PointsToImageDefinitionId: &req.PointsToImageDefinitionId,
		State:                     models.ImageDefinitionState_Ready,
	})
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to create new curated image definition pointer", err)
		return nil, twirp.Internal.Error("failed to create new image definition pointer")
	}

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_definition_id", imageDefinitionId))
	logger.Info(ctx, "created image definition pointer")

	pointerImageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get newly created image definition pointer", err)
		return nil, twirp.Internal.Error("failed to get newly created image definition pointer")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(pointerImageDefinition, nil, nil)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err, kvp.Uint64("image_definition_id", imageDefinitionId))
		return nil, twirp.Internal.Error("failed to get newly created image definition pointer")
	}

	return &adminapi.CreateCuratedImageDefinitionPointerResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) UpdateCuratedImageDefinitionPointer(ctx context.Context, req *adminapi.UpdateCuratedImageDefinitionPointerRequest) (*adminapi.UpdateCuratedImageDefinitionPointerResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	existingImageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			allowPointerValidation(true),
		),
	)
	if err != nil {
		return nil, err
	}

	if existingImageDefinition.PointsToImageDefinitionId == nil {
		logger.Info(ctx, "image definition is not a pointer")
		return nil, twirp.InvalidArgument.Error("image definition is not a pointer")
	}

	ctx = stash.WithLoggingFields(ctx,
		kvp.Uint64("pointer_target_previous", *existingImageDefinition.PointsToImageDefinitionId),
		kvp.Uint64("pointer_target_new", req.PointsToImageDefinitionId),
	)

	// The server will validate points_to_image_definition_id is an existing ImageDefinition and NOT a pointer record
	newImageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.PointsToImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	if existingImageDefinition.Architecture != newImageDefinition.Architecture {
		logger.Info(ctx, "architecture of new pointer target is not equal to previous pointer target")
		return nil, twirp.InvalidArgument.Error("architecture of new pointer target is not equal to previous pointer target")
	}

	if existingImageDefinition.OsType != newImageDefinition.OsType {
		logger.Info(ctx, "os_type of new pointer target is not equal to previous pointer target")
		return nil, twirp.InvalidArgument.Error("os_type of new pointer target is not equal to previous pointer target")
	}

	err = h.imageStore.UpdateImageDefinition(ctx, req.GetImageDefinitionId(), &store.ImageDefinitionUpdatePayload{
		Name:                      wrapperspb.String(req.Name),
		Enabled:                   wrapperspb.Bool(req.Enabled),
		FeatureFlag:               wrapperspb.String(req.FeatureFlag),
		PointsToImageDefinitionId: wrapperspb.UInt64(req.PointsToImageDefinitionId),
	})
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to update image definition pointer", err)
		return nil, twirp.Internal.Error("failed to update image definition pointer")
	}

	logger.Info(ctx, "updated image definition pointer")

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get updated image definition pointer", err)
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(imageDefinition, nil, nil)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition pointer", err)
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	return &adminapi.UpdateCuratedImageDefinitionPointerResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) DeleteCuratedImageDefinitionPointer(ctx context.Context, req *adminapi.DeleteCuratedImageDefinitionPointerRequest) (*adminapi.DeleteCuratedImageDefinitionPointerResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	latestImageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			allowPointerValidation(true),
		),
	)
	if err != nil {
		return nil, err
	}

	if latestImageDefinition.PointsToImageDefinitionId == nil {
		logger.Info(ctx, "image definition is not a pointer")
		return nil, twirp.InvalidArgument.Error("image definition is not a pointer")
	}

	err = h.imageStore.DeleteImageDefinition(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to delete image definition pointer", err)
		return nil, twirp.Internal.Error("failed to delete image definition pointer")
	}

	logger.Info(ctx, "deleted image definition pointer")

	return &adminapi.DeleteCuratedImageDefinitionPointerResponse{}, nil
}
