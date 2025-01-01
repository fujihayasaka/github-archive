package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/internal/models"

	"github.com/github/hosted-compute-ims/gen/ent/imagereplication"
)

func (is *ImagesStore) GetImageReplicationsByImageIdAndVersion(ctx context.Context, imageDefinitionId uint64, version string) (*models.ImageVersionReplicationData, error) {
	res, err := is.readEntClient.ImageReplication.Query().Where(
		imagereplication.ImageDefinitionIDEQ(imageDefinitionId),
		imagereplication.ImageVersionEQ(version),
	).Only(ctx)

	if ent.IsNotFound(err) {
		return &models.ImageVersionReplicationData{
			Id:                    0,
			ImageDefinitionId:     imageDefinitionId,
			ImageVersion:          version,
			RegionReplicationData: make(map[string]models.ImageVersionRegionalReplicationData),
		}, nil
	} else if err != nil {
		return nil, fmt.Errorf("sql: unable to get image replication info from db: %w", err)
	}

	var regionalData map[string]models.ImageVersionRegionalReplicationData
	if err := json.Unmarshal([]byte(res.ReplicationData), &regionalData); err != nil {
		return nil, fmt.Errorf("failed to deserialize regional replication data: %w", err)
	}

	return ImageReplicationFromEnt(res, regionalData), nil
}

func (is *ImagesStore) UpdateImageReplication(ctx context.Context, imageReplicationData *models.ImageVersionReplicationData) error {
	regionalDataJson, err := json.Marshal(imageReplicationData.RegionReplicationData)
	if err != nil {
		return fmt.Errorf("failed to serialize image replication data: %w", err)
	}

	if imageReplicationData.Id == 0 {
		_, err := is.writeEntClient.ImageReplication.Create().
			SetImageDefinitionID(imageReplicationData.ImageDefinitionId).
			SetImageVersion(imageReplicationData.ImageVersion).
			SetReplicationData(string(regionalDataJson)).
			Save(ctx)
		if err != nil {
			return fmt.Errorf("failed to create image replication in db: %w", err)
		}
	} else {
		_, err := is.writeEntClient.ImageReplication.Update().
			Where(
				imagereplication.ImageDefinitionIDEQ(imageReplicationData.ImageDefinitionId),
				imagereplication.ImageVersionEQ(imageReplicationData.ImageVersion)).
			SetReplicationData(string(regionalDataJson)).
			Save(ctx)
		if err != nil {
			return fmt.Errorf("failed to update image replication in db: %w", err)
		}
	}

	return nil
}
