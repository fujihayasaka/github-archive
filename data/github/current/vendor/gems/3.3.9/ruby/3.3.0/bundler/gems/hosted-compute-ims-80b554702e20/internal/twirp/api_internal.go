package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/twitchtv/twirp"
	"go.uber.org/zap/zapcore"
)

// GetImageDetails implements images.InternalImageManagementService.
func (h *InternalImagesApiHandler) GetImageDetails(ctx context.Context, req *internalapi.GetImageDetailsRequest) (*internalapi.GetImageDetailsResponse, error) {
	var imageDefinitionValidator *twirpValidatorOptions
	switch req.ImageKey.Source {
	case ImageSource_Curated:
		imageDefinitionValidator = newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		)
	case ImageSource_Customer:
		imageDefinitionValidator = newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		)
	default:
		h.logger.Info("unsupported image type", h.loggerFieldsForImageKey(req.ImageKey)...)
		return nil, twirp.InvalidArgument.Error("unsupported image type")
	}

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageKey.Id, imageDefinitionValidator)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.manager.GetExactImageVersion(ctx, &internalapi.ImageKey{
		Source:  req.ImageKey.Source,
		Id:      imageDefinition.ResolveImageDefinitionId(),
		Version: req.ImageKey.Version,
	})
	if err != nil {
		h.logger.ErrorWithReport("failed to get exact image version", err, h.loggerFieldsForImageKey(req.ImageKey)...)
		return nil, twirp.Internal.Error("failed to get exact image version")
	}

	if req.ImageKey.Version != models.LatestImageVersion && imageVersion == nil {
		h.logger.Info("image version is not found", h.loggerFieldsForImageKey(req.ImageKey)...)
		return nil, twirp.InvalidArgument.Error("image version is not found")
	}

	imageDetails, err := mapInternalImageDetails(imageDefinition, imageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition to image details", err, h.loggerFieldsForImageKey(req.ImageKey)...)
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	imageDetails.Enabled = isCuratedImageDefinitionEnabledForActor(ctx, imageDefinition, req.Owner.GlobalId)

	return &internalapi.GetImageDetailsResponse{
		ImageDetails: imageDetails,
	}, nil
}

// GetImageReference implements images.InternalImageManagementService.
func (h *InternalImagesApiHandler) GetImageReference(ctx context.Context, req *internalapi.GetImageReferenceRequest) (*internalapi.GetImageReferenceResponse, error) {
	var imageDefinitionValidator *twirpValidatorOptions
	switch req.ImageKey.Source {
	case ImageSource_Curated:
		imageDefinitionValidator = newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		)
	case ImageSource_Customer:
		imageDefinitionValidator = newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
		)
	default:
		h.logger.Info("unsupported image type", h.loggerFieldsForImageKey(req.ImageKey)...)
		return nil, twirp.InvalidArgument.Error("unsupported image type")
	}

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageKey.Id, imageDefinitionValidator)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.manager.GetExactImageVersion(ctx, &internalapi.ImageKey{
		Source:  req.ImageKey.Source,
		Id:      imageDefinition.ResolveImageDefinitionId(),
		Version: req.ImageKey.Version,
	})
	if err != nil {
		h.logger.ErrorWithReport("failed to get exact image version", err, h.loggerFieldsForImageKey(req.ImageKey)...)
		return nil, twirp.Internal.Error("failed to get exact image version")
	}

	if imageVersion == nil {
		if req.ImageKey.Version == models.LatestImageVersion {
			h.logger.Info("image definition does not have enabled versions in ready state", h.loggerFieldsForImageKey(req.ImageKey)...)
			return nil, twirp.InvalidArgument.Error("image definition does not have enabled versions in ready state")
		} else {
			h.logger.Info("image version is not found", h.loggerFieldsForImageKey(req.ImageKey)...)
			return nil, twirp.InvalidArgument.Error("image version is not found")
		}
	}

	if imageVersion.State != models.ImageVersionState_Ready {
		h.logger.Info("requested image version is not ready to use", h.loggerFieldsForImageKey(req.ImageKey)...)
		return nil, twirp.InvalidArgument.Error("requested image version is not ready to use")
	}

	imageReference, err := h.manager.GetImageReference(ctx, imageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to get image reference", err, h.loggerFieldsForImageKey(req.ImageKey)...)
		return nil, twirp.Internal.Error("failed to get image reference")
	}

	res := &internalapi.GetImageReferenceResponse{
		ImageReference:    mapImageReference(imageReference),
		ExactImageVersion: imageVersion.Version,
	}

	return res, nil
}

func (h *InternalImagesApiHandler) loggerFieldsForImageKey(imageKey *internalapi.ImageKey) []zapcore.Field {
	return []zapcore.Field{
		kvp.String("image_key_source", imageKey.Source),
		kvp.Uint64("image_key_id", imageKey.Id),
		kvp.String("image_key_version", imageKey.Version),
	}
}
