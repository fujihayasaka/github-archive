package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/hosted-compute-ims/internal/utils"

	entsql "entgo.io/ent/dialect/sql"

	"github.com/github/hosted-compute-ims/gen/ent"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/suite"
)

var (
	imageDefinitionColumns = []string{"id", "owner_id", "name", "image_type", "enabled", "feature_flag", "os_type", "architecture", "created_at", "updated_at", "subscription_id", "points_to_image_definition_id"}
	imageVersionColumns    = []string{"id", "version", "image_definition_id", "state", "enabled", "size_gb", "created_at", "updated_at"}
)

type ImagesStoreMockSuite struct {
	suite.Suite
	imagesStore IImagesStore
	sqlMock     sqlmock.Sqlmock
	mockDb      *sql.DB
}

func TestImagesStoreMockSuite(t *testing.T) {
	suite.Run(t, new(ImagesStoreMockSuite))
}

func (s *ImagesStoreMockSuite) BeforeTest(_ string, _ string) {
	s.mockDb, s.sqlMock, _ = sqlmock.New()
	drv := entsql.OpenDB("mysql", s.mockDb)
	entClient := ent.NewClient(ent.Driver(drv)).Debug()

	s.imagesStore = NewImagesStore(s.mockDb, entClient, entClient, log.NewNullLogger(), stats.NullStatter)
}

func (s *ImagesStoreMockSuite) AfterTest(_ string, _ string) {
	if err := s.sqlMock.ExpectationsWereMet(); err != nil {
		s.Fail("there were unfulfilled expectations: %s", err)
	}

	s.mockDb.Close()
}

func (s *ImagesStoreMockSuite) Test_ListCuratedImageDefinitions_SuccessReturn() {
	timestamp := time.Now()
	rows := sqlmock.NewRows(imageDefinitionColumns).
		AddRow(1, "owner1", "image1", "Curated", true, nil, "Linux", "X64", timestamp, timestamp, nil, nil).
		AddRow(2, "owner2", "image2", "Curated", true, nil, "Linux", "X64", timestamp, timestamp, nil, nil)

	s.sqlMock.ExpectQuery("SELECT (.+) FROM `image_definition` WHERE `image_definition`.`image_type` = ?").
		WithArgs("Curated").
		WillReturnRows(rows)

	images, err := s.imagesStore.ListCuratedImageDefinitions(context.Background())

	s.Assert().Nil(err)
	s.Assert().Equal(2, len(images))

	for i := uint64(0); i < uint64(len(images)); i++ {
		image := images[i]
		s.Assert().Equal(uint64(i)+1, image.Id)
		s.Assert().Equal(fmt.Sprintf("owner%d", i+1), image.OwnerId)
		s.Assert().Equal(fmt.Sprintf("image%d", i+1), image.Name)
		s.Assert().Equal(models.ImageType_Curated, image.ImageType)
		s.Assert().True(image.Enabled)
		s.Assert().Equal(models.OsType_Linux, image.OsType)
		s.Assert().Equal(models.Architecture_X64, image.Architecture)
		s.Assert().Equal(timestamp, image.CreatedAt)
		s.Assert().Equal(timestamp, *image.UpdatedAt)
		s.Assert().Nil(image.AzureSubscriptionId)
	}
}

func (s *ImagesStoreMockSuite) Test_ListCustomerImageDefinitions_QueryError() {
	ownerId := "owner1"

	s.sqlMock.ExpectQuery("SELECT (.+) FROM `image_definition` (.+) ").
		WithArgs(ownerId, "Customer").
		WillReturnError(errors.New("query error"))

	images, err := s.imagesStore.ListCustomerImageDefinitions(context.Background(), ownerId)

	s.Assert().ErrorContains(err, "query error")
	s.Assert().Nil(images)
}

func (s *ImagesStoreMockSuite) Test_AddImageDefinition_InsertError() {
	s.sqlMock.ExpectExec("INSERT INTO `image_definition` ").
		WillReturnError(errors.New("insert error"))

	insertId, err := s.imagesStore.AddImageDefinition(context.Background(), &models.ImageDefinition{
		ImageType:           models.ImageType_Curated,
		OsType:              models.OsType_Linux,
		OwnerId:             "owner1",
		Name:                "image1",
		Enabled:             true,
		Architecture:        models.Architecture_X64,
		AzureSubscriptionId: nil,
	})

	s.Assert().Zero(insertId)
	s.Assert().ErrorContains(err, "insert error")
}

func (s *ImagesStoreMockSuite) Test_DeleteImageDefinitionSuccess() {
	deletedRow := sqlmock.NewResult(1, 1)

	s.sqlMock.ExpectExec("DELETE FROM `image_definition` WHERE `image_definition`.`id` (.*) AND \\(NOT \\(EXISTS \\(SELECT `image_version`.`image_definition_id` FROM `image_version` WHERE `image_definition`.`id` = `image_version`.`image_definition_id`\\)\\)\\)").
		WithArgs(uint64(1)).
		WillReturnResult(deletedRow)

	err := s.imagesStore.DeleteImageDefinition(context.Background(), uint64(1))
	s.Assert().NoError(err)
}

func (s *ImagesStoreMockSuite) Test_DeleteImageDefinition_FailOnErr() {
	s.sqlMock.ExpectExec("DELETE FROM `image_definition` WHERE `image_definition`.`id` = ? (.+)").
		WillReturnError(errors.New("delete error"))

	err := s.imagesStore.DeleteImageDefinition(context.Background(), uint64(1))
	s.Assert().ErrorContains(err, "delete error")
}

// TODO See comment: https://github.com/github/hosted-compute-ims/pull/367/files#r1457628533
// func (s *ImagesStoreMockSuite) Test_AssignAzureSubscriptionToImageDefinition_Commit() {
// 	freeSubscriptionId := "free-subscription"
// 	imageDefinitionId := uint64(1)

// 	s.sqlMock.ExpectBegin()

// 	s.sqlMock.ExpectQuery("SELECT s.subscription_id FROM azure_subscription s (.+) ?").
// 		WithArgs(1).
// 		WillReturnRows(sqlmock.NewRows([]string{"subscription_id"}).AddRow(freeSubscriptionId))

// 	s.sqlMock.ExpectExec("UPDATE image_definition SET subscription_id = ? (.+)").
// 		WithArgs(freeSubscriptionId, imageDefinitionId).
// 		WillReturnResult(sqlmock.NewResult(0, 1))

// 	s.sqlMock.ExpectCommit()

// 	assignedSubId, err := s.imagesStore.AssignAzureSubscriptionToImageDefinition(context.Background(), imageDefinitionId, 1, 1)

// 	s.Assert().NoError(err)
// 	s.Assert().Equal(freeSubscriptionId, assignedSubId)
// }

// func (s *ImagesStoreMockSuite) Test_AssignAzureSubscriptionToImageDefinition_NoFreeSubscriptionsRollBack() {
// 	imageDefinitionId := uint64(1)

// 	s.sqlMock.ExpectBegin()

// 	s.sqlMock.ExpectQuery("SELECT s.subscription_id FROM azure_subscription s (.+) ?").
// 		WithArgs(1).
// 		WillReturnError(sql.ErrNoRows)

// 	s.sqlMock.ExpectRollback()

// 	assignedSubId, err := s.imagesStore.AssignAzureSubscriptionToImageDefinition(context.Background(), imageDefinitionId, 1, 1)

// 	s.Assert().Zero(assignedSubId)
// 	s.Assert().ErrorContains(err, "no free azure subscriptions to assign image definition")
// }

// func (s *ImagesStoreMockSuite) Test_AssignAzureSubscriptionToImageDefinition_UpdateFailedRollBack() {
// 	freeSubscriptionId := "free-subscription"
// 	imageDefinitionId := uint64(1)

// 	s.sqlMock.ExpectBegin()

// 	s.sqlMock.ExpectQuery("SELECT s.subscription_id FROM azure_subscription s (.+) ?").
// 		WithArgs(1).
// 		WillReturnRows(sqlmock.NewRows([]string{"subscription_id"}).AddRow(freeSubscriptionId))

// 	s.sqlMock.ExpectExec("UPDATE image_definition SET subscription_id = ? (.+)").
// 		WithArgs(freeSubscriptionId, imageDefinitionId).
// 		WillReturnError(errors.New("update error"))

// 	s.sqlMock.ExpectRollback()

// 	assignedSubId, err := s.imagesStore.AssignAzureSubscriptionToImageDefinition(context.Background(), imageDefinitionId, 1, 1)

// 	s.Assert().Zero(assignedSubId)
// 	s.Assert().ErrorContains(err, "failed to assign azure subscription to image definition")
// }

func (s *ImagesStoreMockSuite) Test_ListImageVersionsByDefinitionId() {
	imageDefinitionId := 1
	timestamp := time.Now()

	_ = sqlmock.NewRows(imageDefinitionColumns).
		AddRow(imageDefinitionId, "owner1", "image1", "Curated", true, nil, "Linux", "X64", timestamp, timestamp, nil, nil)

	verRows := sqlmock.NewRows(imageVersionColumns).
		AddRow(1, "1.0.0", imageDefinitionId, "available", true, 1, timestamp, timestamp).
		AddRow(2, "1.0.1", imageDefinitionId, "available", true, 2, timestamp, timestamp)

	s.sqlMock.ExpectQuery("SELECT (.+) FROM `image_version` WHERE `image_version`.`image_definition_id` = ?").
		WithArgs(1).
		WillReturnRows(verRows)

	versions, err := s.imagesStore.ListImageVersionsByDefinitionId(context.Background(), 1)

	s.Assert().NoError(err)
	s.Assert().NotNil(versions)
}

func (s *ImagesStoreMockSuite) Test_ListImageVersions_QueryError() {
	imageDefinitionId := 1
	timestamp := time.Now()

	_ = sqlmock.NewRows(imageDefinitionColumns).
		AddRow(imageDefinitionId, "owner1", "image1", "Curated", true, nil, "Linux", "X64", timestamp, timestamp, nil, nil)

	s.sqlMock.ExpectQuery("SELECT (.+) FROM `image_version` WHERE `image_version`.`image_definition_id` = ?").
		WithArgs(imageDefinitionId).
		WillReturnError(errors.New("query error"))

	versions, err := s.imagesStore.ListImageVersionsByDefinitionId(context.Background(), 1)

	s.Assert().ErrorContains(err, "failed to get image versions: query error")
	s.Assert().Nil(versions)
}

func (s *ImagesStoreMockSuite) Test_AddImageVersion_DefinitionExists() {
	var imageDefinitionId uint64 = 1

	model := models.ImageVersion{
		Version:           "1.0.10",
		ImageDefinitionId: imageDefinitionId,
		State:             models.ImageVersionState_Ready,
		Enabled:           true,
	}

	s.sqlMock.ExpectExec("INSERT INTO `image_version` (.+)").
		WithArgs("1.0.10", "Ready", "", true, "", utils.AnyTime{}, utils.AnyTime{}, imageDefinitionId).
		WillReturnResult(sqlmock.NewResult(1, 1))

	insertId, err := s.imagesStore.AddImageVersion(context.Background(), &model)

	s.Assert().NoError(err)
	s.Assert().Equal(uint64(1), insertId)
}

func (s *ImagesStoreMockSuite) Test_AddImageVersion_DefinitionDoesNotExist() {
	s.T().Skip()

	var imageDefinitionId uint64 = 1

	model := models.ImageVersion{
		Version:           "1.0.10",
		ImageDefinitionId: imageDefinitionId,
		State:             models.ImageVersionState_Ready,
		Enabled:           true,
	}

	s.sqlMock.ExpectBegin()

	s.sqlMock.ExpectQuery("SELECT EXISTS (.+)").
		WithArgs(imageDefinitionId).
		WillReturnRows(sqlmock.NewRows([]string{"EXISTS"}).AddRow(0))

	s.sqlMock.ExpectRollback()

	insertId, err := s.imagesStore.AddImageVersion(context.Background(), &model)

	s.Assert().Zero(insertId)
	s.Assert().ErrorContains(err, "cannot add image version as specified image definition does not exist")
}

func (s *ImagesStoreMockSuite) Test_AddImageVersion_InsertError() {
	var imageDefinitionId uint64 = 1

	model := models.ImageVersion{
		Version:           "1.0.10",
		ImageDefinitionId: imageDefinitionId,
		State:             models.ImageVersionState_Ready,
		Enabled:           true,
	}

	s.sqlMock.ExpectExec("INSERT INTO `image_version` (.+)").
		WithArgs("1.0.10", "Ready", "", true, "", utils.AnyTime{}, utils.AnyTime{}, imageDefinitionId).
		WillReturnError(errors.New("insert error"))

	insertId, err := s.imagesStore.AddImageVersion(context.Background(), &model)

	s.Assert().Zero(insertId)
	s.Assert().ErrorContains(err, "failed to save image version: insert error")
}

func (s *ImagesStoreMockSuite) Test_UpdateImageVersion_UsesSelectFields() {
	var imageVersionId uint64 = 1

	model := models.ImageVersionUpdate{
		Enabled: true,
	}

	s.sqlMock.ExpectExec("UPDATE `image_version` (.+)").
		WithArgs(true, utils.AnyTime{}, imageVersionId).
		WillReturnResult(sqlmock.NewResult(int64(imageVersionId), 1))

	affectedId, err := s.imagesStore.UpdateImageVersion(context.Background(), imageVersionId, &model)

	s.Assert().NoError(err)
	s.Assert().Equal(imageVersionId, affectedId)
}
