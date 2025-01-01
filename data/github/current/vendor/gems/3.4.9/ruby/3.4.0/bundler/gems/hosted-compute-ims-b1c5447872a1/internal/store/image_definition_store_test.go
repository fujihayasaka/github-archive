package store

import (
	"context"
	"database/sql"
	"fmt"
	"testing"

	"github.com/github/go-stats"
	"github.com/github/hosted-compute-ims/internal/store/mysql/testhelper"
	"github.com/github/hosted-compute-ims/internal/utils"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/suite"
)

const (
	ownerIdKx     = "kx_v30"
	ownerIdOx     = "Ox_p3"
	githubOwnerId = "github"
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
	s.dbSuite.SetupSuite()
	s.ctx = context.Background()

	telemetryProvider, _ := telemetry.NewFromEnv()
	logger := telemetryProvider.Logger.Named("image_repository_definition_test")

	s.imagesStore, _ = NewImagesStoreWithMySQLConnection(s.dbSuite.Config(), logger, stats.NullStatter)
}

func (s *ImageDefinitionSuite) SetupTest() {
	tables := []string{
		"image_definition",
		"image_version",
	}
	if err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (
			id,
			owner_id,
			name,
			image_type,
			os_type,
			architecture,
			points_to_image_definition_id,
			feature_flag
		)
		VALUES
		(1, 'github', 'Ubuntu 16.04', 'Curated', 'linux', 'X64', NULL, NULL),
		(2, 'github', 'Ubuntu 18.04', 'Curated', 'linux', 'X64', NULL, NULL),
		(3, 'github', 'Ubuntu 20.04', 'Curated', 'linux', 'X64', NULL, NULL),
		(4, 'github', 'Windows Server 2016', 'Curated', 'windows', 'X64', NULL, NULL),
		(5, 'kx_v30', 'Windows Server 2019', 'Customer', 'windows', 'X64', NULL, NULL),
		(6, 'kx_v30', 'Custom Ubuntu 18.04', 'Customer', 'linux', 'X64', NULL, NULL),
		(7, 'kx_v30', 'Ubuntu 16.04', 'Customer', 'linux', 'X64', NULL, NULL),
		(8, 'Ox_p3', 'Ubuntu 18.04', 'Customer', 'linux', 'X64', NULL, NULL),
		(9, 'github', 'Ubuntu 20.04 (Latest)', 'Curated', 'linux', 'X64', 3, NULL),
		(10, 'github', 'Windows Server 2016 (Latest)', 'Curated', 'windows', 'X64', 4, NULL);
	`)

	s.Require().NoError(err)
}

func (s *ImageDefinitionSuite) Test_GetImageDefinitionById() {
	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, 1)

	s.Require().NoError(err)

	s.Assert().Equal("Ubuntu 16.04", image.Name)
	s.Assert().Equal(models.ImageType_Curated, image.ImageType)
	s.Assert().Equal(models.OsType_Linux, image.OsType)
	s.Assert().Equal("github", image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)

	image, err = s.imagesStore.GetImageDefinitionById(s.ctx, 5)

	s.Require().NoError(err)

	s.Assert().Equal("Windows Server 2019", image.Name)
	s.Assert().Equal(models.ImageType_Customer, image.ImageType)
	s.Assert().Equal(models.OsType_Windows, image.OsType)
	s.Assert().Equal("kx_v30", image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
}

func (s *ImageDefinitionSuite) Test_GetImageDefinitionById_NotExists() {
	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, 40)

	s.Assert().Nil(image)
	s.Assert().ErrorIsf(err, sql.ErrNoRows, "expected sql to return no rows error, got %v", err)
}

func (s *ImageDefinitionSuite) Test_ListCuratedImageDefinitions() {
	images, err := s.imagesStore.ListCuratedImageDefinitions(s.ctx)

	s.Require().NoError(err)
	s.Assert().Len(images, 6)

	for _, i := range images {
		s.Assert().Equal(models.ImageType_Curated, i.ImageType)
		s.Assert().Equal("github", i.OwnerId)
	}
}

func (s *ImageDefinitionSuite) Test_ListCuratedImageDefinitions_NoneExist() {
	tables := []string{
		"image_definition",
		"image_version",
	}
	if err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	images, err := s.imagesStore.ListCuratedImageDefinitions(s.ctx)

	s.Require().NoError(err)
	s.Assert().Nil(images)
}

func (s *ImageDefinitionSuite) Test_ListCustomerImageDefinitions() {
	image, err := s.imagesStore.ListCustomerImageDefinitions(s.ctx, ownerIdKx)

	s.Require().NoError(err)
	s.Assert().Len(image, 3)

	for _, i := range image {
		s.Assert().Equal(models.ImageType_Customer, i.ImageType)
		s.Assert().Equal(ownerIdKx, i.OwnerId)
	}

	image, err = s.imagesStore.ListCustomerImageDefinitions(s.ctx, ownerIdOx)

	s.Require().NoError(err)
	s.Assert().Len(image, 1)

	s.Assert().Equal(models.ImageType_Customer, image[0].ImageType)
	s.Assert().Equal(ownerIdOx, image[0].OwnerId)
}

func (s *ImageDefinitionSuite) Test_ListCustomerImageDefinitions_NoneExist() {
	images, err := s.imagesStore.ListCustomerImageDefinitions(s.ctx, "invalid_owner_id")

	s.Require().NoError(err)
	s.Assert().Nil(images)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Curated() {
	model := models.ImageDefinition{
		OwnerId:      githubOwnerId,
		Name:         "test",
		OsType:       models.OsType_Windows,
		ImageType:    models.ImageType_Curated,
		Architecture: models.Architecture_X64,
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
	s.Assert().Equal(githubOwnerId, image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
	s.Assert().Nil(image.AzureSubscriptionId)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Customer_Existing() {
	model := models.ImageDefinition{
		OwnerId:      ownerIdKx,
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
	s.Assert().Equal(ownerIdKx, image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)
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
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Curated_FailsUniqueKeyConstraint() {
	model := models.ImageDefinition{
		OwnerId:      githubOwnerId,
		Name:         "test",
		OsType:       models.OsType_Windows,
		ImageType:    models.ImageType_Curated,
		Architecture: models.Architecture_X64,
	}

	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &model)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	// Attempt to add it again...
	insertId, err = s.imagesStore.AddImageDefinition(s.ctx, &model)
	s.Assert().Zero(insertId)
	// Expect we fail on a unique key constraint
	s.Assert().ErrorContainsf(err, "Duplicate entry 'test-Curated-github' for key 'image_definition.by_name_image_type'", "Expected error of type Duplicate entry, got %T", err)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Customer_FailsUniqueKeyConstraint() {
	model := models.ImageDefinition{
		OwnerId:      ownerIdKx,
		Name:         "test",
		OsType:       models.OsType_Windows,
		ImageType:    models.ImageType_Customer,
		Architecture: models.Architecture_X64,
	}

	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &model)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	// Attempt to add it again...
	insertId, err = s.imagesStore.AddImageDefinition(s.ctx, &model)
	s.Assert().Zero(insertId)
	// Expect we fail on a unique key constraint
	s.Assert().ErrorContainsf(err, "Duplicate entry 'test-Customer-kx_v30' for key 'image_definition.by_name_image_type'", "Expected error of type Duplicate entry, got %T", err)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_CustomerAndCurated_SameName_PassesUniqueKeyConstraint() {
	modelCustomer := models.ImageDefinition{
		OwnerId:             ownerIdKx,
		Name:                "test",
		OsType:              models.OsType_Windows,
		ImageType:           models.ImageType_Customer,
		Architecture:        models.Architecture_X64,
		AzureSubscriptionId: nil,
	}

	// Add a customer image definition
	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &modelCustomer)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)

	modelCurated := &modelCustomer
	modelCurated.ImageType = models.ImageType_Curated
	modelCurated.OwnerId = githubOwnerId

	// Add a curated image definition with the same name
	insertId, err = s.imagesStore.AddImageDefinition(s.ctx, modelCurated)
	s.Require().NoError(err)
	s.Require().NotZero(insertId)
}

func (s *ImageDefinitionSuite) Test_AddImageDefinition_Latest() {
	modelLatestCurated := models.ImageDefinition{
		OwnerId:                   "github",
		Name:                      "Ubuntu Latest",
		OsType:                    models.OsType_Linux,
		ImageType:                 models.ImageType_Curated,
		Architecture:              models.Architecture_X64,
		PointsToImageDefinitionId: utils.ToPtr(uint64(3)),
	}

	// Add a curated latest image definition
	insertId, err := s.imagesStore.AddImageDefinition(s.ctx, &modelLatestCurated)

	s.Require().NoError(err)
	s.Require().NotZero(insertId)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_Existing() {
	var imageDefinitionId uint64 = 1

	existing, err := s.imagesStore.GetImageDefinitionById(s.ctx, imageDefinitionId)

	s.Require().NoError(err)
	s.Assert().Equal(imageDefinitionId, existing.Id)
	s.Assert().NotNil(existing.CreatedAt)
	s.Assert().NotNil(existing.UpdatedAt)

	toUpdate := models.ImageDefinitionUpdate{
		Enabled: false,
		Name:    "New name",
	}

	updatedRow, err := s.imagesStore.UpdateImageDefinition(s.ctx, imageDefinitionId, &toUpdate)

	s.Require().NoError(err)
	s.Require().NotZero(updatedRow)

	// Assert we return the correct Id
	s.Assert().EqualValues(updatedRow, imageDefinitionId)

	// Get the one we just updated
	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, updatedRow)

	s.Require().NoError(err)

	// Assert none of these fields changes
	s.Assert().Equal(models.ImageType_Curated, image.ImageType)
	s.Assert().Equal(models.OsType_Linux, image.OsType)
	s.Assert().Equal("github", image.OwnerId)
	s.Assert().Equal(models.Architecture_X64, image.Architecture)

	// Assert this changes
	s.Assert().False(image.Enabled) // Default is True on creation
	s.Assert().NotNil(image.UpdatedAt)
	s.Assert().Equal("New name", image.Name)
}

func (s *ImageDefinitionSuite) Test_UpdateImageDefinition_NotExists() {
	IdNotExists := models.ImageDefinitionUpdate{}

	updatedRow, err := s.imagesStore.UpdateImageDefinition(s.ctx, 500, &IdNotExists)

	s.Assert().Zero(updatedRow)
	s.Assert().ErrorContains(err, "failed to update image definition, may not exist")
}

func (s *ImageDefinitionSuite) Test_DeleteImageDefinition_NoVersions() {
	err := s.imagesStore.DeleteImageDefinition(s.ctx, 1)
	s.Require().NoError(err)

	image, err := s.imagesStore.GetImageDefinitionById(s.ctx, 1)
	s.Assert().Nil(image)
	s.Assert().ErrorContains(err, "sql: no rows in result set", "Should not be able to get image definition that has been deleted")
}

func (s *ImageDefinitionSuite) Test_DeleteImageDefinition_WithVersion() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (
			id,
			image_definition_id,
			version,
			state
		)
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
