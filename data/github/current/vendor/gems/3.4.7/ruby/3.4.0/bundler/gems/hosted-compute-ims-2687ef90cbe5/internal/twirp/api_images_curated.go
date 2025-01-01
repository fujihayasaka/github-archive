package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/twitchtv/twirp"

	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/utils"
)

func (h *ImagesApiHandler) GetCuratedImageDefinition(ctx context.Context, req *imagesapi.GetCuratedImageDefinitionRequest) (*imagesapi.GetCuratedImageDefinitionResponse, error) {
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

	latestVersion, err := h.imageStore.GetLatestImageVersion(ctx, imageDefinition.ResolveImageDefinitionId())
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get latest image version for image definition", err)
		return nil, twirp.Internal.Error("failed to get image definition")
	}

	mappedImageDefinition, err := mapImageDefinition(imageDefinition, latestVersion, nil)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image definition", err)
		return nil, twirp.Internal.Error("failed to get image definition")
	}

	mappedImageDefinition.Enabled = h.isCuratedImageDefinitionEnabledForActor(ctx, imageDefinition, req.Owner)

	return &imagesapi.GetCuratedImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) GetCuratedImageVersion(ctx context.Context, req *imagesapi.GetCuratedImageVersionRequest) (*imagesapi.GetCuratedImageVersionResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
		kvp.String("image_version", req.Version),
	)

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withEnabledImageDefinitionForActorValidation(req.Owner),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersion, err := h.GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx, imageDefinition.ResolveImageDefinitionId(), req.Version,
		newTwirpValidator(
			withEnabledImageVersionValidation(),
		),
	)
	if err != nil {
		return nil, err
	}

	mappedImageVersion, err := mapImageVersion(imageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image version", err)
		return nil, twirp.Internal.Error("failed to get image version")
	}

	return &imagesapi.GetCuratedImageVersionResponse{ImageVersion: mappedImageVersion}, nil
}

func (h *ImagesApiHandler) ListCuratedImageVersions(ctx context.Context, req *imagesapi.ListCuratedImageVersionsRequest) (*imagesapi.ListCuratedImageVersionsResponse, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.String("image_type", string(models.ImageType_Curated)),
		kvp.Uint64("image_definition_id", req.ImageDefinitionId),
	)

	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
			withEnabledImageDefinitionForActorValidation(req.Owner),
		),
	)
	if err != nil {
		return nil, err
	}

	imageVersions, err := h.imageStore.ListImageVersionsByDefinitionId(ctx, imageDefinition.ResolveImageDefinitionId())
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to list image versions for image definition", err)
		return nil, twirp.Internal.Error("failed to list image versions")
	}

	// for curated images, we only want customers to be able to see enabled versions
	imageVersions = utils.FilterFunc(imageVersions, func(i *models.ImageVersion) bool {
		return i.Enabled
	})
	models.SortImageVersionsByVersion(imageVersions)

	mappedImageVersions, err := utils.MapFunc(imageVersions, mapImageVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to map image versions", err)
		return nil, twirp.Internal.Error("failed to list image versions")
	}

	return &imagesapi.ListCuratedImageVersionsResponse{ImageVersions: mappedImageVersions}, nil
}

func (h *ImagesApiHandler) ListCuratedImageDefinitions(ctx context.Context, req *imagesapi.ListCuratedImageDefinitionsRequest) (*imagesapi.ListCuratedImageDefinitionsResponse, error) {
	ctx = stash.WithLoggingFields(ctx, kvp.String("image_type", string(models.ImageType_Curated)))

	imageDefinitions, err := h.imageStore.ListCuratedImageDefinitions(ctx)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to list image definitions", err)
		return nil, twirp.Internal.Error("failed to list image definitions")
	}

	imageDefinitions = utils.FilterFunc(imageDefinitions, func(def *models.ImageDefinition) bool {
		// currently, we don't support creating larger runners with macOS images
		// so, exclude them from API response
		if def.OsType == models.OsType_MacOS {
			return false
		}

		// azure dev ops images are not intended for GitHub Runners
		// so, exclude them from API response
		if def.OwnerId == models.AzureDevOpsOwnerId {
			return false
		}

		return true
	})

	var imageDefinitionIds []uint64
	for _, imageDefinition := range imageDefinitions {
		imageDefinitionIds = append(imageDefinitionIds, imageDefinition.Id)
	}

	latestVersionsMap, err := h.imageStore.GetLatestImageVersionsForImageDefinitions(ctx, imageDefinitionIds)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to get latest image versions for image definitions", err)
		return nil, twirp.Internal.Error("failed to list image definitions")
	}

	mappedImageDefinitions := make([]*imagesapi.ImageDefinition, len(imageDefinitions))
	for index, imageDefinition := range imageDefinitions {
		mappedImageDefinitions[index], err = mapImageDefinition(imageDefinition, latestVersionsMap[imageDefinition.ResolveImageDefinitionId()], nil)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to map image definitions", err)
			return nil, twirp.Internal.Error("failed to list image definitions")
		}

		mappedImageDefinitions[index].Enabled = h.isCuratedImageDefinitionEnabledForActor(ctx, imageDefinition, req.Owner)
	}

	if !req.IncludeDisabled {
		mappedImageDefinitions = utils.FilterFunc(mappedImageDefinitions, func(def *imagesapi.ImageDefinition) bool {
			return def.Enabled
		})
	}

	return &imagesapi.ListCuratedImageDefinitionsResponse{
		ImageDefinitions: mappedImageDefinitions,
	}, nil
}
