package commands

import (
	"context"
	"testing"

	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/store/mysql/testhelper"
	"github.com/stretchr/testify/suite"
)

func TestAzureSubscriptionUpdateSuite(t *testing.T) {
	suite.Run(t, new(AzureSubscriptionUpdateSuite))
}

type AzureSubscriptionUpdateSuite struct {
	suite.Suite
	dbSuite testhelper.DatabaseSuite

	ctx         context.Context
	imagesStore *store.ImagesStore
}

func (s *AzureSubscriptionUpdateSuite) SetupSuite() {
	s.dbSuite.SetupSuite("hosted_compute_ims_test_transitions")
	s.ctx = context.Background()

	imagesStore, err := store.NewImagesStoreWithMySQLConnection(s.dbSuite.Config())
	s.Require().NoError(err)

	s.imagesStore = imagesStore
}

func (s *AzureSubscriptionUpdateSuite) SetupTest() {
	tables := []string{
		"azure_subscription",
	}
	err := testhelper.TruncateTables(s.ctx, s.dbSuite.DB(), tables)
	s.Require().NoError(err)
}

func (s *AzureSubscriptionUpdateSuite) Test_UpdateAzureSubscriptions_UpdateExistingSub() {
	// Create a mock config
	cmdHelpers := createCmdHelpers(s)

	// Create an already existing subscription in the database
	err := s.imagesStore.UpsertAzureSubscriptionBySubscriptionId(s.ctx, &models.AzureSubscriptionUpsert{
		SubscriptionId:     "toupdate-1a2b-3c4d-5e6f-7g8h9i0j1k2l",
		ResourcesPrefix:    "old",
		ImageType:          models.ImageType_Customer,
		ImageVersionsLimit: 15,
	})
	s.Require().NoError(err, "UpsertAzureSubscriptionById should not return an error")

	// Create a command instance
	err = Run(context.TODO(), "azure_subscription_update.go", "", cmdHelpers)
	s.Require().NoError(err, "updateAzureSubscriptions should not return an error")

	// Verify subscriptions were added to the database
	subscriptions, err := s.imagesStore.ListAzureSubscriptions(s.ctx)
	s.Require().NoError(err)

	// We should have at least one subscription (from the dev environment in azure_subscription_data.yaml)
	s.Require().NotEmpty(subscriptions, "Subscriptions should not be empty")

	// Verify the subscription data matches what's in azure_subscription_data.yaml for dev environment
	var found bool
	for _, sub := range subscriptions {
		if sub.SubscriptionId == "toupdate-1a2b-3c4d-5e6f-7g8h9i0j1k2l" {
			found = true
			s.Equal("updated-from-file", sub.ResourcesPrefix)
			s.Equal(models.ImageType_Curated, sub.ImageType)
			s.Equal(uint(1), sub.ImageVersionsLimit)
			break
		}
	}
	s.True(found, "The dev subscription from azure_subscription_data.yaml should be found")
}

func (s *AzureSubscriptionUpdateSuite) Test_UpdateAzureSubscriptions_InsertsNewSub() {
	// Create a mock config
	cmdHelpers := createCmdHelpers(s)

	// Create a command instance
	err := Run(context.TODO(), "azure_subscription_update.go", "", cmdHelpers)
	s.Require().NoError(err, "updateAzureSubscriptions should not return an error")

	// Verify subscriptions were added to the database
	subscriptions, err := s.imagesStore.ListAzureSubscriptions(s.ctx)
	s.Require().NoError(err)

	// We should have at least one subscription (from the dev environment in azure_subscription_data.yaml)
	s.Require().NotEmpty(subscriptions, "Subscriptions should not be empty")

	// Verify the subscription data matches what's in azure_subscription_data.yaml for dev environment
	var found bool
	for _, sub := range subscriptions {
		if sub.SubscriptionId == "toinsert-1a2b-3c4d-5e6f-7g8h9i0j1k2l" {
			found = true
			s.Equal("1234567", sub.ResourcesPrefix)
			s.Equal(models.ImageType_Customer, sub.ImageType)
			s.Equal(uint(100), sub.ImageVersionsLimit)
			break
		}
	}
	s.True(found, "The dev subscription from azure_subscription_data.yaml should be found")
}

func createCmdHelpers(s *AzureSubscriptionUpdateSuite) Helpers {
	cfg := &config.Config{
		Env: "dev", // This must match an environment in the azure_subscription_data.yaml file
	}

	// Set up command helpers
	cmdHelpers := Helpers{
		Config:     cfg,
		ImageStore: s.imagesStore,
	}
	return cmdHelpers
}
