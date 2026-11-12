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

	err = CheckAndCloseAffectedAlertsForPackages(
		ctx,
		app,
		eventBody,
		proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		packagePolicy,
		entID,
		orgID,
		repositoryID,
		&userID,
		nil,
	)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String())

	// Verify side-effect alert gets ExceptionAdded and Closed events
	events, err := app.Subsystems.Storage.GetAlertEvents(ctx, alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)
	assert.Equal(t, models.EventExceptionAdded, events[0].EventType)
	assert.Equal(t, uint64(1), *events[0].UserID, "ExceptionAdded uses remediator's user ID")
	assert.Equal(t, models.EventClosed, events[1].EventType)
	assert.Nil(t, events[1].UserID, "side-effect Closed uses bot user (nil)")

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
		UserId:         0, // side-effect closures use bot user (nil)
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
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
	requestorUserID := uint64(100)
	approverUserID := uint64(1)

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

	// Create the review_requested event with the requestor's user ID
	err = app.Subsystems.Storage.CreateAlertEvent(ctx, models.AlertEvent{
		AlertID:   created.ID,
		EventType: models.EventReviewRequested,
		UserID:    &requestorUserID,
		EventBody: []byte(`{"comment":"please approve"}`),
	})
	require.NoError(t, err)

	packagePolicy := &proto.PackagePolicy{
		PackageManager:      alert.PackageEcosystem,
		Name:                alert.PackageName,
		Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:              "Exception approved",
		ExtraAllowedSpdxIds: []string{"GPL-3.0"},
		Contexts:            []string{"distributed"},
	}

	err = AddPackagePolicyForAlert(ctx, app, created, packagePolicy, []string{"distributed"}, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, comment, approverUserID, nil)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	events, err := app.Subsystems.Storage.GetAlertEvents(ctx, alertAfter.ID)
	require.NoError(t, err)
	require.Len(t, events, 4, "expected 4 events: ReviewRequested, ReviewApproved, ExceptionAdded, Closed")

	// Event 0: review_requested (from setup)
	assert.Equal(t, models.EventReviewRequested, events[0].EventType)
	assert.Equal(t, requestorUserID, *events[0].UserID)

	// Event 1: ReviewApproved (approver)
	assert.Equal(t, models.EventReviewApproved, events[1].EventType)
	assert.Equal(t, approverUserID, *events[1].UserID)
	var reviewApprovedBody models.ReviewApprovedEventBody
	err = json.Unmarshal(events[1].EventBody, &reviewApprovedBody)
	require.NoError(t, err)
	assert.Equal(t, comment, reviewApprovedBody.Comment)

	// Event 2: ExceptionAdded (approver)
	assert.Equal(t, models.EventExceptionAdded, events[2].EventType)
	assert.Equal(t, approverUserID, *events[2].UserID)
	var exceptionBody models.ExceptionAddedEventBody
	err = json.Unmarshal(events[2].EventBody, &exceptionBody)
	require.NoError(t, err)

	// Event 3: Closed (should be requestor, not approver!)
	assert.Equal(t, models.EventClosed, events[3].EventType)
	assert.Equal(t, requestorUserID, *events[3].UserID, "close event should use the requestor's user ID, not the approver's")
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
	requestorUserID := uint64(100)
	approverUserID := uint64(1)

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

	// Create the review_requested event with the requestor's user ID
	err = app.Subsystems.Storage.CreateAlertEvent(ctx, models.AlertEvent{
		AlertID:   createdAlert.ID,
		EventType: models.EventReviewRequested,
		UserID:    &requestorUserID,
		EventBody: []byte(`{"comment":"please approve"}`),
	})
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
		approverUserID,
		nil,
	)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Skip the LicensePolicyChanged event to show that the policy was created
	tp.SkipMessage(t)
	// Skip the LicensePolicyChanged event to show that the package was added
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
		UserId:         int64(approverUserID), // Should be approver because it is used to show the approving user
		Comment:        wrapperspb.String("Approving this package"),
		ClosureUserId:  wrapperspb.Int64(int64(requestorUserID)), // Closure user should be the requestor, not the approver
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

	// Verify LicensePolicyChanged event is published first for policy creation
	tp.AssertMessageTopic(t, "github.dependencygraph.v1.LicensePolicyChanged")
	// and another for package addition
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
		ClosureUserId:  wrapperspb.Int64(1),
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
}
