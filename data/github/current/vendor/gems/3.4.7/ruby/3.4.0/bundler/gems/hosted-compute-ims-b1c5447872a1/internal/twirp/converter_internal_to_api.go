package twirp

import (
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"google.golang.org/protobuf/types/known/timestamppb"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
)

const (
	ImageSource_Curated  = "Curated"
	ImageSource_Customer = "Customer"
)

func mapImageVersion(imageVersion *models.ImageVersion) (*imagesapi.ImageVersion, error) {
	if imageVersion == nil {
		return nil, fmt.Errorf("failed to map image version state because image version is nil")
	}

	var sizeGB int32
	if imageVersion.SizeGB != nil {
		sizeGB = *imageVersion.SizeGB
	}

	state, err := mapImageVersionState(imageVersion.State)
	if err != nil {
		return nil, fmt.Errorf("failed to map image version state: %w", err)
	}

	return &imagesapi.ImageVersion{
		ImageDefinitionId: imageVersion.ImageDefinitionId,
		Version:           imageVersion.Version,
		State:             state,
		StateDetails:      imageVersion.StateDetails,
		SizeGb:            sizeGB,
	}, nil
}

func mapAdminImageVersion(imageVersion *models.ImageVersion) (*adminapi.ImageVersion, error) {
	if imageVersion == nil {
		return nil, fmt.Errorf("failed to map image version state because image version is nil")
	}

	var sizeGB int32
	if imageVersion.SizeGB != nil {
		sizeGB = *imageVersion.SizeGB
	}

	state, err := mapImageVersionState(imageVersion.State)
	if err != nil {
		return nil, fmt.Errorf("failed to map image version state: %w", err)
	}

	var updatedAt *timestamppb.Timestamp
	if imageVersion.UpdatedAt != nil {
		updatedAt = timestamppb.New(*imageVersion.UpdatedAt)
	}

	return &adminapi.ImageVersion{
		Id:                imageVersion.Id,
		ImageDefinitionId: imageVersion.ImageDefinitionId,
		Version:           imageVersion.Version,
		State:             state,
		StateDetails:      imageVersion.StateDetails,
		ResourceId:        imageVersion.ResourceId,
		SizeGb:            sizeGB,
		Enabled:           imageVersion.Enabled,
		CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
		UpdatedAt:         updatedAt,
	}, nil
}

func mapImageVersionState(state models.ImageVersionState) (sharedapi.ImageVersionState, error) {
	switch state {
	case models.ImageVersionState_Pending:
		return sharedapi.ImageVersionState_Pending, nil
	case models.ImageVersionState_Provisioning:
		return sharedapi.ImageVersionState_Provisioning, nil
	case models.ImageVersionState_Ready:
		return sharedapi.ImageVersionState_Ready, nil
	case models.ImageVersionState_ProvisionFailed:
		return sharedapi.ImageVersionState_ProvisionFailed, nil
	case models.ImageVersionState_Deleting:
		return sharedapi.ImageVersionState_Deleting, nil
	default:
		return 0, fmt.Errorf("unknown image version state: %s", state)
	}
}

func mapImageDefinition(imageDefinition *models.ImageDefinition, imageVersionsMetadata map[uint64]*models.ImageVersionsStorageMetadata) (*imagesapi.ImageDefinition, error) {
	if imageDefinition == nil {
		return nil, fmt.Errorf("failed to map image definition because image definition is nil")
	}

	osType, err := mapOsType(imageDefinition.OsType)
	if err != nil {
		return nil, fmt.Errorf("failed to map ostype: %w", err)
	}

	architecture, err := mapArchitecture(imageDefinition.Architecture)
	if err != nil {
		return nil, fmt.Errorf("failed to map architecture: %w", err)
	}

	var count int32 = 0
	var imageVersionsSizeGb int32 = 0
	if imageVersionsData, ok := imageVersionsMetadata[imageDefinition.Id]; ok {
		count = imageVersionsData.Count
		imageVersionsSizeGb = imageVersionsData.TotalImageVersionsSizeGB
	}

	return &imagesapi.ImageDefinition{
		Id:                       imageDefinition.Id,
		Name:                     imageDefinition.Name,
		OsType:                   osType,
		Architecture:             architecture,
		Enabled:                  imageDefinition.Enabled,
		LatestVersionSizeGb:      0,
		ImageVersionsCount:       count,
		TotalImageVersionsSizeGb: imageVersionsSizeGb,
	}, nil
}

func mapImageDefinitions(imageDefinitions []*models.ImageDefinition, imageVersionsMetadata map[uint64]*models.ImageVersionsStorageMetadata) ([]*imagesapi.ImageDefinition, error) {
	result := make([]*imagesapi.ImageDefinition, 0, len(imageDefinitions))

	for _, elem := range imageDefinitions {
		mappedElement, err := mapImageDefinition(elem, imageVersionsMetadata)
		if err != nil {
			return nil, err
		}

		result = append(result, mappedElement)
	}

	return result, nil
}

func mapAdminImageDefinition(imageDefinition *models.ImageDefinition) (*adminapi.ImageDefinition, error) {
	if imageDefinition == nil {
		return nil, fmt.Errorf("failed to map image definition because image definition is nil")
	}

	osType, err := mapOsType(imageDefinition.OsType)
	if err != nil {
		return nil, fmt.Errorf("failed to map ostype: %w", err)
	}

	architecture, err := mapArchitecture(imageDefinition.Architecture)
	if err != nil {
		return nil, fmt.Errorf("failed to map architecture: %w", err)
	}

	var updatedAt *timestamppb.Timestamp
	if imageDefinition.UpdatedAt != nil {
		updatedAt = timestamppb.New(*imageDefinition.UpdatedAt)
	}

	var pointsToImageDefinitionId uint64
	if imageDefinition.PointsToImageDefinitionId != nil {
		pointsToImageDefinitionId = *imageDefinition.PointsToImageDefinitionId
	}

	return &adminapi.ImageDefinition{
		Id:                        imageDefinition.Id,
		Name:                      imageDefinition.Name,
		OsType:                    osType,
		Architecture:              architecture,
		Enabled:                   imageDefinition.Enabled,
		FeatureFlag:               utils.FromPtr(imageDefinition.FeatureFlag),
		PointsToImageDefinitionId: pointsToImageDefinitionId,
		CreatedAt:                 timestamppb.New(imageDefinition.CreatedAt),
		UpdatedAt:                 updatedAt,
	}, nil
}

func mapInternalImageDetails(imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion) (*internalapi.ImageDetails, error) {
	if imageDefinition == nil {
		return nil, fmt.Errorf("failed to map image definition because image definition is nil")
	}

	osType, err := mapOsType(imageDefinition.OsType)
	if err != nil {
		return nil, fmt.Errorf("failed to map ostype: %w", err)
	}

	architecture, err := mapArchitecture(imageDefinition.Architecture)
	if err != nil {
		return nil, fmt.Errorf("failed to map architecture: %w", err)
	}

	var latestImageVersionSize int32 = 0
	if imageVersion != nil {
		latestImageVersionSize = utils.FromPtr(imageVersion.SizeGB)
	}

	return &internalapi.ImageDetails{
		Id:           imageDefinition.Id,
		Source:       mapImageSource(imageDefinition.ImageType),
		Name:         imageDefinition.Name,
		OsType:       osType,
		Architecture: architecture,
		SizeGb:       latestImageVersionSize,
	}, nil
}

func mapOsType(osType models.OsType) (sharedapi.OsType, error) {
	switch osType {
	case models.OsType_Linux:
		return sharedapi.OsType_Linux, nil
	case models.OsType_Windows:
		return sharedapi.OsType_Windows, nil
	case models.OsType_MacOS:
		return sharedapi.OsType_MacOS, nil
	default:
		return 0, fmt.Errorf("unknown os type: %s", osType)
	}
}

func mapArchitecture(architecture models.Architecture) (sharedapi.Architecture, error) {
	switch architecture {
	case models.Architecture_X64:
		return sharedapi.Architecture_X64, nil
	case models.Architecture_Arm64:
		return sharedapi.Architecture_Arm64, nil
	default:
		return 0, fmt.Errorf("unknown architecture: %s", architecture)
	}
}

func mapImageSource(imageSource models.ImageType) string {
	switch imageSource {
	case models.ImageType_Curated:
		return ImageSource_Curated
	case models.ImageType_Customer:
		return ImageSource_Customer
	default:
		return ""
	}
}

func mapFunc[T any, P any](collection []*T, mapper func(*T) (*P, error)) ([]*P, error) {
	result := make([]*P, 0, len(collection))

	for _, elem := range collection {
		mappedElement, err := mapper(elem)
		if err != nil {
			return nil, err
		}

		result = append(result, mappedElement)
	}

	return result, nil
}

func filterFunc[T any](collection []T, match func(T) bool) (filtered []T) {
	for _, elem := range collection {
		if match(elem) {
			filtered = append(filtered, elem)
		}
	}

	return filtered
}

func mapImageReference(imageReference *armcompute.ImageReference) *internalapi.ImageReference {
	return &internalapi.ImageReference{
		Id:        *imageReference.ID,
		Offer:     *imageReference.Offer,
		Publisher: *imageReference.Publisher,
		Sku:       *imageReference.SKU,
		Version:   *imageReference.Version,
	}
}
