package cronjobs

import (
	"context"
	"errors"
	"testing"

	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestRetentionJob_Perform_CuratedImages(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}
	imageVersions := []*models.ImageVersion{
		{Id: 1, Version: "1.0.0"},
		{Id: 2, Version: "1.0.1"},
		{Id: 3, Version: "1.0.2"},
	}

	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions, nil)
	mockPromotionStartClient.EXPECT().StartAsyncImageVersionDeletion(gomock.Any(), imageVersions[0].Id).Return(nil)

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_CustomerImages(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCustomerImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Customer,
		VersionsToKeep: 2,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Customer}
	imageVersions := []*models.ImageVersion{
		{Id: 1, Version: "1.0.0"},
		{Id: 2, Version: "1.0.1"},
		{Id: 3, Version: "1.0.2"},
	}

	mockImagesStore.EXPECT().ListAllCustomerImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions, nil)
	mockPromotionStartClient.EXPECT().StartAsyncImageVersionDeletion(gomock.Any(), imageVersions[0].Id).Return(nil)

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_DisableAllFF(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_DisableCuratedImages(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}
	imageVersions := []*models.ImageVersion{
		{Id: 1, Version: "1.0.0"},
		{Id: 2, Version: "1.0.1"},
		{Id: 3, Version: "1.0.2"},
	}

	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions, nil)

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_DisableCustomerImages(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Customer,
		VersionsToKeep: 2,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Customer}
	imageVersions := []*models.ImageVersion{
		{Id: 1, Version: "1.0.0"},
		{Id: 2, Version: "1.0.1"},
		{Id: 3, Version: "1.0.2"},
	}

	mockImagesStore.EXPECT().ListAllCustomerImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions, nil)

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_NoVersion(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}
	imageVersions := []*models.ImageVersion{}

	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions, nil)

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_BelowVersionsToKeep(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}
	imageVersions := []*models.ImageVersion{
		{Id: 1, Version: "1.0.0"},
	}

	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions, nil)

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_DisableRetentionJobFFOffDeleteImageFFOn(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// It should do nothing with Retention Job FF is off and delete images FF is on
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_DisableRetentionJobFFOffDisableDeleteFFOn(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	// When Retention Job FF is on and Delete images is off. It should not delete
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Define the test data
	image1 := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux}
	imageVersions := []*models.ImageVersion{
		{Id: 1, Version: "1.0.0"},
		{Id: 2, Version: "1.0.1"},
		{Id: 3, Version: "1.0.2"},
	}

	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return([]*models.ImageDefinition{image1}, nil)
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), image1.Id).Return(imageVersions, nil)

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there were no errors
	assert.NoError(t, err)
}

func TestRetentionJob_Perform_WithErrorListingImageDefinitions(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob: baseJob,
		Kind:    models.ImageType_Curated,
	}

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListCuratedImageDefinitions(gomock.Any()).Return(nil, errors.New("error listing image definitions"))

	// Call the Perform method
	err := retentionJob.Perform(ctx)

	// Assert that there was an error
	assert.Error(t, err)
}

func TestRetentionJob_ProcessImageVersionDeletion_WithErrorInPromotionStartClient(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob: baseJob,
		Kind:    models.ImageType_Curated,
	}

	// Define the test data
	imageDefinition := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}
	imageVersion := &models.ImageVersion{Id: 1, Version: "1.0.0"}

	mockPromotionStartClient.EXPECT().StartAsyncImageVersionDeletion(gomock.Any(), imageVersion.Id).Return(errors.New("error queueing job"))

	// Call the processImageVersionDeletion method
	err := retentionJob.processImageVersionDeletion(ctx, imageDefinition, imageVersion)

	// Assert that there was an error
	assert.Error(t, err)
}

func TestRetentionJob_cleanUpImageVersions(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Define the test data
	imageDefinition := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}
	imageVersions := []*models.ImageVersion{
		{Id: 1, Version: "1.0.0"},
		{Id: 2, Version: "1.0.1"},
		{Id: 3, Version: "1.0.2"},
	}

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), imageDefinition.Id).Return(imageVersions, nil)
	mockPromotionStartClient.EXPECT().StartAsyncImageVersionDeletion(gomock.Any(), imageVersions[0].Id).Return(nil)

	// Call the cleanUpImageVersions method
	hasErrors, err := retentionJob.cleanUpImageVersions(ctx, imageDefinition)

	// Assert that there were no errors
	assert.NoError(t, err)
	assert.False(t, hasErrors)
}

func TestRetentionJob_cleanUpImageVersions_WithErrorListingImageVersions(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob: baseJob,
	}

	// Define the test data
	imageDefinition := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), imageDefinition.Id).Return(nil, errors.New("error listing image versions"))

	// Call the cleanUpImageVersions method
	hasErrors, err := retentionJob.cleanUpImageVersions(ctx, imageDefinition)

	// Assert that there was an error
	assert.Error(t, err)
	assert.False(t, hasErrors)
}

func TestRetentionJob_cleanUpImageVersions_WithErrorDeletingImageVersion(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	// Create a retention job instance
	retentionJob := &RetentionJob{
		BaseJob:        baseJob,
		Kind:           models.ImageType_Curated,
		VersionsToKeep: 2,
	}

	// Define the test data
	imageDefinition := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}
	imageVersions := []*models.ImageVersion{
		{Id: 1, Version: "1.0.0"},
		{Id: 2, Version: "1.0.1"},
		{Id: 3, Version: "1.0.2"},
	}

	// Set up the expectations for the mock ImagesStore
	mockImagesStore.EXPECT().ListImageVersionsByDefinitionId(gomock.Any(), imageDefinition.Id).Return(imageVersions, nil)
	mockPromotionStartClient.EXPECT().StartAsyncImageVersionDeletion(gomock.Any(), imageVersions[0].Id).Return(errors.New("error deleting image version"))

	// Call the cleanUpImageVersions method
	hasErrors, err := retentionJob.cleanUpImageVersions(ctx, imageDefinition)

	// Assert that there was an error
	assert.NoError(t, err)
	assert.True(t, hasErrors)
}

func TestRetentionJob_ProcessImageVersionDeletion_SkipDeletingState(t *testing.T) {
	ctx := context.Background()
	ctrl, baseJob := setup(t)
	defer ctrl.Finish()

	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobEnable)
	featureflags.TEST_GetFeatureFlagsClient().EnableFeatureFlagGlobally(featureflags.FeatureFlag_ImsRetentionJobDeleteCuratedImages)

	retentionJob := &RetentionJob{
		BaseJob: baseJob,
		Kind:    models.ImageType_Curated,
	}

	imageDefinition := &models.ImageDefinition{Id: 1, OsType: models.OsType_Linux, ImageType: models.ImageType_Curated}
	imageVersion := &models.ImageVersion{
		Id:    1,
		State: models.ImageVersionState_Deleting, // Set state to "Deleting"
	}

	err := retentionJob.processImageVersionDeletion(ctx, imageDefinition, imageVersion)

	assert.NoError(t, err)
}
