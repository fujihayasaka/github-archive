package twirp

import (
	"context"

	"github.com/twitchtv/twirp"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"

	"github.com/github/hosted-compute-ims/gen/ent"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
)

func (h *InternalImagesApiHandler) StartImageVersionGeneration(ctx context.Context, req *internalapi.StartImageVersionGenerationRequest) (*internalapi.StartImageVersionGenerationResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", req.ImageSource),
		kvp.Uint64("image_definition_id", req.ImageId),
		kvp.String("image_version", req.ImageVersion),
		kvp.String("owner_id", req.Owner.GlobalId),
	)

	if req.ImageSource != ImageSource_Customer {
		logger.Info(ctx, "unsupported image type")
		return nil, twirp.InvalidArgument.Error("unsupported image source")
	}

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	var versionsCount int32 = 0
	if versionsSummary, err := h.imageStore.GetImageVersionsSummary(ctx, req.ImageId); err != nil {
		logger.ErrorWithReport(ctx, "failed to get image versions summary for image definition", err)
		return nil, twirp.Internal.Error("failed to create image version")
	} else if versionsSummary != nil {
		versionsCount = versionsSummary.Count
	}

	if versionsCount >= h.getCustomerImageVersionsLimitForActor(ctx, req.Owner) {
		logger.Info(ctx, "image definition already has maximum number of image versions")
		return nil, twirp.ResourceExhausted.Error("image definition already has maximum number of image versions")
	}

	version, err := h.getNextImageVersionAsNeeded(ctx, req.ImageId, req.ImageVersion)
	if err != nil {
		return nil, err
	}
	logger.Info(ctx, "resolved next image version", kvp.String("resolved_to_image_version", version))

	vmGeneration, err := mapApiToVmGeneration(req.VmGeneration)
	if err != nil {
		logger.Info(ctx, "request has invalid vm generation", kvp.String("vm_generation", string(req.VmGeneration)))
		return nil, twirp.InvalidArgument.Error("invalid vm generation")
	}

	osState, err := mapApiToOsState(req.OsState)
	if err != nil {
		logger.Info(ctx, "request has invalid os state", kvp.String("os_state", string(req.OsState)))
		return nil, twirp.InvalidArgument.Error("invalid os state")
	}

	createdImageVersionId, err := h.imageStore.AddImageVersion(ctx, &models.ImageVersion{
		ImageDefinitionId: req.ImageId,
		Version:           version,
		State:             models.ImageVersionState_Generating,
		Enabled:           true,
		VmGeneration:      vmGeneration,
		AgentUser:         req.AgentUser,
		AzurePurchasePlan: req.AzurePurchasePlan,
		OsState:           osState,
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

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_version_id", createdImageVersionId))
	logger.Info(ctx, "created image version for image generation")

	createdImageVersion, err := h.imageStore.GetImageVersionById(ctx, createdImageVersionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get newly created image version", err)
		return nil, twirp.Internal.Error("failed to get newly created image version")
	}

	return &internalapi.StartImageVersionGenerationResponse{
		CreatedImageVersion: createdImageVersion.Version,
	}, nil
}

func (h *InternalImagesApiHandler) UpdateImageVersionGenerationStatus(ctx context.Context, req *internalapi.UpdateImageVersionGenerationStatusRequest) (*internalapi.UpdateImageVersionGenerationStatusResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", req.ImageSource),
		kvp.Uint64("image_definition_id", req.ImageId),
		kvp.String("image_version", req.ImageVersion),
		kvp.String("owner_id", req.Owner.GlobalId),
	)

	if req.ImageSource != ImageSource_Customer {
		logger.Info(ctx, "unsupported image type")
		return nil, twirp.InvalidArgument.Error("unsupported image source")
	}

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, req.ImageId, req.ImageVersion, nil)
	if err != nil {
		return nil, err
	}

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_version_id", imageVersion.Id))

	err = h.imageStore.UpdateImageVersionStateDetailsForState(
		ctx,
		imageVersion.Id,
		models.ImageVersionState_Generating,
		req.StateDetails)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to update image version status", err)
		return nil, twirp.Internal.Error("failed to update image version status")
	}

	logger.Info(ctx, "update image version status for image generation")

	return &internalapi.UpdateImageVersionGenerationStatusResponse{}, nil
}

func (h *InternalImagesApiHandler) FinishImageVersionGeneration(ctx context.Context, req *internalapi.FinishImageVersionGenerationRequest) (*internalapi.FinishImageVersionGenerationResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", req.ImageSource),
		kvp.Uint64("image_definition_id", req.ImageId),
		kvp.String("image_version", req.ImageVersion),
		kvp.String("owner_id", req.Owner.GlobalId),
	)

	if req.ImageSource != ImageSource_Customer {
		logger.Info(ctx, "unsupported image type")
		return nil, twirp.InvalidArgument.Error("unsupported image source")
	}

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Customer),
			withImageOwnerValidation(req.Owner.GlobalId),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, req.ImageId, req.ImageVersion, nil)
	if err != nil {
		return nil, err
	}

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_version_id", imageVersion.Id))

	newState := models.ImageVersionState_Pending
	if !req.Success {
		newState = models.ImageVersionState_ProvisionFailed
	}

	// This does not update state status so that previously updated state details are not overwritten.
	err = h.imageStore.UpdateImageVersionState(
		ctx,
		imageVersion.Id,
		newState,
		req.StateDetails)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to update image version state", err)
		return nil, twirp.Internal.Error("failed to finish image version generation")
	}

	if req.Success {
		if err = h.promotionStartClient.StartAsyncImageVersionProvision(ctx, imageVersion.Id, req.SourceVhdUrl, req.WorkflowOwnerId); err != nil {
			logger.ErrorWithReport(ctx, "failed to queue image version provision job", err)
			return nil, twirp.Internal.Error("failed to start image version provision")
		}
	}

	return &internalapi.FinishImageVersionGenerationResponse{}, nil
}
