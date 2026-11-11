package remediation

import (
	"encoding/json"
	"testing"
	"testing/synctest"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

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

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, comment, uint64(1), nil)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String())

		sameRepoPackageAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertSameRepoPackage.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), sameRepoPackageAlertAfter.Status.String(), "side-effect alert should have been closed")
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

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, comment, 1, nil)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID1, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String())

		sameEnterpriseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertSameEnterprise.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), sameEnterpriseAlertAfter.Status.String(), "side-effect alert should have been closed")
	})
}

func TestCheckAndCloseAffectedAlertsForPackages_PublishesHydroEventForReviewRequestedAlerts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t)
		ctx := t.Context()
		repositoryID := uint64(123)
		orgID := uint64(42)
		entID := uint64(7)
		prNumber := uint32(77)
		userID := uint64(1)

		alertReviewRequested := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
			ManifestName:          "package.json",
			Status:                models.AlertStatusReviewRequested,
			PullRequestNumber:     &prNumber,
		}
		createdAlert, err := app.Subsystems.Storage.CreateAlert(ctx, alertReviewRequested)
		require.NoError(t, err)

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		packagePolicy := &proto.PackagePolicy{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "some-package",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		}

		_, err = app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
			RepositoryId: repositoryID,
			Packages:     []*proto.PackagePolicy{packagePolicy},
		})
		require.NoError(t, err)

		eventBody := models.ExceptionAddedEventBody{
			Level:   models.PolicyLevelToString(proto.PolicyLevel_POLICY_LEVEL_REPOSITORY),
			Comment: "",
		}

		policy, err := app.Subsystems.Storage.GetCompletePolicy(ctx, entID, orgID, repositoryID)
		require.NoError(t, err)

		err = CheckAndCloseAffectedAlertsForPackages(
			ctx,
			app,
			eventBody,
			proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
			packagePolicy,
			policy,
			entID,
			orgID,
			repositoryID,
			&userID,
			nil,
		)
		require.NoError(t, err)

		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String())

		expectedEvent := &dependencygraphv1.LicenseComplianceAlertStatusChanged{
			Alert: &entities.LicenseComplianceAlert{
				AlertId:               int64(alertAfter.ID),
				AlertNumber:           int32(alertAfter.Number),
				CreatedAt:             timestamppb.New(alertAfter.CreatedAt),
				RepositoryId:          int64(repositoryID),
				OrganizationId:        int64(orgID),
				EnterpriseId:          wrapperspb.Int64(int64(entID)),
				PullRequestNumber:     int32(prNumber),
				PullRequestId:         0,
				ManifestName:          "package.json",
				PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "some-package",
				PackageVersion:        "1.0.0",
				SpdxLicenseExpression: "GPL-3.0",
				Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
				ClosureReason:         entities.ClosureReason_CLOSURE_REASON_POLICY_EDITED,
			},
			PreviousStatus: entities.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED,
			UserId:         1,
		}

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
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

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, comment, 1, nil)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID1, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String())

		diffEnterpriseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertDiffEnterprise.Number)
		require.NoError(t, err)
		assert.NotEqual(t, models.AlertStatusClosed.String(), diffEnterpriseAlertAfter.Status.String(), "alert from other enterprise should not have been closed")
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

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, comment, 1, nil)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID1, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String())

		diffPackageAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertDiffPackage.Number)
		require.NoError(t, err)
		assert.NotEqual(t, models.AlertStatusClosed.String(), diffPackageAlertAfter.Status.String(), "other alert should not have been closed")
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

		err = AddPackagePolicyForAlert(ctx, app, createdAlert, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, comment, 1, nil)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID1, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String())

		sameEnterpriseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertSameEnterprise.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), sameEnterpriseAlertAfter.Status.String(), "side-effect alert should have been closed")
		assert.Equal(t, models.AlertResolutionExceptionAdded.String(), sameEnterpriseAlertAfter.Resolution.String(), "side-effect alert should have been resolved with exception added")
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
		Status:                models.AlertStatusReviewRequested,
	}
	created, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)
	require.Equal(t, models.AlertStatusReviewRequested, created.Status)

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                alert.PackageName,
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:              "Exception approved",
		ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		Contexts:            []string{"distributed"},
	}

	err = AddPackagePolicyForAlert(ctx, app, created, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, comment, uint64(1), nil)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

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
		Status:                models.AlertStatusOpen,
	}
	created, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)
	require.Equal(t, models.AlertStatusOpen, created.Status)

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                alert.PackageName,
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:              "Exception added",
		ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		Contexts:            []string{"distributed"},
	}

	err = AddPackagePolicyForAlert(ctx, app, created, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, comment, uint64(1), nil)
	require.NoError(t, err)

	events, err := app.Subsystems.Storage.GetAlertEvents(ctx, created.ID)
	require.NoError(t, err)
	require.Len(t, events, 2, "expected 2 events: ExceptionAdded, Closed (no ReviewApproved)")

	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, models.EventClosed, events[1].EventType)
}

func TestAddPackagePolicyForAlert_WhenAlertStatusIsReviewRequested_PublishesHydroEvent(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)
	prNumber := uint32(99)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-2.0",
		ManifestName:          "package.json",
		Status:                models.AlertStatusReviewRequested,
		PullRequestNumber:     &prNumber,
	}
	createdAlert, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	// Set up test publisher
	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                alert.PackageName,
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:              "Exception approved",
		ExtraAllowedSpdxIds: []string{"GPL-2.0"},
		Contexts:            []string{"distributed", "internal"},
	}

	err = AddPackagePolicyForAlert(
		ctx,
		app,
		createdAlert,
		packagePolicy,
		[]string{"distributed", "internal"},
		proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		"Approving this package",
		1,
		nil,
	)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Skip the LicensePolicyChanged event that's published first
	tp.SkipMessage(t)

	// Verify LicenseComplianceAlertStatusChanged Hydro event was published
	expectedEvent := &dependencygraphv1.LicenseComplianceAlertStatusChanged{
		Alert: &entities.LicenseComplianceAlert{
			AlertId:               int64(alertAfter.ID),
			AlertNumber:           int32(alertAfter.Number),
			CreatedAt:             timestamppb.New(alertAfter.CreatedAt),
			RepositoryId:          int64(repositoryID),
			OrganizationId:        int64(orgID),
			EnterpriseId:          wrapperspb.Int64(int64(entID)),
			PullRequestNumber:     int32(prNumber),
			PullRequestId:         0,
			ManifestName:          "package.json",
			PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "lodash",
			PackageVersion:        "1.0.0",
			SpdxLicenseExpression: "GPL-2.0",
			Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
		},
		PreviousStatus: entities.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED,
		UserId:         1,
		Comment:        wrapperspb.String("Approving this package"),
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
}

func TestAddPackagePolicyForAlert_WhenAlertStatusIsOpen_PublishesHydroEvent(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)
	prNumber := uint32(99)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "lodash",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-2.0",
		ManifestName:          "package.json",
		Status:                models.AlertStatusOpen,
		PullRequestNumber:     &prNumber,
	}
	createdAlert, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	// Set up test publisher
	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                alert.PackageName,
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		ExtraAllowedSpdxIds: []string{"GPL-2.0"},
		Contexts:            []string{"distributed", "internal"},
	}

	err = AddPackagePolicyForAlert(
		ctx,
		app,
		createdAlert,
		packagePolicy,
		[]string{"distributed", "internal"},
		proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		"adding package exception",
		1,
		nil,
	)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Verify LicensePolicyChanged event is published first
	tp.AssertMessageTopic(t, "github.dependencygraph.v1.LicensePolicyChanged")

	// Verify LicenseComplianceAlertStatusChanged event is published with correct content
	expectedEvent := &dependencygraphv1.LicenseComplianceAlertStatusChanged{
		Alert: &entities.LicenseComplianceAlert{
			AlertId:               int64(alertAfter.ID),
			AlertNumber:           int32(alertAfter.Number),
			CreatedAt:             timestamppb.New(alertAfter.CreatedAt),
			RepositoryId:          int64(repositoryID),
			OrganizationId:        int64(orgID),
			EnterpriseId:          wrapperspb.Int64(int64(entID)),
			PullRequestNumber:     int32(prNumber),
			PullRequestId:         0,
			ManifestName:          "package.json",
			PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "lodash",
			PackageVersion:        "1.0.0",
			SpdxLicenseExpression: "GPL-2.0",
			Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
		},
		PreviousStatus: entities.AlertStatus_ALERT_STATUS_OPEN,
		UserId:         1,
		Comment:        wrapperspb.String("adding package exception"),
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
}
