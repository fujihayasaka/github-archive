package featureflags

// This file is intended to define constants for feature flags used in service

type FeatureFlag string

const (
	FeatureFlag_ImagePromotionFastCopy FeatureFlag = "ims_promotion_enable_fastcopy"
	FeatureFlag_VhdCleanUpAfterCreate  FeatureFlag = "ims_vhd_clean_up"

	// These 3 feature flags are used in E2E tests which are run against Lab environment
	// Any change of feature flag name can break E2E tests on lab
	// https://devportal.githubapp.com/feature-flags?searchType=team&name=compute-flex-reviewers
	FeatureFlag_E2E_TestFlag_GloballyEnabled         FeatureFlag = "ims_e2e_test_feature_globally_enabled"
	FeatureFlag_E2E_TestFlag_GloballyDisabled        FeatureFlag = "ims_e2e_test_feature_globally_disabled"
	FeatureFlag_E2E_TestFlag_EnabledPerOwner         FeatureFlag = "ims_e2e_test_feature_enabled_per_owner"
	FeatureFlag_E2E_TestFlag_EnabledPerOwner_OwnerID string      = "O_kgDOAf4wIg" // bbq-beets org
)
