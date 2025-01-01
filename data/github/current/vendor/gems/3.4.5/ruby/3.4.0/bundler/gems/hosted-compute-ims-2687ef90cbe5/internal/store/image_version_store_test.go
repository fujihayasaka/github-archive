package store

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/store/mysql/testhelper"
	"google.golang.org/protobuf/types/known/wrapperspb"

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
	s.dbSuite.SetupSuite("hosted_compute_ims_test_transitions")
	s.ctx = context.Background()

	s.imagesStore, _ = NewImagesStoreWithMySQLConnection(s.dbSuite.Config())
}

func (s *ImageVersionSuite) SetupTest() {
	tables := []string{
		"image_definition",
		"image_version",
	}
	if err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}
}

func (s *ImageVersionSuite) Test_GetImageVersion() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id, points_to_image_definition_id)
		VALUES
		(1, 'test-image', 'Curated', 'github', NULL),
		(2, 'test-image latest', 'Curated', 'github', 1);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, size_gb, vm_generation, os_state, resource_id, azure_subscription_id, agent_user, azure_purchase_plan)
		VALUES
		(1, '1.0.1', 1, 'Ready', true, 4, 'Gen1', 'Generalized', 'test-resource-id', NULL, '', ''),
		(2, '1.0.2', 1, 'Ready', false, NULL, 'Gen2', 'Specialized', '', 3, 'agent_user', 'publisher-offer-sku');
	`)
	s.Require().NoError(err)

	imageVersion, err := s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.1")
	s.Require().NoError(err)
	s.Require().NotNil(imageVersion)
	s.Assert().Equal(uint64(1), imageVersion.Id)
	s.Assert().Equal(uint64(1), imageVersion.ImageDefinitionId)
	s.Assert().Equal("1.0.1", imageVersion.Version)
	s.Assert().Equal(models.ImageVersionState_Ready, imageVersion.State)
	s.Assert().Equal(true, imageVersion.Enabled)
	if s.Assert().NotNil(imageVersion.SizeGB) {
		s.Assert().Equal(int32(4), *imageVersion.SizeGB)
	}
	s.Assert().Equal(models.VmGeneration_Gen1, imageVersion.VmGeneration)
	s.Assert().Equal(models.OsState_Generalized, imageVersion.OsState)
	s.Assert().Equal("test-resource-id", imageVersion.ResourceId)
	s.Assert().Nil(imageVersion.AzureSubscriptionId)
	s.Assert().Equal("", imageVersion.AgentUser)
	s.Assert().Equal("", imageVersion.AzurePurchasePlan)

	imageVersion, err = s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.2")
	s.Require().NoError(err)
	s.Require().NotNil(imageVersion)
	s.Assert().Equal(uint64(2), imageVersion.Id)
	s.Assert().Equal(uint64(1), imageVersion.ImageDefinitionId)
	s.Assert().Equal("1.0.2", imageVersion.Version)
	s.Assert().Equal(models.ImageVersionState_Ready, imageVersion.State)
	s.Assert().Equal(false, imageVersion.Enabled)
	s.Assert().Nil(imageVersion.SizeGB)
	s.Assert().Equal(models.VmGeneration_Gen2, imageVersion.VmGeneration)
	s.Assert().Equal(models.OsState_Specialized, imageVersion.OsState)
	s.Assert().Equal("", imageVersion.ResourceId)
	if s.Assert().NotNil(imageVersion.AzureSubscriptionId) {
		s.Assert().Equal(uint64(3), *imageVersion.AzureSubscriptionId)
	}
	s.Assert().Equal("agent_user", imageVersion.AgentUser)
	s.Assert().Equal("publisher-offer-sku", imageVersion.AzurePurchasePlan)
}

func (s *ImageVersionSuite) Test_ListImageVersionsByDefinitionId() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id, points_to_image_definition_id)
		VALUES
		(1, 'test-image', 'Curated', 'github', NULL),
		(2, 'test-image latest', 'Curated', 'github', 1);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, size_gb, vm_generation, os_state, resource_id, azure_subscription_id, agent_user, azure_purchase_plan)
		VALUES
		(1, '1.0.1', 1, 'Ready', true, 4, 'Gen1', 'Generalized', 'test-resource-id', NULL, NULL, NULL),
		(2, '1.0.2', 1, 'Ready', false, NULL, 'Gen2', 'Specialized', '', 3, 'agent_user', 'publisher-offer-sku');
	`)
	s.Require().NoError(err)

	images, err := s.imagesStore.ListImageVersionsByDefinitionId(s.ctx, 1)

	s.Require().NoError(err)

	s.Assert().Len(images, 2, "There should be 4 image versions")

	for _, i := range images {
		s.Assert().Equal(uint64(1), i.ImageDefinitionId, "All image versions should have the same image definition id")
	}
}

func (s *ImageVersionSuite) Test_GetImageVersionsSummariesForImageDefinitions() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES (1, 'test-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, size_gb, vm_generation)
		VALUES
		(1, '1.0.1', 1, 'Ready', true, 4, 'Gen1'),
		(2, '1.0.2', 1, 'Ready', true, 3, 'Gen1'),
		(3, '1.0.3', 1, 'Ready', true, 2, 'Gen1'),
		(4, '1.0.4', 1, 'Ready', true, 1, 'Gen1');
	`)
	s.Require().NoError(err)

	var imageId uint64 = 1
	versionsSummaryMap, err := s.imagesStore.GetImageVersionsSummariesForImageDefinitions(s.ctx, []uint64{imageId})

	s.Require().NoError(err)

	s.Assert().Equal(1, len(versionsSummaryMap), "We should get image versions summary for only one image definition ")
	versionsSummary, ok := versionsSummaryMap[imageId]
	s.Assert().True(ok, "The image versions summary should be found")

	s.Assert().Equal(int32(4), versionsSummary.Count, "The image version count should be correct")
	s.Assert().Equal(int32(10), versionsSummary.TotalImageVersionsSizeGB, "The image version total size should be correct")
}

func (s *ImageVersionSuite) Test_GetImageVersionsSummary() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES (1, 'test-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, size_gb, vm_generation)
		VALUES
		(1, '1.0.1', 1, 'Ready', true, 4, 'Gen1'),
		(2, '1.0.2', 1, 'Ready', true, 3, 'Gen1'),
		(3, '1.0.3', 1, 'Ready', true, 2, 'Gen1'),
		(4, '1.0.4', 1, 'Ready', true, 1, 'Gen1');
	`)
	s.Require().NoError(err)

	versionsSummary, err := s.imagesStore.GetImageVersionsSummary(s.ctx, 1)

	s.Require().NoError(err)

	s.Assert().Equal(int32(4), versionsSummary.Count, "The image version count should be correct")
	s.Assert().Equal(int32(10), versionsSummary.TotalImageVersionsSizeGB, "The image version total size should be correct")
}

func (s *ImageVersionSuite) Test_AddImageVersion() {
	model := models.ImageVersion{
		Version:           "1.0.10",
		ImageDefinitionId: 1,
		State:             models.ImageVersionState_Ready,
		Enabled:           true,
		VmGeneration:      models.VmGeneration_Gen1,
		AgentUser:         "",
		AzurePurchasePlan: "",
		OsState:           models.OsState_Generalized,
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
	s.Assert().Equal(models.VmGeneration_Gen1, imageVersion.VmGeneration, "The image version should have the correct vm generation")
	s.Assert().Equal(models.OsState_Generalized, imageVersion.OsState, "The image version should have the correct os state")
}

func (s *ImageVersionSuite) Test_AddImageVersion_DifferentEnumCombinations() {
	model := models.ImageVersion{
		Version:           "1.0.0",
		ImageDefinitionId: 1,
		State:             models.ImageVersionState_ProvisionFailed,
		Enabled:           true,
		VmGeneration:      models.VmGeneration_Gen2,
		AgentUser:         "",
		AzurePurchasePlan: "",
		OsState:           models.OsState_Specialized,
	}

	addedRow, err := s.imagesStore.AddImageVersion(s.ctx, &model)
	s.Require().NoError(err)
	s.Require().NotZero(addedRow)

	imageVersion, err := s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.0")

	s.Require().NoError(err)
	s.Assert().Equal(uint64(addedRow), imageVersion.Id, "The image version should have the correct id")
	s.Assert().Equal(uint64(1), imageVersion.ImageDefinitionId, "The image version should have the correct image definition id")
	s.Assert().Equal("1.0.0", imageVersion.Version, "The image version should have the correct version")
	s.Assert().Equal(models.ImageVersionState_ProvisionFailed, imageVersion.State, "The image version should have the correct state")
	s.Assert().Equal("", imageVersion.StateDetails, "The image version should have the correct state details")
	s.Assert().Equal(true, imageVersion.Enabled, "The image version should have the correct enabled state")
	s.Assert().Equal((*int32)(nil), imageVersion.SizeGB, "The image version should have the correct size")
	s.Assert().Equal(models.VmGeneration_Gen2, imageVersion.VmGeneration, "The image version should have the correct vm generation")
	s.Assert().Equal(models.OsState_Specialized, imageVersion.OsState, "The image version should have the correct os state")
}

func (s *ImageVersionSuite) Test_AddImageVersion_DefinitionNotExists() {
	sizeGB := int32(10)
	model := &models.ImageVersion{
		Version:           "1.0.10",
		ImageDefinitionId: 1000,
		State:             models.ImageVersionState_Ready,
		Enabled:           true,
		SizeGB:            &sizeGB,
		VmGeneration:      models.VmGeneration_Gen1,
		AgentUser:         "",
		AzurePurchasePlan: "",
		OsState:           models.OsState_Generalized,
	}

	addedRow, err := s.imagesStore.AddImageVersion(s.ctx, model)
	s.Require().NotZero(addedRow)

	s.Assert().NoError(err)
}

func (s *ImageVersionSuite) Test_UpdateImageVersion_Enabled() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, resource_id)
		VALUES (1001, '1.0.0', 501, 'Ready', true, "");
	`)
	s.Require().NoError(err)

	var imageVersionId uint64 = 1001

	existing, err := s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Equal(true, existing.Enabled)

	err = s.imagesStore.UpdateImageVersion(s.ctx, imageVersionId, &ImageVersionUpdatePayload{
		Enabled: wrapperspb.Bool(false),
	})
	s.Require().NoError(err)

	existing, err = s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Equal(false, existing.Enabled)

	err = s.imagesStore.UpdateImageVersion(s.ctx, imageVersionId, &ImageVersionUpdatePayload{
		Enabled: wrapperspb.Bool(true),
	})
	s.Require().NoError(err)

	existing, err = s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Equal(true, existing.Enabled)
}

func (s *ImageVersionSuite) Test_UpdateImageVersion_ResourceId() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, resource_id)
		VALUES (1001, '1.0.0', 501, 'Ready', true, "");
	`)
	s.Require().NoError(err)

	var imageVersionId uint64 = 1001

	existing, err := s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Equal("", existing.ResourceId)

	err = s.imagesStore.UpdateImageVersion(s.ctx, imageVersionId, &ImageVersionUpdatePayload{
		ResourceId: wrapperspb.String("test-resource-id"),
	})
	s.Require().NoError(err)

	existing, err = s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Equal("test-resource-id", existing.ResourceId)

	err = s.imagesStore.UpdateImageVersion(s.ctx, imageVersionId, &ImageVersionUpdatePayload{
		ResourceId: wrapperspb.String(""),
	})
	s.Require().NoError(err)

	existing, err = s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Equal("", existing.ResourceId)
}

func (s *ImageVersionSuite) Test_UpdateImageVersion_SizeGB() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, size_gb)
		VALUES (1001, '1.0.0', 501, 'Ready', true, NULL);
	`)
	s.Require().NoError(err)

	var imageVersionId uint64 = 1001

	existing, err := s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Equal("", existing.ResourceId)

	err = s.imagesStore.UpdateImageVersion(s.ctx, imageVersionId, &ImageVersionUpdatePayload{
		SizeGB: wrapperspb.Int32(30),
	})
	s.Require().NoError(err)

	existing, err = s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().NotNil(existing.SizeGB)
	s.Require().Equal(int32(30), *existing.SizeGB)

	err = s.imagesStore.UpdateImageVersion(s.ctx, imageVersionId, &ImageVersionUpdatePayload{
		SizeGB: wrapperspb.Int32(0),
	})
	s.Require().NoError(err)

	existing, err = s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Nil(existing.SizeGB)

	err = s.imagesStore.UpdateImageVersion(s.ctx, imageVersionId, &ImageVersionUpdatePayload{
		SizeGB: wrapperspb.Int32(-5),
	})
	s.Require().NoError(err)

	existing, err = s.imagesStore.GetImageVersionById(s.ctx, imageVersionId)
	s.Require().NoError(err)
	s.Require().Equal(imageVersionId, existing.Id)
	s.Require().Nil(existing.SizeGB)
}

func (s *ImageVersionSuite) Test_UpdateImageVersion_VersionNotFound() {
	err := s.imagesStore.UpdateImageVersion(s.ctx, 500, &ImageVersionUpdatePayload{})
	s.Assert().ErrorContains(err, "ent: image_version not found")
}

func (s *ImageVersionSuite) Test_UpdateImageVersionState() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES (1, 'test-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, size_gb, vm_generation)
		VALUES
		(3, '1.0.3', 1, 'Ready', true, 2, 'Gen1'),
		(4, '1.0.4', 1, 'Ready', true, 1, 'Gen1');
	`)
	s.Require().NoError(err)

	newStateDetails := "Image Version is just bad"

	err = s.imagesStore.UpdateImageVersionState(s.ctx, 4, models.ImageVersionState_ProvisionFailed, newStateDetails)
	s.Require().NoError(err)

	// Get the one we just updated
	imageVersion, err := s.imagesStore.GetImageVersionByDefinitionIdAndVersion(s.ctx, 1, "1.0.4")
	s.Require().NoError(err)

	// assert that the update was successful
	s.Assert().Equal(models.ImageVersionState_ProvisionFailed, imageVersion.State, "The updated image version should have the new state")
	s.Assert().Equal(newStateDetails, imageVersion.StateDetails, "The updated image version should have the new state details")
}

func (s *ImageVersionSuite) Test_UpdateImageVersionStateDetailsForState() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES (1, 'test-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, size_gb, vm_generation)
		VALUES
		(3, '1.0.3', 1, 'Ready', true, 2, 'Gen1'),
		(4, '1.0.4', 1, 'Ready', true, 1, 'Gen1');
	`)
	s.Require().NoError(err)

	newStateDetails := "Image Version is broken"

	// failed to update image version state details for unexpected state
	err = s.imagesStore.UpdateImageVersionStateDetailsForState(s.ctx, 4, models.ImageVersionState_Deleting, newStateDetails)
	s.Require().ErrorContains(err, "failed to update image version state")

	imageVersion, err := s.imagesStore.GetImageVersionById(s.ctx, 4)
	s.Assert().NoError(err)
	s.Assert().Equal("Ready", string(imageVersion.State), "The updated image version should have the same state")
	s.Assert().Equal("", imageVersion.StateDetails, "The updated image version should have the new state details")

	// update image version state details for expected state
	err = s.imagesStore.UpdateImageVersionStateDetailsForState(s.ctx, 4, "Ready", newStateDetails)
	s.Assert().NoError(err)

	imageVersion, err = s.imagesStore.GetImageVersionById(s.ctx, 4)
	s.Assert().NoError(err)
	s.Assert().Equal("Ready", string(imageVersion.State), "The updated image version should have the same state")
	s.Assert().Equal(newStateDetails, imageVersion.StateDetails, "The updated image version should have the new state details")
}

func (s *ImageVersionSuite) Test_DeleteImageVersion() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES (1, 'test-image', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, enabled, size_gb, vm_generation)
		VALUES (1, '1.0.1', 1, 'Ready', true, 4, 'Gen1');
	`)
	s.Require().NoError(err)

	err = s.imagesStore.DeleteImageVersionById(s.ctx, 1)
	s.Require().NoError(err)

	_, err = s.imagesStore.GetImageVersionById(s.ctx, 1)
	s.Require().ErrorContains(err, "no rows in result set", "The image version should be deleted")
}

func (s *ImageVersionSuite) Test_GetLatestImageVersions() {
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
		(1, '1.0.1', 1, 'Ready', true),
		(2, '1.0.2', 1, 'Ready', true),
		(3, '1.0.3', 1, 'Ready', true),
		(4, '1.0.4', 1, 'Ready', true),
		(5, '4.2.1', 2, 'Ready', true),
		(6, '4.0.2', 2, 'Ready', true),
		(7, '4.4.4', 2, 'Ready', true);
	`)
	s.Require().NoError(err)

	imageDefinitionIds := []uint64{1, 2}

	imageVersions, err := s.imagesStore.GetLatestImageVersionsForImageDefinitions(s.ctx, imageDefinitionIds)

	s.Require().NoError(err)

	s.Assert().Len(imageVersions, 2, "There should be 2 image version.")
	s.Assert().Equal("1.0.4", imageVersions[1].Version, "The first image version should be the latest")
	s.Assert().Equal("4.4.4", imageVersions[2].Version, "The second image version should be the latest")
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
		('4.2.1', 3, 'Ready', true),
		('4.0.2', 3, 'Ready', true),
		('4.4.4', 3, 'Ready', true);
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

	// Call the GetLatestImageVersion function
	latestImageVersions, err := s.imagesStore.GetLatestImageVersionsForImageDefinitions(s.ctx, []uint64{3, 4})
	s.Require().NoError(err)

	// Check if the returned image version is the ones with the latest version
	s.Assert().Equal(2, len(latestImageVersions), "There should be 2 latest image versions")
	s.Assert().Equal("4.5.6", latestImageVersions[3].Version, "The latest image version for image 3 should have the correct version")
	s.Assert().Equal("7.8.9", latestImageVersions[4].Version, "The latest image version for image 4 should have the correct version")
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
		('1.0.0', 8, 'Ready', true),
		('2.0.0', 8, 'Ready', false),
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

func (s *ImageVersionSuite) TestImagesStore_GetAllImageVersionsSummary() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES
		(1, 'image-1', 'Curated', 'github'),
		(2, 'image-2', 'Curated', 'partner'),
		(3, 'image-3', 'Customer', 'O_Fake'),
		(4, 'image-4', 'Customer', 'O_Fake');
	`)
	s.Require().NoError(err)

	// Insert multiple image versions into the database
	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (version, image_definition_id, state, size_gb)
		VALUES
		('1.0.0', 1, 'Ready', 20),
		('2.0.0', 1, 'Ready', 10),
		('3.0.0', 1, 'Ready', NULL),
		('101.50.71', 2, 'Ready', NULL),
		('101.50.72', 2, 'Ready', 200),
		('0.1.0', 3, 'Ready', 1),
		('0.1.0', 4, 'Ready', 3),
		('0.1.1', 4, 'Ready', 5),
		('0.1.2', 4, 'Ready', 8);
	`)
	s.Require().NoError(err)

	curatedResult, err := s.imagesStore.GetAllImageVersionsSummary(s.ctx, models.ImageType_Curated)
	s.Require().NoError(err)
	s.Require().Equal(int32(5), curatedResult.Count)
	s.Require().Equal(int32(230), curatedResult.TotalImageVersionsSizeGB)

	customerResult, err := s.imagesStore.GetAllImageVersionsSummary(s.ctx, models.ImageType_Customer)
	s.Require().NoError(err)
	s.Require().Equal(int32(4), customerResult.Count)
	s.Require().Equal(int32(17), customerResult.TotalImageVersionsSizeGB)
}

func (s *ImageVersionSuite) TestImagesStore_GetAllImageVersionsSummary_EmptyList() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, image_type, owner_id)
		VALUES
		(1, 'image-1', 'Curated', 'github');
	`)
	s.Require().NoError(err)

	// Insert multiple image versions into the database
	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (version, image_definition_id, state, size_gb)
		VALUES ('1.0.0', 1, 'Ready', 20);
	`)
	s.Require().NoError(err)

	curatedResult, err := s.imagesStore.GetAllImageVersionsSummary(s.ctx, models.ImageType_Curated)
	s.Require().NoError(err)
	s.Require().Equal(int32(1), curatedResult.Count)
	s.Require().Equal(int32(20), curatedResult.TotalImageVersionsSizeGB)

	customerResult, err := s.imagesStore.GetAllImageVersionsSummary(s.ctx, models.ImageType_Customer)
	s.Require().NoError(err)
	s.Require().Equal(int32(0), customerResult.Count)
	s.Require().Equal(int32(0), customerResult.TotalImageVersionsSizeGB)
}
