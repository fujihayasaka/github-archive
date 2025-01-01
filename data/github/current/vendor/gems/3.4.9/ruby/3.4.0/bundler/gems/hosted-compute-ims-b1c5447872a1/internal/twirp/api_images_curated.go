package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/twitchtv/twirp"

	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	"github.com/github/hosted-compute-ims/internal/models"
)

func (h *ImagesApiHandler) GetCuratedImageDefinition(ctx context.Context, req *imagesapi.GetCuratedImageDefinitionRequest) (*imagesapi.GetCuratedImageDefinitionResponse, error) {
	imageDefinition, err := h.GetAndValidateImageDefinition(ctx, req.ImageDefinitionId,
		newTwirpValidator(
			withImageTypeValidation(models.ImageType_Curated),
		),
	)
	if err != nil {
		return nil, err
	}

	// We don't need image version metadata for curated images.
	storageMetadata := map[uint64]*models.ImageVersionsStorageMetadata{}

	mappedImageDefinition, err := mapImageDefinition(imageDefinition, storageMetadata)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definition", err, kvp.Uint64("image_definition_id", req.ImageDefinitionId))
		return nil, twirp.Internal.Error("failed to map image definition")
	}

	mappedImageDefinition.Enabled = isCuratedImageDefinitionEnabledForActor(ctx, imageDefinition, req.Owner)

	latestVersion, err := h.imageStore.GetLatestImageVersion(ctx, imageDefinition.ResolveImageDefinitionId())
	if err != nil {
		h.logger.ErrorWithReport("failed to get latest image version for image definition", err, kvp.Uint64("image_definition_id", imageDefinition.Id))
		return nil, twirp.Internal.Error("failed to get latest image version for image definition")
	}

	if latestVersion != nil {
		mappedImageDefinition.LatestVersion = latestVersion.Version
		if latestVersion.SizeGB != nil {
			mappedImageDefinition.SizeGb = *latestVersion.SizeGB
			mappedImageDefinition.LatestVersionSizeGb = *latestVersion.SizeGB
		}
	}

	return &imagesapi.GetCuratedImageDefinitionResponse{
		ImageDefinition: mappedImageDefinition,
	}, nil
}

func (h *ImagesApiHandler) GetCuratedImageVersion(ctx context.Context, req *imagesapi.GetCuratedImageVersionRequest) (*imagesapi.GetCuratedImageVersionResponse, error) {
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
		h.logger.ErrorWithReport("failed to map image version", err,
			kvp.Uint64("image_definition_id", req.GetImageDefinitionId()),
			kvp.String("image_version", req.GetVersion()),
		)
		return nil, twirp.Internal.Error("failed to map image version")
	}

	return &imagesapi.GetCuratedImageVersionResponse{ImageVersion: mappedImageVersion}, nil
}

func (h *ImagesApiHandler) ListCuratedImageVersions(ctx context.Context, req *imagesapi.ListCuratedImageVersionsRequest) (*imagesapi.ListCuratedImageVersionsResponse, error) {
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
		h.logger.ErrorWithReport("failed to list image versions for image definition", err, kvp.Uint64("image_definition_id", req.GetImageDefinitionId()))
		return nil, twirp.Internal.Error("failed to list image versions for image definition")
	}

	// for curated images, we only want customers to be able to see enabled versions
	imageVersions = filterFunc(imageVersions, func(i *models.ImageVersion) bool {
		return i.Enabled
	})
	models.SortImageVersionsByVersion(imageVersions)

	mappedImageVersions, err := mapFunc(imageVersions, mapImageVersion)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image versions", err)
		return nil, twirp.Internal.Error("failed to map image version")
	}

	return &imagesapi.ListCuratedImageVersionsResponse{ImageVersions: mappedImageVersions}, nil
}

func (h *ImagesApiHandler) ListCuratedImageDefinitions(ctx context.Context, req *imagesapi.ListCuratedImageDefinitionsRequest) (*imagesapi.ListCuratedImageDefinitionsResponse, error) {
	imageDefinitions, err := h.imageStore.ListCuratedImageDefinitions(ctx)
	if err != nil {
		h.logger.ErrorWithReport("failed to list image definitions", err)
		return nil, twirp.Internal.Error("failed to list image definitions")
	}

	imageDefinitions = filterFunc(imageDefinitions, func(def *models.ImageDefinition) bool {
		// currently, we don't support creating larger runners with macOS images
		// so, exclude them from API response
		return def.OsType != models.OsType_MacOS
	})

	// We don't need image version metadata for curated images.
	storageMetadata := map[uint64]*models.ImageVersionsStorageMetadata{}

	mappedImageDefinitions, err := mapImageDefinitions(imageDefinitions, storageMetadata)
	if err != nil {
		h.logger.ErrorWithReport("failed to map image definitions", err)
		return nil, twirp.Internal.Error("failed to map image definitions")
	}

	// It will makes N + 1 calls to the DB. Currently, we limit the number of image versions per image definition is 100.
	// Need to optimize if we extend the limitation in the future.
	for i, mappedImageDefinition := range mappedImageDefinitions {
		mappedImageDefinition.Enabled = isCuratedImageDefinitionEnabledForActor(ctx, imageDefinitions[i], req.Owner)

		if mappedImageDefinition.Enabled || req.IncludeDisabled {
			latestVersion, err := h.imageStore.GetLatestImageVersion(ctx, imageDefinitions[i].ResolveImageDefinitionId())
			if err != nil {
				h.logger.ErrorWithReport("failed to get latest image version for image definition", err, kvp.Uint64("image_definition_id", mappedImageDefinition.Id))
				return nil, twirp.Internal.Error("failed to get latest image version for image definition")
			}

			if latestVersion != nil {
				mappedImageDefinition.LatestVersion = latestVersion.Version
				if latestVersion.SizeGB != nil {
					mappedImageDefinition.SizeGb = *latestVersion.SizeGB
					mappedImageDefinition.LatestVersionSizeGb = *latestVersion.SizeGB
				}
			}
		}
	}

	if !req.IncludeDisabled {
		// for curated images, we only want customers to be able to see enabled definitions
		mappedImageDefinitions = filterFunc(mappedImageDefinitions, func(i *imagesapi.ImageDefinition) bool {
			return i.Enabled
		})
	}

	return &imagesapi.ListCuratedImageDefinitionsResponse{
		ImageDefinitions: mappedImageDefinitions,
	}, nil
}
