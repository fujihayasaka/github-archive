package store

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/gen/ent/imageversion"

	"github.com/github/hosted-compute-ims/internal/models"
)

func (is *ImagesStore) GetImageVersionById(ctx context.Context, id uint64) (*models.ImageVersion, error) {
	entImageVersion, err := is.readEntClient.ImageVersion.Get(ctx, id)
	if ent.IsNotFound(err) {
		return nil, sql.ErrNoRows
	} else if err != nil {
		return nil, fmt.Errorf("sql: unable to get image definition id %w", err)
	}

	return ImageVersionFromEnt(entImageVersion), nil
}

func (is *ImagesStore) GetImageVersionByDefinitionIdAndVersion(ctx context.Context, imageDefinitionId uint64, version string) (*models.ImageVersion, error) {
	entImageVersion, err := is.readEntClient.ImageVersion.Query().Where(
		imageversion.ImageDefinitionIDEQ(imageDefinitionId),
		imageversion.VersionEQ(version),
	).Only(ctx)
	if ent.IsNotFound(err) {
		return nil, sql.ErrNoRows
	} else if err != nil {
		return nil, fmt.Errorf("sql: unable to get image version by image definition id and version: %w", err)
	}

	return ImageVersionFromEnt(entImageVersion), nil
}

func (is *ImagesStore) ListImageVersionsByDefinitionId(ctx context.Context, imageDefinitionId uint64) ([]*models.ImageVersion, error) {
	entImageVersions, err := is.readEntClient.ImageVersion.Query().Where(
		imageversion.ImageDefinitionIDEQ(imageDefinitionId),
	).All(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get image versions: %w", err)
	}

	var modelImageVersions []*models.ImageVersion
	for _, entImageVersion := range entImageVersions {
		modelImageVersions = append(modelImageVersions, ImageVersionFromEnt(entImageVersion))
	}

	return modelImageVersions, nil
}

func (is *ImagesStore) GetImageVersionsCountByDefinitionId(ctx context.Context, imageDefinitionId uint64) (int, error) {
	count, err := is.readEntClient.ImageVersion.Query().
		Where(imageversion.ImageDefinitionIDEQ(imageDefinitionId)).
		Count(ctx)
	if err != nil {
		return 0, fmt.Errorf("failed to get image versions count: %w", err)
	}

	return count, nil
}

func (is *ImagesStore) AddImageVersion(ctx context.Context, version *models.ImageVersion) (uint64, error) {
	save, err := is.writeEntClient.ImageVersion.Create().
		SetVersion(version.Version).
		SetImageDefinitionID(version.ImageDefinitionId).
		SetState(imageversion.State(version.State)).
		SetResourceID(version.ResourceId).
		SetEnabled(version.Enabled).
		Save(ctx)
	if err != nil {
		return 0, fmt.Errorf("failed to save image version: %w", err)
	}

	return save.ID, nil
}

func (is *ImagesStore) UpdateImageVersion(ctx context.Context, id uint64, updateVersion *models.ImageVersionUpdate) (uint64, error) {
	rowsAffected, err := is.writeEntClient.ImageVersion.Update().
		Where(imageversion.IDEQ(id)).
		SetEnabled(updateVersion.Enabled).
		Save(ctx)
	if err != nil {
		return 0, fmt.Errorf("failed to update image version: %w", err)
	}

	if rowsAffected < 1 {
		return 0, fmt.Errorf("failed to update image version state: %w", sql.ErrNoRows)
	}

	return uint64(rowsAffected), nil
}

func (is *ImagesStore) DeleteImageVersionById(ctx context.Context, id uint64) error {
	err := is.writeEntClient.ImageVersion.DeleteOneID(id).Exec(ctx)
	if err != nil {
		return err
	}

	return nil
}

func (is *ImagesStore) UpdateImageVersionState(ctx context.Context, id uint64, state models.ImageVersionState, stateDetails string) error {
	rowsAffected, err := is.writeEntClient.ImageVersion.Update().
		Where(imageversion.IDEQ(id)).
		SetState(imageversion.State(state)).
		SetStateDetails(stateDetails).
		Save(ctx)
	if err != nil {
		return err
	}

	if rowsAffected < 1 {
		return fmt.Errorf("failed to update image version state: %w", sql.ErrNoRows)
	}

	return nil
}

// UpdateImageVersionStateDetailsForState only updates state details of specific state.
// If state is not equal to expected one, it doesn't make sense to update state details.
func (is *ImagesStore) UpdateImageVersionStateDetailsForState(ctx context.Context, id uint64, state models.ImageVersionState, stateDetails string) error {
	rowsAffected, err := is.writeEntClient.ImageVersion.Update().
		Where(imageversion.IDEQ(id), imageversion.StateEQ(imageversion.State(state))).
		SetStateDetails(stateDetails).
		Save(ctx)
	if err != nil {
		return fmt.Errorf("failed to update image version: %w", err)
	}

	if rowsAffected < 1 {
		return fmt.Errorf("failed to update image version state details: %w", sql.ErrNoRows)
	}

	return nil
}

func (is *ImagesStore) UpdateImageVersionSize(ctx context.Context, id uint64, sizeGB int32) error {
	rowsAffected, err := is.writeEntClient.ImageVersion.Update().
		Where(imageversion.IDEQ(id)).
		SetSizeGB(sizeGB).
		Save(ctx)
	if err != nil {
		return fmt.Errorf("failed to update image version size: %w", err)
	}

	if rowsAffected < 1 {
		return fmt.Errorf("failed to update image version size: %w", sql.ErrNoRows)
	}

	return nil
}

func (is *ImagesStore) GetLatestImageVersion(ctx context.Context, imageDefinitionId uint64) (*models.ImageVersion, error) {
	entImageVersions, err := is.readEntClient.ImageVersion.
		Query().
		Where(imageversion.ImageDefinitionIDEQ(imageDefinitionId)).
		Where(imageversion.StateEQ(imageversion.StateReady)).
		Where(imageversion.EnabledEQ(true)).
		All(ctx)

	if ent.IsNotFound(err) {
		return nil, sql.ErrNoRows
	}

	imageVersions := make([]*models.ImageVersion, 0)
	for _, entImageVersion := range entImageVersions {
		imageVersions = append(imageVersions, ImageVersionFromEnt(entImageVersion))
	}

	if len(imageVersions) == 0 {
		return nil, nil
	}

	models.SortImageVersionsByVersion(imageVersions)

	//#nosec G602: false positive
	return imageVersions[0], nil
}
