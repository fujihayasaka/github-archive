package twirp

import (
	"errors"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	twirperr "github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestGetAlert_MissingRepoID(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.GetAlertRequest{
		Number: 1,
	}
	_, err = server.GetAlert(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "repository_id")
}

func TestGetAlert_MissingNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.GetAlertRequest{
		RepositoryId: 1,
	}
	_, err = server.GetAlert(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "number")
}

func TestGetAlert_DoesntExist(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.GetAlertRequest{
		RepositoryId: 1,
		Number:       1,
	}
	resp, err := server.GetAlert(t.Context(), req)
	require.NoError(t, err)
	assert.Nil(t, resp.Alert)  // Expecting nil since no alert exists
	assert.Nil(t, resp.Events) // Expecting nil events as well
}

func TestGetAlert_Exists(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	resolution := models.AlertResolutionLicensesAdded
	businessID := uint64(10)
	pullRequestNumber := uint32(5)

	amendment := models.ClosureReasonAmendment

	// First, create an alert directly in the storage
	alertInfo := models.Alert{
		Number:                1,
		Resolution:            resolution,
		RepositoryID:          2,
		OrganizationID:        3,
		EnterpriseID:          &businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    4,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.2.3",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
		PackageRepoNWO:        "jestjs/jest",
		ClosureReason:         &amendment,
	}
	_, err = app.Subsystems.Storage.CreateAlert(t.Context(), alertInfo)
	require.NoError(t, err)

	req := &proto.GetAlertRequest{
		RepositoryId: alertInfo.RepositoryID,
		Number:       alertInfo.Number,
	}
	resp, err := server.GetAlert(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp.Alert)
	assert.Equal(t, alertInfo.Number, resp.Alert.Number)
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_OPEN, resp.Alert.Status)
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_LICENSES_ADDED, resp.Alert.Resolution)
	assert.WithinDuration(t, time.Now(), resp.Alert.CreatedAt.AsTime(), time.Minute)
	assert.Equal(t, alertInfo.RepositoryID, resp.Alert.RepositoryId)
	assert.Equal(t, alertInfo.OrganizationID, resp.Alert.OrganizationId)
	assert.Equal(t, businessID, resp.Alert.EnterpriseId)
	assert.Equal(t, alertInfo.ManifestName, resp.Alert.ManifestName)
	assert.Equal(t, alertInfo.ManifestLineNumber, resp.Alert.ManifestLineNumber)
	assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, resp.Alert.PackageEcosystem)
	assert.Equal(t, alertInfo.PackageName, resp.Alert.PackageName)
	assert.Equal(t, alertInfo.PackageVersion, resp.Alert.PackageVersion)
	assert.Equal(t, alertInfo.SPDXLicenseExpression, resp.Alert.License)
	assert.Equal(t, *alertInfo.PullRequestNumber, resp.Alert.PullRequestNumber)
	assert.Equal(t, alertInfo.PackageRepoNWO, resp.Alert.PackageRepoNwo)
	assert.Equal(t, proto.ClosureReason_CLOSURE_REASON_AMENDMENT, resp.Alert.ClosureReason)
}

func TestGetAlert_ExistsWithoutResolutionBusinessIDAndPullRequestNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// First, create an alert directly in the storage
	alertInfo := models.Alert{
		Number:                1,
		RepositoryID:          2,
		OrganizationID:        3,
		ManifestName:          "package.json",
		ManifestLineNumber:    4,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.2.3",
		SPDXLicenseExpression: "MIT",
	}
	_, err = app.Subsystems.Storage.CreateAlert(t.Context(), alertInfo)
	require.NoError(t, err)

	req := &proto.GetAlertRequest{
		RepositoryId: alertInfo.RepositoryID,
		Number:       alertInfo.Number,
	}
	resp, err := server.GetAlert(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp.Alert)
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_OPEN, resp.Alert.Status)
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_UNKNOWN, resp.Alert.Resolution)
	assert.Equal(t, uint64(0), resp.Alert.EnterpriseId)
	assert.Equal(t, uint32(0), resp.Alert.PullRequestNumber)
}

func TestRequestAlertDismissal_MissingRepoID(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RequestAlertDismissalRequest{
		Number: 1,
		UserId: 1,
	}
	_, err = server.RequestAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "repository_id")
}

func TestRequestAlertDismissal_MissingNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RequestAlertDismissalRequest{
		RepositoryId: 1,
		UserId:       1,
	}
	_, err = server.RequestAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "number")
}

func TestRequestAlertDismissal_MissingUserId(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RequestAlertDismissalRequest{
		RepositoryId: 1,
		Number:       1,
	}
	_, err = server.RequestAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "user_id")
}

func TestRequestAlertDismissal_AlertDoesNotExist(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RequestAlertDismissalRequest{
		RepositoryId: 1,
		Number:       1,
		UserId:       1,
	}
	_, err = server.RequestAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var notFoundErr twirperr.Error
	assert.True(t, errors.As(err, &notFoundErr))
	assert.Equal(t, twirperr.ErrorCode("not_found"), notFoundErr.Code())
	assert.Contains(t, notFoundErr.Msg(), "alert not found")
}

func TestRequestAlertDismissal_Transitions(t *testing.T) {
	testCases := []struct {
		name          string
		initialStatus models.AlertStatus
		shouldSucceed bool
	}{
		{
			name:          "Valid transition: Open status → ReviewRequested",
			initialStatus: models.AlertStatusOpen,
			shouldSucceed: true,
		},
		{
			name:          "Valid transition: ReviewDenied → ReviewRequested",
			initialStatus: models.AlertStatusReviewDenied,
			shouldSucceed: true,
		},
		{
			name:          "Invalid transition: Closed status → ReviewRequested",
			initialStatus: models.AlertStatusClosed,
			shouldSucceed: false,
		},
		{
			name:          "Invalid transition: ReviewRequested → ReviewRequested",
			initialStatus: models.AlertStatusReviewRequested,
			shouldSucceed: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
			require.NoError(t, err)
			server := &Server{app: app}

			s := app.Subsystems.Storage
			ctx := t.Context()
			businessID := uint64(3)
			repositoryID := uint64(1)
			pullRequestNumber := uint32(3)

			alert := models.Alert{
				Number:                1,
				RepositoryID:          repositoryID,
				OrganizationID:        1,
				EnterpriseID:          &businessID,
				ManifestName:          "package.json",
				ManifestLineNumber:    1,
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "jest",
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "MIT",
				PullRequestNumber:     &pullRequestNumber,
				Status:                tc.initialStatus,
			}

			_, err = s.CreateAlert(ctx, alert)
			require.NoError(t, err)

			retrievedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
			require.NoError(t, err)
			require.Equal(t, tc.initialStatus, retrievedAlert.Status)

			req := &proto.RequestAlertDismissalRequest{
				RepositoryId: repositoryID,
				Number:       alert.Number,
				UserId:       1,
			}
			_, err = server.RequestAlertDismissal(ctx, req)

			if tc.shouldSucceed {
				require.NoError(t, err)
				retrievedAlert, err = s.GetAlert(ctx, repositoryID, alert.Number)
				require.NoError(t, err)
				assert.Equal(t, models.AlertStatusReviewRequested, retrievedAlert.Status)
			} else {
				require.Error(t, err)
				var twirpErr twirperr.Error
				assert.True(t, errors.As(err, &twirpErr))
				assert.Equal(t, twirperr.ErrorCode("failed_precondition"), twirpErr.Code())

				retrievedAlert, err = s.GetAlert(ctx, repositoryID, alert.Number)
				require.NoError(t, err)
				assert.Equal(t, tc.initialStatus, retrievedAlert.Status)
			}
		})
	}
}

func TestRequestAlertDismissal_Success(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	s := app.Subsystems.Storage
	r := require.New(t)
	ctx := t.Context()
	businessID := uint64(3)
	repositoryID := uint64(1)
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Number:                1,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err = s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.AlertStatusOpen, alert.Status)

	req := &proto.RequestAlertDismissalRequest{
		RepositoryId:  repositoryID,
		Number:        alert.Number,
		UserId:        1,
		ClosureReason: proto.ClosureReason_CLOSURE_REASON_PRIVATE_PACKAGE,
		Comment:       "This is internal",
	}
	_, err = server.RequestAlertDismissal(ctx, req)
	r.NoError(err)

	updatedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
	r.NoError(err)
	r.Equal(models.AlertStatusReviewRequested, updatedAlert.Status)
	r.NotNil(updatedAlert.ClosureReason)
	r.Equal("private_package", *updatedAlert.ClosureReason)

	// Check that an AlertEvent was created
	events, err := s.GetAlertEvents(ctx, updatedAlert.ID)
	r.NoError(err)
	r.Len(events, 1)
	assert.Equal(t, models.EventReviewRequested, events[0].EventType)
	assert.Equal(t, &req.UserId, events[0].UserID)
	assert.JSONEq(t, `{"comment": "This is internal", "closure_reason": "private_package"}`, string(events[0].EventBody))
}

func TestRequestAlertDismissal_PublishesHydroEvent(t *testing.T) {
	tp := testpublisher.NewTestPublisher(t)
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	app.Subsystems.EventPublisher = tp.Publisher

	server := &Server{app: app}
	s := app.Subsystems.Storage
	r := require.New(t)
	ctx := t.Context()
	businessID := uint64(3)
	repositoryID := uint64(1)
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Number:                1,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.AlertStatusOpen, createdAlert.Status)

	req := &proto.RequestAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       createdAlert.Number,
		UserId:       1,
	}
	_, err = server.RequestAlertDismissal(ctx, req)
	r.NoError(err)

	// Get the updated alert to get the timestamp
	updatedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)

	expectedEvent := &dependencygraphv1.LicenseComplianceAlertStatusChanged{
		Alert: &entities.LicenseComplianceAlert{
			AlertId:               int64(updatedAlert.ID),
			AlertNumber:           int32(updatedAlert.Number),
			CreatedAt:             timestamppb.New(updatedAlert.CreatedAt),
			RepositoryId:          int64(repositoryID),
			OrganizationId:        1,
			EnterpriseId:          wrapperspb.Int64(int64(businessID)),
			PullRequestNumber:     int32(pullRequestNumber),
			PullRequestId:         0, // We don't have PR ID in this context
			ManifestName:          "package.json",
			PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "jest",
			PackageVersion:        "1.0.0",
			SpdxLicenseExpression: "MIT",
			Status:                entities.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED,
		},
		PreviousStatus: entities.AlertStatus_ALERT_STATUS_OPEN,
		UserId:         1,
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
}

func TestRequestAlertDismissal_Twice(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	s := app.Subsystems.Storage
	r := require.New(t)
	ctx := t.Context()
	businessID := uint64(3)
	repositoryID := uint64(1)
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Number:                1,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err = s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.AlertStatusOpen, alert.Status)

	req := &proto.RequestAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
		UserId:       1,
	}
	_, err = server.RequestAlertDismissal(ctx, req)
	r.NoError(err)

	// Error because already in ReviewRequested state
	_, err = server.RequestAlertDismissal(ctx, req)
	var twirpErr twirperr.Error
	assert.True(t, errors.As(err, &twirpErr))
	r.Equal(twirperr.ErrorCode("failed_precondition"), twirpErr.Code())

	// Check that only one AlertEvent was created
	updatedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
	r.NoError(err)
	events, err := s.GetAlertEvents(ctx, updatedAlert.ID)
	r.NoError(err)
	r.Len(events, 1)
}

func TestRequestAlertDismissalById_MissingAlertID(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RequestAlertDismissalByIdRequest{
		UserId: 1,
	}
	_, err = server.RequestAlertDismissalById(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "alert_id")
}

func TestRequestAlertDismissalById_MissingUserId(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RequestAlertDismissalByIdRequest{
		AlertId: 1,
	}
	_, err = server.RequestAlertDismissalById(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "user_id")
}

func TestRequestAlertDismissalById_AlertDoesNotExist(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.RequestAlertDismissalByIdRequest{
		AlertId: 999,
		UserId:  1,
	}
	_, err = server.RequestAlertDismissalById(t.Context(), req)
	require.Error(t, err)

	var notFoundErr twirperr.Error
	assert.True(t, errors.As(err, &notFoundErr))
	assert.Equal(t, twirperr.ErrorCode("not_found"), notFoundErr.Code())
	assert.Contains(t, notFoundErr.Msg(), "alert not found")
}

func TestRequestAlertDismissalById_Success(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	s := app.Subsystems.Storage
	r := require.New(t)
	ctx := t.Context()
	businessID := uint64(3)
	repositoryID := uint64(1)
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Number:                1,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.AlertStatusOpen, createdAlert.Status)

	req := &proto.RequestAlertDismissalByIdRequest{
		AlertId:       createdAlert.ID,
		UserId:        1,
		ClosureReason: proto.ClosureReason_CLOSURE_REASON_PRIVATE_PACKAGE,
		Comment:       "This is internal",
	}
	_, err = server.RequestAlertDismissalById(ctx, req)
	r.NoError(err)

	updatedAlert, err := s.GetAlertByID(ctx, createdAlert.ID)
	r.NoError(err)
	r.Equal(models.AlertStatusReviewRequested, updatedAlert.Status)
	r.NotNil(updatedAlert.ClosureReason)
	r.Equal("private_package", *updatedAlert.ClosureReason)
}

func TestDenyAlertDismissal_MissingRepoID(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.DenyAlertDismissalRequest{
		Number:  1,
		UserId:  1,
		Comment: "Not valid",
	}
	_, err = server.DenyAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "repository_id")
}

func TestDenyAlertDismissal_MissingNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.DenyAlertDismissalRequest{
		RepositoryId: 1,
		UserId:       1,
		Comment:      "Not valid",
	}
	_, err = server.DenyAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "number")
}

func TestDenyAlertDismissal_MissingUserId(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.DenyAlertDismissalRequest{
		RepositoryId: 1,
		Number:       1,
		Comment:      "Not valid",
	}
	_, err = server.DenyAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "user_id")
}

func TestDenyAlertDismissal_MissingComment(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.DenyAlertDismissalRequest{
		RepositoryId: 1,
		Number:       1,
		UserId:       1,
	}
	_, err = server.DenyAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "comment")
}

func TestDenyAlertDismissal_AlertDoesNotExist(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.DenyAlertDismissalRequest{
		RepositoryId: 1,
		Number:       1,
		UserId:       1,
		Comment:      "Not valid",
	}
	_, err = server.DenyAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var notFoundErr twirperr.Error
	assert.True(t, errors.As(err, &notFoundErr))
	assert.Equal(t, twirperr.ErrorCode("not_found"), notFoundErr.Code())
	assert.Contains(t, notFoundErr.Msg(), "alert not found")
}

func TestDenyAlertDismissal_Transitions(t *testing.T) {
	testCases := []struct {
		name          string
		initialStatus models.AlertStatus
		shouldSucceed bool
	}{
		{
			name:          "Valid transition: ReviewRequested → ReviewDenied",
			initialStatus: models.AlertStatusReviewRequested,
			shouldSucceed: true,
		},
		{
			name:          "Invalid transition: Open status → ReviewDenied",
			initialStatus: models.AlertStatusOpen,
			shouldSucceed: false,
		},
		{
			name:          "Invalid transition: ReviewDenied → ReviewDenied",
			initialStatus: models.AlertStatusReviewDenied,
			shouldSucceed: false,
		},
		{
			name:          "Invalid transition: Close status → ReviewDenied",
			initialStatus: models.AlertStatusClosed,
			shouldSucceed: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
			require.NoError(t, err)
			server := &Server{app: app}

			s := app.Subsystems.Storage
			ctx := t.Context()
			businessID := uint64(3)
			repositoryID := uint64(1)
			pullRequestNumber := uint32(3)

			alert := models.Alert{
				Number:                1,
				RepositoryID:          repositoryID,
				OrganizationID:        1,
				EnterpriseID:          &businessID,
				ManifestName:          "package.json",
				ManifestLineNumber:    1,
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "jest",
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "MIT",
				PullRequestNumber:     &pullRequestNumber,
				Status:                tc.initialStatus,
			}

			_, err = s.CreateAlert(ctx, alert)
			require.NoError(t, err)

			retrievedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
			require.NoError(t, err)
			require.Equal(t, tc.initialStatus, retrievedAlert.Status)

			reqDeny := &proto.DenyAlertDismissalRequest{
				RepositoryId: repositoryID,
				Number:       alert.Number,
				UserId:       1,
				Comment:      "Not valid",
			}

			_, err = server.DenyAlertDismissal(ctx, reqDeny)

			if tc.shouldSucceed {
				require.NoError(t, err)
				retrievedAlert, err = s.GetAlert(ctx, repositoryID, alert.Number)
				require.NoError(t, err)
				assert.Equal(t, models.AlertStatusReviewDenied, retrievedAlert.Status)
			} else {
				require.Error(t, err)
				var twirpErr twirperr.Error
				assert.True(t, errors.As(err, &twirpErr))
				assert.Equal(t, twirperr.ErrorCode("failed_precondition"), twirpErr.Code())

				retrievedAlert, err = s.GetAlert(ctx, repositoryID, alert.Number)
				require.NoError(t, err)
				assert.Equal(t, tc.initialStatus, retrievedAlert.Status)
			}
		})
	}
}

func TestDenyAlertDismissal_Success(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	s := app.Subsystems.Storage
	r := require.New(t)
	ctx := t.Context()
	businessID := uint64(3)
	repositoryID := uint64(1)
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Number:                1,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	_, err = s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.AlertStatusOpen, alert.Status)

	// First, request dismissal to set status to ReviewRequested
	reqDismiss := &proto.RequestAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
		UserId:       1,
	}
	_, err = server.RequestAlertDismissal(ctx, reqDismiss)
	r.NoError(err)

	// Now, deny the dismissal request
	reqDeny := &proto.DenyAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
		UserId:       2,
		Comment:      "I don't want to dismiss this alert",
	}
	_, err = server.DenyAlertDismissal(ctx, reqDeny)
	r.NoError(err)

	updatedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
	require.NoError(t, err)
	require.Equal(t, models.AlertStatusReviewDenied, updatedAlert.Status)

	// Check that two AlertEvents were created
	events, err := s.GetAlertEvents(ctx, updatedAlert.ID)
	require.NoError(t, err)
	require.Len(t, events, 2)
	assert.Equal(t, models.EventReviewRequested, events[0].EventType)
	assert.Equal(t, &reqDismiss.UserId, events[0].UserID)
	assert.JSONEq(t, "{}", string(events[0].EventBody))

	assert.Equal(t, models.EventReviewDenied, events[1].EventType)
	assert.Equal(t, &reqDeny.UserId, events[1].UserID)
	expectedBody := `{"comment": "I don't want to dismiss this alert"}`
	assert.JSONEq(t, expectedBody, string(events[1].EventBody))
}

func TestDenyAlertDismissal_PublishesHydroEvent(t *testing.T) {
	tp := testpublisher.NewTestPublisher(t)
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	app.Subsystems.EventPublisher = tp.Publisher

	server := &Server{app: app}
	s := app.Subsystems.Storage
	r := require.New(t)
	ctx := t.Context()
	businessID := uint64(3)
	repositoryID := uint64(1)
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Number:                1,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &businessID,
		Status:                models.AlertStatusReviewRequested,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.AlertStatusReviewRequested, createdAlert.Status)

	// Deny the dismissal request
	reqDeny := &proto.DenyAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       createdAlert.Number,
		UserId:       2,
		Comment:      "I don't want to dismiss this alert",
	}
	_, err = server.DenyAlertDismissal(ctx, reqDeny)
	r.NoError(err)

	// Get the updated alert
	updatedAlert, err := s.GetAlert(ctx, repositoryID, createdAlert.Number)
	r.NoError(err)

	// Verify Hydro event was published
	expectedEvent := &dependencygraphv1.LicenseComplianceAlertStatusChanged{
		Alert: &entities.LicenseComplianceAlert{
			AlertId:               int64(updatedAlert.ID),
			AlertNumber:           int32(updatedAlert.Number),
			CreatedAt:             timestamppb.New(updatedAlert.CreatedAt),
			RepositoryId:          int64(repositoryID),
			OrganizationId:        1,
			EnterpriseId:          wrapperspb.Int64(int64(businessID)),
			PullRequestNumber:     int32(pullRequestNumber),
			PullRequestId:         0,
			ManifestName:          "package.json",
			PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "jest",
			PackageVersion:        "1.0.0",
			SpdxLicenseExpression: "MIT",
			Status:                entities.AlertStatus_ALERT_STATUS_REVIEW_DENIED,
		},
		PreviousStatus: entities.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED,
		UserId:         2,
		Comment:        wrapperspb.String(reqDeny.Comment),
	}

	tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", expectedEvent)
}

func TestGetReviewableAlerts_OrgAndEnterprise(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	ctx := t.Context()
	orgID := uint64(100)
	entID := uint64(200)

	// Create alerts with different statuses and org/enterprise IDs
	alerts := []models.Alert{
		{Number: 1, OrganizationID: orgID, Status: models.AlertStatusReviewRequested, PackageName: "a"},
		{Number: 2, OrganizationID: orgID, Status: models.AlertStatusOpen, PackageName: "b"},
		{Number: 3, EnterpriseID: &entID, Status: models.AlertStatusReviewRequested, PackageName: "c"},
		{Number: 4, EnterpriseID: &entID, Status: models.AlertStatusClosed, PackageName: "d"},
		{Number: 5, OrganizationID: orgID, Status: models.AlertStatusReviewRequested, PackageName: "e"},
	}
	for _, alert := range alerts {
		_, err := app.Subsystems.Storage.CreateAlert(ctx, alert)
		require.NoError(t, err)
	}

	// Org-level request
	orgReq := &proto.GetReviewableAlertsRequest{OrganizationId: orgID}
	orgResp, err := server.GetReviewableAlerts(ctx, orgReq)
	require.NoError(t, err)
	require.NotNil(t, orgResp)
	var orgNumbers []uint32
	for _, a := range orgResp.Alerts {
		orgNumbers = append(orgNumbers, a.Number)
		assert.Equal(t, proto.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED, a.Status)
	}
	assert.ElementsMatch(t, []uint32{1, 5}, orgNumbers)

	// Enterprise-level request
	entReq := &proto.GetReviewableAlertsRequest{EnterpriseId: entID}
	entResp, err := server.GetReviewableAlerts(ctx, entReq)
	require.NoError(t, err)
	require.NotNil(t, entResp)
	var entNumbers []uint32
	for _, a := range entResp.Alerts {
		entNumbers = append(entNumbers, a.Number)
		assert.Equal(t, proto.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED, a.Status)
	}
	assert.ElementsMatch(t, []uint32{3}, entNumbers)
}

func TestGetReviewableAlerts_NotFound(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	ctx := t.Context()
	// No alerts created for these org/enterprise IDs
	orgReq := &proto.GetReviewableAlertsRequest{OrganizationId: 9999}
	orgResp, err := server.GetReviewableAlerts(ctx, orgReq)
	require.NoError(t, err)
	require.NotNil(t, orgResp)
	assert.Empty(t, orgResp.Alerts)

	entReq := &proto.GetReviewableAlertsRequest{EnterpriseId: 8888}
	entResp, err := server.GetReviewableAlerts(ctx, entReq)
	require.NoError(t, err)
	require.NotNil(t, entResp)
	assert.Empty(t, entResp.Alerts)
}

func TestGetReviewableAlerts_MissingOrgAndEnterprise(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	ctx := t.Context()
	req := &proto.GetReviewableAlertsRequest{} // Both IDs missing
	_, err = server.GetReviewableAlerts(ctx, req)
	require.Error(t, err)
	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "organization_id or enterprise_id")
}

func TestGetReviewableAlerts_BothOrgAndEnterpriseSet(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	ctx := t.Context()
	req := &proto.GetReviewableAlertsRequest{
		OrganizationId: 1,
		EnterpriseId:   2, // Both IDs set
	}
	_, err = server.GetReviewableAlerts(ctx, req)
	require.Error(t, err)
	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "organization_id and enterprise_id cannot both be set")
}

func TestGetAlert_WithEvents(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	s := app.Subsystems.Storage
	r := require.New(t)
	ctx := t.Context()
	businessID := uint64(3)
	repositoryID := uint64(1)
	pullRequestNumber := uint32(3)

	// Create an alert
	alert := models.Alert{
		Number:                1,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
	}

	createdAlert, err := s.CreateAlert(ctx, alert)
	r.NoError(err)
	r.Equal(models.AlertStatusOpen, createdAlert.Status)

	// Request dismissal to create a review_requested event
	userID1 := uint64(10)
	reqDismiss := &proto.RequestAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
		UserId:       userID1,
	}
	_, err = server.RequestAlertDismissal(ctx, reqDismiss)
	r.NoError(err)

	// Deny the dismissal request to create a review_denied event
	userID2 := uint64(20)
	reqDeny := &proto.DenyAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
		UserId:       userID2,
		Comment:      "Not approved",
	}
	_, err = server.DenyAlertDismissal(ctx, reqDeny)
	r.NoError(err)

	// Now get the alert and verify events are included
	req := &proto.GetAlertRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
	}
	resp, err := server.GetAlert(ctx, req)
	r.NoError(err)
	r.NotNil(resp.Alert)
	r.NotNil(resp.Events)
	r.Len(resp.Events, 2)

	// Verify the first event (review_requested)
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_REQUESTED, resp.Events[0].EventType)
	assert.Equal(t, userID1, resp.Events[0].UserId)
	assert.Equal(t, createdAlert.ID, resp.Events[0].AlertId)
	assert.NotNil(t, resp.Events[0].OccurredAt)
	assert.JSONEq(t, "{}", resp.Events[0].EventBody)

	// Verify the second event (review_denied)
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_DENIED, resp.Events[1].EventType)
	assert.Equal(t, userID2, resp.Events[1].UserId)
	assert.Equal(t, createdAlert.ID, resp.Events[1].AlertId)
	assert.NotNil(t, resp.Events[1].OccurredAt)
	assert.JSONEq(t, `{"comment": "Not approved"}`, resp.Events[1].EventBody)
}

func TestGetAlert_NoEvents(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// Create an alert without any events
	alertInfo := models.Alert{
		Number:                1,
		RepositoryID:          2,
		OrganizationID:        3,
		ManifestName:          "package.json",
		ManifestLineNumber:    4,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.2.3",
		SPDXLicenseExpression: "MIT",
	}
	_, err = app.Subsystems.Storage.CreateAlert(t.Context(), alertInfo)
	require.NoError(t, err)

	req := &proto.GetAlertRequest{
		RepositoryId: alertInfo.RepositoryID,
		Number:       alertInfo.Number,
	}
	resp, err := server.GetAlert(t.Context(), req)
	require.NoError(t, err)
	require.NotNil(t, resp.Alert)
	require.NotNil(t, resp.Events)
	assert.Empty(t, resp.Events) // No events should be present
}

func TestExpireAlertDismissal_ValidationErrors(t *testing.T) {
	testCases := []struct {
		name          string
		req           *proto.ExpireAlertDismissalRequest
		expectedError string
	}{
		{
			name: "Missing repository_id",
			req: &proto.ExpireAlertDismissalRequest{
				Number:          1,
				ExpiryTimestamp: timestamppb.New(time.Now()),
			},
			expectedError: "repository_id",
		},
		{
			name: "Missing number",
			req: &proto.ExpireAlertDismissalRequest{
				RepositoryId:    1,
				ExpiryTimestamp: timestamppb.New(time.Now()),
			},
			expectedError: "number",
		},
		{
			name: "Missing expiry_timestamp",
			req: &proto.ExpireAlertDismissalRequest{
				RepositoryId: 1,
				Number:       1,
			},
			expectedError: "expiry_timestamp",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
			require.NoError(t, err)
			server := &Server{app: app}

			_, err = server.ExpireAlertDismissal(t.Context(), tc.req)
			require.Error(t, err)

			var reqArgErr twirperr.Error
			assert.True(t, errors.As(err, &reqArgErr))
			assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
			assert.Contains(t, reqArgErr.Msg(), tc.expectedError)
		})
	}
}

func TestExpireAlertDismissal_AlertDoesNotExist(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.ExpireAlertDismissalRequest{
		RepositoryId:    1,
		Number:          999,
		ExpiryTimestamp: timestamppb.New(time.Now()),
	}
	_, err = server.ExpireAlertDismissal(t.Context(), req)
	require.Error(t, err)

	var notFoundErr twirperr.Error
	assert.True(t, errors.As(err, &notFoundErr))
	assert.Equal(t, twirperr.ErrorCode("not_found"), notFoundErr.Code())
}

func TestExpireAlertDismissal_InvalidAlertStateTransitions(t *testing.T) {
	testCases := []struct {
		name          string
		initialStatus models.AlertStatus
	}{
		{
			name:          "Invalid transition: Open → Open",
			initialStatus: models.AlertStatusOpen,
		},
		{
			name:          "Invalid transition: Closed → Open",
			initialStatus: models.AlertStatusClosed,
		},
		{
			name:          "Invalid transition: ReviewDenied → Open",
			initialStatus: models.AlertStatusReviewDenied,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
			require.NoError(t, err)
			server := &Server{app: app}

			s := app.Subsystems.Storage
			ctx := t.Context()
			businessID := uint64(3)
			repositoryID := uint64(1)
			pullRequestNumber := uint32(3)

			alert := models.Alert{
				Number:                1,
				RepositoryID:          repositoryID,
				OrganizationID:        1,
				EnterpriseID:          &businessID,
				ManifestName:          "package.json",
				ManifestLineNumber:    1,
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "jest",
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "MIT",
				PullRequestNumber:     &pullRequestNumber,
				Status:                tc.initialStatus,
			}

			_, err = s.CreateAlert(ctx, alert)
			require.NoError(t, err)

			retrievedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
			require.NoError(t, err)
			require.Equal(t, tc.initialStatus, retrievedAlert.Status)

			req := &proto.ExpireAlertDismissalRequest{
				RepositoryId:    repositoryID,
				Number:          alert.Number,
				ExpiryTimestamp: timestamppb.New(time.Now()),
			}
			_, err = server.ExpireAlertDismissal(ctx, req)

			require.Error(t, err)
			var twirpErr twirperr.Error
			assert.True(t, errors.As(err, &twirpErr))
			assert.Equal(t, twirperr.ErrorCode("failed_precondition"), twirpErr.Code())

			retrievedAlert, err = s.GetAlert(ctx, repositoryID, alert.Number)
			require.NoError(t, err)
			assert.Equal(t, tc.initialStatus, retrievedAlert.Status)
		})
	}
}

func TestExpireAlertDismissal_Success(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	s := app.Subsystems.Storage
	ctx := t.Context()
	repositoryID := uint64(1)
	businessID := uint64(3)
	pullRequestNumber := uint32(3)

	alert := models.Alert{
		Number:                1,
		RepositoryID:          repositoryID,
		OrganizationID:        1,
		EnterpriseID:          &businessID,
		ManifestName:          "package.json",
		ManifestLineNumber:    1,
		PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
		PackageName:           "jest",
		PackageVersion:        "1.0.0",
		SPDXLicenseExpression: "MIT",
		PullRequestNumber:     &pullRequestNumber,
		Status:                models.AlertStatusReviewRequested,
	}

	_, err = s.CreateAlert(ctx, alert)
	require.NoError(t, err)

	// Use a specific time (truncated to second precision as databases typically store timestamps)
	expiryTime := time.Date(2024, 1, 15, 10, 30, 0, 0, time.UTC)
	req := &proto.ExpireAlertDismissalRequest{
		RepositoryId:    repositoryID,
		Number:          alert.Number,
		ExpiryTimestamp: timestamppb.New(expiryTime),
	}
	resp, err := server.ExpireAlertDismissal(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// Verify response contains the alert and events
	require.NotNil(t, resp.Alert)
	assert.Equal(t, proto.AlertStatus_ALERT_STATUS_OPEN, resp.Alert.Status)
	assert.Equal(t, alert.Number, resp.Alert.Number)

	// Verify response contains the EventReviewExpired event
	require.Len(t, resp.Events, 1)
	assert.Equal(t, proto.AlertEventType_ALERT_EVENT_TYPE_REVIEW_EXPIRED, resp.Events[0].EventType)
	assert.Equal(t, uint64(0), resp.Events[0].UserId) // System event has no user
	assert.Equal(t, expiryTime.Unix(), resp.Events[0].OccurredAt.AsTime().Unix())

	// Verify database state also changed correctly
	updatedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen, updatedAlert.Status)

	events, err := s.GetAlertEvents(ctx, updatedAlert.ID)
	require.NoError(t, err)
	require.Len(t, events, 1)
	assert.Equal(t, models.EventReviewExpired, events[0].EventType)
	assert.Nil(t, events[0].UserID)
	assert.Equal(t, expiryTime, events[0].OccurredAt)
}

func TestExpireAlertDismissalByBatch_EmptyDismissals(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.ExpireAlertDismissalByBatchRequest{
		Dismissals: []*proto.ExpiredAlertDismissal{},
	}
	_, err = server.ExpireAlertDismissalByBatch(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "dismissals")
}

func TestExpireAlertDismissalByBatch_MissingRepositoryId(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	expiryTime := time.Now()
	req := &proto.ExpireAlertDismissalByBatchRequest{
		Dismissals: []*proto.ExpiredAlertDismissal{
			{
				AlertNumber:     1,
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
		},
	}
	_, err = server.ExpireAlertDismissalByBatch(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "repository_id")
}

func TestExpireAlertDismissalByBatch_MissingNumber(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	expiryTime := time.Now()
	req := &proto.ExpireAlertDismissalByBatchRequest{
		Dismissals: []*proto.ExpiredAlertDismissal{
			{
				RepositoryId:    1,
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
		},
	}
	_, err = server.ExpireAlertDismissalByBatch(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "alert_number")
}

func TestExpireAlertDismissalByBatch_MissingExpiryTimestamp(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	req := &proto.ExpireAlertDismissalByBatchRequest{
		Dismissals: []*proto.ExpiredAlertDismissal{
			{
				RepositoryId: 1,
				AlertNumber:  1,
			},
		},
	}
	_, err = server.ExpireAlertDismissalByBatch(t.Context(), req)
	require.Error(t, err)

	var reqArgErr twirperr.Error
	assert.True(t, errors.As(err, &reqArgErr))
	assert.Equal(t, twirperr.ErrorCode("invalid_argument"), reqArgErr.Code())
	assert.Contains(t, reqArgErr.Msg(), "expiry_timestamp")
}

func TestExpireAlertDismissalByBatch_AlertNotFound(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	expiryTime := time.Now()
	req := &proto.ExpireAlertDismissalByBatchRequest{
		Dismissals: []*proto.ExpiredAlertDismissal{
			{
				RepositoryId:    999,
				AlertNumber:     999,
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
		},
	}
	_, err = server.ExpireAlertDismissalByBatch(t.Context(), req)
	require.Error(t, err)

	var notFoundErr twirperr.Error
	assert.True(t, errors.As(err, &notFoundErr))
	assert.Equal(t, twirperr.ErrorCode("not_found"), notFoundErr.Code())
}

func TestExpireAlertDismissalByBatch_Success(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	s := app.Subsystems.Storage
	ctx := t.Context()
	expiryTime := time.Now().Truncate(time.Second)

	// Create three alerts in ReviewRequested state
	alerts := []models.Alert{
		{
			RepositoryID:          1,
			Status:                models.AlertStatusReviewRequested,
			ManifestName:          "package.json",
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "pkg1",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "MIT",
		},
		{
			RepositoryID:          1,
			Status:                models.AlertStatusReviewRequested,
			ManifestName:          "package.json",
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "pkg2",
			PackageVersion:        "2.0.0",
			SPDXLicenseExpression: "Apache-2.0",
		},
		{
			RepositoryID:          2,
			Status:                models.AlertStatusReviewRequested,
			ManifestName:          "go.mod",
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			PackageName:           "pkg3",
			PackageVersion:        "3.0.0",
			SPDXLicenseExpression: "BSD-3-Clause",
		},
	}

	for idx, alert := range alerts {
		createdAlert, err := s.CreateAlert(ctx, alert)
		require.NoError(t, err)

		// Number and ID exist only after creating alert
		alerts[idx].Number = createdAlert.Number
		alerts[idx].ID = createdAlert.ID
	}

	req := &proto.ExpireAlertDismissalByBatchRequest{
		Dismissals: []*proto.ExpiredAlertDismissal{
			{
				RepositoryId:    alerts[0].RepositoryID,
				AlertNumber:     alerts[0].Number,
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
			{
				RepositoryId:    alerts[1].RepositoryID,
				AlertNumber:     alerts[1].Number,
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
			{
				RepositoryId:    alerts[2].RepositoryID,
				AlertNumber:     alerts[2].Number,
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
		},
	}

	resp, err := server.ExpireAlertDismissalByBatch(ctx, req)
	require.NoError(t, err)
	require.Len(t, resp.ExpiredAlerts, 3)

	// Verify response contains correct alert data
	for i, expiredAlert := range resp.ExpiredAlerts {
		assert.Equal(t, alerts[i].RepositoryID, expiredAlert.RepositoryId)
		assert.Equal(t, alerts[i].Number, expiredAlert.AlertNumber)
		assert.Equal(t, alerts[i].ID, expiredAlert.AlertId)
	}

	// Verify all alerts are now Open
	alert1, err := s.GetAlert(ctx, alerts[0].RepositoryID, alerts[0].Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen, alert1.Status)

	alert2, err := s.GetAlert(ctx, alerts[1].RepositoryID, alerts[1].Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen, alert2.Status)

	alert3, err := s.GetAlert(ctx, alerts[2].RepositoryID, alerts[2].Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen, alert3.Status)
}

func TestExpireAlertDismissalByBatch_SkipsInvalidStates(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	s := app.Subsystems.Storage
	ctx := t.Context()
	expiryTime := time.Now().Truncate(time.Second)

	// Create alerts in different states
	alerts := []models.Alert{
		{
			RepositoryID:          1,
			Status:                models.AlertStatusReviewRequested, // Valid
			ManifestName:          "package.json",
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "pkg1",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "MIT",
		},
		{
			RepositoryID:          1,
			Status:                models.AlertStatusOpen, // Already open, will be skipped
			ManifestName:          "package.json",
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "pkg2",
			PackageVersion:        "2.0.0",
			SPDXLicenseExpression: "Apache-2.0",
		},
		{
			RepositoryID:          1,
			Status:                models.AlertStatusReviewRequested, // Valid
			ManifestName:          "package.json",
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "pkg3",
			PackageVersion:        "3.0.0",
			SPDXLicenseExpression: "BSD-3-Clause",
		},
	}

	for idx, alert := range alerts {
		createdAlert, err := s.CreateAlert(ctx, alert)
		require.NoError(t, err)

		// Number and ID exist only after creating alert
		alerts[idx].Number = createdAlert.Number
		alerts[idx].ID = createdAlert.ID
	}

	req := &proto.ExpireAlertDismissalByBatchRequest{
		Dismissals: []*proto.ExpiredAlertDismissal{
			{
				RepositoryId:    alerts[0].RepositoryID,
				AlertNumber:     alerts[0].Number,
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
			{
				RepositoryId:    alerts[1].RepositoryID,
				AlertNumber:     alerts[1].Number, // This one is already Open
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
			{
				RepositoryId:    alerts[2].RepositoryID,
				AlertNumber:     alerts[2].Number,
				ExpiryTimestamp: timestamppb.New(expiryTime),
			},
		},
	}

	// Should succeed even though alert 2 is already Open
	resp, err := server.ExpireAlertDismissalByBatch(ctx, req)
	require.NoError(t, err)
	require.Len(t, resp.ExpiredAlerts, 2)

	// Verify response contains only successfully expired alerts (1 and 3, skipping 2)
	expectedAlerts := []models.Alert{alerts[0], alerts[2]}
	for i, expiredAlert := range resp.ExpiredAlerts {
		assert.Equal(t, expectedAlerts[i].RepositoryID, expiredAlert.RepositoryId)
		assert.Equal(t, expectedAlerts[i].Number, expiredAlert.AlertNumber)
		assert.Equal(t, expectedAlerts[i].ID, expiredAlert.AlertId)
	}

	// Verify alert 1 and 3 are now Open
	alert1, err := s.GetAlert(ctx, alerts[0].RepositoryID, alerts[0].Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen, alert1.Status)

	alert2, err := s.GetAlert(ctx, alerts[1].RepositoryID, alerts[1].Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen, alert2.Status) // Still Open

	alert3, err := s.GetAlert(ctx, alerts[2].RepositoryID, alerts[2].Number)
	require.NoError(t, err)
	assert.Equal(t, models.AlertStatusOpen, alert3.Status)
}
