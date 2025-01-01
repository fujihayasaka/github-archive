package store

import (
	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/internal/models"
)

func ImageDefinitionFromEnt(ent *ent.ImageDefinition) *models.ImageDefinition {
	return &models.ImageDefinition{
		Id:                         ent.ID,
		OwnerId:                    ent.OwnerID,
		ImageType:                  models.ImageType(ent.ImageType),
		Name:                       ent.Name,
		Enabled:                    ent.Enabled,
		FeatureFlag:                ent.FeatureFlag,
		OsType:                     models.OsType(ent.OsType),
		Architecture:               models.Architecture(ent.Architecture),
		CreatedAt:                  ent.CreatedAt,
		UpdatedAt:                  &ent.UpdatedAt,
		PointsToImageDefinitionId:  ent.PointsToImageDefinitionID,
		State:                      models.ImageDefinitionState(ent.State),
		RunnerGroupId:              ent.RunnerGroupID,
		IsImageGenerationSupported: ent.IsImageGenerationSupported,
	}
}

func ImageVersionFromEnt(ent *ent.ImageVersion) *models.ImageVersion {
	return &models.ImageVersion{
		Id:                  ent.ID,
		Version:             ent.Version,
		ImageDefinitionId:   ent.ImageDefinitionID,
		State:               models.ImageVersionState(ent.State),
		StateDetails:        ent.StateDetails,
		ResourceId:          ent.ResourceID,
		SizeGB:              ent.SizeGB,
		Enabled:             ent.Enabled,
		CreatedAt:           ent.CreatedAt,
		UpdatedAt:           &ent.UpdatedAt,
		AzureSubscriptionId: ent.AzureSubscriptionID,
		VmGeneration:        models.VmGeneration(ent.VMGeneration),
		AgentUser:           ent.AgentUser,
		AzurePurchasePlan:   ent.AzurePurchasePlan,
		OsState:             models.OsState(ent.OsState),
	}
}

func AzureSubscriptionFromEnt(ent *ent.AzureSubscription) *models.AzureSubscription {
	return &models.AzureSubscription{
		Id:                 ent.ID,
		SubscriptionId:     ent.SubscriptionID,
		ImageType:          models.ImageType(ent.ImageType),
		ResourcesPrefix:    ent.ResourcesPrefix,
		CreatedAt:          ent.CreatedAt,
		UpdatedAt:          &ent.UpdatedAt,
		ImageVersionsCount: ent.ImageVersionsCount,
		ImageVersionsLimit: ent.ImageVersionsLimit,
	}
}

func ImageReplicationFromEnt(ent *ent.ImageReplication, regionReplicationData map[string]models.ImageVersionRegionalReplicationData) *models.ImageVersionReplicationData {
	return &models.ImageVersionReplicationData{
		Id:                    ent.ID,
		ImageDefinitionId:     ent.ImageDefinitionID,
		ImageVersion:          ent.ImageVersion,
		RegionReplicationData: regionReplicationData,
	}
}
