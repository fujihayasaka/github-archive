package featureflags

// This file is intended to define constants for feature flags used in service

type FeatureFlag string

const (
	FeatureFlag_ImsRetentionJobEnable                 FeatureFlag = "ims_retention_job_enable"
	FeatureFlag_ImsRetentionJobDeleteCuratedImages    FeatureFlag = "ims_retention_job_delete_curated_images"
	FeatureFlag_ImsRetentionJobDeleteCustomerImages   FeatureFlag = "ims_retention_job_delete_customer_images"
	FeatureFlag_ImsRetentionJobDeleteImages           FeatureFlag = "ims_retention_job_delete_images"
	FeatureFlag_CustomerImageDefinitionsLimitIncrease FeatureFlag = "ims_customer_image_definitions_limit_increase"
	FeatureFlag_CustomerImageVersionsLimitIncrease    FeatureFlag = "ims_customer_image_versions_limit_increase"
	FeatureFlag_ImsImageEventsPublishingJobEnable     FeatureFlag = "ims_image_events_publishing_job_enable"

	// These 3 feature flags are used in E2E tests which are run against Lab environment
	// Any change of feature flag name can break E2E tests on lab
	// https://devportal.githubapp.com/feature-flags?searchType=team&name=compute-flex-reviewers
	TEST_FeatureFlag_E2E_TestFlag_GloballyEnabled         FeatureFlag = "ims_e2e_test_feature_globally_enabled"
	TEST_FeatureFlag_E2E_TestFlag_GloballyDisabled        FeatureFlag = "ims_e2e_test_feature_globally_disabled"
	TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner         FeatureFlag = "ims_e2e_test_feature_enabled_per_owner"
	TEST_FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID string      = "O_kgDOAf4wIg" // bbq-beets org
	TEST_FeatureFlag_FakeUser_GlobalID                    string      = "U_kgAB"       // 'U_' for user and 'kgAB' is encoded '[0,1]'
)
