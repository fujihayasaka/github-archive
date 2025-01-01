package twirp

import (
	"context"
	"slices"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/gen/ent"
	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

func (h *ImagesAdminApiHandler) GetCuratedImageDefinition(ctx context.Context, req *adminapi.GetCuratedImageDefinitionRequest) (*adminapi.GetCuratedImageDefinitionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
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
		logger.ErrorWithReport(ctx, "failed to get image versions summary for image definition", err)
		return nil, twirp.Internal.Error("failed to get image definition")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(imageDefinition, latestVersion, versionsSummary)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err)
		return nil, twirp.Internal.Error("failed to get image definition")
	}

	return &adminapi.GetCuratedImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) GetCuratedImageVersion(ctx context.Context, req *adminapi.GetCuratedImageVersionRequest) (*adminapi.GetCuratedImageVersionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		kvp.String("image_version", req.Version),
	)

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, req.ImageDefinitionId, req.Version, nil)
	if err != nil {
		return nil, err
	}

	mappedImageVersion, err := mapAdminImageVersion(imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image version", err)
		return nil, twirp.Internal.Error("failed to get image version")
	}

	if mappedImageVersion.ResourceId == "" && imageVersion.State == models.ImageVersionState_Ready && imageDefinition.IsGalleryImageDefinition() {
		mappedImageVersion.ResourceId, err = h.promotionClient.GalleryProvider().GetImageVersionResourceId(ctx, imageVersion)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to get image version resource id", err)
			return nil, twirp.Internal.Error("failed to get image version")
		}
		logger.Info(ctx, "resourceId is empty for image version in Ready state")
	}

	return &adminapi.GetCuratedImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}

func (h *ImagesAdminApiHandler) ListCuratedImageDefinitions(ctx context.Context, req *adminapi.ListCuratedImageDefinitionsRequest) (*adminapi.ListCuratedImageDefinitionsResponse, error) {
	ctx = stash.WithLoggingFields(ctx, kvp.String("image_type", string(models.ImageType_Curated)))

	imageDefinitions, err := h.imageStore.ListCuratedImageDefinitions(ctx)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to list curated image definitions", err)
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

	mappedImageDefinitions := make([]*adminapi.ImageDefinition, len(imageDefinitions))
	for index, imageDefinition := range imageDefinitions {
		mappedImageDefinitions[index], err = mapAdminImageDefinition(imageDefinition, latestVersionsMap[imageDefinition.Id], versionsSummariesMap[imageDefinition.Id])
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to map image definitions", err)
			return nil, twirp.Internal.Error("failed to list image definitions")
		}
	}

	return &adminapi.ListCuratedImageDefinitionsResponse{
		ImageDefinitions: mappedImageDefinitions,
	}, nil
}

func (h *ImagesAdminApiHandler) ListCuratedImageVersions(ctx context.Context, req *adminapi.ListCuratedImageVersionsRequest) (*adminapi.ListCuratedImageVersionsResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersions, err := h.imageStore.ListImageVersionsByDefinitionId(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to list curated image versions", err)
		return nil, twirp.Internal.Error("failed to list image versions")
	}

	models.SortImageVersionsByVersion(imageVersions)

	mappedImageVersions := make([]*adminapi.ImageVersion, 0, len(imageVersions))
	for _, imageVersion := range imageVersions {
		mappedImageVersion, err := mapAdminImageVersion(imageVersion)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to map curated image versions", err)
			return nil, twirp.Internal.Error("failed to list image versions")
		}

		if mappedImageVersion.ResourceId == "" && imageVersion.State == models.ImageVersionState_Ready && imageDefinition.IsGalleryImageDefinition() {
			mappedImageVersion.ResourceId, err = h.promotionClient.GalleryProvider().GetImageVersionResourceId(ctx, imageVersion)
			if err != nil {
				logger.ErrorWithReport(ctx, "failed to get image version resource id", err)
				return nil, twirp.Internal.Error("failed to get image version")
			}
			logger.Info(ctx, "resourceId is empty for image version in Ready state")
		}

		mappedImageVersions = append(mappedImageVersions, mappedImageVersion)
	}

	return &adminapi.ListCuratedImageVersionsResponse{
		ImageVersions: mappedImageVersions,
	}, nil
}

func (h *ImagesAdminApiHandler) CreateCuratedImageDefinition(ctx context.Context, req *adminapi.CreateCuratedImageDefinitionRequest) (*adminapi.CreateCuratedImageDefinitionResponse, error) {
	ctx = stash.WithLoggingFields(ctx, kvp.String("image_type", string(models.ImageType_Curated)))

	if !slices.Contains(models.AllowedCuratedImagesOwners, req.OwnerId) {
		logger.Info(ctx, "request has invalid owner_id", kvp.String("owner_id", req.OwnerId))
		return nil, twirp.InvalidArgument.Error("invalid owner_id")
	}

	osType, err := mapApiToOsType(req.OsType)
	if err != nil {
		logger.Info(ctx, "request has invalid os type", kvp.String("os_type", string(req.OsType)))
		return nil, twirp.InvalidArgument.Error("invalid os_type")
	}

	architecture, err := mapApiToArchitecture(req.Architecture)
	if err != nil {
		logger.Info(ctx, "request has invalid architecture", kvp.String("architecture", string(req.Architecture)))
		return nil, twirp.InvalidArgument.Error("invalid architecture")
	}

	var featureFlag *string
	if req.FeatureFlag != "" {
		featureFlag = &req.FeatureFlag
	}

	imageDefinitionId, err := h.imageStore.AddImageDefinition(ctx, &models.ImageDefinition{
		OwnerId:                    req.OwnerId,
		Name:                       req.Name,
		ImageType:                  models.ImageType_Curated,
		Enabled:                    req.Enabled,
		FeatureFlag:                featureFlag,
		OsType:                     osType,
		Architecture:               architecture,
		State:                      models.ImageDefinitionState_Ready,
		IsImageGenerationSupported: req.IsImageGenerationSupported,
	})
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to create a new curated image definition", err)
		return nil, twirp.Internal.Error("failed to create a new image definition")
	}

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_definition_id", imageDefinitionId))
	logger.Info(ctx, "created image definition")

	imageDefinition, err := h.imageStore.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get newly created image definition", err)
		return nil, twirp.Internal.Error("failed to get newly created image definition")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(imageDefinition, nil, nil)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err)
		return nil, twirp.Internal.Error("failed to get newly created image definition")
	}

	return &adminapi.CreateCuratedImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesAdminApiHandler) DeleteCuratedImageDefinition(ctx context.Context, req *adminapi.DeleteCuratedImageDefinitionRequest) (*adminapi.DeleteCuratedImageDefinitionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	isReferenced, err := h.isImageDefinitionReferencedByPointer(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to check if image definition is referenced by any pointer", err)
		return nil, twirp.Internal.Error("failed to delete image definition")
	}
	if isReferenced {
		logger.Info(ctx, "failed to delete image definition because it is referenced by pointer", kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.InvalidArgument.Error("failed to delete image definition because it is referenced by pointer. Delete pointer first.")
	}

	imageVersions, err := h.imageStore.ListImageVersionsByDefinitionId(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to check if image definition has any image versions", err)
		return nil, twirp.Internal.Error("failed to delete image definition")
	}
	if len(imageVersions) > 0 {
		logger.Info(ctx, "failed to delete image definition because it has image versions")
		return nil, twirp.InvalidArgument.Error("failed to delete image definition because it has image versions")
	}

	err = h.imageStore.DeleteImageDefinition(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to delete image definition", err)
		return nil, twirp.Internal.Error("failed to delete image definition")
	}

	logger.Info(ctx, "deleted image definition")

	return &adminapi.DeleteCuratedImageDefinitionResponse{}, nil
}

func (h *ImagesAdminApiHandler) DeleteCuratedImageVersion(ctx context.Context, req *adminapi.DeleteCuratedImageVersionRequest) (*adminapi.DeleteCuratedImageVersionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		kvp.String("image_version", req.Version),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
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
		return nil, twirp.Internal.Error("failed to get updated image version")
	}

	mappedImageVersion, err := mapAdminImageVersion(imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map updated image version", err)
		return nil, twirp.Internal.Error("failed to get updated image version")
	}

	return &adminapi.DeleteCuratedImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}

func (h *ImagesAdminApiHandler) UpdateCuratedImageVersion(ctx context.Context, req *adminapi.UpdateCuratedImageVersionRequest) (*adminapi.UpdateCuratedImageVersionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		kvp.String("image_version", req.Version),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
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

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_version_id", imageVersion.Id))

	err = h.imageStore.UpdateImageVersion(ctx, imageVersion.Id, &store.ImageVersionUpdatePayload{
		Enabled: wrapperspb.Bool(req.Enabled),
	})
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to update image version", err)
		return nil, twirp.Internal.Error("failed to update image version")
	}

	logger.Info(ctx, "updated image version")

	updatedImageVersion, err := h.imageStore.GetImageVersionById(ctx, imageVersion.Id)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get updated image version", err)
		return nil, twirp.Internal.Error("failed to get updated image version")
	}

	mappedImageVersion, err := mapAdminImageVersion(updatedImageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map updated image version", err)
		return nil, twirp.Internal.Error("failed to get updated image version")
	}

	return &adminapi.UpdateCuratedImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}

func (h *ImagesAdminApiHandler) CreateCuratedImageVersion(ctx context.Context, req *adminapi.CreateCuratedImageVersionRequest) (*adminapi.CreateCuratedImageVersionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		kvp.String("image_version", req.Version),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	version, err := h.getNextImageVersionAsNeeded(ctx, req.GetImageDefinitionId(), req.Version)
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

	imageVersionId, err := h.imageStore.AddImageVersion(ctx, &models.ImageVersion{
		Version:           version,
		ImageDefinitionId: req.ImageDefinitionId,
		Enabled:           req.Enabled,
		State:             models.ImageVersionState_Pending,
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
			logger.ErrorWithReport(ctx, "failed to create a new image version", err)
			return nil, twirp.Internal.Error("failed to create a new image version")
		}
	}

	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_version_id", imageVersionId))

	logger.Info(ctx, "created image version")

	if err = h.promotionStartClient.StartAsyncImageVersionProvision(ctx, imageVersionId, req.GetSourceVhdUrl(), ""); err != nil {
		logger.ErrorWithReport(ctx, "failed to start image version provision", err)
		return nil, twirp.Internal.Error("failed to start image version provision")
	}

	imageVersion, err := h.imageStore.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get newly created image version", err)
		return nil, twirp.Internal.Error("failed to get newly created image version")
	}

	mappedImageVersion, err := mapAdminImageVersion(imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image version", err)
		return nil, twirp.Internal.Error("failed to get newly created image version")
	}

	return &adminapi.CreateCuratedImageVersionResponse{
		ImageVersion: mappedImageVersion,
	}, nil
}

func (h *ImagesAdminApiHandler) UpdateCuratedImageDefinition(ctx context.Context, req *adminapi.UpdateCuratedImageDefinitionRequest) (*adminapi.UpdateCuratedImageDefinitionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	_, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			allowPointerValidation(false),
		),
	)
	if err != nil {
		return nil, err
	}

	err = h.imageStore.UpdateImageDefinition(ctx, req.ImageDefinitionId, &store.ImageDefinitionUpdatePayload{
		Name:                       wrapperspb.String(req.Name),
		Enabled:                    wrapperspb.Bool(req.Enabled),
		FeatureFlag:                wrapperspb.String(req.FeatureFlag),
		IsImageGenerationSupported: wrapperspb.Bool(req.IsImageGenerationSupported),
	})
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to update curated image definition", err)
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

	versionsMetadata, err := h.imageStore.GetImageVersionsSummary(ctx, req.ImageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get image versions summary for updated image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition")
	}

	mappedImageDefinition, err := mapAdminImageDefinition(imageDefinition, latestVersion, versionsMetadata)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err)
		return nil, twirp.Internal.Error("failed to get updated image definition")
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
