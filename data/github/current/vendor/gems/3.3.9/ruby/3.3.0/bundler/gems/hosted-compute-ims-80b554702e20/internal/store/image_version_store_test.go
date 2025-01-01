package store

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/go-stats"
	"github.com/github/hosted-compute-ims/internal/store/mysql/testhelper"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/suite"
)

type ImageVersionSuite struct {
	suite.Suite
	dbSuite testhelper.DatabaseSuite

	ctx         context.Context
	imagesStore IImagesStore
}

func TestImageVersionSuite(t *testing.T) {
	suite.Run(t, new(ImageVersionSuite))
}

func (s *ImageVersionSuite) SetupSuite() {
	s.dbSuite.SetupSuite()
	s.ctx = context.Background()

	telemetryProvider, _ := telemetry.NewFromEnv()
	logger := telemetryProvider.Logger.Named("image_repository_version_test")

	s.imagesStore, _ = NewImagesStoreWithMySQLConnection(s.dbSuite.Config(), logger, stats.NullStatter)
}

func (s *ImageVersionSuite) SetupTest() {
	tables := []string{
		"image_definition",
		"image_version",
	}
	if err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id, points_to_image_definition_id)
		VALUES
		(1, 'test-image', 'Curated', 'github', NULL),
		(2, 'test-image latest', 'Curated', 'github', 1);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled)
		VALUES
		(1, '1.0.1', 1, 'ready', true),
		(2, '1.0.2', 1, 'ready', true),
		(3, '1.0.3', 1, 'ready', true),
		(4, '1.0.4', 1, 'ready', true);
	`)
	s.Require().NoError(err)
}

func (s *ImageVersionSuite) Test_GetImageVersionsCountByDefinitionId() {
	count, err := s.imagesStore.GetImageVersionsCountByDefinitionId(s.ctx, 1)

	s.Require().NoError(err)

	s.Assert().Equal(4, count, "The image version count should be correct")
}

func (s *ImageVersionSuite) Test_GetImageVersionForCurated() {
	imageVersion, err := s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.1")

	s.Require().NoError(err)

	s.Assert().Equal(uint64(1), imageVersion.Id, "The image version should have the correct id")
	s.Assert().Equal(uint64(1), imageVersion.ImageDefinitionId, "The image version should have the correct image definition id")
	s.Assert().Equal("1.0.1", imageVersion.Version, "The image version should have the correct version")
	s.Assert().Equal(models.ImageVersionState_Ready, imageVersion.State, "The image version should have the correct state")
	s.Assert().Equal(true, imageVersion.Enabled, "The image version should have the correct enabled state")
	s.Assert().Equal((*int32)(nil), imageVersion.SizeGB, "The image version should have the correct size")
}

func (s *ImageVersionSuite) Test_AddImageVersion() {
	model := models.ImageVersion{
		Version:           "1.0.10",
		ImageDefinitionId: 1,
		State:             models.ImageVersionState_Ready,
		Enabled:           true,
	}

	addedRow, err := s.imagesStore.AddImageVersion(s.ctx, &model)

	s.Require().NoError(err)
	s.Require().NotZero(addedRow)

	// Get the one we just added
	imageVersion, err := s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.10")

	s.Require().NoError(err)

	s.Assert().Equal(uint64(addedRow), imageVersion.Id, "The image version should have the correct id")
	s.Assert().Equal(uint64(1), imageVersion.ImageDefinitionId, "The image version should have the correct image definition id")
	s.Assert().Equal("1.0.10", imageVersion.Version, "The image version should have the correct version")
	s.Assert().Equal(models.ImageVersionState_Ready, imageVersion.State, "The image version should have the correct state")
	s.Assert().Equal("", imageVersion.StateDetails, "The image version should have the correct state details")
	s.Assert().Equal(true, imageVersion.Enabled, "The image version should have the correct enabled state")
	s.Assert().Equal((*int32)(nil), imageVersion.SizeGB, "The image version should have the correct size")
}

func (s *ImageVersionSuite) Test_AddImageVersion_DefinitionNotExists() {
	sizeGB := int32(10)
	model := models.ImageVersion{
		Version:           "1.0.10",
		ImageDefinitionId: 1000,
		State:             models.ImageVersionState_Ready,
		Enabled:           true,
		SizeGB:            &sizeGB,
	}

	addedRow, err := s.imagesStore.AddImageVersion(s.ctx, &model)
	s.Require().NotZero(addedRow)

	s.Assert().NoError(err)
}

func (s *ImageVersionSuite) Test_AddImageVersion_ToLatest() {
	sizeGB := int32(10)
	model := models.ImageVersion{
		Version:           "1.0.10",
		ImageDefinitionId: 2, // image definition id of latest record
		State:             models.ImageVersionState_Ready,
		Enabled:           true,
		SizeGB:            &sizeGB,
	}

	addedRow, err := s.imagesStore.AddImageVersion(s.ctx, &model)
	s.Require().NotZero(addedRow)

	s.Assert().NoError(err)
}

func (s *ImageVersionSuite) Test_ListImageVersionsByDefinitionId() {
	images, err := s.imagesStore.ListImageVersionsByDefinitionId(s.ctx, 1)

	s.Require().NoError(err)

	s.Assert().Len(images, 4, "There should be 4 image versions")

	for _, i := range images {
		s.Assert().Equal(uint64(1), i.ImageDefinitionId, "All image versions should have the same image definition id")
	}
}

func (s *ImageVersionSuite) Test_UpdateImageVersion() {
	existing, err := s.imagesStore.GetImageVersionById(s.ctx, 4)
	s.Require().NoError(err)

	toUpdate := &models.ImageVersionUpdate{
		Enabled: false,
	}

	affectedRow, err := s.imagesStore.UpdateImageVersion(s.ctx, existing.Id, toUpdate)

	s.Require().NoError(err)
	s.Require().NotZero(affectedRow)

	// Get the one we just updated
	imageVersion, err := s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.4")
	s.Require().NoError(err)

	// assert that the update was successful
	s.Assert().NotNil(imageVersion.UpdatedAt, "The updated image version should have an updated at timestamp")
	s.Assert().Equal(existing.State, imageVersion.State, "State should be unchanged")
	s.Assert().Equal(existing.StateDetails, imageVersion.StateDetails, "State details should be unchanged")
	s.Assert().Equal(existing.Version, imageVersion.Version, "Version should be unchanged")
	s.Assert().Equal(existing.ImageDefinitionId, imageVersion.ImageDefinitionId, "Image definition id should be unchanged")
	s.Assert().Equal(toUpdate.Enabled, imageVersion.Enabled, "The updated image version should have the new enabled state")
}

func (s *ImageVersionSuite) Test_UpdateImageVersionState() {
	newStateDetails := "Image Version is just bad"

	err := s.imagesStore.UpdateImageVersionState(s.ctx, 4, models.ImageVersionState_ProvisionFailed, newStateDetails)

	s.Require().NoError(err)

	// Get the one we just updated
	imageVersion, err := s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.4")
	s.Require().NoError(err)

	// assert that the update was successful
	s.Assert().Equal(models.ImageVersionState_ProvisionFailed, imageVersion.State, "The updated image version should have the new state")
	s.Assert().Equal(newStateDetails, imageVersion.StateDetails, "The updated image version should have the new state details")
}

func (s *ImageVersionSuite) Test_UpdateImageVersionStateDetailsForState() {
	newStateDetails := "Image Version is broken"

	// failed to update image version state details for unexpected state
	err := s.imagesStore.UpdateImageVersionStateDetailsForState(s.ctx, 4, models.ImageVersionState_Deleting, newStateDetails)
	s.Assert().ErrorContains(err, "failed to update image version state")

	imageVersion, err := s.imagesStore.GetImageVersionById(s.ctx, 4)
	s.Assert().NoError(err)
	s.Assert().Equal("Ready", string(imageVersion.State), "The updated image version should have the same state")
	s.Assert().Equal("", imageVersion.StateDetails, "The updated image version should have the new state details")

	// update image version state details for expected state
	err = s.imagesStore.UpdateImageVersionStateDetailsForState(s.ctx, 4, "ready", newStateDetails)
	s.Assert().NoError(err)

	imageVersion, err = s.imagesStore.GetImageVersionById(s.ctx, 4)
	s.Assert().NoError(err)
	s.Assert().Equal("Ready", string(imageVersion.State), "The updated image version should have the same state")
	s.Assert().Equal(newStateDetails, imageVersion.StateDetails, "The updated image version should have the new state details")
}

func (s *ImageVersionSuite) Test_UpdateImageVersionSize() {
	newSize := int32(10)

	err := s.imagesStore.UpdateImageVersionSize(s.ctx, 4, newSize)

	s.Require().NoError(err)

	// Get the one we just updated
	imageVersion, err := s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.4")
	s.Require().NoError(err)

	// assert that the update was successful
	s.Assert().Equal(&newSize, imageVersion.SizeGB, "The updated image version should have the new size")
}

func (s *ImageVersionSuite) Test_DeleteImageVersion() {
	err := s.imagesStore.DeleteImageVersionById(s.ctx, 1)

	s.Require().NoError(err)
}

func (s *ImageVersionSuite) TestImagesStore_GetLatestImageVersion() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES
		(3, 'test-latest-version-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	// Insert multiple image versions into the database
	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (version, image_definition_id, state, enabled)
		VALUES
		('4.2.1', 3, 'ready', true),
		('4.0.2', 3, 'ready', true),
		('4.4.4', 3, 'ready', true);
	`)
	s.Require().NoError(err)

	// Call the GetLatestImageVersion function
	latestImageVersion, err := s.imagesStore.GetLatestImageVersion(s.ctx, 3)
	s.Require().NoError(err)

	// Check if the returned image version is the one with the latest version
	s.Assert().Equal("4.4.4", latestImageVersion.Version, "The latest image version should have the correct version")
}

func (s *ImageVersionSuite) TestImagesStore_GetLatestImageVersionCrossImageDefinitions() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES
		(3, 'cross-test-latest-version-image-1', 'Curated', 'github'),
		(4, 'cross-test-latest-version-image-2', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	// Insert multiple image versions into the database
	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (version, image_definition_id, state, enabled)
		VALUES
		('1.2.3', 3, 'ready', true),
		('4.5.6', 3, 'ready', true),
		('7.8.9', 4, 'ready', true);
	`)
	s.Require().NoError(err)

	// Call the GetLatestImageVersion function
	latestImageVersion, err := s.imagesStore.GetLatestImageVersion(s.ctx, 3)
	s.Require().NoError(err)

	// Check if the returned image version is the one with the latest version
	s.Assert().Equal("4.5.6", latestImageVersion.Version, "The latest image version should have the correct version")
}

func (s *ImageVersionSuite) TestImagesStore_GetLatestImageVersionSingleVersion() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES
		(5, 'test-single-latest-version-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	// Insert multiple image versions into the database
	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (version, image_definition_id, state, enabled)
		VALUES
		('1.2.3', 5, 'ready', true);
	`)
	s.Require().NoError(err)

	// Call the GetLatestImageVersion function
	latestImageVersion, err := s.imagesStore.GetLatestImageVersion(s.ctx, 5)
	s.Require().NoError(err)

	// Check if the returned image version is the one with the latest version
	s.Assert().Equal("1.2.3", latestImageVersion.Version, "The latest image version should have the correct version")
}

func (s *ImageVersionSuite) TestImagesStore_GetLatestImageVersionIgnoreDisabledAndNotReady() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES
		(8, 'test-single-latest-version-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	// Insert multiple image versions into the database
	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (version, image_definition_id, state, enabled)
		VALUES
		('1.0.0', 8, 'ready', true),
		('2.0.0', 8, 'ready', false),
		('3.0.0', 8, 'provisioning', true);
	`)
	s.Require().NoError(err)

	// Call the GetLatestImageVersion function
	latestImageVersion, err := s.imagesStore.GetLatestImageVersion(s.ctx, 8)
	s.Require().NoError(err)

	// Check if the returned image version is the one with the latest version
	s.Assert().Equal("1.0.0", latestImageVersion.Version, "The latest image version should have the correct version")
}

func (s *ImageVersionSuite) TestImagesStore_GetLatestImageNoImageVersions() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES
		(6, 'test-single-latest-version-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	// Call the GetLatestImageVersion function
	latestImageVersion, err := s.imagesStore.GetLatestImageVersion(s.ctx, 6)
	s.Require().NoError(err)
	s.Require().Nil(latestImageVersion)
}
