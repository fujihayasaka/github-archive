package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/gen/ent/imagedefinition"

	"github.com/github/hosted-compute-ims/internal/models"
)

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

func (is *ImagesStore) ListCustomerImageDefinitions(ctx context.Context, ownerId string) ([]*models.ImageDefinition, error) {
	all, err := is.readEntClient.ImageDefinition.
		Query().
		Where(
			imagedefinition.OwnerIDEQ(ownerId),
			imagedefinition.ImageTypeEQ(imagedefinition.ImageType(models.ImageType_Customer)),
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

func (is *ImagesStore) UpdateImageDefinition(ctx context.Context, id uint64, updateDefinition *models.ImageDefinitionUpdate) (uint64, error) {
	updateCount, err := is.writeEntClient.ImageDefinition.Update().
		Where(imagedefinition.IDEQ(id)).
		SetName(updateDefinition.Name).
		SetEnabled(updateDefinition.Enabled).
		ClearFeatureFlag().
		SetNillableFeatureFlag(updateDefinition.FeatureFlag).
		SetNillablePointsToImageDefinitionID(updateDefinition.PointsToImageDefinitionId).
		Save(ctx)
	if err != nil {
		return 0, err
	}

	if updateCount < 1 {
		return 0, errors.New("failed to update image definition, may not exist")
	}

	return uint64(updateCount), err
}
