package store

import (
	"context"
	"fmt"
	"sync"
	"testing"

	"github.com/github/hosted-compute-ims/internal/store/mysql/testhelper"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/stretchr/testify/suite"

	"github.com/github/go-stats"
)

type AssignAzureSubTxSuite struct {
	suite.Suite
	dbSuite testhelper.DatabaseSuite

	ctx         context.Context
	imagesStore IImagesStore
}

func TestAssignAzureSubTxSuite(t *testing.T) {
	suite.Run(t, new(AssignAzureSubTxSuite))
}

func (s *AssignAzureSubTxSuite) SetupSuite() {
	s.dbSuite.SetupSuite()
	s.ctx = context.Background()

	telemetryProvider, _ := telemetry.NewFromEnv()
	logger := telemetryProvider.Logger.Named("image_store_read_lock_tx_test")

	s.imagesStore, _ = NewImagesStoreWithMySQLConnection(s.dbSuite.Config(), logger, stats.NullStatter)
}

func (s *AssignAzureSubTxSuite) SetupTest() {
	tables := []string{
		"image_definition",
		"azure_subscription",
	}
	if err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	_, err := s.dbSuite.DB().Write.Exec(`
		INSERT INTO azure_subscription (
			id,
			subscription_id,
			image_type,
			image_count,
			resources_prefix
		)
		VALUES
		(1,'sub1','Customer', 0, 'prefix1'),
		(2,'sub2','Customer', 0, 'prefix2'),
		(3,'sub3','Customer', 2, 'prefix3'),
		(4,'sub4','Customer', 3, 'prefix4'),
		(5,'sub5','Customer', 4, 'prefix5');
	`)

	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`
		INSERT INTO image_definition (
			id,
			owner_id,
			name,
			image_type
		)
		VALUES
		(500,'github','test-5','Customer'),
		(600,'github','test-6','Customer'),
		(700,'github','test-7','Customer');
	`)

	s.Require().NoError(err)
}

func (s *AssignAzureSubTxSuite) Test_AssignAzureSubscriptionToImageDefinition_Sequential() {
	const queryLimit = 1

	const maxImageDefinitionsPerSubscription = 1

	subId1, err := s.imagesStore.AssignAzureSubscriptionToImageDefinition(s.ctx, 500, maxImageDefinitionsPerSubscription, queryLimit)
	s.Require().NoError(err)

	definition, _ := s.imagesStore.GetImageDefinitionById(s.ctx, 500)
	s.Assert().Equal(subId1, *definition.AzureSubscriptionId)

	subId2, err := s.imagesStore.AssignAzureSubscriptionToImageDefinition(s.ctx, 600, maxImageDefinitionsPerSubscription, queryLimit)
	s.Require().NoError(err)

	definition, err = s.imagesStore.GetImageDefinitionById(s.ctx, 600)
	s.Require().NoError(err)

	s.Assert().Equal(subId2, *definition.AzureSubscriptionId)

	s.Assert().NotEqual(subId1, subId2)

	_, err = s.imagesStore.AssignAzureSubscriptionToImageDefinition(s.ctx, 700, maxImageDefinitionsPerSubscription, queryLimit)
	s.Assert().ErrorContainsf(err, "no subscriptions currently available", "Expected error with no subscriptions available, got %T", err)
}

func (s *AssignAzureSubTxSuite) Test_AssignAzureSubscriptionToImageDefinition_ImageDefinitionAlreadyAssignedSubscription() {
	_, err := s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE azure_subscription`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE image_definition`)
	s.Require().NoError(err)

	// Insert a single subscription
	_, err = s.dbSuite.DB().
		Write.
		Exec(`INSERT INTO azure_subscription (id, subscription_id, image_type, image_count, resources_prefix) VALUES (52,'sub1','Customer',0, 'prefix1')`)
	s.Require().NoError(err)

	// Insert an image definition with an already assigned subscription
	_, err = s.dbSuite.DB().
		Write.
		Exec(`INSERT INTO image_definition (id, owner_id, name, image_type, azure_subscription_id) VALUES (500,'github','test-5','Customer',52)`)

	s.Require().NoError(err)

	const queryLimit = 1

	const maxImageDefinitionsPerSubscription = 1

	assignedSub, err := s.imagesStore.AssignAzureSubscriptionToImageDefinition(s.ctx, 500, maxImageDefinitionsPerSubscription, queryLimit)
	s.Assert().Equal(uint64(0), assignedSub)
	s.Assert().ErrorContainsf(err, "image definition already assigned subscription", "Expected error with image definition already assigned, got %T", err)

	definition, _ := s.imagesStore.GetImageDefinitionById(s.ctx, 500)
	s.Assert().Equal(uint64(52), *definition.AzureSubscriptionId)
}

func (s *AssignAzureSubTxSuite) Test_AssignAzureSubscriptionToImageDefinition_InParallel() {
	_, err := s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE azure_subscription`)
	s.Require().NoError(err)

	// Insert a single subscription to force a race condition
	_, err = s.dbSuite.DB().
		Write.
		Exec(`INSERT INTO azure_subscription (id, subscription_id, image_type, image_count, resources_prefix) VALUES (1,'sub1','Customer',0, 'prefix1')`)

	s.Require().NoError(err)

	const queryLimit = 1

	const maxImageDefinitionsPerSubscription = 1

	imageDefinitionIds := []uint64{500, 600, 700}
	errorChan := make(chan error, len(imageDefinitionIds))
	successChan := make(chan uint64, len(imageDefinitionIds))

	updatedIds := []uint64{}
	errors := []error{}

	var wg sync.WaitGroup

	for _, id := range imageDefinitionIds {
		wg.Add(1)

		go func(id uint64) {
			defer wg.Done()

			_, err := s.imagesStore.AssignAzureSubscriptionToImageDefinition(s.ctx, id, maxImageDefinitionsPerSubscription, queryLimit)

			if err != nil {
				errorChan <- err
			} else {
				successChan <- id
			}
		}(id)
	}

	wg.Wait()

	close(errorChan)
	close(successChan)

	for err := range errorChan {
		errors = append(errors, err)
	}

	for id := range successChan {
		updatedIds = append(updatedIds, id)
	}

	// We have a single subscription to assign to three image definitions, where maxImageDefinitionsPerSubscription is 1
	// Expect two errors to be returned
	s.Assert().Equal(2, len(errors))
	s.Assert().ErrorContainsf(errors[0], "no subscriptions currently available", "Expected no subscriptions available error, got %T", errors[0])
	s.Assert().ErrorContainsf(errors[1], "no subscriptions currently available", "Expected no subscriptions available error, got %T", errors[0])

	s.Assert().Equal(1, len(updatedIds))

	definition, err := s.imagesStore.GetImageDefinitionById(s.ctx, updatedIds[0])
	s.Require().NoError(err)

	s.Assert().NotNil(definition.AzureSubscriptionId)
}

func (s *AssignAzureSubTxSuite) Test_UnassignAzureSubscriptionFromImageDefinition() {
	_, err := s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE azure_subscription`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE image_definition`)
	s.Require().NoError(err)

	// Insert a single subscription with image count 1
	_, err = s.dbSuite.DB().
		Write.
		Exec(`INSERT INTO azure_subscription (id, subscription_id, image_type, image_count, resources_prefix) VALUES (52,'sub1','Customer',1, 'prefix1')`)
	s.Require().NoError(err)

	// Insert an image definition with an already assigned subscription
	_, err = s.dbSuite.DB().
		Write.
		Exec(`INSERT INTO image_definition (id, owner_id, name, image_type, azure_subscription_id) VALUES (500,'github','test-5','Customer',52)`)

	s.Require().NoError(err)

	err = s.imagesStore.UnassignAzureSubscriptionFromImageDefinition(s.ctx, 500)
	s.Require().NoError(err)

	sub, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 52)
	s.Require().NoError(err)
	s.Assert().Equal(0, sub.ImageCount)

	definition, _ := s.imagesStore.GetImageDefinitionById(s.ctx, 500)
	s.Assert().Nil(definition.AzureSubscriptionId)
}

func (s *AssignAzureSubTxSuite) Test_UnassignAzureSubscriptionFromImageDefinition_AlreadyUnassigned() {
	_, err := s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE azure_subscription`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE image_definition`)
	s.Require().NoError(err)

	// Insert a single subscription with image count 1
	_, err = s.dbSuite.DB().
		Write.
		Exec(`INSERT INTO azure_subscription (id, subscription_id, image_type, image_count, resources_prefix) VALUES (52,'sub1','Customer',1, 'prefix1')`)
	s.Require().NoError(err)

	// Insert an image definition with no subscription
	_, err = s.dbSuite.DB().
		Write.
		Exec(`INSERT INTO image_definition (id, owner_id, name, image_type) VALUES (500,'github','test-5','Customer')`)

	s.Require().NoError(err)

	err = s.imagesStore.UnassignAzureSubscriptionFromImageDefinition(s.ctx, 500)
	s.Assert().ErrorContainsf(err, "failed to unassign azure subscription from image definition, may already be unassigned", "Expected error with already unassigned, got %T", err)

	sub, err := s.imagesStore.GetAzureSubscriptionById(s.ctx, 52)
	s.Require().NoError(err)
	s.Assert().Equal(1, sub.ImageCount)

	definition, _ := s.imagesStore.GetImageDefinitionById(s.ctx, 500)
	s.Assert().Nil(definition.AzureSubscriptionId)
}

func (s *AssignAzureSubTxSuite) Test_UnassignAzureSubscriptionFromImageDefinition_SubscriptionDoesntExist() {
	_, err := s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE azure_subscription`)
	s.Require().NoError(err)

	_, err = s.dbSuite.DB().Write.Exec(`TRUNCATE TABLE image_definition`)
	s.Require().NoError(err)

	// Insert an image definition with non existent subscription
	_, err = s.dbSuite.DB().
		Write.
		Exec(`INSERT INTO image_definition (id, owner_id, name, image_type, azure_subscription_id) VALUES (500,'github','test-5','Customer',36)`)

	s.Require().NoError(err)

	err = s.imagesStore.UnassignAzureSubscriptionFromImageDefinition(s.ctx, 500)
	s.Assert().ErrorContainsf(err, "failed to decrement azure subscription image count", "Expected error with failed to decrement image count, got %T", err)
}
