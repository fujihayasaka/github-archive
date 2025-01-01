package store

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/gen/ent/imagedefinition"
	"github.com/github/hosted-compute-ims/gen/ent/imageversion"
	"github.com/golang/protobuf/ptypes/wrappers"

	"github.com/github/hosted-compute-ims/internal/models"
)

type ImageVersionUpdatePayload struct {
	Enabled    *wrappers.BoolValue
	ResourceId *wrappers.StringValue
	SizeGB     *wrappers.Int32Value
}

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

func (is *ImagesStore) GetImageVersionsSummariesForImageDefinitions(ctx context.Context, imageDefinitionIds []uint64) (map[uint64]*models.ImageVersionsSummary, error) {
	// ent owns the contract
	//
	//nolint:tagliatelle
	var queryResult []struct {
		ImageDefinitionID uint64 `json:"image_definition_id,omitempty"`
		Count             int32
		Sum               int32
	}

	err := is.readEntClient.ImageVersion.Query().
		Where(imageversion.ImageDefinitionIDIn(imageDefinitionIds...)).
		GroupBy(imageversion.FieldImageDefinitionID).
		Aggregate(ent.Count(), ent.Sum(imageversion.FieldSizeGB)).
		Scan(ctx, &queryResult)
	if err != nil {
		return nil, fmt.Errorf("failed to get image versions count and size: %w", err)
	}

	imageVersionMetadatas := make(map[uint64]*models.ImageVersionsSummary)
	if len(queryResult) == 0 {
		return imageVersionMetadatas, nil
	}

	for _, metadata := range queryResult {
		imageVersionMetadatas[metadata.ImageDefinitionID] = &models.ImageVersionsSummary{
			Count:                    metadata.Count,
			TotalImageVersionsSizeGB: metadata.Sum,
		}
	}

	return imageVersionMetadatas, nil
}

func (is *ImagesStore) GetImageVersionsSummary(ctx context.Context, imageDefinitionId uint64) (*models.ImageVersionsSummary, error) {
	imageVersionsMetadata, err := is.GetImageVersionsSummariesForImageDefinitions(ctx, []uint64{imageDefinitionId})
	if err != nil {
		return nil, err
	}

	return imageVersionsMetadata[imageDefinitionId], nil
}

func (is *ImagesStore) GetAllImageVersionsSummary(ctx context.Context, imageType models.ImageType) (*models.ImageVersionsSummary, error) {
	var rawOutput []struct {
		Count, Sum int32
	}

	err := is.readEntClient.ImageVersion.Query().
		Where(
			imageversion.HasImageDefinitionWith(imagedefinition.ImageTypeEQ(imagedefinition.ImageType(imageType))),
		).
		Aggregate(
			ent.Count(),
			ent.Sum(imageversion.FieldSizeGB),
		).
		Scan(ctx, &rawOutput)
	if err != nil {
		return nil, fmt.Errorf("failed to run DB query for image versions summary: %w", err)
	}

	if len(rawOutput) != 1 {
		return nil, fmt.Errorf("unexpected output of db query")
	}

	summary := &models.ImageVersionsSummary{
		Count:                    rawOutput[0].Count,
		TotalImageVersionsSizeGB: rawOutput[0].Sum,
	}

	return summary, nil
}

func (is *ImagesStore) AddImageVersion(ctx context.Context, version *models.ImageVersion) (uint64, error) {
	save, err := is.writeEntClient.ImageVersion.Create().
		SetVersion(version.Version).
		SetImageDefinitionID(version.ImageDefinitionId).
		SetState(imageversion.State(version.State)).
		SetResourceID(version.ResourceId).
		SetEnabled(version.Enabled).
		SetVMGeneration(imageversion.VMGeneration(version.VmGeneration)).
		SetAgentUser(version.AgentUser).
		SetAzurePurchasePlan(version.AzurePurchasePlan).
		SetOsState(imageversion.OsState(version.OsState)).
		Save(ctx)
	if err != nil {
		return 0, fmt.Errorf("failed to save image version: %w", err)
	}

	return save.ID, nil
}

func (is *ImagesStore) UpdateImageVersion(ctx context.Context, id uint64, updatePayload *ImageVersionUpdatePayload) error {
	updateRequest := is.writeEntClient.ImageVersion.UpdateOneID(id)

	if updatePayload.Enabled != nil {
		updateRequest.SetEnabled(updatePayload.Enabled.Value)
	}

	if updatePayload.ResourceId != nil {
		updateRequest.SetResourceID(updatePayload.ResourceId.Value)
	}

	if updatePayload.SizeGB != nil {
		if updatePayload.SizeGB.Value > 0 {
			updateRequest.SetSizeGB(updatePayload.SizeGB.Value)
		} else {
			updateRequest.ClearSizeGB()
		}
	}

	if _, err := updateRequest.Save(ctx); err != nil {
		return err
	}

	return nil
}

func (is *ImagesStore) DeleteImageVersionById(ctx context.Context, id uint64) error {
	err := is.writeEntClient.ImageVersion.DeleteOneID(id).Exec(ctx)
	if err != nil {
		return err
	}

	return nil
}

func (is *ImagesStore) UpdateImageVersionState(ctx context.Context, id uint64, state models.ImageVersionState, stateDetails string) error {
	_, err := is.writeEntClient.ImageVersion.UpdateOneID(id).
		SetState(imageversion.State(state)).
		SetStateDetails(stateDetails).
		Save(ctx)
	if err != nil {
		return err
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

func (is *ImagesStore) GetLatestImageVersionsForImageDefinitions(ctx context.Context, imageDefinitionIds []uint64) (map[uint64]*models.ImageVersion, error) {
	entImageVersions, err := is.readEntClient.ImageVersion.
		Query().
		Where(imageversion.ImageDefinitionIDIn(imageDefinitionIds...)).
		Where(imageversion.StateEQ(imageversion.StateReady)).
		Where(imageversion.EnabledEQ(true)).
		All(ctx)

	if ent.IsNotFound(err) {
		return nil, sql.ErrNoRows
	}

	imageVersionDict := make(map[uint64][]*models.ImageVersion)
	for _, entImageVersion := range entImageVersions {
		imageDefinitionID := entImageVersion.ImageDefinitionID
		imageVersion := ImageVersionFromEnt(entImageVersion)
		imageVersionDict[imageDefinitionID] = append(imageVersionDict[imageDefinitionID], imageVersion)
	}

	latestImageVersions := make(map[uint64]*models.ImageVersion)
	if len(imageVersionDict) == 0 {
		return latestImageVersions, nil
	}

	for imageDefinitionId, imageVersions := range imageVersionDict {
		models.SortImageVersionsByVersion(imageVersions)

		latestImageVersions[imageDefinitionId] = imageVersions[0]
	}

	return latestImageVersions, nil
}
