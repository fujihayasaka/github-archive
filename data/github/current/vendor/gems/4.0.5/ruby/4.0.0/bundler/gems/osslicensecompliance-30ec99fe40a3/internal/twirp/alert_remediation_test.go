package twirp

import (
	"encoding/json"
	"testing"

	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/internal/twirp/twcerr/twcerrtesting"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestCreatePackageException_RepoLevel(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)
	enterpriseID := uint64(200)
	organizationID := uint64(100)
	pullRequestNumber := uint32(10)

	// Only GPL-2.0 is allowed by the policy.
	_, err := server.CreateRepositoryPolicy(t.Context(), &proto.CreateRepositoryPolicyRequest{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0"},
			},
		},
	})
	require.NoError(t, err)

	newJob := models.CheckJob{
		RepositoryID:      repositoryID,
		PullRequestNumber: pullRequestNumber,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    organizationID,
		EnterpriseID:      &enterpriseID,
	}

	dbJob, err := server.app.Subsystems.Storage.CreateCheckJob(t.Context(), newJob)
	require.NoError(t, err)

	dbJob.Status = models.Fail
	err = server.app.Subsystems.Storage.UpdateCheckJob(t.Context(), dbJob)
	require.NoError(t, err)

	// Create an alert for a package with an MIT license, which is not allowed.
	_, err = server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT OR Apache-2.0",
		PullRequestNumber:     &pullRequestNumber,
	})
	require.NoError(t, err)

	alert, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alert)
	require.Equal(t, "lodash", alert.PackageName)
	require.Equal(t, "MIT OR Apache-2.0", alert.SPDXLicenseExpression)
	require.Equal(t, models.AlertStatusOpen, alert.Status)

	req := &proto.CreatePackageExceptionRequest{
		RepositoryId:  repositoryID,
		PolicyLevel:   proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		UserId:        1,
		AlertNumber:   1,
		Contexts:      testhelpers.AllDistributionContexts,
		Comment:       "It makes sense to add this package exception",
		ClosureReason: proto.ClosureReason_CLOSURE_REASON_INACCURATE_LICENSE,
	}
	resp, err := server.CreatePackageException(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Check the policy again to make sure the package exception was added.
	policyResp, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repositoryID})
	require.NoError(t, err)
	require.NotNil(t, policyResp)
	require.Len(t, policyResp.Policy.Packages, 1)
	pkgPolicy := policyResp.Policy.Packages[0]
	assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, pkgPolicy.PackageManager)
	assert.Equal(t, "lodash", pkgPolicy.Name)
	assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
	assert.Equal(t, "Exception created via API", pkgPolicy.Reason)
	assert.ElementsMatch(t, []string{"MIT", "Apache-2.0"}, pkgPolicy.ExtraAllowedSpdxIds)

	// Check that the alert is now marked as resolved.
	alertAfter, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alertAfter)
	require.NotNil(t, alertAfter.Resolution)
	require.Equal(t, models.AlertResolutionExceptionAdded, alertAfter.Resolution)
	require.Equal(t, models.AlertStatusClosed, alertAfter.Status)
	require.NotNil(t, alertAfter.ClosureReason)
	require.Equal(t, "inaccurate_license", *alertAfter.ClosureReason)

	// Check that 2 alert events were created
	events, err := server.app.Subsystems.Storage.GetAlertEvents(t.Context(), alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	// One event for adding the exception
	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, uint64(1), *events[0].UserID)
	var exceptionEventBody models.ExceptionAddedEventBody
	err = json.Unmarshal(events[0].EventBody, &exceptionEventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", exceptionEventBody.PackageManager)
	assert.Equal(t, "lodash", exceptionEventBody.PackageName)
	assert.Equal(t, "repository", exceptionEventBody.Level)

	// One event for the closing the alert.
	assert.Equal(t, models.EventClosed, events[1].EventType)
	assert.Equal(t, uint64(1), *events[1].UserID)

	// Check that the check job status was updated to pass.
	checkJob, err := server.app.Subsystems.Storage.GetCheckJob(t.Context(), repositoryID, pullRequestNumber)
	require.NoError(t, err)
	require.Equal(t, models.Pass, checkJob.Status)
}

func TestCreatePackageException_EmptyLicense(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)
	enterpriseID := uint64(200)
	organizationID := uint64(100)
	pullRequestNumber := uint32(10)

	// Only MIT is allowed by the policy.
	_, err := server.CreateRepositoryPolicy(t.Context(), &proto.CreateRepositoryPolicyRequest{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT"},
			},
		},
	})
	require.NoError(t, err)

	newJob := models.CheckJob{
		RepositoryID:      repositoryID,
		PullRequestNumber: pullRequestNumber,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    organizationID,
		EnterpriseID:      &enterpriseID,
	}

	dbJob, err := server.app.Subsystems.Storage.CreateCheckJob(t.Context(), newJob)
	require.NoError(t, err)

	dbJob.Status = models.Fail
	err = server.app.Subsystems.Storage.UpdateCheckJob(t.Context(), dbJob)
	require.NoError(t, err)

	// Create an alert for a package with an empty license.
	_, err = server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "", // This is not necessarily ideal because it's not valid SPDX
		PullRequestNumber:     &pullRequestNumber,
	})
	require.NoError(t, err)

	alert, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alert)
	require.Equal(t, "lodash", alert.PackageName)
	require.Equal(t, "", alert.SPDXLicenseExpression)
	require.Equal(t, models.AlertStatusOpen, alert.Status)

	req := &proto.CreatePackageExceptionRequest{
		RepositoryId: repositoryID,
		PolicyLevel:  proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		UserId:       1,
		AlertNumber:  1,
		Contexts:     testhelpers.AllDistributionContexts,
		Comment:      "Adding exception for package with no license",
	}
	resp, err := server.CreatePackageException(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Check the policy again to make sure the package exception was added.
	policyResp, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repositoryID})
	require.NoError(t, err)
	require.NotNil(t, policyResp)
	require.Len(t, policyResp.Policy.Packages, 1)
	pkgPolicy := policyResp.Policy.Packages[0]
	assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, pkgPolicy.PackageManager)
	assert.Equal(t, "lodash", pkgPolicy.Name)
	assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
	assert.Equal(t, "Exception created via API", pkgPolicy.Reason)
	assert.ElementsMatch(t, []string{evaluator.LicenseRefEmpty}, pkgPolicy.ExtraAllowedSpdxIds)

	// Check that the alert is now marked as resolved.
	alertAfter, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alertAfter)
	require.NotNil(t, alertAfter.Resolution)
	require.Equal(t, models.AlertResolutionExceptionAdded, alertAfter.Resolution)
	require.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Check that 2 alert events were created
	events, err := server.app.Subsystems.Storage.GetAlertEvents(t.Context(), alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	// One event for adding the exception
	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, uint64(1), *events[0].UserID)
	var exceptionEventBody models.ExceptionAddedEventBody
	err = json.Unmarshal(events[0].EventBody, &exceptionEventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", exceptionEventBody.PackageManager)
	assert.Equal(t, "lodash", exceptionEventBody.PackageName)
	assert.Equal(t, "repository", exceptionEventBody.Level)

	// One event for the closing the alert.
	assert.Equal(t, models.EventClosed, events[1].EventType)
	assert.Equal(t, uint64(1), *events[1].UserID)

	// Check that the check job status was updated to pass.
	checkJob, err := server.app.Subsystems.Storage.GetCheckJob(t.Context(), repositoryID, pullRequestNumber)
	require.NoError(t, err)
	require.Equal(t, models.Pass, checkJob.Status)
}

// TestCreatePackageException_RepoLevel_DuplicatePackagePolicy tests that creating a package exception
// for a package that already has a package policy in the repository policy updates the existing policy
// rather than adding a new one.
func TestCreatePackageException_RepoLevel_DuplicatePackagePolicy(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)

	// Only GPL-2.0 is allowed by the policy.
	_, err := server.CreateRepositoryPolicy(t.Context(), &proto.CreateRepositoryPolicyRequest{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0"},
			},
		},
		Packages: []*proto.PackagePolicy{
			{
				PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:                "leftpad",
				Action:              proto.PackageAction_PACKAGE_ACTION_BLOCKED,
				Reason:              "This package sucks",
				ExtraAllowedSpdxIds: []string{"MIT"},
			},
		},
	})
	require.NoError(t, err)

	// Create an alert for a package with an MIT license, which is not allowed.
	_, err = server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "leftpad",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	})
	require.NoError(t, err)

	alert, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alert)
	require.Equal(t, "leftpad", alert.PackageName)
	require.Equal(t, "MIT", alert.SPDXLicenseExpression)
	require.Equal(t, models.AlertStatusOpen, alert.Status)

	req := &proto.CreatePackageExceptionRequest{
		RepositoryId: repositoryID,
		PolicyLevel:  proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		UserId:       1,
		AlertNumber:  1,
		Contexts:     testhelpers.AllDistributionContexts,
		Comment:      "Exception for leftpad package",
	}
	resp, err := server.CreatePackageException(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Check the policy again to make sure the package exception was added, and there is still only one package policy.
	policyResp, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repositoryID})
	require.NoError(t, err)
	require.NotNil(t, policyResp)
	require.Len(t, policyResp.Policy.Packages, 1)
	pkgPolicy := policyResp.Policy.Packages[0]
	assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, pkgPolicy.PackageManager)
	assert.Equal(t, "leftpad", pkgPolicy.Name)
	assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
	assert.Equal(t, "Exception created via API", pkgPolicy.Reason)
	assert.Equal(t, []string{"MIT"}, pkgPolicy.ExtraAllowedSpdxIds)

	// Check that the alert is now marked as resolved.
	alertAfter, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alertAfter)
	require.NotNil(t, alertAfter.Resolution)
	require.Equal(t, models.AlertResolutionExceptionAdded, alertAfter.Resolution)
	require.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Check that 2 alert events were created
	events, err := server.app.Subsystems.Storage.GetAlertEvents(t.Context(), alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	// One event for adding the exception
	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, uint64(1), *events[0].UserID)
	var eventBody map[string]string
	err = json.Unmarshal(events[0].EventBody, &eventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", eventBody["package_manager"])
	assert.Equal(t, "leftpad", eventBody["package_name"])
	assert.Equal(t, "repository", eventBody["level"])

	// One event for the closing the alert.
	assert.Equal(t, models.EventClosed, events[1].EventType)
	assert.Equal(t, uint64(1), *events[1].UserID)
	err = json.Unmarshal(events[1].EventBody, &eventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", eventBody["package_manager"])
	assert.Equal(t, "leftpad", eventBody["package_name"])
	assert.Equal(t, "repository", eventBody["level"])
}

func TestCreatePackageException_OrgLevel(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)
	orgID := uint64(42)

	// Only GPL-2.0 is allowed by the policy.
	_, err := server.CreateOrganizationPolicy(t.Context(), &proto.CreateOrganizationPolicyRequest{
		OrganizationId: orgID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	// Create an alert for a package with an MIT license, which is not allowed.
	_, err = server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	})
	require.NoError(t, err)

	alert, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alert)
	require.Equal(t, "lodash", alert.PackageName)
	require.Equal(t, "MIT", alert.SPDXLicenseExpression)
	require.Equal(t, models.AlertStatusOpen, alert.Status)

	req := &proto.CreatePackageExceptionRequest{
		RepositoryId:   repositoryID,
		OrganizationId: orgID,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
		UserId:         1,
		AlertNumber:    1,
		Contexts:       testhelpers.AllDistributionContexts,
		Comment:        "It makes sense to add this package exception",
	}
	resp, err := server.CreatePackageException(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Check the policy again to make sure the package exception was added.
	policyResp, err := server.GetOrganizationPolicy(t.Context(), &proto.GetOrganizationPolicyRequest{OrganizationId: orgID})
	require.NoError(t, err)
	require.NotNil(t, policyResp)
	require.Len(t, policyResp.Policy.DistributionPolicies, 3)
	for _, dp := range policyResp.Policy.DistributionPolicies {
		require.Len(t, dp.Packages, 1)
		pkgPolicy := dp.Packages[0]
		assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, pkgPolicy.PackageManager)
		assert.Equal(t, "lodash", pkgPolicy.Name)
		assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
		assert.Equal(t, "Exception created via API", pkgPolicy.Reason)
		assert.ElementsMatch(t, []string{"MIT"}, pkgPolicy.ExtraAllowedSpdxIds)
	}

	// Check that the alert is now marked as resolved.
	alertAfter, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alertAfter)
	require.NotNil(t, alertAfter.Resolution)
	require.Equal(t, models.AlertResolutionExceptionAdded, alertAfter.Resolution)
	require.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Check that 2 alert events were created
	events, err := server.app.Subsystems.Storage.GetAlertEvents(t.Context(), alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	// One event for adding the exception
	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, uint64(1), *events[0].UserID)
	var eventBody map[string]string
	err = json.Unmarshal(events[0].EventBody, &eventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", eventBody["package_manager"])
	assert.Equal(t, "lodash", eventBody["package_name"])
	assert.Equal(t, "organization", eventBody["level"])

	// One event for the closing the alert.
	assert.Equal(t, models.EventClosed, events[1].EventType)
	assert.Equal(t, uint64(1), *events[1].UserID)
	err = json.Unmarshal(events[1].EventBody, &eventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", eventBody["package_manager"])
	assert.Equal(t, "lodash", eventBody["package_name"])
	assert.Equal(t, "organization", eventBody["level"])
}

func TestCreatePackageException_OrgLevel_DuplicatePolicy(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)
	orgID := uint64(42)

	// Only GPL-2.0 is allowed by the policy.
	_, err := server.CreateOrganizationPolicy(t.Context(), &proto.CreateOrganizationPolicyRequest{
		OrganizationId: orgID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
		Packages: []*proto.PackagePolicy{
			{
				PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:                "leftpad",
				Action:              proto.PackageAction_PACKAGE_ACTION_BLOCKED,
				Reason:              "This package is bad",
				ExtraAllowedSpdxIds: []string{"MIT"},
				Contexts:            testhelpers.AllDistributionContexts,
			},
		},
	})
	require.NoError(t, err)

	// Create an alert for a package with an MIT license, which is not allowed.
	_, err = server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "leftpad",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	})
	require.NoError(t, err)

	alert, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alert)
	require.Equal(t, "leftpad", alert.PackageName)
	require.Equal(t, "MIT", alert.SPDXLicenseExpression)
	require.Equal(t, models.AlertStatusOpen, alert.Status)

	req := &proto.CreatePackageExceptionRequest{
		RepositoryId:   repositoryID,
		OrganizationId: orgID,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
		UserId:         1,
		AlertNumber:    1,
		Contexts:       testhelpers.AllDistributionContexts,
		Comment:        "It makes sense to add this package exception",
	}
	resp, err := server.CreatePackageException(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Check the policy again to make sure the package exception was added, and there is still only one package policy.
	policyResp, err := server.GetOrganizationPolicy(t.Context(), &proto.GetOrganizationPolicyRequest{OrganizationId: orgID})
	require.NoError(t, err)
	require.NotNil(t, policyResp)
	require.Len(t, policyResp.Policy.DistributionPolicies, 3)
	for _, dp := range policyResp.Policy.DistributionPolicies {
		require.Len(t, dp.Packages, 1)
		pkgPolicy := dp.Packages[0]
		assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, pkgPolicy.PackageManager)
		assert.Equal(t, "leftpad", pkgPolicy.Name)
		assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
		assert.Equal(t, "Exception created via API", pkgPolicy.Reason)
		assert.ElementsMatch(t, []string{"MIT"}, pkgPolicy.ExtraAllowedSpdxIds)
	}

	// Check that the alert is now marked as resolved.
	alertAfter, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alertAfter)
	require.NotNil(t, alertAfter.Resolution)
	require.Equal(t, models.AlertResolutionExceptionAdded, alertAfter.Resolution)
	require.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Check that 2 alert events were created
	events, err := server.app.Subsystems.Storage.GetAlertEvents(t.Context(), alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	// One event for adding the exception
	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, uint64(1), *events[0].UserID)
	var eventBody map[string]string
	err = json.Unmarshal(events[0].EventBody, &eventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", eventBody["package_manager"])
	assert.Equal(t, "leftpad", eventBody["package_name"])
	assert.Equal(t, "organization", eventBody["level"])

	// One event for the closing the alert.
	assert.Equal(t, models.EventClosed, events[1].EventType)
	assert.Equal(t, uint64(1), *events[1].UserID)
	err = json.Unmarshal(events[1].EventBody, &eventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", eventBody["package_manager"])
	assert.Equal(t, "leftpad", eventBody["package_name"])
	assert.Equal(t, "organization", eventBody["level"])
}

func TestCreatePackageException_EnterpriseLevel(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)

	// Only GPL-2.0 is allowed by the policy.
	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	// Create an alert for a package with an MIT license, which is not allowed.
	entIDPtr := entID
	_, err = server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entIDPtr,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	})
	require.NoError(t, err)

	alert, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alert)
	require.Equal(t, "lodash", alert.PackageName)
	require.Equal(t, "MIT", alert.SPDXLicenseExpression)
	require.Equal(t, models.AlertStatusOpen, alert.Status)

	req := &proto.CreatePackageExceptionRequest{
		RepositoryId:   repositoryID,
		OrganizationId: orgID,
		EnterpriseId:   entID,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
		UserId:         1,
		AlertNumber:    1,
		Contexts:       testhelpers.AllDistributionContexts,
		Comment:        "It makes sense to add this package exception",
	}
	resp, err := server.CreatePackageException(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Check the policy again to make sure the package exception was added.
	policyResp, err := server.GetEnterprisePolicy(t.Context(), &proto.GetEnterprisePolicyRequest{EnterpriseId: entID})
	require.NoError(t, err)
	require.NotNil(t, policyResp)
	require.Len(t, policyResp.Policy.DistributionPolicies, 3)
	for _, dp := range policyResp.Policy.DistributionPolicies {
		require.Len(t, dp.Packages, 1)
		pkgPolicy := dp.Packages[0]
		assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, pkgPolicy.PackageManager)
		assert.Equal(t, "lodash", pkgPolicy.Name)
		assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
		assert.Equal(t, "Exception created via API", pkgPolicy.Reason)
		assert.ElementsMatch(t, []string{"MIT"}, pkgPolicy.ExtraAllowedSpdxIds)
	}

	// Check that the alert is now marked as resolved.
	alertAfter, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alertAfter)
	require.NotNil(t, alertAfter.Resolution)
	require.Equal(t, models.AlertResolutionExceptionAdded, alertAfter.Resolution)
	require.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Check that 2 alert events were created
	events, err := server.app.Subsystems.Storage.GetAlertEvents(t.Context(), alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	// One event for adding the exception
	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, uint64(1), *events[0].UserID)
	var eventBody map[string]string
	err = json.Unmarshal(events[0].EventBody, &eventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", eventBody["package_manager"])
	assert.Equal(t, "lodash", eventBody["package_name"])
	assert.Equal(t, "enterprise", eventBody["level"])

	// One event for the closing the alert.
	assert.Equal(t, models.EventClosed, events[1].EventType)
	assert.Equal(t, uint64(1), *events[1].UserID)
	err = json.Unmarshal(events[1].EventBody, &eventBody)
	require.NoError(t, err)
	assert.Equal(t, "npm", eventBody["package_manager"])
	assert.Equal(t, "lodash", eventBody["package_name"])
	assert.Equal(t, "enterprise", eventBody["level"])
}

func TestWildcardValidation(t *testing.T) {
	testCases := []struct {
		name        string
		pattern     string
		packageName string
		wantErr     bool
		errContains string
	}{
		{
			name:        "valid pattern with wildcard at end",
			pattern:     "my-*",
			packageName: "my-package",
			wantErr:     false,
		},
		{
			name:        "valid pattern with wildcard at beginning",
			pattern:     "*-lib",
			packageName: "test-lib",
			wantErr:     false,
		},
		{
			name:        "valid pattern with wildcard in middle",
			pattern:     "my-*-lib",
			packageName: "my-test-lib",
			wantErr:     false,
		},
		{
			name:        "valid pattern with minimum length",
			pattern:     "a*b",
			packageName: "axb",
			wantErr:     false,
		},
		{
			name:        "invalid pattern with multiple wildcards",
			pattern:     "my-*-*",
			packageName: "my-test-lib",
			wantErr:     true,
			errContains: "only one wildcard '*' is allowed",
		},
		{
			name:        "invalid pattern with three wildcards",
			pattern:     "*-*-*",
			packageName: "a-b-c",
			wantErr:     true,
			errContains: "only one wildcard '*' is allowed",
		},
		{
			name:        "invalid pattern too short - empty",
			pattern:     "",
			packageName: "package",
			wantErr:     true,
			errContains: "must have at least two non-wildcard characters",
		},
		{
			name:        "invalid pattern too short - one character",
			pattern:     "a",
			packageName: "package",
			wantErr:     true,
			errContains: "must have at least two non-wildcard characters",
		},
		{
			name:        "invalid pattern too short - two characters",
			pattern:     "ab",
			packageName: "package",
			wantErr:     true,
			errContains: "must have at least two non-wildcard characters",
		},
		{
			name:        "invalid pattern too short - only wildcard",
			pattern:     "*",
			packageName: "package",
			wantErr:     true,
			errContains: "must have at least two non-wildcard characters",
		},
		{
			name:        "invalid pattern too short - wildcard plus one character",
			pattern:     "*a",
			packageName: "package",
			wantErr:     true,
			errContains: "must have at least two non-wildcard characters",
		},
		{
			name:        "invalid pattern too short - one character plus wildcard",
			pattern:     "a*",
			packageName: "package",
			wantErr:     true,
			errContains: "must have at least two non-wildcard characters",
		},
		// Pattern matching tests
		{
			name:        "pattern matches - prefix wildcard",
			pattern:     "*-utils",
			packageName: "my-utils",
			wantErr:     false,
		},
		{
			name:        "pattern matches - suffix wildcard",
			pattern:     "lodash-*",
			packageName: "lodash-core",
			wantErr:     false,
		},
		{
			name:        "pattern matches - middle wildcard",
			pattern:     "react-*-plugin",
			packageName: "react-router-plugin",
			wantErr:     false,
		},
		{
			name:        "pattern matches - exact match with wildcard",
			pattern:     "test*ing",
			packageName: "testing",
			wantErr:     false,
		},
		{
			name:        "pattern matches - longer middle section",
			pattern:     "@scope/*-lib",
			packageName: "@scope/my-awesome-lib",
			wantErr:     false,
		},
		{
			name:        "pattern does not match - wrong prefix",
			pattern:     "react-*",
			packageName: "vue-component",
			wantErr:     true,
			errContains: "does not match package name",
		},
		{
			name:        "pattern does not match - wrong suffix",
			pattern:     "*-utils",
			packageName: "my-helpers",
			wantErr:     true,
			errContains: "does not match package name",
		},
		{
			name:        "pattern does not match - missing prefix",
			pattern:     "prefix-*",
			packageName: "fix-something",
			wantErr:     true,
			errContains: "does not match package name",
		},
		{
			name:        "pattern does not match - missing suffix",
			pattern:     "*-suffix",
			packageName: "something-suf",
			wantErr:     true,
			errContains: "does not match package name",
		},
		{
			name:        "pattern does not match - partial prefix match",
			pattern:     "test-*",
			packageName: "tes-package",
			wantErr:     true,
			errContains: "does not match package name",
		},
		{
			name:        "pattern does not match - partial suffix match",
			pattern:     "*-test",
			packageName: "package-tes",
			wantErr:     true,
			errContains: "does not match package name",
		},
		{
			name:        "pattern matches - empty wildcard section",
			pattern:     "pre*fix",
			packageName: "prefix",
			wantErr:     false,
		},
		{
			name:        "pattern matches - complex real-world example",
			pattern:     "@types/*",
			packageName: "@types/node",
			wantErr:     false,
		},
		{
			name:        "no wildcard - exact match",
			pattern:     "express",
			packageName: "express",
			wantErr:     false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateWildcardForPackageException(tc.pattern, tc.packageName)

			if tc.wantErr {
				require.Error(t, err)
				if tc.errContains != "" {
					assert.Contains(t, err.Error(), tc.errContains)
				}
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestCreatePackageException_Pattern(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)

	// Creating an alert, despite not having an actual policy to violate
	_, err := server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "my-awesome-lib",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	})
	require.NoError(t, err)

	req := &proto.CreatePackageExceptionRequest{
		RepositoryId: repositoryID,
		PolicyLevel:  proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		UserId:       1,
		AlertNumber:  1,
		Action:       proto.PackageAction_PACKAGE_ACTION_PRIVATE,
		Pattern:      "my-*",
		Comment:      "Want an exception. Please.",
	}
	resp, err := server.CreatePackageException(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Check the policy again to make sure the package exception was added.
	policyResp, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repositoryID})
	require.NoError(t, err)
	require.NotNil(t, policyResp)
	require.Len(t, policyResp.Policy.Packages, 1)
	pkgPolicy := policyResp.Policy.Packages[0]
	assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, pkgPolicy.PackageManager)
	assert.Equal(t, "my-*", pkgPolicy.Name)
	assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_PRIVATE, pkgPolicy.Action)
	assert.Equal(t, "Exception created via API", pkgPolicy.Reason)
	assert.Equal(t, []string{"MIT"}, pkgPolicy.ExtraAllowedSpdxIds)
}

func TestCreatePackageException_BadPattern(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)

	// Creating an alert, despite not having an actual policy to violate
	_, err := server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "my-awesome-lib",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	})
	require.NoError(t, err)

	req := &proto.CreatePackageExceptionRequest{
		RepositoryId: repositoryID,
		PolicyLevel:  proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		UserId:       1,
		AlertNumber:  1,
		Action:       proto.PackageAction_PACKAGE_ACTION_PRIVATE,
		Pattern:      "*-awesome-*", // Invalid: multiple wildcards
		Contexts:     testhelpers.AllDistributionContexts,
		Comment:      "Want an exception. Please.",
	}
	resp, err := server.CreatePackageException(t.Context(), req)
	require.Error(t, err)
	assert.Equal(t, "twirp error invalid_argument: pattern invalid pattern \"*-awesome-*\": only one wildcard '*' is allowed", err.Error())
	assert.Nil(t, resp)

	// Check the policy again to make sure the package exception was not added.
	policyResp, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repositoryID})
	require.Error(t, err)
	require.Nil(t, policyResp)
}

// TestCreatePackageException_NoPolicy tests that creating a package exception
// for a package when there is no existing policy at the specified level returns success.
func TestCreatePackageException_NoPolicy(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)

	// Creating an alert, despite not having an actual policy to violate
	_, err := server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	})
	require.NoError(t, err)

	policyLevels := []proto.PolicyLevel{
		proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
		proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
	}

	for _, level := range policyLevels {
		t.Run(level.String(), func(t *testing.T) {
			req := &proto.CreatePackageExceptionRequest{
				RepositoryId:   repositoryID,
				OrganizationId: orgID,
				EnterpriseId:   entID,
				PolicyLevel:    level,
				UserId:         1,
				AlertNumber:    1,
				Contexts:       testhelpers.AllDistributionContexts,
				Comment:        "It makes sense to add this package exception",
			}
			resp, err := server.CreatePackageException(t.Context(), req)
			require.NoError(t, err)
			require.NotNil(t, resp)
		})
	}
}

func TestCreatePackageException_NoAlert(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)

	// Only GPL-2.0 is allowed by the policy.
	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	policyLevels := []proto.PolicyLevel{
		proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
		proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
	}

	for _, level := range policyLevels {
		t.Run(level.String(), func(t *testing.T) {
			req := &proto.CreatePackageExceptionRequest{
				RepositoryId:   repositoryID,
				OrganizationId: orgID,
				EnterpriseId:   entID,
				PolicyLevel:    level,
				UserId:         1,
				AlertNumber:    1, // There is no alert with this number
				Contexts:       testhelpers.AllDistributionContexts,
				Comment:        "It makes sense to add this package exception",
			}
			resp, err := server.CreatePackageException(t.Context(), req)
			require.Error(t, err)
			require.Nil(t, resp)
			assert.Equal(t, twirp.NotFoundError("alert not found"), err)
		})
	}
}

func TestAddLicensesForAlert(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)

	_, err := server.app.Subsystems.Storage.CreateRepositoryPolicy(t.Context(), &proto.RepositoryPolicy{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	_, err = server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	})
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId: repositoryID,
		AlertNumber:  1,
		UserId:       1,
		PolicyLevel:  proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		Contexts:     testhelpers.AllDistributionContexts,
		Comment:      "It makes sense to add this package exception",
	}
	_, err = server.AddLicensesForAlert(t.Context(), req)
	require.NoError(t, err)

	policy, err := server.app.Subsystems.Storage.GetRepositoryPolicyByRepoID(t.Context(), repositoryID)
	require.NoError(t, err)
	licenses := policy.Licenses
	require.Len(t, licenses.Allowed, 2)

	licenseIDs := []string{}
	for _, license := range licenses.Allowed {
		licenseIDs = append(licenseIDs, license.SpdxId)
	}
	assert.ElementsMatch(t, []string{"MIT", "GPL-3.0"}, licenseIDs)

	alertAfter, err := server.app.Subsystems.Storage.GetAlert(t.Context(), repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	events, err := server.app.Subsystems.Storage.GetAlertEvents(t.Context(), alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	assert.Equal(t, models.EventLicensesAdded, events[0].EventType)
	assert.Equal(t, req.UserId, *events[0].UserID)
	var licensesEventBody models.LicensesAddedEventBody
	err = json.Unmarshal(events[0].EventBody, &licensesEventBody)
	require.NoError(t, err)
	assert.Equal(t, []string{"GPL-3.0"}, licensesEventBody.Licenses)
	assert.NotEmpty(t, licensesEventBody.Level)

	assert.Equal(t, models.EventClosed, events[1].EventType)
	assert.Equal(t, req.UserId, *events[1].UserID)
}

func TestAddLicensesForAlert_InvalidSPDXExpression(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)
	invalidExpression := "MIT AND bad-id"

	_, err := server.app.Subsystems.Storage.CreateRepositoryPolicy(t.Context(), &proto.RepositoryPolicy{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	_, err = server.app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: invalidExpression,
	})
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId: repositoryID,
		AlertNumber:  1,
		UserId:       1,
		PolicyLevel:  proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		Contexts:     testhelpers.AllDistributionContexts,
		Comment:      "It makes sense to add this package exception",
	}
	_, err = server.AddLicensesForAlert(t.Context(), req)
	require.Error(t, err)

	cause := "unknown license 'bad-id' at offset 8"
	twcerrtesting.AssertInvalidSPDXExpressionErr(t, err, twirp.Internal, cause, invalidExpression)
}

func TestAddLicensesForAlert_Validation(t *testing.T) {
	testCases := []struct {
		name          string
		request       *proto.AddLicensesForAlertRequest
		expectedError string
	}{
		{
			name: "missing repository_id",
			request: &proto.AddLicensesForAlertRequest{
				RepositoryId:   0,
				AlertNumber:    1,
				UserId:         1,
				PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
				Contexts:       testhelpers.AllDistributionContexts,
				OrganizationId: 42,
				Comment:        "Adding license exception",
			},
			expectedError: "repository_id",
		},
		{
			name: "missing alert_number",
			request: &proto.AddLicensesForAlertRequest{
				RepositoryId:   123,
				AlertNumber:    0,
				UserId:         1,
				PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
				Contexts:       testhelpers.AllDistributionContexts,
				OrganizationId: 42,
				Comment:        "Adding license exception",
			},
			expectedError: "alert_number",
		},
		{
			name: "missing user_id",
			request: &proto.AddLicensesForAlertRequest{
				RepositoryId:   123,
				AlertNumber:    1,
				UserId:         0,
				PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
				Contexts:       testhelpers.AllDistributionContexts,
				OrganizationId: 42,
				Comment:        "Adding license exception",
			},
			expectedError: "user_id",
		},
		{
			name: "missing policy_level",
			request: &proto.AddLicensesForAlertRequest{
				RepositoryId:   123,
				AlertNumber:    1,
				UserId:         1,
				PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_UNKNOWN,
				Contexts:       testhelpers.AllDistributionContexts,
				OrganizationId: 42,
				Comment:        "Adding license exception",
			},
			expectedError: "policy_level",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			server := newTestServer(t)

			_, err := server.AddLicensesForAlert(t.Context(), tc.request)
			require.Error(t, err)
			var twerr twirp.Error
			require.ErrorAs(t, err, &twerr)
			assert.Equal(t, twirp.InvalidArgument, twerr.Code())
		})
	}
}

func TestAddLicensesForAlert_AlertNotFound(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(123)

	_, err := server.app.Subsystems.Storage.CreateRepositoryPolicy(t.Context(), &proto.RepositoryPolicy{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId: repositoryID,
		AlertNumber:  999, // Non-existent alert
		UserId:       1,
		PolicyLevel:  proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		Contexts:     testhelpers.AllDistributionContexts,
		Comment:      "Adding license exception",
	}

	_, err = server.AddLicensesForAlert(t.Context(), req)
	require.Error(t, err)
	assert.Equal(t, twirp.NotFoundError("alert not found"), err)
}
