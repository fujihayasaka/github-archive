package cronjobs

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestImageEventsPublishingJob_Perform(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsImageEventsPublishingJobEnable)

	// Create a replication job instance
	ImageEventsPublishingJob := &ImageEventsPublishingJob{
		BaseJob: baseJob,
	}
	var runnerGroupId uint64 = 10

	// Define the test data
	image1 := &models.ImageDefinition{
		Id:            1,
		Name:          "linux-img",
		OsType:        models.OsType_Linux,
		ImageType:     models.ImageType_Customer,
		RunnerGroupId: &runnerGroupId,
		OwnerId:       "O_blah",
	}
	image2 := &models.ImageDefinition{
		Id:            2,
		Name:          "win-img",
		OsType:        models.OsType_Windows,
		ImageType:     models.ImageType_Customer,
		RunnerGroupId: &runnerGroupId,
		OwnerId:       "O_blah2",
	}

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListAllCustomerImageOwners(gomock.Any()).Return([]string{image1.OwnerId, image2.OwnerId}, nil)
	mockImagesStore.EXPECT().ListCustomerImageDefinitionsByOwner(gomock.Any(), image1.OwnerId).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListCustomerImageDefinitionsByOwner(gomock.Any(), image2.OwnerId).Return([]*models.ImageDefinition{image2}, nil)

	// Call the Perform method
	err := ImageEventsPublishingJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestImageEventsPublishingJob_Perform_ImagesStore_NoOwners(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsImageEventsPublishingJobEnable)

	// Create a replication job instance
	ImageEventsPublishingJob := &ImageEventsPublishingJob{
		BaseJob: baseJob,
	}

	// Set up the expectation for the mock ImagesStore
	mockImagesStore.EXPECT().ListAllCustomerImageOwners(gomock.Any()).Return([]string{}, nil)

	// Call the Perform method
	err := ImageEventsPublishingJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestImageEventsPublishingJob_Perform_ImagesStore_NoOwnerImages(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsImageEventsPublishingJobEnable)

	// Create a replication job instance
	ImageEventsPublishingJob := &ImageEventsPublishingJob{
		BaseJob: baseJob,
	}

	// Set up the expectation for the mock ImagesStore
	mockImagesStore.EXPECT().ListAllCustomerImageOwners(gomock.Any()).Return([]string{"blah"}, nil)
	mockImagesStore.EXPECT().ListCustomerImageDefinitionsByOwner(gomock.Any(), "blah").Return(nil, nil)

	// Call the Perform method
	err := ImageEventsPublishingJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestImageEventsPublishingJob_Perform_ImagesStore_GetAllOwnersError(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsImageEventsPublishingJobEnable)

	// Create a replication job instance
	ImageEventsPublishingJob := &ImageEventsPublishingJob{
		BaseJob: baseJob,
	}

	// Set up the expectation for the mock ImagesStore
	mockImagesStore.EXPECT().ListAllCustomerImageOwners(gomock.Any()).Return(nil, fmt.Errorf("test"))

	// Call the Perform method
	err := ImageEventsPublishingJob.Perform(ctx)

	// Assert that the error matches the expected error
	assert.ErrorContains(t, err, "customer image events publishing job finished with errors")
}

func TestImageEventsPublishingJob_Perform_ImagesStore_ListAllImagesByOwnerError(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsImageEventsPublishingJobEnable)

	// Create a replication job instance
	ImageEventsPublishingJob := &ImageEventsPublishingJob{
		BaseJob: baseJob,
	}

	// Set up the expectation for the mock ImagesStore
	mockImagesStore.EXPECT().ListAllCustomerImageOwners(gomock.Any()).Return([]string{"blah"}, nil)
	mockImagesStore.EXPECT().ListCustomerImageDefinitionsByOwner(gomock.Any(), "blah").Return(nil, fmt.Errorf("test"))

	// Call the Perform method
	err := ImageEventsPublishingJob.Perform(ctx)

	// Assert that the error matches the expected error
	assert.ErrorContains(t, err, "customer image events publishing job finished with errors")
}
