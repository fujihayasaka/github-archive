package remediation

import (
	"encoding/json"
	"testing"
	"testing/synctest"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newTestApp(t *testing.T) *application.Application {
	t.Helper()
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	t.Cleanup(func() {
		err = app.Close()
		if err != nil {
			t.Errorf("failed to close app: %v", err)
		}
	})
	return app
}

func TestApplyLicensesToPolicy_OrganizationLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	orgID := uint64(42)
	repositoryID := uint64(123)

	_, err := app.Subsystems.Storage.CreateOrganizationPolicy(ctx, &proto.OrganizationPolicy{
		OrganizationId: orgID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
			{
				Name: "internal",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
			{
				Name: "network",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
		},
	})
	require.NoError(t, err)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	alertAfterCreate, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		AlertNumber:    1,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		Comment:        "It makes sense to add this package exception",
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req)
	require.NoError(t, err)

	policy, err := app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, orgID)
	require.NoError(t, err)
	require.Len(t, policy.DistributionPolicies, 3)
	licenses := policy.DistributionPolicies[0].Licenses
	require.Len(t, licenses.Allowed, 2)

	licenseIDs := []string{}
	for _, license := range licenses.Allowed {
		licenseIDs = append(licenseIDs, license.SpdxId)
	}
	assert.ElementsMatch(t, []string{"MIT", "GPL-3.0"}, licenseIDs)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.Closed, alertAfter.Status)
}

func TestApplyLicensesToPolicy_EnterpriseLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	orgID := uint64(42)
	entID := uint64(7)
	repositoryID := uint64(123)

	_, err := app.Subsystems.Storage.CreateEnterprisePolicy(ctx, &proto.EnterprisePolicy{
		EnterpriseId: entID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
			{
				Name: "internal",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
			{
				Name: "network",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
					},
				},
			},
		},
	})
	require.NoError(t, err)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	alertAfterCreate, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		AlertNumber:    1,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		EnterpriseId:   entID,
		Comment:        "It makes sense to add this package exception",
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req)
	require.NoError(t, err)

	policy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, entID)
	require.NoError(t, err)
	require.Len(t, policy.DistributionPolicies, 3)
	licenses := policy.DistributionPolicies[0].Licenses
	require.Len(t, licenses.Allowed, 2)

	licenseIDs := []string{}
	for _, license := range licenses.Allowed {
		licenseIDs = append(licenseIDs, license.SpdxId)
	}
	assert.ElementsMatch(t, []string{"MIT", "GPL-3.0"}, licenseIDs)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.Closed, alertAfter.Status)
}

func TestApplyLicensesToPolicy_NoDuplicateLicenses(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)

	_, err := app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts},
				{SpdxId: "GPL-3.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	alert, err := app.Subsystems.Storage.CreateAlert(ctx, models.Alert{
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
		Comment:      "Adding license exception",
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alert, []string{"GPL-3.0"}, req)
	require.NoError(t, err)

	policy, err := app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, repositoryID)
	require.NoError(t, err)

	licenses := policy.GetLicenses()
	require.Len(t, licenses.Allowed, 2)

	licenseIDs := []string{}
	for _, license := range licenses.Allowed {
		licenseIDs = append(licenseIDs, license.SpdxId)
	}
	assert.ElementsMatch(t, []string{"MIT", "GPL-3.0"}, licenseIDs)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.Closed, alertAfter.Status)
}

func TestApplyLicensesToPolicy_CreatesRepositoryPolicy(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	alertAfterCreate, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		AlertNumber:    1,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		Comment:        "Adding license exception",
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req)
	require.NoError(t, err)

	policy, err := app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, repositoryID)
	require.NoError(t, err)
	licenses := policy.Licenses
	require.Len(t, licenses.Allowed, 1)
	assert.Equal(t, "GPL-3.0", licenses.Allowed[0].SpdxId)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.Closed, alertAfter.Status)
}

func TestApplyLicensesToPolicy_CreatesOrganizationPolicy(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	alertAfterCreate, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		AlertNumber:    1,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		Comment:        "Adding license exception",
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req)
	require.NoError(t, err)

	policy, err := app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, orgID)
	require.NoError(t, err)
	require.Len(t, policy.DistributionPolicies, 3)
	licenses := policy.DistributionPolicies[0].Licenses
	require.Len(t, licenses.Allowed, 1)
	assert.Equal(t, "GPL-3.0", licenses.Allowed[0].SpdxId)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.Closed, alertAfter.Status)
}

func TestApplyLicensesToPolicy_CreatesEnterprisePolicy(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	alertAfterCreate, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		AlertNumber:    1,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		EnterpriseId:   entID,
		Comment:        "Adding license exception",
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req)
	require.NoError(t, err)

	policy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, entID)
	require.NoError(t, err)
	require.Len(t, policy.DistributionPolicies, 3)
	licenses := policy.DistributionPolicies[0].Licenses
	require.Len(t, licenses.Allowed, 1)
	assert.Equal(t, "GPL-3.0", licenses.Allowed[0].SpdxId)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.Closed, alertAfter.Status)
}

func TestAddLicensesForAlert_CreatesAlertEvents(t *testing.T) {
	tests := []struct {
		name        string
		policyLevel proto.PolicyLevel
	}{
		{
			name:        "repository level",
			policyLevel: proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		},
		{
			name:        "organization level",
			policyLevel: proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
		},
		{
			name:        "enterprise level",
			policyLevel: proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app := newTestApp(t)
			ctx := t.Context()
			repositoryID := uint64(123)
			orgID := uint64(42)
			entID := uint64(7)
			comment := "an alert comment"

			alert := models.Alert{
				RepositoryID:          repositoryID,
				OrganizationID:        orgID,
				EnterpriseID:          &entID,
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "some-package",
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "GPL-3.0",
				Status:                models.Open,
			}
			_, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
			require.NoError(t, err)

			alertAfterCreate, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
			require.NoError(t, err)
			req := &proto.AddLicensesForAlertRequest{
				RepositoryId:   repositoryID,
				UserId:         1,
				PolicyLevel:    tt.policyLevel,
				Contexts:       testhelpers.AllDistributionContexts,
				OrganizationId: orgID,
				EnterpriseId:   entID,
				Comment:        comment,
			}

			err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req)
			require.NoError(t, err)

			alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
			require.NoError(t, err)
			assert.Equal(t, models.Closed, alertAfter.Status)

			events, err := app.Subsystems.Storage.GetAlertEvents(ctx, alertAfter.ID)
			require.NoError(t, err)
			require.Len(t, events, 2)

			assert.Equal(t, models.EventLicensesAdded, events[0].EventType)
			var licensesEventBody models.LicensesAddedEventBody
			err = json.Unmarshal(events[0].EventBody, &licensesEventBody)
			require.NoError(t, err)
			assert.Equal(t, []string{"GPL-3.0"}, licensesEventBody.Licenses)
			assert.NotEmpty(t, licensesEventBody.Level)
			assert.Equal(t, req.UserId, *events[0].UserID)

			assert.Equal(t, models.EventClosed, events[1].EventType)
		})
	}
}

func TestAddLicensesForAlert_WhenAlertStatusIsReviewRequested_ClosingCreatesReviewApprovedEvent(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)
	comment := "an alert comment"

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
		Status:                models.ReviewRequested,
	}
	_, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	alertAfterCreate, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		EnterpriseId:   entID,
		Comment:        comment,
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)

	assert.Equal(t, models.Closed, alertAfter.Status)

	events, err := app.Subsystems.Storage.GetAlertEvents(ctx, alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 3)

	assert.Equal(t, models.EventReviewApproved, events[0].EventType)
	var reviewApprovedBody models.ReviewApprovedEventBody
	err = json.Unmarshal(events[0].EventBody, &reviewApprovedBody)
	require.NoError(t, err)
	assert.Equal(t, comment, reviewApprovedBody.Comment)
	assert.Equal(t, req.UserId, *events[0].UserID)

	assert.Equal(t, models.EventLicensesAdded, events[1].EventType)
	var licensesEventBody models.LicensesAddedEventBody
	err = json.Unmarshal(events[1].EventBody, &licensesEventBody)
	require.NoError(t, err)
	assert.Equal(t, []string{"GPL-3.0"}, licensesEventBody.Licenses)
	assert.NotEmpty(t, licensesEventBody.Level)
	assert.Equal(t, req.UserId, *events[1].UserID)

	assert.Equal(t, models.EventClosed, events[2].EventType)
}

func TestAddLicensesForAlert_RepoPolicyRemediationClosesOtherAlerts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t)
		ctx := t.Context()
		repositoryID := uint64(123)
		orgID := uint64(42)
		entID := uint64(7)
		comment := "an alert comment"

		alertForRequest := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlert, err := app.Subsystems.Storage.CreateAlert(ctx, alertForRequest)
		require.NoError(t, err)

		alertSameRepoLicense := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlertSameRepoLicense, err := app.Subsystems.Storage.CreateAlert(ctx, alertSameRepoLicense)
		require.NoError(t, err)

		req := &proto.AddLicensesForAlertRequest{
			RepositoryId:   repositoryID,
			UserId:         1,
			PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
			Contexts:       testhelpers.AllDistributionContexts,
			OrganizationId: orgID,
			EnterpriseId:   entID,
			Comment:        comment,
		}
		err = AddLicensesToPolicyForAlert(ctx, app, createdAlert, []string{"GPL-3.0"}, req)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), alertAfter.Status.String())

		sameRepoLicenseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertSameRepoLicense.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), sameRepoLicenseAlertAfter.Status.String(), "side-effect alert should have been closed")
	})
}

func TestAddLicensesForAlert_EnterprisePolicyRemediationClosesOtherAlerts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t)
		ctx := t.Context()
		repositoryID1 := uint64(123)
		repositoryID2 := uint64(456)
		orgID1 := uint64(42)
		orgID2 := uint64(99)
		entID := uint64(7)
		comment := "an alert comment"

		alertForRequest := models.Alert{
			RepositoryID:          repositoryID1,
			OrganizationID:        orgID1,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlert, err := app.Subsystems.Storage.CreateAlert(ctx, alertForRequest)
		require.NoError(t, err)

		alertSameEnterpriseDiffRepo := models.Alert{
			RepositoryID:          repositoryID2,
			OrganizationID:        orgID2,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlertSameEnterprise, err := app.Subsystems.Storage.CreateAlert(ctx, alertSameEnterpriseDiffRepo)
		require.NoError(t, err)

		req := &proto.AddLicensesForAlertRequest{
			RepositoryId:   repositoryID1,
			UserId:         1,
			PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
			Contexts:       testhelpers.AllDistributionContexts,
			OrganizationId: orgID1,
			EnterpriseId:   entID,
			Comment:        comment,
		}
		err = AddLicensesToPolicyForAlert(ctx, app, createdAlert, []string{"GPL-3.0"}, req)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID1, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), alertAfter.Status.String())

		sameEnterpriseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertSameEnterprise.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), sameEnterpriseAlertAfter.Status.String(), "side-effect alert should have been closed")
	})
}

func TestAddLicensesForAlert_SideEffectAlertsAreClosed(t *testing.T) {
	tests := []struct {
		name        string
		policyLevel proto.PolicyLevel
	}{
		{
			name:        "repository level",
			policyLevel: proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		},
		{
			name:        "enterprise level",
			policyLevel: proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				app := newTestApp(t)
				ctx := t.Context()
				repositoryID := uint64(123)
				orgID := uint64(42)
				entID := uint64(7)

				alertForRequest := models.Alert{
					RepositoryID:          repositoryID,
					OrganizationID:        orgID,
					EnterpriseID:          &entID,
					PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
					PackageName:           "some-package",
					PackageVersion:        "1.0.0",
					SPDXLicenseExpression: "GPL-3.0",
				}
				createdAlert, err := app.Subsystems.Storage.CreateAlert(ctx, alertForRequest)
				require.NoError(t, err)

				alertSideEffect := models.Alert{
					RepositoryID:          repositoryID,
					OrganizationID:        orgID,
					EnterpriseID:          &entID,
					PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
					PackageName:           "some-package",
					PackageVersion:        "1.0.0",
					SPDXLicenseExpression: "GPL-3.0",
				}
				createdAlertSideEffect, err := app.Subsystems.Storage.CreateAlert(ctx, alertSideEffect)
				require.NoError(t, err)

				req := &proto.AddLicensesForAlertRequest{
					RepositoryId:   repositoryID,
					UserId:         1,
					PolicyLevel:    tt.policyLevel,
					Contexts:       testhelpers.AllDistributionContexts,
					OrganizationId: orgID,
					EnterpriseId:   entID,
					Comment:        "an alert comment",
				}
				err = AddLicensesToPolicyForAlert(ctx, app, createdAlert, []string{"GPL-3.0"}, req)
				require.NoError(t, err)

				// Wait for async side-effect alert closures to complete
				synctest.Wait()

				alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
				require.NoError(t, err)
				assert.Equal(t, models.Closed, alertAfter.Status, "original alert should be closed")

				sideEffectAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertSideEffect.Number)
				require.NoError(t, err)
				assert.Equal(t, models.Closed, sideEffectAlertAfter.Status, "side-effect alert should be closed")
			})
		})
	}
}

func TestCheckAndCloseAffectedAlertsForLicenses_RepositoryLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)

	alertSameRepoLicense := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	createdAlertSameRepoLicense, err := app.Subsystems.Storage.CreateAlert(ctx, alertSameRepoLicense)
	require.NoError(t, err)

	alertDifferentLicenseExpression := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0 AND MIT",
	}
	createdAlertDiffLicense, err := app.Subsystems.Storage.CreateAlert(ctx, alertDifferentLicenseExpression)
	require.NoError(t, err)

	alertAnotherRepo := models.Alert{
		RepositoryID:          repositoryID + 1,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	createdAlertAnotherRepo, err := app.Subsystems.Storage.CreateAlert(ctx, alertAnotherRepo)
	require.NoError(t, err)

	// Create repository policy with GPL-3.0
	_, err = app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-3.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		EnterpriseId:   entID,
	}

	eventBodyPayload := models.LicensesAddedEventBody{
		Licenses: []string{"GPL-3.0"},
		Level:    models.PolicyLevelToString(req.PolicyLevel),
		Comment:  "",
	}

	err = CheckAndCloseAffectedAlertsForLicenses(
		ctx,
		app,
		eventBodyPayload,
		req.PolicyLevel,
		entID,
		orgID,
		repositoryID,
		&req.UserId,
	)
	require.NoError(t, err)

	sameRepoLicenseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertSameRepoLicense.Number)
	require.NoError(t, err)
	assert.Equal(t, models.Closed.String(), sameRepoLicenseAlertAfter.Status.String(), "alert with same license should have been closed")

	diffLicenseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertDiffLicense.Number)
	require.NoError(t, err)
	assert.Equal(t, models.Open.String(), diffLicenseAlertAfter.Status.String(), "alert with different license should remain open")

	anotherRepoAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, alertAnotherRepo.RepositoryID, createdAlertAnotherRepo.Number)
	require.NoError(t, err)
	assert.Equal(t, models.Open.String(), anotherRepoAlertAfter.Status.String())
}

func TestCheckAndCloseAffectedAlertsForLicenses_EnterpriseLevel(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID1 := uint64(123)
	repositoryID2 := uint64(456)
	repositoryID3 := uint64(789)
	repositoryID4 := uint64(999)
	orgID1 := uint64(42)
	orgID2 := uint64(99)
	entID := uint64(7)

	alertSameEnterpriseDiffRepo := models.Alert{
		RepositoryID:          repositoryID2,
		OrganizationID:        orgID2,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	createdAlertSameEnterprise, err := app.Subsystems.Storage.CreateAlert(ctx, alertSameEnterpriseDiffRepo)
	require.NoError(t, err)

	alertDifferentLicenseExpression := models.Alert{
		RepositoryID:          repositoryID3,
		OrganizationID:        orgID1,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0 AND MIT",
	}
	createdAlertDiffLicense, err := app.Subsystems.Storage.CreateAlert(ctx, alertDifferentLicenseExpression)
	require.NoError(t, err)

	anotherEntID := uint64(8)
	alertAnotherEnterprise := models.Alert{
		RepositoryID:          repositoryID4,
		OrganizationID:        orgID1,
		EnterpriseID:          &anotherEntID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
	}
	createdAlertAnotherEnt, err := app.Subsystems.Storage.CreateAlert(ctx, alertAnotherEnterprise)
	require.NoError(t, err)

	// Create enterprise policy with GPL-3.0
	_, err = app.Subsystems.Storage.CreateEnterprisePolicy(ctx, &proto.EnterprisePolicy{
		EnterpriseId: entID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "GPL-3.0"},
					},
				},
			},
		},
	})
	require.NoError(t, err)
	policyLevel := proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE

	eventBodyPayload := models.LicensesAddedEventBody{
		Licenses: []string{"GPL-3.0"},
		Level:    models.PolicyLevelToString(policyLevel),
		Comment:  "",
	}

	userID := uint64(1)

	err = CheckAndCloseAffectedAlertsForLicenses(
		ctx,
		app,
		eventBodyPayload,
		policyLevel,
		entID,
		orgID1,
		repositoryID1,
		&userID,
	)
	require.NoError(t, err)

	sameEnterpriseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertSameEnterprise.Number)
	require.NoError(t, err)
	assert.Equal(t, models.Closed.String(), sameEnterpriseAlertAfter.Status.String(), "alert in same enterprise should have been closed")

	diffLicenseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID3, createdAlertDiffLicense.Number)
	require.NoError(t, err)
	assert.Equal(t, models.Open.String(), diffLicenseAlertAfter.Status.String(), "alert with different license should remain open")

	anotherEntAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID4, createdAlertAnotherEnt.Number)
	require.NoError(t, err)
	assert.Equal(t, models.Open.String(), anotherEntAlertAfter.Status.String(), "alert in different enterprise should remain open")
}
