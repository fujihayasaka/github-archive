package twirp

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/twitchtv/twirp"
)

// GetImageDetails implements images.InternalImageManagementService.
func (h *InternalImagesApiHandler) GetImageDetails(ctx context.Context, req *internalapi.GetImageDetailsRequest) (*internalapi.GetImageDetailsResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", req.ImageSource),
		kvp.Uint64("image_definition_id", req.ImageId),
		kvp.String("image_version", req.ImageVersion),
		kvp.String("owner_id", req.Owner.GlobalId),
	)

	var imageDefinitionValidator *twirpValidatorOptions
	switch req.ImageSource {
	// We handle marketplace images as curated images in IMS.
	case ImageSource_Curated, ImageSource_Marketplace:
		imageDefinitionValidator = newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		)
	case ImageSource_Customer:
		imageDefinitionValidator = newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		)
	default:
		logger.Info(ctx, "unsupported image type")
		return nil, twirp.InvalidArgument.Error("unsupported image type")
	}

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageId, imageDefinitionValidator)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.getExactImageVersion(ctx, imageDefinition.ResolveImageDefinitionId(), req.ImageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get exact image version", err)
		return nil, twirp.Internal.Error("failed to get exact image version")
	}

	if req.ImageVersion != models.LatestImageVersion && imageVersion == nil {
		logger.Info(ctx, "image version is not found")
		return nil, twirp.InvalidArgument.Error("image version is not found")
	}

	imageDetails, err := mapInternalImageDetails(imageDefinition, imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition to image details", err)
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	imageDetails.Enabled = h.isCuratedImageDefinitionEnabledForActor(ctx, imageDefinition, req.Owner)

	return &internalapi.GetImageDetailsResponse{
		ImageDetails: imageDetails,
	}, nil
}

// GetImageReference implements images.InternalImageManagementService.
func (h *InternalImagesApiHandler) GetImageReference(ctx context.Context, req *internalapi.GetImageReferenceRequest) (*internalapi.GetImageReferenceResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", req.ImageSource),
		kvp.Uint64("image_definition_id", req.ImageId),
		kvp.String("image_version", req.ImageVersion),
	)

	var imageDefinitionValidator *twirpValidatorOptions
	switch req.ImageSource {
	// We handle marketplace images as curated images in IMS.
	case ImageSource_Curated, ImageSource_Marketplace:
		imageDefinitionValidator = newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		)
	case ImageSource_Customer:
		imageDefinitionValidator = newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
		)
	default:
		logger.Info(ctx, "unsupported image type")
		return nil, twirp.InvalidArgument.Error("unsupported image type")
	}

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageId, imageDefinitionValidator)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.getExactImageVersion(ctx, imageDefinition.ResolveImageDefinitionId(), req.ImageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get exact image version", err)
		return nil, twirp.Internal.Error("failed to get exact image version")
	}

	if imageVersion == nil {
		if req.ImageVersion == models.LatestImageVersion {
			logger.Info(ctx, "image definition does not have enabled versions in ready state")
			return nil, twirp.InvalidArgument.Error("image definition does not have enabled versions in ready state")
		} else {
			logger.Info(ctx, "image version is not found")
			return nil, twirp.InvalidArgument.Error("image version is not found")
		}
	}

	ctx = stash.WithLoggingFields(ctx, kvp.String("exact_image_version", imageVersion.Version))

	if imageVersion.State != models.ImageVersionState_Ready {
		logger.Info(ctx, "requested image version is not ready to use")
		return nil, twirp.InvalidArgument.Error("requested image version is not ready to use")
	}

	imageReference, err := mapInternalImageReference(imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image version to image reference", err)
		return nil, twirp.Internal.Error("failed to map image version")
	}

	if imageDefinition.IsGalleryImageDefinition() {
		if imageReference.ResourceId == "" {
			imageReference.ResourceId, err = h.promotionClient.GalleryProvider().GetImageVersionResourceId(ctx, imageVersion)
			if err != nil {
				logger.ErrorWithReport(ctx, "failed to get image version resource id", err)
				return nil, twirp.Internal.Error("failed to get image version resource id")
			}
			logger.Info(ctx, "resourceId is empty for image version in Ready state")
		}
	}

	return &internalapi.GetImageReferenceResponse{
		ImageReference:    imageReference,
		ResourceId:        imageReference.ResourceId,
		ExactImageVersion: imageReference.ExactImageVersion,
		OsState:           imageReference.OsState,
		AgentUser:         imageReference.AgentUser,
		AzurePurchasePlan: imageReference.AzurePurchasePlan,
	}, nil
}

func (h *InternalImagesApiHandler) getExactImageVersion(ctx context.Context, imageDefinitionId uint64, version string) (*models.ImageVersion, error) {
	var (
		imageVersion *models.ImageVersion
		err          error
	)

	if version == models.LatestImageVersion {
		imageVersion, err = h.imageStore.GetLatestImageVersion(ctx, imageDefinitionId)
		if err != nil {
			return nil, fmt.Errorf("failed to get latest image version: %w", err)
		}
	} else {
		imageVersion, err = h.imageStore.GetImageVersionByDefinitionIdAndVersion(ctx, imageDefinitionId, version)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil, nil
			}
			return nil, fmt.Errorf("failed to get specific image version: %w", err)
		}
	}
	return imageVersion, nil
}
