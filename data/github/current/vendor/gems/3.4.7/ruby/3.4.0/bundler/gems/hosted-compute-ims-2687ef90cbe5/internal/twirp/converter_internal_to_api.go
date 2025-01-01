package twirp

import (
	"fmt"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
)

const (
	ImageSource_Curated     = "Curated"
	ImageSource_Customer    = "Customer"
	ImageSource_Marketplace = "Marketplace"
)

func mapImageVersion(imageVersion *models.ImageVersion) (*imagesapi.ImageVersion, error) {
	if imageVersion == nil {
		return nil, fmt.Errorf("failed to map image version because it is nil")
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
		CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
	}, nil
}

func mapAdminImageVersion(imageVersion *models.ImageVersion) (*adminapi.ImageVersion, error) {
	if imageVersion == nil {
		return nil, fmt.Errorf("failed to map image version because it is nil")
	}

	var sizeGB int32
	if imageVersion.SizeGB != nil {
		sizeGB = *imageVersion.SizeGB
	}

	state, err := mapImageVersionState(imageVersion.State)
	if err != nil {
		return nil, fmt.Errorf("failed to map image version state: %w", err)
	}

	vmGeneration, err := mapVmGeneration(imageVersion.VmGeneration)
	if err != nil {
		return nil, fmt.Errorf("failed to map vm generation: %w", err)
	}

	osState, err := mapOsState(imageVersion.OsState)
	if err != nil {
		return nil, fmt.Errorf("failed to map os state: %w", err)
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
		VmGeneration:      vmGeneration,
		AgentUser:         imageVersion.AgentUser,
		AzurePurchasePlan: imageVersion.AzurePurchasePlan,
		OsState:           osState,
		CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
		UpdatedAt:         updatedAt,
	}, nil
}

func mapImageDefinitionState(state models.ImageDefinitionState) (sharedapi.ImageDefinitionState, error) {
	switch state {
	case models.ImageDefinitionState_Ready:
		return sharedapi.ImageDefinitionState_ImageDefinitionReady, nil
	case models.ImageDefinitionState_Deleting:
		return sharedapi.ImageDefinitionState_ImageDefinitionDeleting, nil
	default:
		return 0, fmt.Errorf("unknown state: %s", state)
	}
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
	case models.ImageVersionState_Generating:
		return sharedapi.ImageVersionState_Generating, nil
	default:
		return 0, fmt.Errorf("unknown image version state: %s", state)
	}
}

func mapImageDefinition(imageDefinition *models.ImageDefinition, latestVersion *models.ImageVersion, versionsSummary *models.ImageVersionsSummary) (*imagesapi.ImageDefinition, error) {
	if imageDefinition == nil {
		return nil, fmt.Errorf("failed to map image definition because it is nil")
	}

	osType, err := mapOsType(imageDefinition.OsType)
	if err != nil {
		return nil, fmt.Errorf("failed to map ostype: %w", err)
	}

	architecture, err := mapArchitecture(imageDefinition.Architecture)
	if err != nil {
		return nil, fmt.Errorf("failed to map architecture: %w", err)
	}

	state, err := mapImageDefinitionState(imageDefinition.State)
	if err != nil {
		return nil, fmt.Errorf("failed to map image definition state: %w", err)
	}

	result := &imagesapi.ImageDefinition{
		Id:                         imageDefinition.Id,
		Name:                       imageDefinition.Name,
		OwnerId:                    imageDefinition.OwnerId,
		OsType:                     osType,
		Architecture:               architecture,
		Enabled:                    imageDefinition.Enabled,
		State:                      state,
		IsImageGenerationSupported: imageDefinition.IsImageGenerationSupported,
	}

	if imageDefinition.RunnerGroupId != nil {
		result.RunnerGroupId = wrapperspb.UInt64(*imageDefinition.RunnerGroupId)
	}

	if latestVersion != nil {
		result.LatestVersion = latestVersion.Version
		if latestVersion.SizeGB != nil {
			result.LatestVersionSizeGb = *latestVersion.SizeGB
		}
	}

	if versionsSummary != nil {
		result.ImageVersionsCount = versionsSummary.Count
		result.TotalImageVersionsSizeGb = versionsSummary.TotalImageVersionsSizeGB
	}

	return result, nil
}

func mapAdminImageDefinition(imageDefinition *models.ImageDefinition, latestVersion *models.ImageVersion, versionsSummary *models.ImageVersionsSummary) (*adminapi.ImageDefinition, error) {
	if imageDefinition == nil {
		return nil, fmt.Errorf("failed to map image definition because it is nil")
	}

	osType, err := mapOsType(imageDefinition.OsType)
	if err != nil {
		return nil, fmt.Errorf("failed to map ostype: %w", err)
	}

	architecture, err := mapArchitecture(imageDefinition.Architecture)
	if err != nil {
		return nil, fmt.Errorf("failed to map architecture: %w", err)
	}

	state, err := mapImageDefinitionState(imageDefinition.State)
	if err != nil {
		return nil, fmt.Errorf("failed to map image definition state: %w", err)
	}

	var updatedAt *timestamppb.Timestamp
	if imageDefinition.UpdatedAt != nil {
		updatedAt = timestamppb.New(*imageDefinition.UpdatedAt)
	}

	var pointsToImageDefinitionId uint64
	if imageDefinition.PointsToImageDefinitionId != nil {
		pointsToImageDefinitionId = *imageDefinition.PointsToImageDefinitionId
	}

	result := &adminapi.ImageDefinition{
		Id:                         imageDefinition.Id,
		Name:                       imageDefinition.Name,
		OwnerId:                    imageDefinition.OwnerId,
		State:                      state,
		OsType:                     osType,
		Architecture:               architecture,
		Enabled:                    imageDefinition.Enabled,
		FeatureFlag:                utils.FromPtr(imageDefinition.FeatureFlag),
		PointsToImageDefinitionId:  pointsToImageDefinitionId,
		CreatedAt:                  timestamppb.New(imageDefinition.CreatedAt),
		UpdatedAt:                  updatedAt,
		IsImageGenerationSupported: imageDefinition.IsImageGenerationSupported,
	}

	if latestVersion != nil {
		result.LatestVersion = latestVersion.Version
		if latestVersion.SizeGB != nil {
			result.LatestVersionSizeGb = *latestVersion.SizeGB
		}
	}

	if versionsSummary != nil {
		result.ImageVersionsCount = versionsSummary.Count
	}

	return result, nil
}

func mapInternalImageDetails(imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion) (*internalapi.ImageDetails, error) {
	if imageDefinition == nil {
		return nil, fmt.Errorf("failed to map image definition because it is nil")
	}

	osType, err := mapOsType(imageDefinition.OsType)
	if err != nil {
		return nil, fmt.Errorf("failed to map ostype: %w", err)
	}

	architecture, err := mapArchitecture(imageDefinition.Architecture)
	if err != nil {
		return nil, fmt.Errorf("failed to map architecture: %w", err)
	}

	var imageVersionSize int32 = 0
	if imageVersion != nil {
		imageVersionSize = utils.FromPtr(imageVersion.SizeGB)
	}

	return &internalapi.ImageDetails{
		Id:           imageDefinition.Id,
		Source:       mapImageSource(imageDefinition.ImageType),
		Name:         imageDefinition.Name,
		OsType:       osType,
		Architecture: architecture,
		SizeGb:       imageVersionSize,
	}, nil
}

func mapInternalImageReference(imageVersion *models.ImageVersion) (*internalapi.ImageReference, error) {
	if imageVersion == nil {
		return nil, fmt.Errorf("failed to map image version because it is nil")
	}

	osState, err := mapOsState(imageVersion.OsState)
	if err != nil {
		return nil, fmt.Errorf("failed to map os state: %w", err)
	}

	return &internalapi.ImageReference{
		ResourceId:        imageVersion.ResourceId,
		ExactImageVersion: imageVersion.Version,
		OsState:           osState,
		AgentUser:         imageVersion.AgentUser,
		AzurePurchasePlan: imageVersion.AzurePurchasePlan,
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

func mapVmGeneration(vmGeneration models.VmGeneration) (sharedapi.VmGeneration, error) {
	switch vmGeneration {
	case models.VmGeneration_Gen1:
		return sharedapi.VmGeneration_Gen1, nil
	case models.VmGeneration_Gen2:
		return sharedapi.VmGeneration_Gen2, nil
	default:
		return 0, fmt.Errorf("unknown vm generation: %s", vmGeneration)
	}
}

func mapOsState(state models.OsState) (sharedapi.OsState, error) {
	switch state {
	case models.OsState_Generalized:
		return sharedapi.OsState_Generalized, nil
	case models.OsState_Specialized:
		return sharedapi.OsState_Specialized, nil
	default:
		return 0, fmt.Errorf("unknown os state: %s", state)
	}
}
