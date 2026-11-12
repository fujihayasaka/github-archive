package remediation

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/require"
)

func TestCloseOutdatedAlerts_HasNilEventBody(t *testing.T) {
	r := require.New(t)
	app := newTestApp(t)
	s := app.Subsystems.Storage
	ctx := t.Context()
	repositoryID := testhelpers.RandomIDForDatabase()
	pullRequestID := uint64(12345)

	alert := models.Alert{
		RepositoryID:          repositoryID,
		OrganizationID:        testhelpers.RandomIDForDatabase(),
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "test-package",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.AlertStatusOpen, createdAlert.Status)

	CloseOutdatedAlerts(ctx, app, []*models.Alert{createdAlert}, pullRequestID)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)
	r.Equal(models.AlertStatusClosed, retrievedAlert.Status)
	r.Equal(models.AlertResolutionOutdated, retrievedAlert.Resolution)

	events, err := s.GetAlertEvents(ctx, createdAlert.ID)
	r.NoError(err)
	r.Len(events, 1)
	r.Equal(models.EventClosed, events[0].EventType)
	r.Nil(events[0].UserID, "System-initiated closure should have nil UserID")
	r.JSONEq("{}", string(events[0].EventBody))
}
