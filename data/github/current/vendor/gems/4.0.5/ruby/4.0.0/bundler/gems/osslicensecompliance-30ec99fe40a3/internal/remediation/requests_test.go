package remediation

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/require"
)

func TestRequestAlertDismissal_OpenToReviewRequestedToDenied(t *testing.T) {
	app := newTestApp(t)
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)

	alert := &models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	s := app.Subsystems.Storage

	userID := uint64(12345)

	_, err := s.CreateAlert(ctx, *alert)
	require.NoError(t, err)

	alert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.NotNil(t, alert)
	require.Equal(t, models.AlertStatusOpen, alert.Status)

	// Open -> ReviewRequested
	amendment := models.ClosureReasonAmendment
	err = RequestAlertClosure(ctx, app, alert, userID, "please let me use this", &amendment)
	require.NoError(t, err)

	alert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.AlertStatusReviewRequested, alert.Status)

	// ReviewRequested -> ReviewDenied
	err = DenyClosureRequest(ctx, app, alert, userID, "no.")
	require.NoError(t, err)

	alert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.AlertStatusReviewDenied, alert.Status)

	// Verify alert events
	events, err := s.GetAlertEvents(ctx, alert.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)

	require.Equal(t, models.EventReviewRequested, events[0].EventType)
	require.Equal(t, models.EventReviewDenied, events[1].EventType)
}

func TestRequestAlertDismissal_ClosedToReviewRequested_DoesNotUpdate(t *testing.T) {
	app := newTestApp(t)
	s := app.Subsystems.Storage
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestNumber := uint32(3)
	userID := uint64(12345)

	alert := &models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err := s.CreateAlert(ctx, *alert)
	require.NoError(t, err)

	alert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.AlertStatusOpen, alert.Status)

	// Move to Closed
	CloseOutdatedAlerts(ctx, app, []*models.Alert{alert}, uint64(pullRequestNumber))
	alert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.AlertStatusClosed, alert.Status)

	// Invalid transition: Closed to ReviewRequested
	amendment := models.ClosureReasonAmendment
	err = RequestAlertClosure(ctx, app, alert, userID, "please let me use this", &amendment)
	require.ErrorIs(t, err, ErrStatusChangeNotAllowed)

	// Alert should still be Closed
	alert, err = s.GetAlert(ctx, repositoryID, 1)
	require.NoError(t, err)
	require.Equal(t, models.AlertStatusClosed, alert.Status) // still Closed

	// No new events created
	events, err := s.GetAlertEvents(ctx, alert.ID)
	require.NoError(t, err)
	require.Len(t, events, 1)
	require.Equal(t, models.EventClosed, events[0].EventType)
}
