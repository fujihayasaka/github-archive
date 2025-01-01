package twirp

import (
	"testing"
	"time"

	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestInternalToApiConverter_MapImageVersion(t *testing.T) {
	baseImageVersion := models.ImageVersion{
		Id:                  5,
		Version:             "1.0.0",
		ImageDefinitionId:   4,
		State:               models.ImageVersionState_Ready,
		StateDetails:        "details",
		SizeGB:              utils.ToPtr[int32](5),
		ResourceId:          "resource-id",
		Enabled:             true,
		AzureSubscriptionId: nil,
		VmGeneration:        models.VmGeneration_Gen1,
		AgentUser:           "",
		AzurePurchasePlan:   "",
		CreatedAt:           time.Date(2024, time.January, 1, 0, 0, 0, 0, time.Local),
		UpdatedAt:           nil,
	}

	t.Run("base case", func(t *testing.T) {
		mappedVersion, err := mapImageVersion(&baseImageVersion)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(4), mappedVersion.ImageDefinitionId)
			assert.Equal(t, "1.0.0", mappedVersion.Version)
			assert.Equal(t, sharedapi.ImageVersionState_Ready, mappedVersion.State)
			assert.Equal(t, "details", mappedVersion.StateDetails)
			assert.Equal(t, int32(5), mappedVersion.SizeGb)
			assert.Equal(t, timestamppb.New(baseImageVersion.CreatedAt), mappedVersion.CreatedAt)
		}
	})

	t.Run("nil size is zero", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.SizeGB = nil

		mappedVersion, err := mapImageVersion(&imageVersion)
		if assert.NoError(t, err) {
			assert.Equal(t, int32(0), mappedVersion.SizeGb)
		}
	})

	t.Run("unknown state", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.State = models.ImageVersionState("")

		_, err := mapImageVersion(&imageVersion)
		assert.ErrorContains(t, err, "failed to map image version state")
	})

	t.Run("nil image version", func(t *testing.T) {
		_, err := mapImageVersion(nil)
		assert.ErrorContains(t, err, "failed to map image version because it is nil")
	})
}

func TestInternalToApiConverter_MapAdminImageVersion(t *testing.T) {
	baseImageVersion := models.ImageVersion{
		Id:                  5,
		Version:             "1.0.0",
		ImageDefinitionId:   4,
		State:               models.ImageVersionState_Ready,
		StateDetails:        "details",
		SizeGB:              utils.ToPtr[int32](5),
		ResourceId:          "resource-id",
		Enabled:             true,
		AzureSubscriptionId: nil,
		VmGeneration:        models.VmGeneration_Gen2,
		OsState:             models.OsState_Specialized,
		AgentUser:           "custom-user",
		AzurePurchasePlan:   "aa:bb:cc",
		CreatedAt:           time.Date(2024, time.January, 1, 0, 0, 0, 0, time.Local),
		UpdatedAt:           nil,
	}

	t.Run("base case", func(t *testing.T) {
		mappedVersion, err := mapAdminImageVersion(&baseImageVersion)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(5), mappedVersion.Id)
			assert.Equal(t, uint64(4), mappedVersion.ImageDefinitionId)
			assert.Equal(t, "1.0.0", mappedVersion.Version)
			assert.Equal(t, sharedapi.ImageVersionState_Ready, mappedVersion.State)
			assert.Equal(t, "details", mappedVersion.StateDetails)
			assert.Equal(t, int32(5), mappedVersion.SizeGb)
			assert.Equal(t, sharedapi.VmGeneration_Gen2, mappedVersion.VmGeneration)
			assert.Equal(t, sharedapi.OsState_Specialized, mappedVersion.OsState)
			assert.Equal(t, timestamppb.New(baseImageVersion.CreatedAt), mappedVersion.CreatedAt)
			assert.Equal(t, "resource-id", mappedVersion.ResourceId)
			assert.Equal(t, "custom-user", mappedVersion.AgentUser)
			assert.Equal(t, "aa:bb:cc", mappedVersion.AzurePurchasePlan)
		}
	})

	t.Run("nil size", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.SizeGB = nil

		mappedVersion, err := mapAdminImageVersion(&imageVersion)
		if assert.NoError(t, err) {
			assert.Equal(t, int32(0), mappedVersion.SizeGb)
		}
	})

	t.Run("updatedAt", func(t *testing.T) {
		updatedAt := time.Date(2024, time.January, 2, 0, 0, 0, 0, time.Local)
		imageVersion := baseImageVersion
		imageVersion.UpdatedAt = &updatedAt

		mappedVersion, err := mapAdminImageVersion(&imageVersion)
		assert.NoError(t, err)
		assert.Equal(t, timestamppb.New(updatedAt), mappedVersion.UpdatedAt)
	})

	t.Run("unknown state", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.State = models.ImageVersionState("")

		_, err := mapAdminImageVersion(&imageVersion)
		assert.ErrorContains(t, err, "failed to map image version state")
	})

	t.Run("unknown vmGeneration", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.VmGeneration = models.VmGeneration("")

		_, err := mapAdminImageVersion(&imageVersion)
		assert.ErrorContains(t, err, "failed to map vm generation: unknown vm generation")
	})

	t.Run("unknown osState", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.OsState = models.OsState("")

		_, err := mapAdminImageVersion(&imageVersion)
		assert.ErrorContains(t, err, "failed to map os state: unknown os state")
	})

	t.Run("nil image version", func(t *testing.T) {
		_, err := mapAdminImageVersion(nil)
		assert.ErrorContains(t, err, "failed to map image version because it is nil")
	})
}

func TestInternalToApiConverter_MapImageDefinition(t *testing.T) {
	baseImageDefinition := models.ImageDefinition{
		Id:                         3,
		Name:                       "image-1",
		OwnerId:                    "definition-owner",
		ImageType:                  models.ImageType_Curated,
		Enabled:                    true,
		FeatureFlag:                nil,
		OsType:                     models.OsType_Linux,
		Architecture:               models.Architecture_X64,
		PointsToImageDefinitionId:  nil,
		CreatedAt:                  time.Date(2024, time.January, 1, 0, 0, 0, 0, time.Local),
		UpdatedAt:                  nil,
		State:                      models.ImageDefinitionState_Ready,
		RunnerGroupId:              nil,
		IsImageGenerationSupported: true,
	}

	t.Run("base case", func(t *testing.T) {
		mappedDefinition, err := mapImageDefinition(&baseImageDefinition, nil, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(3), mappedDefinition.Id)
			assert.Equal(t, "image-1", mappedDefinition.Name)
			assert.Equal(t, "definition-owner", mappedDefinition.OwnerId)
			assert.Equal(t, sharedapi.OsType_Linux, mappedDefinition.OsType)
			assert.Equal(t, sharedapi.Architecture_X64, mappedDefinition.Architecture)
			assert.Equal(t, true, mappedDefinition.Enabled)
			assert.Equal(t, sharedapi.ImageDefinitionState_ImageDefinitionReady, mappedDefinition.State)
			assert.Equal(t, baseImageDefinition.IsImageGenerationSupported, mappedDefinition.IsImageGenerationSupported)
		}
	})

	t.Run("nil image definition", func(t *testing.T) {
		_, err := mapImageDefinition(nil, nil, nil)
		assert.ErrorContains(t, err, "failed to map image definition because it is nil")
	})

	t.Run("unknown ostype", func(t *testing.T) {
		imageDefinition := baseImageDefinition
		imageDefinition.OsType = models.OsType("")

		_, err := mapImageDefinition(&imageDefinition, nil, nil)
		assert.ErrorContains(t, err, "failed to map ostype")
	})

	t.Run("unknown architecture", func(t *testing.T) {
		imageDefinition := baseImageDefinition
		imageDefinition.Architecture = models.Architecture("")

		_, err := mapImageDefinition(&imageDefinition, nil, nil)
		assert.ErrorContains(t, err, "failed to map architecture")
	})

	t.Run("unknown state", func(t *testing.T) {
		imageDefinition := baseImageDefinition
		imageDefinition.State = models.ImageDefinitionState("")

		_, err := mapImageDefinition(&imageDefinition, nil, nil)
		assert.ErrorContains(t, err, "failed to map image definition state")
	})

	t.Run("with latest image version", func(t *testing.T) {
		latestImageVersionWithoutSize := &models.ImageVersion{Version: "1.0.0", SizeGB: nil}
		latestImageVersionWithSize := &models.ImageVersion{Version: "1.0.0", SizeGB: utils.ToPtr[int32](10)}

		mappedDefinition, err := mapImageDefinition(&baseImageDefinition, latestImageVersionWithoutSize, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, "1.0.0", mappedDefinition.LatestVersion)
			assert.Equal(t, int32(0), mappedDefinition.LatestVersionSizeGb)
		}

		mappedDefinition, err = mapImageDefinition(&baseImageDefinition, latestImageVersionWithSize, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, "1.0.0", mappedDefinition.LatestVersion)
			assert.Equal(t, int32(10), mappedDefinition.LatestVersionSizeGb)
		}
	})

	t.Run("with image versions summary", func(t *testing.T) {
		versionsSummary := &models.ImageVersionsSummary{Count: 10, TotalImageVersionsSizeGB: 100}

		mappedDefinition, err := mapImageDefinition(&baseImageDefinition, nil, versionsSummary)
		if assert.NoError(t, err) {
			assert.Equal(t, int32(10), mappedDefinition.ImageVersionsCount)
			assert.Equal(t, int32(100), mappedDefinition.TotalImageVersionsSizeGb)
		}
	})
}

func TestInternalToApiConverter_MapAdminImageDefinition(t *testing.T) {
	baseImageDefinition := models.ImageDefinition{
		Id:                         3,
		Name:                       "image-1",
		OwnerId:                    "definition-owner",
		ImageType:                  models.ImageType_Curated,
		Enabled:                    true,
		FeatureFlag:                nil,
		OsType:                     models.OsType_Linux,
		Architecture:               models.Architecture_X64,
		PointsToImageDefinitionId:  nil,
		CreatedAt:                  time.Date(2024, time.January, 1, 0, 0, 0, 0, time.Local),
		UpdatedAt:                  nil,
		State:                      models.ImageDefinitionState_Ready,
		RunnerGroupId:              nil,
		IsImageGenerationSupported: true,
	}

	t.Run("base case", func(t *testing.T) {
		mappedDefinition, err := mapAdminImageDefinition(&baseImageDefinition, nil, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(3), mappedDefinition.Id)
			assert.Equal(t, "image-1", mappedDefinition.Name)
			assert.Equal(t, "definition-owner", mappedDefinition.OwnerId)
			assert.Equal(t, sharedapi.OsType_Linux, mappedDefinition.OsType)
			assert.Equal(t, sharedapi.Architecture_X64, mappedDefinition.Architecture)
			assert.Equal(t, true, mappedDefinition.Enabled)
			assert.Equal(t, sharedapi.ImageDefinitionState_ImageDefinitionReady, mappedDefinition.State)
			assert.Equal(t, uint64(0), mappedDefinition.PointsToImageDefinitionId)
			assert.Equal(t, "", mappedDefinition.FeatureFlag)
			assert.Equal(t, timestamppb.New(baseImageDefinition.CreatedAt), mappedDefinition.CreatedAt)
			assert.Equal(t, baseImageDefinition.IsImageGenerationSupported, mappedDefinition.IsImageGenerationSupported)
		}
	})

	t.Run("nil image definition", func(t *testing.T) {
		_, err := mapAdminImageDefinition(nil, nil, nil)
		assert.ErrorContains(t, err, "failed to map image definition because it is nil")
	})

	t.Run("unknown ostype", func(t *testing.T) {
		imageDefinition := baseImageDefinition
		imageDefinition.OsType = models.OsType("")

		_, err := mapAdminImageDefinition(&imageDefinition, nil, nil)
		assert.ErrorContains(t, err, "failed to map ostype")
	})

	t.Run("unknown architecture", func(t *testing.T) {
		imageDefinition := baseImageDefinition
		imageDefinition.Architecture = models.Architecture("")

		_, err := mapAdminImageDefinition(&imageDefinition, nil, nil)
		assert.ErrorContains(t, err, "failed to map architecture")
	})

	t.Run("unknown state", func(t *testing.T) {
		imageDefinition := baseImageDefinition
		imageDefinition.State = models.ImageDefinitionState("")

		_, err := mapAdminImageDefinition(&imageDefinition, nil, nil)
		assert.ErrorContains(t, err, "failed to map image definition state")
	})

	t.Run("updatedAt", func(t *testing.T) {
		updatedAt := time.Date(2024, time.January, 2, 0, 0, 0, 0, time.Local)
		imageDefinition := baseImageDefinition
		imageDefinition.UpdatedAt = &updatedAt

		mappedDefinition, err := mapAdminImageDefinition(&imageDefinition, nil, nil)
		assert.NoError(t, err)
		assert.Equal(t, timestamppb.New(updatedAt), mappedDefinition.UpdatedAt)
	})

	t.Run("pointsToImageDefinitionId", func(t *testing.T) {
		imageDefinition := baseImageDefinition
		imageDefinition.PointsToImageDefinitionId = utils.ToPtr[uint64](3)

		mappedDefinition, err := mapAdminImageDefinition(&imageDefinition, nil, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(3), mappedDefinition.PointsToImageDefinitionId)
		}
	})

	t.Run("featureFlag", func(t *testing.T) {
		imageDefinition := baseImageDefinition
		imageDefinition.FeatureFlag = utils.ToPtr[string]("feature-flag")

		mappedDefinition, err := mapAdminImageDefinition(&imageDefinition, nil, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, "feature-flag", mappedDefinition.FeatureFlag)
		}
	})

	t.Run("with latest image version", func(t *testing.T) {
		latestImageVersionWithoutSize := &models.ImageVersion{Version: "1.0.0", SizeGB: nil}
		latestImageVersionWithSize := &models.ImageVersion{Version: "1.0.0", SizeGB: utils.ToPtr[int32](10)}

		mappedDefinition, err := mapAdminImageDefinition(&baseImageDefinition, latestImageVersionWithoutSize, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, "1.0.0", mappedDefinition.LatestVersion)
			assert.Equal(t, int32(0), mappedDefinition.LatestVersionSizeGb)
		}

		mappedDefinition, err = mapAdminImageDefinition(&baseImageDefinition, latestImageVersionWithSize, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, "1.0.0", mappedDefinition.LatestVersion)
			assert.Equal(t, int32(10), mappedDefinition.LatestVersionSizeGb)
		}
	})

	t.Run("with image versions summary", func(t *testing.T) {
		versionsSummary := &models.ImageVersionsSummary{Count: 10, TotalImageVersionsSizeGB: 100}

		mappedDefinition, err := mapAdminImageDefinition(&baseImageDefinition, nil, versionsSummary)
		if assert.NoError(t, err) {
			assert.Equal(t, int32(10), mappedDefinition.ImageVersionsCount)
		}
	})
}

func TestInternalToApiConverter_MapInternalImageDetails(t *testing.T) {
	baseImageDefinition := models.ImageDefinition{
		Id:                        3,
		Name:                      "image-1",
		OwnerId:                   "definition-owner",
		ImageType:                 models.ImageType_Curated,
		Enabled:                   true,
		FeatureFlag:               nil,
		OsType:                    models.OsType_Linux,
		Architecture:              models.Architecture_X64,
		PointsToImageDefinitionId: nil,
		CreatedAt:                 time.Date(2024, time.January, 1, 0, 0, 0, 0, time.Local),
		UpdatedAt:                 nil,
		State:                     models.ImageDefinitionState_Ready,
	}
	baseImageVersion := models.ImageVersion{
		Id:                  5,
		Version:             "1.0.0",
		ImageDefinitionId:   4,
		State:               models.ImageVersionState_Ready,
		StateDetails:        "details",
		SizeGB:              utils.ToPtr[int32](5),
		ResourceId:          "resource-id",
		Enabled:             true,
		AzureSubscriptionId: nil,
		VmGeneration:        models.VmGeneration_Gen1,
		AgentUser:           "",
		AzurePurchasePlan:   "",
		CreatedAt:           time.Date(2024, time.January, 1, 0, 0, 0, 0, time.Local),
		UpdatedAt:           nil,
	}

	t.Run("base case", func(t *testing.T) {
		mappedInternalDetails, err := mapInternalImageDetails(&baseImageDefinition, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(3), mappedInternalDetails.Id)
			assert.Equal(t, "Curated", mappedInternalDetails.Source)
			assert.Equal(t, "image-1", mappedInternalDetails.Name)
			assert.Equal(t, sharedapi.OsType_Linux, mappedInternalDetails.OsType)
			assert.Equal(t, sharedapi.Architecture_X64, mappedInternalDetails.Architecture)
			assert.Equal(t, int32(0), mappedInternalDetails.SizeGb)
		}
	})

	t.Run("with image version", func(t *testing.T) {
		mappedInternalDetails, err := mapInternalImageDetails(&baseImageDefinition, &baseImageVersion)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(3), mappedInternalDetails.Id)
			assert.Equal(t, "Curated", mappedInternalDetails.Source)
			assert.Equal(t, "image-1", mappedInternalDetails.Name)
			assert.Equal(t, sharedapi.OsType_Linux, mappedInternalDetails.OsType)
			assert.Equal(t, sharedapi.Architecture_X64, mappedInternalDetails.Architecture)
			assert.Equal(t, int32(5), mappedInternalDetails.SizeGb)
		}
	})

	t.Run("nil image definition", func(t *testing.T) {
		_, err := mapInternalImageDetails(nil, nil)
		assert.ErrorContains(t, err, "failed to map image definition because it is nil")
	})
}

func TestInternalToApiConverter_MapImageDefinition_RunnerGroupId(t *testing.T) {
	baseImageDefinition := models.ImageDefinition{
		Id:            3,
		Name:          "image-1",
		OwnerId:       "definition-owner",
		ImageType:     models.ImageType_Customer,
		Enabled:       true,
		OsType:        models.OsType_Linux,
		Architecture:  models.Architecture_X64,
		State:         models.ImageDefinitionState_Ready,
		RunnerGroupId: nil, // RunnerGroupId is nil
	}

	t.Run("RunnerGroupId is nil", func(t *testing.T) {
		mappedDefinition, err := mapImageDefinition(&baseImageDefinition, nil, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(3), mappedDefinition.Id)
			assert.Equal(t, "image-1", mappedDefinition.Name)
			assert.Equal(t, "definition-owner", mappedDefinition.OwnerId)
			assert.Equal(t, sharedapi.OsType_Linux, mappedDefinition.OsType)
			assert.Equal(t, sharedapi.Architecture_X64, mappedDefinition.Architecture)
			assert.Equal(t, true, mappedDefinition.Enabled)
			assert.Equal(t, sharedapi.ImageDefinitionState_ImageDefinitionReady, mappedDefinition.State)
		}
	})

	t.Run("RunnerGroupId is not nil", func(t *testing.T) {
		runnerGroupId := uint64(42)
		imageDefinitionWithRunnerGroupId := baseImageDefinition
		imageDefinitionWithRunnerGroupId.RunnerGroupId = &runnerGroupId

		mappedDefinition, err := mapImageDefinition(&imageDefinitionWithRunnerGroupId, nil, nil)
		if assert.NoError(t, err) {
			assert.Equal(t, uint64(3), mappedDefinition.Id)
			assert.Equal(t, "image-1", mappedDefinition.Name)
			assert.Equal(t, "definition-owner", mappedDefinition.OwnerId)
			assert.Equal(t, sharedapi.OsType_Linux, mappedDefinition.OsType)
			assert.Equal(t, sharedapi.Architecture_X64, mappedDefinition.Architecture)
			assert.Equal(t, true, mappedDefinition.Enabled)
			assert.Equal(t, sharedapi.ImageDefinitionState_ImageDefinitionReady, mappedDefinition.State)
			assert.Equal(t, uint64(42), mappedDefinition.RunnerGroupId.Value)
		}
	})
}

func TestInternalToApiConverter_MapInternalImageReference(t *testing.T) {
	baseImageVersion := models.ImageVersion{
		Id:                  5,
		Version:             "1.2.3",
		ImageDefinitionId:   4,
		State:               models.ImageVersionState_Ready,
		StateDetails:        "details",
		SizeGB:              utils.ToPtr[int32](5),
		ResourceId:          "resource-id",
		Enabled:             true,
		AzureSubscriptionId: nil,
		VmGeneration:        models.VmGeneration_Gen2,
		OsState:             models.OsState_Specialized,
		AgentUser:           "my-user",
		AzurePurchasePlan:   "aa:bb:cc",
		CreatedAt:           time.Date(2024, time.January, 1, 0, 0, 0, 0, time.Local),
		UpdatedAt:           nil,
	}

	t.Run("base case", func(t *testing.T) {
		mappedInternalReference, err := mapInternalImageReference(&baseImageVersion)
		if assert.NoError(t, err) {
			assert.Equal(t, "1.2.3", mappedInternalReference.ExactImageVersion)
			assert.Equal(t, "resource-id", mappedInternalReference.ResourceId)
			assert.Equal(t, "my-user", mappedInternalReference.AgentUser)
			assert.Equal(t, "aa:bb:cc", mappedInternalReference.AzurePurchasePlan)
			assert.Equal(t, sharedapi.OsState_Specialized, mappedInternalReference.OsState)
		}
	})

	t.Run("failed to map os state", func(t *testing.T) {
		imageVersion := baseImageVersion
		imageVersion.OsState = models.OsState("")
		_, err := mapInternalImageReference(&imageVersion)
		assert.ErrorContains(t, err, "failed to map os state: unknown os state")
	})

	t.Run("nil image version", func(t *testing.T) {
		_, err := mapInternalImageReference(nil)
		assert.ErrorContains(t, err, "failed to map image version because it is nil")
	})
}
