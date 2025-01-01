package store

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/github/go-stats"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store/mysql/testhelper"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/stretchr/testify/suite"
)

type ImageReplicationSuite struct {
	suite.Suite
	dbSuite testhelper.DatabaseSuite

	ctx         context.Context
	imagesStore IImagesStore
}

func TestImageReplicationSuite(t *testing.T) {
	suite.Run(t, new(ImageReplicationSuite))
}

func (s *ImageReplicationSuite) SetupSuite() {
	s.dbSuite.SetupSuite()
	s.ctx = context.Background()

	telemetryProvider, _ := telemetry.NewFromEnv()
	logger := telemetryProvider.Logger.Named("image_repository_replication_test")

	s.imagesStore, _ = NewImagesStoreWithMySQLConnection(s.dbSuite.Config(), logger, stats.NullStatter)
}

func (s *ImageReplicationSuite) SetupTest() {
	tables := []string{
		"image_replication",
	}
	if err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	regionalDataJson, err := json.Marshal(map[string]models.ImageVersionRegionalReplicationData{
		"eastus": {
			VMCount:      2,
			ReplicaCount: 2,
		},
		"westus": {
			VMCount:      3,
			ReplicaCount: 1,
		},
	})
	if err != nil {
		panic(fmt.Sprintf("failed to serialize image replication data: %s", err))
	}

	_, err = s.dbSuite.DB().Write.Exec(fmt.Sprintf(`
		INSERT INTO image_replication (id, image_definition_id, image_version, replication_data)
		VALUES
		(1, 1, '1.0.0', '%s'),
		(3, 1, '1.0.1', '%s'),
		(4, 2, '1.0.0', '%s');
	`, string(regionalDataJson), string(regionalDataJson), string(regionalDataJson)))
	s.Require().NoError(err)
}

func (s *ImageReplicationSuite) Test_GetImageReplicationsByImageIdAndVersion() {
	replicationData, err := s.imagesStore.GetImageReplicationsByImageIdAndVersion(s.ctx, 1, "1.0.0")

	s.Require().NoError(err)

	s.Assert().Equal(2, len(replicationData.RegionReplicationData), "We should have gotten the correct number of replicas back")
	s.Assert().Equal(uint64(1), replicationData.ImageDefinitionId, "The image version should have the correct image definition id")
	s.Assert().Equal("1.0.0", replicationData.ImageVersion, "The image version should have the correct version")

	imageReplica := replicationData.RegionReplicationData["eastus"]
	s.Assert().Equal(int32(2), imageReplica.VMCount, "The image version should have the correct vm count")
	s.Assert().Equal(int32(2), imageReplica.ReplicaCount, "The image version should have the correct replica count")

	imageReplica = replicationData.RegionReplicationData["westus"]
	s.Assert().Equal(int32(3), imageReplica.VMCount, "The image version should have the correct vm count")
	s.Assert().Equal(int32(1), imageReplica.ReplicaCount, "The image version should have the correct replica count")
}

func (s *ImageReplicationSuite) Test_AddImageReplication() {
	err := s.imagesStore.UpdateImageReplication(s.ctx, &models.ImageVersionReplicationData{
		ImageDefinitionId: 1,
		ImageVersion:      "1.0.2",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"eastus": {
				VMCount:      100,
				ReplicaCount: 2,
			},
		},
	})

	s.Require().NoError(err)

	var replicationData *models.ImageVersionReplicationData
	replicationData, err = s.imagesStore.GetImageReplicationsByImageIdAndVersion(s.ctx, 1, "1.0.2")
	s.Require().NoError(err)

	s.Assert().Equal(uint64(1), replicationData.ImageDefinitionId, "The image version should have the correct image definition id")
	s.Assert().Equal("1.0.2", replicationData.ImageVersion, "The image version should have the correct version")

	imageReplica := replicationData.RegionReplicationData["eastus"]
	s.Assert().Equal(int32(100), imageReplica.VMCount, "The image version should have the correct vm count")
	s.Assert().Equal(int32(2), imageReplica.ReplicaCount, "The image version should have the correct replica count")
}

func (s *ImageReplicationSuite) Test_UpdateImageReplication() {
	var replicationData *models.ImageVersionReplicationData
	replicationData, err := s.imagesStore.GetImageReplicationsByImageIdAndVersion(s.ctx, 1, "1.0.1")

	s.Require().NoError(err)

	// Should just clear what's there and replace it with the new data
	err = s.imagesStore.UpdateImageReplication(s.ctx, &models.ImageVersionReplicationData{
		Id:                replicationData.Id,
		ImageDefinitionId: 1,
		ImageVersion:      "1.0.1",
		RegionReplicationData: map[string]models.ImageVersionRegionalReplicationData{
			"westus2": {
				VMCount:      1000,
				ReplicaCount: 4,
			},
		},
	})

	s.Require().NoError(err)

	replicationData, err = s.imagesStore.GetImageReplicationsByImageIdAndVersion(s.ctx, 1, "1.0.1")
	s.Require().NoError(err)

	s.Assert().Equal(uint64(1), replicationData.ImageDefinitionId, "The image version should have the correct image definition id")
	s.Assert().Equal("1.0.1", replicationData.ImageVersion, "The image version should have the correct version")

	imageReplica := replicationData.RegionReplicationData["westus2"]
	s.Assert().Equal(int32(1000), imageReplica.VMCount, "The image version should have the correct vm count")
	s.Assert().Equal(int32(4), imageReplica.ReplicaCount, "The image version should have the correct replica count")
}
