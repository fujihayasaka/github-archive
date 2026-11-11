package remediation

import (
	"encoding/json"
	"testing"
	"testing/synctest"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAddPackagePolicyForAlert_NewPolicy(t *testing.T) {
	app := newTestApp(t)
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)

	// Creating an alert, despite not having an actual policy to violate
	alert, err := app.Subsystems.Storage.CreateAlert(t.Context(), models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-2.0",
	})
	require.NoError(t, err)

	policyLevels := []proto.PolicyLevel{
		proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION,
		proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE,
	}
	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                "lodash",
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:              "Exception created via API",
		ExtraAllowedSpdxIds: []string{"GPL-2.0"},
		Contexts:            []string{"distributed"},
	}

	for _, level := range policyLevels {
		t.Run(level.String(), func(t *testing.T) {
			err := AddPackagePolicyForAlert(t.Context(),
				app,
				alert,
				packagePolicy,
				[]string{"distributed"},
				level,
				"This is a good package.",
				uint64(27),
			)
			require.NoError(t, err)

			// Verify that the package policy was created
			var storedPolicy *proto.PackagePolicy
			switch level {
			case proto.PolicyLevel_POLICY_LEVEL_REPOSITORY:
				repoPolicy, err := app.Subsystems.Storage.GetRepositoryPolicyByRepoID(t.Context(), repositoryID)
				require.NoError(t, err)
				require.NotNil(t, repoPolicy)
				for _, pp := range repoPolicy.Packages {
					if pp.Name == "lodash" {
						storedPolicy = pp
						break
					}
				}
			case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
				orgPolicy, err := app.Subsystems.Storage.GetOrganizationPolicyByOrgID(t.Context(), orgID)
				require.NoError(t, err)
				require.NotNil(t, orgPolicy)
				for _, pp := range orgPolicy.DistributionPolicies[0].Packages {
					if pp.Name == "lodash" {
						storedPolicy = pp
						break
					}
				}
			case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
				entPolicy, err := app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(t.Context(), entID)
				require.NoError(t, err)
				require.NotNil(t, entPolicy)
				for _, pp := range entPolicy.DistributionPolicies[0].Packages {
					if pp.Name == "lodash" {
						storedPolicy = pp
						break
					}
				}
			}
			require.NotNil(t, storedPolicy)
			require.Equal(t, packagePolicy.Name, storedPolicy.Name)
			require.Equal(t, packagePolicy.Action, storedPolicy.Action)
			require.Equal(t, packagePolicy.Reason, storedPolicy.Reason)
			require.ElementsMatch(t, packagePolicy.ExtraAllowedSpdxIds, storedPolicy.ExtraAllowedSpdxIds)
		})
	}
}

func TestAddPackagesForAlert_RepoPolicyRemediationClosesOtherAlerts(t *testing.T) {
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

		alertSameRepoPackage := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "2.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlertSameRepoPackage, err := app.Subsystems.Storage.CreateAlert(ctx, alertSameRepoPackage)
		require.NoError(t, err)

		packagePolicy := &proto.PackagePolicy{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "some-package",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		}

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, comment, uint64(1))
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), alertAfter.Status.String())

		sameRepoPackageAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertSameRepoPackage.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), sameRepoPackageAlertAfter.Status.String(), "side-effect alert should have been closed")
	})
}

func TestAddPackageForAlert_EnterprisePolicyRemediationClosesOtherAlerts(t *testing.T) {
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

		packagePolicy := &proto.PackagePolicy{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "some-package",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		}

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, comment, 1)
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

func TestAddPackageForAlert_EnterprisePolicyRemediationDoesntTouchAlertsFromOtherEnterprise(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t)
		ctx := t.Context()
		repositoryID1 := uint64(123)
		repositoryID2 := uint64(456)
		orgID1 := uint64(42)
		orgID2 := uint64(99)
		entID := uint64(7)
		entIDOther := uint64(8)
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

		alertDiffEnterpriseDiffRepo := models.Alert{
			RepositoryID:          repositoryID2,
			OrganizationID:        orgID2,
			EnterpriseID:          &entIDOther,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlertDiffEnterprise, err := app.Subsystems.Storage.CreateAlert(ctx, alertDiffEnterpriseDiffRepo)
		require.NoError(t, err)

		packagePolicy := &proto.PackagePolicy{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "some-package",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		}

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, comment, 1)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID1, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), alertAfter.Status.String())

		diffEnterpriseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertDiffEnterprise.Number)
		require.NoError(t, err)
		assert.NotEqual(t, models.Closed.String(), diffEnterpriseAlertAfter.Status.String(), "alert from other enterprise should not have been closed")
	})
}

func TestAddPackageForAlert_EnterprisePolicyRemediationDoesntTouchUnrelatedAlerts(t *testing.T) {
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

		alertDiffPackageDiffRepo := models.Alert{
			RepositoryID:          repositoryID2,
			OrganizationID:        orgID2,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "other-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlertDiffPackage, err := app.Subsystems.Storage.CreateAlert(ctx, alertDiffPackageDiffRepo)
		require.NoError(t, err)

		packagePolicy := &proto.PackagePolicy{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "some-package",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		}

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, comment, 1)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID1, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), alertAfter.Status.String())

		diffPackageAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertDiffPackage.Number)
		require.NoError(t, err)
		assert.NotEqual(t, models.Closed.String(), diffPackageAlertAfter.Status.String(), "other alert should not have been closed")
	})
}

func TestAddPackageForAlert_WildcardPolicy_EnterprisePolicyRemediationClosesOtherAlerts(t *testing.T) {
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

		packagePolicy := &proto.PackagePolicy{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "some-*",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		}

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, comment, 1)
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

func TestAddPackagePolicyForAlert_CreatesReviewApprovedEventWhenReviewRequested(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)
	comment := "approving this package exception"

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
	created, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)
	require.Equal(t, models.ReviewRequested, created.Status)

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                alert.PackageName,
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:              "Exception approved",
		ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		Contexts:            []string{"distributed"},
	}

	err = AddPackagePolicyForAlert(ctx, app, created, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, comment, uint64(1))
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.Closed, alertAfter.Status)

	events, err := app.Subsystems.Storage.GetAlertEvents(ctx, alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 3, "expected 3 events: ReviewApproved, ExceptionAdded, Closed")

	// First event should be ReviewApproved
	assert.Equal(t, models.EventReviewApproved, events[0].EventType)
	assert.Equal(t, uint64(1), *events[0].UserID)
	var reviewApprovedBody models.ReviewApprovedEventBody
	err = json.Unmarshal(events[0].EventBody, &reviewApprovedBody)
	require.NoError(t, err)
	assert.Equal(t, comment, reviewApprovedBody.Comment)

	// Second event should be ExceptionAdded
	assert.Equal(t, models.EventExceptionAdded, events[1].EventType)
	var exceptionBody models.ExceptionAddedEventBody
	err = json.Unmarshal(events[1].EventBody, &exceptionBody)
	require.NoError(t, err)

	// Third event should be Closed
	assert.Equal(t, models.EventClosed, events[2].EventType)
}

func TestAddPackagePolicyForAlert_DoesNotCreateReviewApprovedEventWhenNotReviewRequested(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)
	comment := "adding package exception"

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
	created, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)
	require.Equal(t, models.Open, created.Status)

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                alert.PackageName,
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:              "Exception added",
		ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		Contexts:            []string{"distributed"},
	}

	err = AddPackagePolicyForAlert(ctx, app, created, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, comment, uint64(1))
	require.NoError(t, err)

	events, err := app.Subsystems.Storage.GetAlertEvents(ctx, created.ID)
	require.NoError(t, err)
	require.Len(t, events, 2, "expected 2 events: ExceptionAdded, Closed (no ReviewApproved)")

	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, models.EventClosed, events[1].EventType)
}
