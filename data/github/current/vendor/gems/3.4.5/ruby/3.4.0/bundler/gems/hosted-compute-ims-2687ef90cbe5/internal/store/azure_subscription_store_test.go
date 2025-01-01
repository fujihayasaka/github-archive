package store

import (
	"context"
	"testing"

	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/gen/ent/azuresubscription"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store/mysql/testhelper"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/suite"
)

func TestAzureSubscriptionSuite(t *testing.T) {
	suite.Run(t, new(AzureSubscriptionSuite))
}

type AzureSubscriptionSuite struct {
	suite.Suite
	dbSuite testhelper.DatabaseSuite

	ctx         context.Context
	imagesStore *ImagesStore
}

func (s *AzureSubscriptionSuite) SetupSuite() {
	s.dbSuite.SetupSuite("hosted_compute_ims_test")
	s.ctx = context.Background()

	imagesStore, err := NewImagesStoreWithMySQLConnection(s.dbSuite.Config())
	s.Require().NoError(err)

	s.imagesStore = imagesStore
}

func (s *AzureSubscriptionSuite) SetupTest() {
	tables := []string{
		"image_definition",
		"image_version",
		"azure_subscription",
	}
	err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables)
	s.Require().NoError(err)
}

func (s *AzureSubscriptionSuite) Test_ListAzureSubscriptions() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
		(1, 'test1', 'test1', 'Curated', 5, 100),
		(2, 'test2', 'test2', 'Customer', 200, 10000),
		(3, 'test3', 'test3', 'Mixed', 0, 30);
	`)
	s.Require().NoError(err)

	azureSubscriptions, err := s.imagesStore.ListAzureSubscriptions(s.ctx)
	s.Require().NoError(err)
	s.Require().Equal(3, len(azureSubscriptions))
	s.Require().Equal(uint64(1), azureSubscriptions[0].Id)
	s.Require().Equal("test1", azureSubscriptions[0].SubscriptionId)
	s.Require().Equal(models.ImageType_Curated, azureSubscriptions[0].ImageType)
	s.Require().Equal(uint(5), azureSubscriptions[0].ImageVersionsCount)
	s.Require().Equal(uint(100), azureSubscriptions[0].ImageVersionsLimit)
	s.Require().Equal(uint64(2), azureSubscriptions[1].Id)
	s.Require().Equal("test2", azureSubscriptions[1].SubscriptionId)
	s.Require().Equal(models.ImageType_Customer, azureSubscriptions[1].ImageType)
	s.Require().Equal(uint(200), azureSubscriptions[1].ImageVersionsCount)
	s.Require().Equal(uint(10000), azureSubscriptions[1].ImageVersionsLimit)
	s.Require().Equal(uint64(3), azureSubscriptions[2].Id)
	s.Require().Equal("test3", azureSubscriptions[2].SubscriptionId)
	s.Require().Equal(models.ImageType("Mixed"), azureSubscriptions[2].ImageType)
	s.Require().Equal(uint(0), azureSubscriptions[2].ImageVersionsCount)
	s.Require().Equal(uint(30), azureSubscriptions[2].ImageVersionsLimit)
}

func (s *AzureSubscriptionSuite) Test_GetAzureSubscriptionsById() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
		(1, 'test1', 'test1', 'Curated', 5, 100),
		(2, 'test2', 'test2', 'Customer', 200, 10000),
		(3, 'test3', 'test3', 'Mixed', 0, 30);
	`)
	s.Require().NoError(err)

	azureSubscription, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 2)
	s.Require().NoError(err)
	s.Require().Equal(uint64(2), azureSubscription.Id)
	s.Require().Equal("test2", azureSubscription.SubscriptionId)
	s.Require().Equal(models.ImageType_Customer, azureSubscription.ImageType)
	s.Require().Equal(uint(200), azureSubscription.ImageVersionsCount)
	s.Require().Equal(uint(10000), azureSubscription.ImageVersionsLimit)
}

func (s *AzureSubscriptionSuite) Test_GetAzureSubscriptionCandidates_ChooseCorrectImageType() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
		(1, 'test1', 'test1', 'Curated', 0, 100),
		(2, 'test2', 'test2', 'Customer', 0, 100),
		(3, 'test3', 'test3', 'Mixed', 0, 100);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, owner_id, image_type)
		VALUES
		(1, 'test1', 'test', 'Curated'),
		(2, 'test2', 'test', 'Customer');
	`)
	s.Require().NoError(err)

	candidates, err := s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 1)
	s.Require().NoError(err)
	s.assertAzureSubscriptionsList([]uint64{1, 3}, candidates)

	candidates, err = s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 2)
	s.Require().NoError(err)
	s.assertAzureSubscriptionsList([]uint64{2, 3}, candidates)
}

func (s *AzureSubscriptionSuite) Test_GetAzureSubscriptionCandidates_SkipDevSubscription() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, owner_id, image_type)
		VALUES
		(1, 'test1', 'test', 'Curated'),
		(2, 'test2', 'test', 'Customer');
	`)
	s.Require().NoError(err)

	allSubscriptionImageTypes := []azuresubscription.ImageType{azuresubscription.ImageTypeCurated, azuresubscription.ImageTypeCustomer, azuresubscription.ImageTypeMixed}
	for _, imageType := range allSubscriptionImageTypes {
		err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), []string{"azure_subscription"})
		s.NoError(err)

		_, err = s.dbSuite.DB().Write.Exec(`
			INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
			VALUES
			(1, ?, 'test1', ?, 0, 100);
			`, utils.SharedDevImagesSubscriptionId, imageType)
		s.Require().NoError(err)

		candidates, err := s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 1)
		s.Require().NoError(err)
		s.Require().Empty(candidates)

		candidates, err = s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 2)
		s.Require().NoError(err)
		s.Require().Empty(candidates)
	}
}

func (s *AzureSubscriptionSuite) Test_GetAzureSubscriptionCandidates_ChooseSubscriptionsWithFreeSlots() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
		(1, 'test1', 'test1', 'Curated', 0, 0),
		(2, 'test2', 'test2', 'Curated', 0, 100),
		(3, 'test3', 'test3', 'Curated', 63, 100),
		(4, 'test4', 'test4', 'Curated', 100, 100),
		(5, 'test5', 'test5', 'Curated', 101, 100);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, owner_id, image_type)
		VALUES (1, 'test1', 'test', 'Curated');
	`)
	s.Require().NoError(err)

	candidates, err := s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 1)
	s.Require().NoError(err)
	s.assertAzureSubscriptionsList([]uint64{2, 3}, candidates)
}

func (s *AzureSubscriptionSuite) Test_GetAzureSubscriptionCandidates_NoSubscriptionAvailable() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, owner_id, image_type)
		VALUES (1, 'test1', 'test', 'Curated');
	`)
	s.Require().NoError(err)

	candidates, err := s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().Empty(candidates)
}

func (s *AzureSubscriptionSuite) Test_GetAzureSubscriptionCandidates_FailedToGetImageDefinition() {
	_, err := s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 1)
	s.Require().ErrorContains(err, "failed to get image definition by id")
}

func (s *AzureSubscriptionSuite) Test_GetAzureSubscriptionCandidates_NoImageVersionsAssignedYet() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
		(1, 'test1', 'test1', 'Curated', 0, 100),
		(2, 'test2', 'test2', 'Curated', 100, 100),
		(3, 'test3', 'test3', 'Curated', 0, 100);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, owner_id, image_type)
		VALUES (1, 'test1', 'test', 'Curated');
	`)
	s.Require().NoError(err)

	candidates, err := s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 1)
	s.Require().NoError(err)
	s.assertAzureSubscriptionsList([]uint64{1, 3}, candidates)
}

func (s *AzureSubscriptionSuite) Test_GetAzureSubscriptionCandidates_UsedSubscriptionsHaveHigherPriority() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
		(1, 'test1', 'test1', 'Curated', 2, 100),
		(2, 'test2', 'test2', 'Curated', 1, 100),
		(3, 'test3', 'test3', 'Curated', 1, 100),
		(4, 'test4', 'test4', 'Curated', 0, 100),
		(5, 'test5', 'test5', 'Curated', 100, 100),
		(6, 'test6', 'test6', 'Curated', 0, 100);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, owner_id, image_type)
		VALUES
		(1, 'test1', 'test', 'Curated'),
		(2, 'test2', 'test', 'Curated');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES
		(1, '1.0.0', 1, 'Ready', 3),
		(2, '1.0.0', 2, 'Ready', 2),
		(3, '2.0.0', 2, 'Ready', NULL),
		(4, '2.0.0', 1, 'Ready', 1),
		(5, '3.0.0', 1, 'Ready', 1),
		(6, '3.0.0', 2, 'Ready', 5);
	`)
	s.Require().NoError(err)

	// the order of unused subscriptions should be random but used subscription should higher priority
	// so running store function multiple times to make sure that this rule is fulfilled
	for i := 0; i < 10; i++ {
		candidates, err := s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 1)
		s.Require().NoError(err)
		s.Require().Len(candidates, 5)
		s.Require().Equal(uint64(1), candidates[0].ID)
		s.Require().Equal(uint64(3), candidates[1].ID)
		s.assertAzureSubscriptionsList([]uint64{2, 4, 6}, candidates[2:])

		candidates, err = s.imagesStore.getAzureSubscriptionCandidates(s.ctx, 2)
		s.Require().NoError(err)
		s.Require().Len(candidates, 5)
		s.Require().Equal(uint64(2), candidates[0].ID)
		s.assertAzureSubscriptionsList([]uint64{1, 3, 4, 6}, candidates[1:])
	}
}

func (s *AzureSubscriptionSuite) Test_AttemptToAssignAzureSubscriptionToImageVersion_AssignSuccessfully() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES (1, 'test1', 'test1', 'Curated', 50, 100);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES (1, '1.0.0', 1, 'Ready', NULL);
	`)
	s.Require().NoError(err)

	assigned, err := s.imagesStore.attemptToAssignAzureSubscriptionToImageVersion(s.ctx, 1, 1)
	s.Require().NoError(err)
	s.Require().True(assigned)

	// validate that image version count was incremented successfully for subscription
	sub, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().Equal(uint(51), sub.ImageVersionsCount)

	// validate that azure subscription was saved to image version successfully
	iv, err := s.imagesStore.GetImageVersionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().Equal(utils.ToPtr[uint64](1), iv.AzureSubscriptionId)
}

func (s *AzureSubscriptionSuite) Test_AttemptToAssignAzureSubscriptionToImageVersion_RaceCondition_SubscriptionNoFreeSlots() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES (1, 'test1', 'test1', 'Curated', 100, 100);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES (1, '1.0.0', 1, 'Ready', NULL);
	`)
	s.Require().NoError(err)

	assigned, err := s.imagesStore.attemptToAssignAzureSubscriptionToImageVersion(s.ctx, 1, 1)
	s.Require().NoError(err)
	s.Require().False(assigned)

	// validate that image version count was not incremented for subscription
	sub, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().Equal(uint(100), sub.ImageVersionsCount)

	// validate that azure subscription was not saved to image version
	iv, err := s.imagesStore.GetImageVersionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().Nil(iv.AzureSubscriptionId)
}

func (s *AzureSubscriptionSuite) Test_AttemptToAssignAzureSubscriptionToImageVersion_FailedToUpdateImageVersion() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES (1, 'test1', 'test1', 'Curated', 50, 100);
	`)
	s.Require().NoError(err)

	assigned, err := s.imagesStore.attemptToAssignAzureSubscriptionToImageVersion(s.ctx, 1, 1)
	s.Require().ErrorContains(err, "failed to update image version with assigned subscription")
	s.Require().False(assigned)

	// validate that transaction was rolled back successfully and image version count was not incremented
	sub, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().Equal(uint(50), sub.ImageVersionsCount)
}

func (s *AzureSubscriptionSuite) Test_AssignAzureSubscriptionToImageVersion_FailedToGetImageVersion() {
	_, err := s.imagesStore.AssignAzureSubscriptionToImageVersion(s.ctx, 1)
	s.Require().ErrorContains(err, "failed to get image version by id")
}

func (s *AzureSubscriptionSuite) Test_AssignAzureSubscriptionToImageVersion_ImageVersionAlreadyAssigned() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES (1, '1.0.0', 1, 'Ready', 1);
	`)
	s.Require().NoError(err)

	iv, err := s.imagesStore.AssignAzureSubscriptionToImageVersion(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().NotNil(iv)
	s.Require().Equal(utils.ToPtr[uint64](1), iv.AzureSubscriptionId)
}

func (s *AzureSubscriptionSuite) Test_AssignAzureSubscriptionToImageVersion_FailedToGetCandidates() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES (1, '1.0.0', 1, 'Ready', NULL);
	`)
	s.Require().NoError(err)

	_, err = s.imagesStore.AssignAzureSubscriptionToImageVersion(s.ctx, 1)
	s.Require().ErrorContains(err, "failed to get azure subscription candidates")
}

func (s *AzureSubscriptionSuite) Test_AssignAzureSubscriptionToImageVersion_NoAvailableCandidates() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, owner_id, image_type)
		VALUES (1, 'test1', 'test', 'Curated');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES (1, '1.0.0', 1, 'Ready', NULL);
	`)
	s.Require().NoError(err)

	_, err = s.imagesStore.AssignAzureSubscriptionToImageVersion(s.ctx, 1)
	s.Require().ErrorContains(err, "no available azure subscriptions for image version assignment")
}

func (s *AzureSubscriptionSuite) Test_AssignAzureSubscriptionToImageVersion_AssignedSuccessfully() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
			(1, 'test1', 'test1', 'Curated', 0, 100),
			(2, 'test2', 'test2', 'Curated', 0, 100);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (id, name, owner_id, image_type)
		VALUES (1, 'test1', 'test', 'Curated');
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES
			(1, '1.0.0', 1, 'Ready', 2),
			(2, '2.0.0', 1, 'Ready', NULL);
	`)
	s.Require().NoError(err)

	iv, err := s.imagesStore.AssignAzureSubscriptionToImageVersion(s.ctx, 2)
	s.Require().NoError(err)
	s.Require().Equal(utils.ToPtr[uint64](2), iv.AzureSubscriptionId)

	// validate image version count increment in azure subscription table
	subWithId1, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().Equal(uint(0), subWithId1.ImageVersionsCount)
	subWithId2, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 2)
	s.Require().NoError(err)
	s.Require().Equal(uint(1), subWithId2.ImageVersionsCount)
}

func (s *AzureSubscriptionSuite) Test_UnassignAzureSubscriptionFromImageVersion_FailedToGetImageVersion() {
	err := s.imagesStore.UnassignAzureSubscriptionFromImageVersion(s.ctx, 1)
	s.Require().ErrorContains(err, "failed to get image version by id")
}

func (s *AzureSubscriptionSuite) Test_UnassignAzureSubscriptionFromImageVersion_ImageVersionAlreadyUnassigned() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES (1, '1.0.0', 1, 'Ready', NULL);
	`)
	s.Require().NoError(err)

	err = s.imagesStore.UnassignAzureSubscriptionFromImageVersion(s.ctx, 1)
	s.Require().NoError(err)
}

func (s *AzureSubscriptionSuite) Test_UnassignAzureSubscriptionFromImageVersion_FailedToDecrementSubscriptionUsage() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES (1, '1.0.0', 1, 'Ready', 1);
	`)
	s.Require().NoError(err)

	err = s.imagesStore.UnassignAzureSubscriptionFromImageVersion(s.ctx, 1)
	s.Require().ErrorContains(err, "failed to decrement image versions count for subscription")

	// validate that image version assignment is still present if fails to decrement azure subscription usage
	iv, err := s.imagesStore.GetImageVersionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().NotNil(iv)
	s.Require().Equal(utils.ToPtr[uint64](1), iv.AzureSubscriptionId)
}

func (s *AzureSubscriptionSuite) Test_UnassignAzureSubscriptionFromImageVersion_Success() {
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES (1, 'test1', 'test1', 'Curated', 1, 100);
	`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_version (id, version, image_definition_id, state, azure_subscription_id)
		VALUES (1, '1.0.0', 1, 'Ready', 1);
	`)
	s.Require().NoError(err)

	err = s.imagesStore.UnassignAzureSubscriptionFromImageVersion(s.ctx, 1)
	s.Require().NoError(err)

	// validate that image version assignment is still present if fails to decrement azure subscription usage
	iv, err := s.imagesStore.GetImageVersionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().NotNil(iv)
	s.Require().Nil(iv.AzureSubscriptionId)

	// validate that azure subscription usage is decremented
	azSub, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().NotNil(azSub)
	s.Require().Equal(uint(0), azSub.ImageVersionsCount)
}

func (s *AzureSubscriptionSuite) Test_UpsertAzureSubscriptionBySubscriptionId_CreateNew() {
	// Ensure no subscriptions exist
	subscriptions, err := s.imagesStore.ListAzureSubscriptions(s.ctx)
	s.Require().NoError(err)
	s.Require().Empty(subscriptions)

	// Create a new subscription via upsert
	newSub := &models.AzureSubscriptionUpsert{
		SubscriptionId:     "new-subscription-id",
		ImageType:          models.ImageType_Customer,
		ResourcesPrefix:    "new-prefix",
		ImageVersionsLimit: 500,
	}

	err = s.imagesStore.UpsertAzureSubscriptionBySubscriptionId(s.ctx, newSub)
	s.Require().NoError(err)

	// Verify the subscription was created
	subscriptions, err = s.imagesStore.ListAzureSubscriptions(s.ctx)
	s.Require().NoError(err)
	s.Require().Len(subscriptions, 1)

	createdSub := subscriptions[0]
	s.Require().Equal("new-subscription-id", createdSub.SubscriptionId)
	s.Require().Equal(models.ImageType_Customer, createdSub.ImageType)
	s.Require().Equal("new-prefix", createdSub.ResourcesPrefix)
	s.Require().Equal(uint(500), createdSub.ImageVersionsLimit)
	s.Require().Equal(uint(0), createdSub.ImageVersionsCount) // Should start at 0
}

func (s *AzureSubscriptionSuite) Test_UpsertAzureSubscriptionBySubscriptionId_UpdateExisting() {
	// Create an initial subscription directly in the database
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
		(1, 'existing-subscription-id', 'old-prefix', 'Curated', 10, 100);
	`)
	s.Require().NoError(err)

	// Update the subscription via upsert
	updateSub := &models.AzureSubscriptionUpsert{
		SubscriptionId:     "existing-subscription-id",
		ImageType:          models.ImageType_Customer,
		ResourcesPrefix:    "updated-prefix",
		ImageVersionsLimit: 1000,
	}

	err = s.imagesStore.UpsertAzureSubscriptionBySubscriptionId(s.ctx, updateSub)
	s.Require().NoError(err)

	// Verify the subscription was updated
	subscriptions, err := s.imagesStore.ListAzureSubscriptions(s.ctx)
	s.Require().NoError(err)
	s.Require().Len(subscriptions, 1)

	updatedSub := subscriptions[0]
	s.Require().Equal(uint64(1), updatedSub.Id) // ID should remain the same
	s.Require().Equal("existing-subscription-id", updatedSub.SubscriptionId)
	s.Require().Equal(models.ImageType_Customer, updatedSub.ImageType) // Should be updated
	s.Require().Equal("updated-prefix", updatedSub.ResourcesPrefix)    // Should be updated
	s.Require().Equal(uint(1000), updatedSub.ImageVersionsLimit)       // Should be updated
	s.Require().Equal(uint(10), updatedSub.ImageVersionsCount)         // Should remain unchanged
}

func (s *AzureSubscriptionSuite) Test_UpsertAzureSubscriptionBySubscriptionId_PreservesImageVersionsCount() {
	// Create an initial subscription with some image versions count
	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (id, subscription_id, resources_prefix, image_type, image_versions_count, image_versions_limit)
		VALUES
		(1, 'count-test-subscription', 'test-prefix', 'Mixed', 25, 100);
	`)
	s.Require().NoError(err)

	// Update the subscription via upsert
	updateSub := &models.AzureSubscriptionUpsert{
		SubscriptionId:     "count-test-subscription",
		ImageType:          models.ImageType_Curated,
		ResourcesPrefix:    "new-prefix",
		ImageVersionsLimit: 200,
	}

	err = s.imagesStore.UpsertAzureSubscriptionBySubscriptionId(s.ctx, updateSub)
	s.Require().NoError(err)

	// Verify the subscription was updated but image versions count preserved
	subscription, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 1)
	s.Require().NoError(err)
	s.Require().Equal("count-test-subscription", subscription.SubscriptionId)
	s.Require().Equal(models.ImageType_Curated, subscription.ImageType)
	s.Require().Equal("new-prefix", subscription.ResourcesPrefix)
	s.Require().Equal(uint(200), subscription.ImageVersionsLimit)
	s.Require().Equal(uint(25), subscription.ImageVersionsCount) // Should be preserved
}

func (s *AzureSubscriptionSuite) Test_UpsertAzureSubscriptionBySubscriptionId_AllImageTypes() {
	testCases := []struct {
		name      string
		imageType models.ImageType
	}{
		{"Curated", models.ImageType_Curated},
		{"Customer", models.ImageType_Customer},
		{"Mixed", models.ImageType("Mixed")},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {
			// Clean up before each test case
			err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), []string{"azure_subscription"})
			s.Require().NoError(err)

			newSub := &models.AzureSubscriptionUpsert{
				SubscriptionId:     "test-" + tc.name + "-subscription",
				ImageType:          tc.imageType,
				ResourcesPrefix:    "test-prefix",
				ImageVersionsLimit: 50,
			}

			err = s.imagesStore.UpsertAzureSubscriptionBySubscriptionId(s.ctx, newSub)
			s.Require().NoError(err)

			// Verify the subscription was created with correct image type
			subscriptions, err := s.imagesStore.ListAzureSubscriptions(s.ctx)
			s.Require().NoError(err)
			s.Require().Len(subscriptions, 1)

			createdSub := subscriptions[0]
			s.Require().Equal(tc.imageType, createdSub.ImageType)
		})
	}
}

func (s *AzureSubscriptionSuite) Test_UpsertAzureSubscriptionBySubscriptionId_MultipleUpserts() {
	subscriptionId := "multi-upsert-test"

	// First upsert - create
	firstUpsert := &models.AzureSubscriptionUpsert{
		SubscriptionId:     subscriptionId,
		ImageType:          models.ImageType_Customer,
		ResourcesPrefix:    "first-prefix",
		ImageVersionsLimit: 100,
	}

	err := s.imagesStore.UpsertAzureSubscriptionBySubscriptionId(s.ctx, firstUpsert)
	s.Require().NoError(err)

	// Second upsert - update
	secondUpsert := &models.AzureSubscriptionUpsert{
		SubscriptionId:     subscriptionId,
		ImageType:          models.ImageType_Curated,
		ResourcesPrefix:    "second-prefix",
		ImageVersionsLimit: 200,
	}

	err = s.imagesStore.UpsertAzureSubscriptionBySubscriptionId(s.ctx, secondUpsert)
	s.Require().NoError(err)

	// Third upsert - update again
	thirdUpsert := &models.AzureSubscriptionUpsert{
		SubscriptionId:     subscriptionId,
		ImageType:          models.ImageType("Mixed"),
		ResourcesPrefix:    "third-prefix",
		ImageVersionsLimit: 300,
	}

	err = s.imagesStore.UpsertAzureSubscriptionBySubscriptionId(s.ctx, thirdUpsert)
	s.Require().NoError(err)

	// Verify final state
	subscriptions, err := s.imagesStore.ListAzureSubscriptions(s.ctx)
	s.Require().NoError(err)
	s.Require().Len(subscriptions, 1) // Should still be just one subscription

	finalSub := subscriptions[0]
	s.Require().Equal(subscriptionId, finalSub.SubscriptionId)
	s.Require().Equal(models.ImageType("Mixed"), finalSub.ImageType)
	s.Require().Equal("third-prefix", finalSub.ResourcesPrefix)
	s.Require().Equal(uint(300), finalSub.ImageVersionsLimit)
}

func (s *AzureSubscriptionSuite) assertAzureSubscriptionsList(expectedList []uint64, actualList []*ent.AzureSubscription) {
	actualIds := make([]uint64, 0, len(actualList))
	for _, actual := range actualList {
		actualIds = append(actualIds, actual.ID)
	}

	s.Require().ElementsMatch(expectedList, actualIds)
}
