package resources

import (
	"fmt"
	"slices"

	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
)

type sharedImagesDevConfigImage struct {
	Id                     uint64 `yaml:"id"`
	SharedGalleryImageName string `yaml:"sharedGalleryImageName"`
}

type sharedImagesDevConfigGallery struct {
	SubscriptionId string `yaml:"subscriptionId"`
	ResourceGroup  string `yaml:"resourceGroup"`
	GalleryName    string `yaml:"galleryName"`
}

type sharedImagesDevConfig struct {
	SharedGallery sharedImagesDevConfigGallery `yaml:"sharedGallery"`
	CuratedImages []sharedImagesDevConfigImage `yaml:"curatedImages"`
}

func getGalleryImageVersionKeyForSharedDevImage(imageVersion *models.ImageVersion) (*azure.GalleryImageVersionKey, error) {
	// shared dev images on shared dev subscription don't follow IMS image layout
	// so, we use "shared-images.yml" config to resolve correct resource names on shared subscription

	devConfig, err := utils.GetDevConfig[sharedImagesDevConfig]("shared-images.yml")
	if err != nil {
		return nil, fmt.Errorf("failed to parse dev config: %w", err)
	}

	imageIndex := slices.IndexFunc(devConfig.CuratedImages, func(m sharedImagesDevConfigImage) bool { return m.Id == imageVersion.ImageDefinitionId })
	if imageIndex < 0 {
		return nil, fmt.Errorf("failed to find curated shared image with id %d in dev config", imageVersion.ImageDefinitionId)
	}

	return azure.NewGalleryImageVersionKey(
		devConfig.SharedGallery.SubscriptionId,
		devConfig.SharedGallery.ResourceGroup,
		devConfig.SharedGallery.GalleryName,
		devConfig.CuratedImages[imageIndex].SharedGalleryImageName,
		imageVersion.Version,
	), nil
}
