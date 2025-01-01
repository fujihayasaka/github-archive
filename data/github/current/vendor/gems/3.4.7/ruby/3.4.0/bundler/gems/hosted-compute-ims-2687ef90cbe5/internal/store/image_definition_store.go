package store

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/gen/ent/imagedefinition"
	"github.com/github/hosted-compute-ims/gen/ent/predicate"
	"github.com/golang/protobuf/ptypes/wrappers"

	"github.com/github/hosted-compute-ims/internal/models"
)

type ImageDefinitionUpdatePayload struct {
	Name                       *wrappers.StringValue
	Enabled                    *wrappers.BoolValue
	FeatureFlag                *wrappers.StringValue
	PointsToImageDefinitionId  *wrappers.UInt64Value
	RunnerGroupId              *wrappers.UInt64Value
	State                      *models.ImageDefinitionState
	IsImageGenerationSupported *wrappers.BoolValue
}

func (is *ImagesStore) GetImageDefinitionById(ctx context.Context, id uint64) (*models.ImageDefinition, error) {
	res, err := is.readEntClient.ImageDefinition.Get(ctx, id)

	if ent.IsNotFound(err) {
		return nil, sql.ErrNoRows
	} else if err != nil {
		return nil, fmt.Errorf("sql: unable to get image definition by id: %w", err)
	}

	return ImageDefinitionFromEnt(res), nil
}

func (is *ImagesStore) ListCuratedImageDefinitions(ctx context.Context) ([]*models.ImageDefinition, error) {
	all, err := is.readEntClient.ImageDefinition.
		Query().
		Where(
			imagedefinition.ImageTypeEQ(imagedefinition.ImageType(models.ImageType_Curated)),
		).
		All(ctx)
	if err != nil {
		return nil, err
	}

	var modelsDefinitions []*models.ImageDefinition
	for _, entDefinition := range all {
		modelsDefinitions = append(modelsDefinitions, ImageDefinitionFromEnt(entDefinition))
	}

	return modelsDefinitions, err
}

func (is *ImagesStore) ListAllCustomerImageDefinitions(ctx context.Context) ([]*models.ImageDefinition, error) {
	return is.listCustomerImagesBase(
		ctx,
		[]predicate.ImageDefinition{
			imagedefinition.ImageTypeEQ(
				imagedefinition.ImageType(models.ImageType_Customer),
			),
		},
	)
}

// List all the ownerIds of customer image definitions
func (is *ImagesStore) ListAllCustomerImageOwners(ctx context.Context) ([]string, error) {
	allOwnerIds, err := is.readEntClient.ImageDefinition.
		Query().
		Where(
			imagedefinition.ImageTypeEQ(imagedefinition.ImageType(models.ImageType_Customer)),
		).
		Unique(true).
		Select(imagedefinition.FieldOwnerID).
		Strings(ctx)
	if err != nil {
		return nil, err
	}

	return allOwnerIds, nil
}

func (is *ImagesStore) ListCustomerImageDefinitionsByOwner(ctx context.Context, ownerId string) ([]*models.ImageDefinition, error) {
	return is.listCustomerImagesBase(
		ctx,
		[]predicate.ImageDefinition{
			imagedefinition.OwnerIDEQ(ownerId),
			imagedefinition.ImageTypeEQ(
				imagedefinition.ImageType(models.ImageType_Customer),
			),
		},
	)
}

func (is *ImagesStore) listCustomerImagesBase(ctx context.Context, queryConditions []predicate.ImageDefinition) ([]*models.ImageDefinition, error) {
	all, err := is.readEntClient.ImageDefinition.
		Query().
		Where(
			queryConditions...,
		).
		All(ctx)
	if err != nil {
		return nil, err
	}

	var modelsDefinitions []*models.ImageDefinition
	for _, entDefinition := range all {
		modelsDefinitions = append(modelsDefinitions, ImageDefinitionFromEnt(entDefinition))
	}

	return modelsDefinitions, nil
}

func (is *ImagesStore) GetImageDefinitionsCountByOwnerId(ctx context.Context, ownerId string) (int, error) {
	count, err := is.readEntClient.ImageDefinition.Query().
		Where(
			imagedefinition.OwnerIDEQ(ownerId),
			imagedefinition.ImageTypeEQ(imagedefinition.ImageType(models.ImageType_Customer)),
		).
		Count(ctx)
	if err != nil {
		return 0, fmt.Errorf("failed to get image definitions count: %w", err)
	}

	return count, nil
}

func (is *ImagesStore) AddImageDefinition(ctx context.Context, image *models.ImageDefinition) (uint64, error) {
	savedImageDefinition, err := is.writeEntClient.ImageDefinition.Create().
		SetOwnerID(image.OwnerId).
		SetImageType(imagedefinition.ImageType(image.ImageType)).
		SetName(image.Name).
		SetEnabled(image.Enabled).
		SetOsType(imagedefinition.OsType(image.OsType)).
		SetArchitecture(imagedefinition.Architecture(image.Architecture)).
		SetNillablePointsToImageDefinitionID(image.PointsToImageDefinitionId).
		SetNillableFeatureFlag(image.FeatureFlag).
		SetState(imagedefinition.State(models.ImageDefinitionState_Ready)).
		SetNillableRunnerGroupID(image.RunnerGroupId).
		SetIsImageGenerationSupported(image.IsImageGenerationSupported).
		Save(ctx)
	if err != nil {
		return 0, err
	}

	return savedImageDefinition.ID, nil
}

func (is *ImagesStore) DeleteImageDefinition(ctx context.Context, id uint64) error {
	deletedRows, err := is.writeEntClient.ImageDefinition.
		Delete().
		Where(imagedefinition.IDEQ(id), imagedefinition.Not(imagedefinition.HasImageVersion())).
		Exec(ctx)
	if err != nil {
		return err
	}

	if deletedRows < 1 {
		return fmt.Errorf("failed to delete image definition, may have associated versions, expected 1 row to be deleted")
	}

	return err
}

func (is *ImagesStore) UpdateImageDefinition(ctx context.Context, id uint64, updatePayload *ImageDefinitionUpdatePayload) error {
	updateRequest := is.writeEntClient.ImageDefinition.UpdateOneID(id)

	if updatePayload.Name != nil {
		updateRequest.SetName(updatePayload.Name.Value)
	}

	if updatePayload.Enabled != nil {
		updateRequest.SetEnabled(updatePayload.Enabled.Value)
	}

	if updatePayload.State != nil {
		updateRequest.SetState(imagedefinition.State(*updatePayload.State))
	}

	if updatePayload.FeatureFlag != nil {
		if updatePayload.FeatureFlag.Value == "" {
			updateRequest.ClearFeatureFlag()
		} else {
			updateRequest.SetFeatureFlag(updatePayload.FeatureFlag.Value)
		}
	}

	if updatePayload.PointsToImageDefinitionId != nil {
		if updatePayload.PointsToImageDefinitionId.Value == 0 {
			updateRequest.ClearPointsToImageDefinitionID()
		} else {
			updateRequest.SetPointsToImageDefinitionID(updatePayload.PointsToImageDefinitionId.Value)
		}
	}

	if updatePayload.RunnerGroupId != nil {
		if updatePayload.RunnerGroupId.Value == 0 {
			updateRequest.ClearRunnerGroupID()
		} else {
			updateRequest.SetRunnerGroupID(updatePayload.RunnerGroupId.Value)
		}
	}

	if updatePayload.IsImageGenerationSupported != nil {
		updateRequest.SetIsImageGenerationSupported(updatePayload.IsImageGenerationSupported.Value)
	}

	if _, err := updateRequest.Save(ctx); err != nil {
		return err
	}

	return nil
}

func (is *ImagesStore) CheckImageDefinitionNameAlreadyUsed(ctx context.Context, ownerId string, name string) (bool, error) {
	return is.readEntClient.ImageDefinition.Query().
		Where(
			imagedefinition.OwnerIDEQ(ownerId),
			imagedefinition.NameEQ(name),
		).
		Exist(ctx)
}
