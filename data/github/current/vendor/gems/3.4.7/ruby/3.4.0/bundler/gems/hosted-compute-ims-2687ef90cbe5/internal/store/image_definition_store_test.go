package store

import (
	"context"
	"database/sql"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/store/mysql/testhelper"
	"github.com/github/hosted-compute-ims/internal/utils"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/suite"
)

type ImageDefinitionSuite struct {
	suite.Suite
	dbSuite testhelper.DatabaseSuite

	ctx         context.Context
	imagesStore IImagesStore
}

func TestImageDefinitionSuite(t *testing.T) {
	suite.Run(t, new(ImageDefinitionSuite))
}

func (s *ImageDefinitionSuite) SetupSuite() {
	s.dbSuite.SetupSuite("hosted_compute_ims_test_transitions")
	s.ctx = context.Background()

	s.imagesStore, _ = NewImagesStoreWithMySQLConnection(s.dbSuite.Config())
}

func (s *ImageDefinitionSuite) SetupTest() {
	tables := []string{
		"image_definition",
		"image_version",
	}
	if err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}
}

func (s *ImageDefinitionSuite) Test_GetImageDefinitionById() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, points_to_image_definition_id, feature_flag, runner_group_id, is_image_generation_supported)
		VALUES
		(1, 'github', 'Ubuntu 16.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL, true),
		(5, 'partner', 'Windows Server 2019', 'Customer', 'windows', 'Arm64', 1, 'my-feature-flag', 3, false);
	`)

	s.Require().NoError(err)

	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().NotNil(image)
	s.Assert().Equal(uint64(1), image.Id)
	s.Assert().Equal(models.GithubOwnerId, image.OwnerId)
	s.Assert().Equal("Ubuntu 16.04", image.Name)
	s.Assert().Equal(models.ImageType_Curated, image.ImageType)
	s.Assert().Equal(models.OsType_Linux, image.OsType)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
	s.Assert().Nil(image.PointsToImageDefinitionId)
	s.Assert().Nil(image.FeatureFlag)
	s.Assert().Nil(image.RunnerGroupId)
	s.Assert().True(image.IsImageGenerationSupported)

	image, err = s.imagesStore.GetImageDefinitionById(s.ctx, 5)
	s.Require().NoError(err)
	s.Require().NotNil(image)
	s.Assert().Equal(uint64(5), image.Id)
	s.Assert().Equal(models.PartnerOwnerId, image.OwnerId)
	s.Assert().Equal("Windows Server 2019", image.Name)
	s.Assert().Equal(models.ImageType_Customer, image.ImageType)
	s.Assert().Equal(models.OsType_Windows, image.OsType)
	s.Assert().Equal(models.Architecture_Arm64, image.Architecture)
	if s.Assert().NotNil(image.PointsToImageDefinitionId) {
		s.Assert().Equal(uint64(1), *image.PointsToImageDefinitionId)
	}
	if s.Assert().NotNil(image.FeatureFlag) {
		s.Assert().Equal("my-feature-flag", *image.FeatureFlag)
	}
	if s.Assert().NotNil(image.RunnerGroupId) {
		s.Assert().Equal(uint64(3), *image.RunnerGroupId)
	}
	s.Assert().False(image.IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_ListNImageDefinitions() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, points_to_image_definition_id, feature_flag, runner_group_id)
		VALUES
		(1, 'github', 'Ubuntu 16.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(2, 'github', 'Ubuntu 18.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(3, 'github', 'Ubuntu 20.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(4, 'github', 'Windows Server 2016', 'Curated', 'windows', 'X64', NULL, NULL, NULL),
		(5, 'kx_v30', 'Windows Server 2019', 'Customer', 'windows', 'X64', NULL, NULL, 1),
		(6, 'kx_v30', 'Custom Ubuntu 18.04', 'Customer', 'linux', 'X64', NULL, NULL, 2),
		(7, 'kx_v30', 'Ubuntu 16.04', 'Customer', 'linux', 'X64', NULL, NULL, 3),
		(8, 'Ox_p3', 'Ubuntu 18.04', 'Customer', 'linux', 'X64', NULL, NULL, 4),
		(9, 'github', 'Ubuntu 20.04 (Latest)', 'Curated', 'linux', 'X64', 3, NULL, NULL),
		(10, 'github', 'Windows Server 2016 (Latest)', 'Curated', 'windows', 'X64', 4, NULL, NULL);
	`)
	s.Require().NoError(err)

	owners, err := s.imagesStore.ListAllCustomerImageOwners(s.ctx)
	s.Require().NoError(err)
	s.Require().Len(owners, 2)
	s.Contains(owners, "kx_v30")
	s.Contains(owners, "Ox_p3")
}

func (s *ImageDefinitionSuite) Test_GetImageDefinitionById_NotExists() {
	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, 40)

	s.Assert().Nil(image)
	s.Assert().ErrorIsf(err, sql.ErrNoRows, "expected sql to return no rows error, got %v", err)
}

func (s *ImageDefinitionSuite) Test_ListCuratedImageDefinitions() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, points_to_image_definition_id, feature_flag, runner_group_id)
		VALUES
		(1, 'github', 'Ubuntu 16.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(2, 'github', 'Ubuntu 18.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(3, 'github', 'Ubuntu 20.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(4, 'github', 'Windows Server 2016', 'Curated', 'windows', 'X64', NULL, NULL, NULL),
		(5, 'kx_v30', 'Windows Server 2019', 'Customer', 'windows', 'X64', NULL, NULL, 1),
		(6, 'kx_v30', 'Custom Ubuntu 18.04', 'Customer', 'linux', 'X64', NULL, NULL, 2),
		(7, 'kx_v30', 'Ubuntu 16.04', 'Customer', 'linux', 'X64', NULL, NULL, 3),
		(8, 'Ox_p3', 'Ubuntu 18.04', 'Customer', 'linux', 'X64', NULL, NULL, 4),
		(9, 'github', 'Ubuntu 20.04 (Latest)', 'Curated', 'linux', 'X64', 3, NULL, NULL),
		(10, 'github', 'Windows Server 2016 (Latest)', 'Curated', 'windows', 'X64', 4, NULL, NULL);
	`)
	s.Require().NoError(err)

	images, err := s.imagesStore.ListCuratedImageDefinitions(s.ctx)

	s.Require().NoError(err)
	s.Assert().Len(images, 6)

	for _, i := range images {
		s.Assert().Equal(models.ImageType_Curated, i.ImageType)
		s.Assert().Equal("github", i.OwnerId)
		s.Assert().False(i.IsImageGenerationSupported)
	}
}

func (s *ImageDefinitionSuite) Test_ListCuratedImageDefinitions_NoImages() {
	images, err := s.imagesStore.ListCuratedImageDefinitions(s.ctx)

	s.Require().NoError(err)
	s.Assert().Nil(images)
}

func (s *ImageDefinitionSuite) Test_ListCustomerImageDefinitions() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, points_to_image_definition_id, feature_flag, runner_group_id)
		VALUES
		(1, 'github', 'Ubuntu 16.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(2, 'github', 'Ubuntu 18.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(3, 'github', 'Ubuntu 20.04', 'Curated', 'linux', 'X64', NULL, NULL, NULL),
		(4, 'github', 'Windows Server 2016', 'Curated', 'windows', 'X64', NULL, NULL, NULL),
		(5, 'kx_v30', 'Windows Server 2019', 'Customer', 'windows', 'X64', NULL, NULL, 1),
		(6, 'kx_v30', 'Custom Ubuntu 18.04', 'Customer', 'linux', 'X64', NULL, NULL, 2),
		(7, 'kx_v30', 'Ubuntu 16.04', 'Customer', 'linux', 'X64', NULL, NULL, 3),
		(8, 'Ox_p3', 'Ubuntu 18.04', 'Customer', 'linux', 'X64', NULL, NULL, 4),
		(9, 'github', 'Ubuntu 20.04 (Latest)', 'Curated', 'linux', 'X64', 3, NULL, NULL),
		(10, 'github', 'Windows Server 2016 (Latest)', 'Curated', 'windows', 'X64', 4, NULL, NULL);
	`)
	s.Require().NoError(err)

	var (
		firstOwnerId  = "kx_v30"
		secondOwnerId = "Ox_p3"
	)

	image, err := s.imagesStore.ListCustomerImageDefinitionsByOwner(s.ctx, firstOwnerId)

	s.Require().NoError(err)
	s.Assert().Len(image, 3)

	for _, i := range image {
		s.Assert().Equal(models.ImageType_Customer, i.ImageType)
		s.Assert().Equal(firstOwnerId, i.OwnerId)
		s.Assert().False(i.IsImageGenerationSupported)
	}

	image, err = s.imagesStore.ListCustomerImageDefinitionsByOwner(s.ctx, secondOwnerId)

	s.Require().NoError(err)
	s.Assert().Len(image, 1)

	s.Assert().Equal(models.ImageType_Customer, image[0].ImageType)
	s.Assert().Equal(secondOwnerId, image[0].OwnerId)
	s.Assert().False(image[0].IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_ListCustomerImageDefinitions_NoImages() {
	images, err := s.imagesStore.ListCustomerImageDefinitionsByOwner(s.ctx, "invalid_owner_id")

	s.Require().NoError(err)
	s.Assert().Empty(images)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Curated() {
	model := models.ImageDefinition{
		OwnerId:                    models.GithubOwnerId,
		Name:                       "test",
		OsType:                     models.OsType_Windows,
		ImageType:                  models.ImageType_Curated,
		Architecture:               models.Architecture_X64,
		IsImageGenerationSupported: true,
	}

	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &model)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	// Get the one we just added
	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, insertId)

	s.Require().NoError(err)
	s.Assert().Equal("test", image.Name)
	s.Assert().Equal(models.ImageType_Curated, image.ImageType)
	s.Assert().Equal(models.OsType_Windows, image.OsType)
	s.Assert().Equal(models.GithubOwnerId, image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
	s.Assert().Nil(image.RunnerGroupId)
	s.Assert().True(image.IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Customer_Existing() {
	model := models.ImageDefinition{
		OwnerId:      "kx_v30",
		Name:         "test",
		OsType:       models.OsType_Windows,
		ImageType:    models.ImageType_Customer,
		Architecture: models.Architecture_X64,
	}

	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &model)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	// Get the one we just added
	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, insertId)

	s.Require().NoError(err)
	s.Assert().Equal("test", image.Name)
	s.Assert().Equal(models.ImageType_Customer, image.ImageType)
	s.Assert().Equal(models.OsType_Windows, image.OsType)
	s.Assert().Equal(model.OwnerId, image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
	s.Assert().False(image.IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Customer_NewCustomer() {
	model := models.ImageDefinition{
		OwnerId:      "new customer",
		Name:         "test",
		OsType:       models.OsType_Windows,
		ImageType:    models.ImageType_Customer,
		Architecture: models.Architecture_X64,
	}

	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &model)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	// Get the one we just added
	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, insertId)

	s.Require().NoError(err)
	s.Assert().Equal("test", image.Name)
	s.Assert().Equal(models.ImageType_Customer, image.ImageType)
	s.Assert().Equal(models.OsType_Windows, image.OsType)
	s.Assert().Equal("new customer", image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
	s.Assert().False(image.IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Latest() {
	modelLatestCurated := models.ImageDefinition{
		OwnerId:                    models.GithubOwnerId,
		Name:                       "Ubuntu Latest",
		OsType:                     models.OsType_Linux,
		ImageType:                  models.ImageType_Curated,
		Architecture:               models.Architecture_X64,
		PointsToImageDefinitionId:  utils.ToPtr[uint64](3),
		IsImageGenerationSupported: true,
	}

	// Add a curated latest image definition
	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &modelLatestCurated)
	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, insertId)
	s.Require().NoError(err)
	s.Assert().Equal("Ubuntu Latest", image.Name)
	s.Assert().Equal(models.ImageType_Curated, image.ImageType)
	s.Assert().Equal(models.OsType_Linux, image.OsType)
	s.Assert().Equal(models.GithubOwnerId, image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
	if s.Assert().NotNil(image.PointsToImageDefinitionId) {
		s.Assert().Equal(uint64(3), *image.PointsToImageDefinitionId)
	}
	s.Assert().True(image.IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Curated_NilRunnerGroupId() {
	modelCurated := models.ImageDefinition{
		OwnerId:       models.GithubOwnerId,
		Name:          "test",
		OsType:        models.OsType_Linux,
		ImageType:     models.ImageType_Curated,
		Architecture:  models.Architecture_X64,
		RunnerGroupId: nil,
	}
	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &modelCurated)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, insertId)
	s.Require().NoError(err)
	s.Assert().Equal("test", image.Name)
	s.Assert().Equal(models.ImageType_Curated, image.ImageType)
	s.Assert().Equal(models.OsType_Linux, image.OsType)
	s.Assert().Equal(models.GithubOwnerId, image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
	s.Assert().Nil(image.RunnerGroupId)
	s.Assert().False(image.IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Customer_RunnerGroupId() {
	var runnerGroupId uint64 = 3
	modelCurated := models.ImageDefinition{
		OwnerId:       "kx_v30",
		Name:          "test",
		OsType:        models.OsType_Linux,
		ImageType:     models.ImageType_Customer,
		Architecture:  models.Architecture_X64,
		RunnerGroupId: &runnerGroupId,
	}
	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &modelCurated)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, insertId)
	s.Require().NoError(err)
	s.Assert().Equal("test", image.Name)
	s.Assert().Equal(models.ImageType_Customer, image.ImageType)
	s.Assert().Equal(models.OsType_Linux, image.OsType)
	s.Assert().Equal("kx_v30", image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
	if s.Assert().NotNil(image.RunnerGroupId) {
		s.Assert().Equal(runnerGroupId, *image.RunnerGroupId)
	}
	s.Assert().False(image.IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_Update_Name() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture)
		VALUES (1001, 'github', 'Initial image name', 'Curated', 'Linux', 'X64');
	`)
	s.Require().NoError(err)

	imageDefinitionId := uint64(1001)

	imageDefinition, err := s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal("Initial image name", imageDefinition.Name)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		Name: wrapperspb.String("Initial image name 2"),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal("Initial image name 2", imageDefinition.Name)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_Update_Enabled() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, enabled)
		VALUES (1001, 'github', 'image name', 'Curated', 'Linux', 'X64', true);
	`)
	s.Require().NoError(err)

	imageDefinitionId := uint64(1001)

	imageDefinition, err := s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(true, imageDefinition.Enabled)
	s.Require().Nil(imageDefinition.FeatureFlag)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		Enabled: wrapperspb.Bool(false),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(false, imageDefinition.Enabled)
	s.Require().Nil(imageDefinition.FeatureFlag)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		Enabled: wrapperspb.Bool(true),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(true, imageDefinition.Enabled)
	s.Require().Nil(imageDefinition.FeatureFlag)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_Update_Is_Image_Generation_Supported() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, is_image_generation_supported)
		VALUES (1001, 'github', 'image name', 'Curated', 'Linux', 'X64', true);
	`)
	s.Require().NoError(err)

	imageDefinitionId := uint64(1001)

	imageDefinition, err := s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().True(imageDefinition.IsImageGenerationSupported)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		IsImageGenerationSupported: wrapperspb.Bool(false),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(false, imageDefinition.IsImageGenerationSupported)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		IsImageGenerationSupported: wrapperspb.Bool(true),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(true, imageDefinition.IsImageGenerationSupported)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_Update_State() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, state)
		VALUES (1001, 'github', 'image name', 'Curated', 'Linux', 'X64', 'Ready');
	`)
	s.Require().NoError(err)

	imageDefinitionId := uint64(1001)

	imageDefinition, err := s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(models.ImageDefinitionState_Ready, imageDefinition.State)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		State: utils.ToPtr(models.ImageDefinitionState_Deleting),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(models.ImageDefinitionState_Deleting, imageDefinition.State)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_Update_FeatureFlag() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, enabled, feature_flag)
		VALUES (1001, 'github', 'image name', 'Curated', 'Linux', 'X64', false, NULL);
	`)
	s.Require().NoError(err)

	var (
		imageDefinitionId uint64 = 1001
		featureFlagName          = "test-feature-flag"
	)

	imageDefinition, err := s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(false, imageDefinition.Enabled)
	s.Require().Nil(imageDefinition.FeatureFlag)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		FeatureFlag: wrapperspb.String(featureFlagName),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(false, imageDefinition.Enabled)
	s.Require().NotNil(imageDefinition.FeatureFlag)
	s.Require().Equal(featureFlagName, *imageDefinition.FeatureFlag)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		FeatureFlag: wrapperspb.String(""),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Equal(false, imageDefinition.Enabled)
	s.Require().Nil(imageDefinition.FeatureFlag)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_Update_PointsToImageDefinitionId() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, points_to_image_definition_id)
		VALUES (1001, 'github', 'image name', 'Curated', 'Linux', 'X64', NULL);
	`)
	s.Require().NoError(err)

	var (
		imageDefinitionId       uint64 = 1001
		pointsToImageDefinition uint64 = 2
	)

	imageDefinition, err := s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Nil(imageDefinition.PointsToImageDefinitionId)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		PointsToImageDefinitionId: wrapperspb.UInt64(pointsToImageDefinition),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().NotNil(imageDefinition.PointsToImageDefinitionId)
	s.Require().Equal(pointsToImageDefinition, *imageDefinition.PointsToImageDefinitionId)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		PointsToImageDefinitionId: wrapperspb.UInt64(0),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Assert().Equal(imageDefinitionId, imageDefinition.Id)
	s.Assert().Nil(imageDefinition.PointsToImageDefinitionId)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_Update_RunnerGroupId() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture, runner_group_id)
		VALUES (1001, 'github', 'image name', 'Curated', 'Linux', 'X64', NULL);
	`)
	s.Require().NoError(err)

	var (
		imageDefinitionId uint64 = 1001
		runnerGroupId     uint64 = 2
	)

	imageDefinition, err := s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().Nil(imageDefinition.RunnerGroupId)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		RunnerGroupId: wrapperspb.UInt64(runnerGroupId),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Require().Equal(imageDefinitionId, imageDefinition.Id)
	s.Require().NotNil(imageDefinition.RunnerGroupId)
	s.Require().Equal(runnerGroupId, *imageDefinition.RunnerGroupId)

	err = s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &ImageDefinitionUpdatePayload{
		RunnerGroupId: wrapperspb.UInt64(0),
	})
	s.Require().NoError(err)

	imageDefinition, err = s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)
	s.Require().NoError(err)
	s.Assert().Equal(imageDefinitionId, imageDefinition.Id)
	s.Assert().Nil(imageDefinition.RunnerGroupId)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_DefinitionNotFound() {
	err := s.imagesStore.UpdateImageDefinition(s.ctx, 500, &ImageDefinitionUpdatePayload{})
	s.Assert().ErrorContains(err, "ent: image_definition not found")
}

func (s *ImageDefinitionSuite) Test_DeleteImageDefinition_NoVersions() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture)
		VALUES (1, 'github', 'Ubuntu 16.04', 'Curated', 'linux', 'X64');
	`)
	s.Require().NoError(err)

	err = s.imagesStore.DeleteImageDefinition(s.ctx, 1)
	s.Require().NoError(err)

	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, 1)
	s.Assert().Nil(image)
	s.Assert().ErrorContains(err, "sql: no rows in result set", "Should not be able to get image definition that has been deleted")
}

func (s *ImageDefinitionSuite) Test_DeleteImageDefinition_WithVersion() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, owner_id, name, image_type, os_type, architecture)
		VALUES (2, 'github', 'Ubuntu 16.04', 'Curated', 'linux', 'X64');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, image_definition_id, version, state)
		VALUES
		(1, 2, '1.0.0', 'Ready'),
		(2, 2, '1.0.1', 'Ready');
	`)
	s.Require().NoError(err)

	deleteErr := s.imagesStore.DeleteImageDefinition(s.ctx, 2)
	s.Assert().ErrorContains(deleteErr, "failed to delete image definition, may have associated versions")

	// Assert image still exists
	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, 2)
	s.Assert().NoError(err)
	s.Assert().NotNil(image)
}
