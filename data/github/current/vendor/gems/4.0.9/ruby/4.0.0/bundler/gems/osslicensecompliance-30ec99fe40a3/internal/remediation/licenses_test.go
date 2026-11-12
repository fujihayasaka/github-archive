package remediation

import (
	"encoding/json"
	"testing"
	"testing/synctest"
	"time"

	"github.com/github/github-telemetry-go/log"
	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
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
				Status:                models.AlertStatusOpen,
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
				ClosureReason:  proto.ClosureReason_CLOSURE_REASON_PRIVATE_PACKAGE,
			}

			err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req, models.ClosureReasonFromProto(req.ClosureReason))
			require.NoError(t, err)

			alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
			require.NoError(t, err)
			assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)
			require.NotNil(t, alertAfter.ClosureReason)
			assert.Equal(t, "private_package", *alertAfter.ClosureReason)

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
			var closeEventBody models.CloseAlertEventBody
			err = json.Unmarshal(events[1].EventBody, &closeEventBody)
			require.NoError(t, err)
			assert.Equal(t, comment, closeEventBody.Comment)
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
		Status:                models.AlertStatusReviewRequested,
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

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req, nil)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)

	assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

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
		err = AddLicensesToPolicyForAlert(ctx, app, createdAlert, []string{"GPL-3.0"}, req, nil)
		require.NoError(t, err)

		// Wait for async side-effect alert closures to complete
		synctest.Wait()

		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String())

		sameRepoLicenseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertSameRepoLicense.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), sameRepoLicenseAlertAfter.Status.String(), "side-effect alert should have been closed")
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
		err = AddLicensesToPolicyForAlert(ctx, app, createdAlert, []string{"GPL-3.0"}, req, nil)
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
				err = AddLicensesToPolicyForAlert(ctx, app, createdAlert, []string{"GPL-3.0"}, req, nil)
				require.NoError(t, err)

				// Wait for async side-effect alert closures to complete
				synctest.Wait()

				alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
				require.NoError(t, err)
				assert.Equal(t, models.AlertStatusClosed, alertAfter.Status, "original alert should be closed")

				sideEffectAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertSideEffect.Number)
				require.NoError(t, err)
				assert.Equal(t, models.AlertStatusClosed, sideEffectAlertAfter.Status, "side-effect alert should be closed")
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
		nil, // No original alert in this test scenario
	)
	require.NoError(t, err)

	sameRepoLicenseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertSameRepoLicense.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed.String(), sameRepoLicenseAlertAfter.Status.String(), "alert with same license should have been closed")

	diffLicenseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlertDiffLicense.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen.String(), diffLicenseAlertAfter.Status.String(), "alert with different license should remain open")

	anotherRepoAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, alertAnotherRepo.RepositoryID, createdAlertAnotherRepo.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen.String(), anotherRepoAlertAfter.Status.String())
}

func TestCheckAndCloseAffectedAlertsForLicenses_PublishesHydroEventForReviewRequestedAlerts(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)
	prNumber := uint32(88)
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

	_, err = app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-3.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	eventBodyPayload := models.LicensesAddedEventBody{
		Licenses: []string{"GPL-3.0"},
		Level:    models.PolicyLevelToString(proto.PolicyLevel_POLICY_LEVEL_REPOSITORY),
		Comment:  "",
	}

	err = CheckAndCloseAffectedAlertsForLicenses(
		ctx,
		app,
		eventBodyPayload,
		proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
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
}

func TestCheckAndCloseAffectedAlertsForLicenses_PublishesHydroEventForOpenAlerts(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := uint64(123)
	orgID := uint64(42)
	entID := uint64(7)
	prNumber := uint32(88)
	userID := uint64(1)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        orgID,
		EnterpriseID:          &entID,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
		ManifestName:          "package.json",
		Status:                models.AlertStatusOpen,
		PullRequestNumber:     &prNumber,
	}
	createdAlert, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher

	_, err = app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
		RepositoryId: repositoryID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-3.0", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	eventBodyPayload := models.LicensesAddedEventBody{
		Licenses: []string{"GPL-3.0"},
		Level:    models.PolicyLevelToString(proto.PolicyLevel_POLICY_LEVEL_REPOSITORY),
		Comment:  "",
	}

	err = CheckAndCloseAffectedAlertsForLicenses(
		ctx,
		app,
		eventBodyPayload,
		proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
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
		PreviousStatus: entities.AlertStatus_ALERT_STATUS_OPEN,
		UserId:         1,
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
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
		nil, // No original alert in this test scenario
	)
	require.NoError(t, err)

	sameEnterpriseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID2, createdAlertSameEnterprise.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed.String(), sameEnterpriseAlertAfter.Status.String(), "alert in same enterprise should have been closed")

	diffLicenseAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID3, createdAlertDiffLicense.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen.String(), diffLicenseAlertAfter.Status.String(), "alert with different license should remain open")

	anotherEntAlertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID4, createdAlertAnotherEnt.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen.String(), anotherEntAlertAfter.Status.String(), "alert in different enterprise should remain open")
}

func TestAddLicensesForAlert_WhenAlertStatusIsReviewRequested_PublishesHydroEvent(t *testing.T) {
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
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
		ManifestName:          "package.json",
		Status:                models.AlertStatusReviewRequested,
		PullRequestNumber:     &prNumber,
	}
	_, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	alertAfterCreate, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)

	// Set up test publisher
	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		EnterpriseId:   entID,
		Comment:        "Approving this",
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req, nil)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
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
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SpdxLicenseExpression: "GPL-3.0",
			Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
		},
		PreviousStatus: entities.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED,
		UserId:         1,
		Comment:        wrapperspb.String("Approving this"),
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
}

func TestAddLicensesForAlert_WhenAlertStatusIsOpen_PublishesHydroEvent(t *testing.T) {
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
		PackageName:           "some-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "GPL-3.0",
		ManifestName:          "package.json",
		Status:                models.AlertStatusOpen,
		PullRequestNumber:     &prNumber,
	}
	_, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
	require.NoError(t, err)

	alertAfterCreate, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)

	// Set up test publisher
	tp := testpublisher.NewTestPublisher(t)
	app.Subsystems.EventPublisher = tp.Publisher

	req := &proto.AddLicensesForAlertRequest{
		RepositoryId:   repositoryID,
		UserId:         1,
		PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
		Contexts:       testhelpers.AllDistributionContexts,
		OrganizationId: orgID,
		EnterpriseId:   entID,
		Comment:        "Adding license",
	}

	err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req, nil)
	require.NoError(t, err)

	alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

	// Skip the LicensePolicyChanged event that's always published
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
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SpdxLicenseExpression: "GPL-3.0",
			Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
		},
		PreviousStatus: entities.AlertStatus_ALERT_STATUS_OPEN,
		UserId:         1,
		Comment:        wrapperspb.String("Adding license"),
	}

	// Verify LicenseComplianceAlertStatusChanged Hydro event was published
	// (status was Open, not ReviewRequested)
	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
}

func TestAddLicensesForAlert_PublishesCheckProgressedEventWhenCheckJobPasses(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t)
		ctx := t.Context()
		repositoryID := uint64(123)
		orgID := uint64(42)
		entID := uint64(7)
		prNumber := uint32(99)

		// Create a check job (fail) for this PR
		checkJob := models.CheckJob{
			RepositoryID:      repositoryID,
			PullRequestNumber: prNumber,
			BaseSHA:           "base123",
			CommitSHA:         "commit456",
			OrganizationID:    orgID,
			EnterpriseID:      &entID,
		}
		createdJob, err := app.Subsystems.Storage.CreateCheckJob(ctx, checkJob)
		require.NoError(t, err)
		createdJob.Status = models.Fail
		err = app.Subsystems.Storage.UpdateCheckJob(ctx, createdJob)
		require.NoError(t, err)

		// Create a single open alert on this PR
		alert := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
			ManifestName:          "package.json",
			Status:                models.AlertStatusOpen,
			PullRequestNumber:     &prNumber,
		}
		_, err = app.Subsystems.Storage.CreateAlert(ctx, alert)
		require.NoError(t, err)

		alertAfterCreate, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
		require.NoError(t, err)

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		req := &proto.AddLicensesForAlertRequest{
			RepositoryId:   repositoryID,
			UserId:         1,
			PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
			Contexts:       testhelpers.AllDistributionContexts,
			OrganizationId: orgID,
			EnterpriseId:   entID,
		}

		err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req, nil)
		require.NoError(t, err)

		synctest.Wait()

		// Alert should be closed
		alertAfter, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed, alertAfter.Status)

		// Check job should be pass
		updatedJob, err := app.Subsystems.Storage.GetCheckJob(ctx, repositoryID, prNumber)
		require.NoError(t, err)
		assert.Equal(t, models.Pass, updatedJob.Status)

		// Skip the LicensePolicyChanged event that's always published
		tp.SkipMessage(t)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckProgressed",
			&dependencygraphv1.PullRequestLicenseCheckProgressed{
				CommitSha:      "commit456",
				RepositoryId:   int64(repositoryID),
				CheckJobStatus: entities.CheckJobStatus_CHECK_JOB_STATUS_PASS,
				LogMessage:     "✓ License check passed",
				Title:          &wrapperspb.StringValue{Value: "No new license compliance alerts in code changed by this pull request"},
				ProgressedAt:   timestamppb.New(time.Now()),
			})
	})
}

func TestAddLicensesForAlert_NoCheckProgressedEventWhenOpenAlertsRemain(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		app := newTestApp(t)
		ctx := t.Context()
		repositoryID := uint64(123)
		orgID := uint64(42)
		entID := uint64(7)
		prNumber := uint32(99)

		// Create a check job (fail) for this PR
		checkJob := models.CheckJob{
			RepositoryID:      repositoryID,
			PullRequestNumber: prNumber,
			BaseSHA:           "base123",
			CommitSHA:         "commit456",
			OrganizationID:    orgID,
			EnterpriseID:      &entID,
		}
		createdJob, err := app.Subsystems.Storage.CreateCheckJob(ctx, checkJob)
		require.NoError(t, err)
		createdJob.Status = models.Fail
		err = app.Subsystems.Storage.UpdateCheckJob(ctx, createdJob)
		require.NoError(t, err)

		// Create TWO open alerts on this PR — closing one won't pass the check job
		alert1 := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
			ManifestName:          "package.json",
			Status:                models.AlertStatusOpen,
			PullRequestNumber:     &prNumber,
		}
		_, err = app.Subsystems.Storage.CreateAlert(ctx, alert1)
		require.NoError(t, err)

		alert2 := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "another-package",
			PackageVersion:        "2.0.0",
			SPDXLicenseExpression: "AGPL-3.0",
			ManifestName:          "package.json",
			Status:                models.AlertStatusOpen,
			PullRequestNumber:     &prNumber,
		}
		_, err = app.Subsystems.Storage.CreateAlert(ctx, alert2)
		require.NoError(t, err)

		alertAfterCreate, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
		require.NoError(t, err)

		tp := testpublisher.NewTestPublisher(t)
		app.Subsystems.EventPublisher = tp.Publisher

		req := &proto.AddLicensesForAlertRequest{
			RepositoryId:   repositoryID,
			UserId:         1,
			PolicyLevel:    proto.PolicyLevel_POLICY_LEVEL_REPOSITORY,
			Contexts:       testhelpers.AllDistributionContexts,
			OrganizationId: orgID,
			EnterpriseId:   entID,
		}

		// Add GPL-3.0 — closes alert1 but alert2 (AGPL-3.0) remains open
		err = AddLicensesToPolicyForAlert(ctx, app, alertAfterCreate, []string{"GPL-3.0"}, req, nil)
		require.NoError(t, err)

		synctest.Wait()

		// First alert closed, second still open
		alertAfter1, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 1)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed, alertAfter1.Status)

		alertAfter2, err := app.Subsystems.Storage.GetAlert(ctx, repositoryID, 2)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusOpen, alertAfter2.Status)

		// Check job should still be fail
		updatedJob, err := app.Subsystems.Storage.GetCheckJob(ctx, repositoryID, prNumber)
		require.NoError(t, err)
		assert.Equal(t, models.Fail, updatedJob.Status)

		tp.SkipMessage(t) // LicensePolicyChanged
		tp.SkipMessage(t) // LicenseComplianceAlertStatusChanged
		tp.SkipMessage(t) // PullRequestLicenseCheckComplete (async)
		tp.AssertNoMessagePublished(t)
	})
}
