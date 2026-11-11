package twirp

import (
	"errors"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	twirperr "github.com/twitchtv/twirp"
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

	resolution := models.PolicyChanged
	businessID := uint64(10)
	pullRequestNumber := uint32(5)

	// First, create an alert directly in the storage
	alertInfo := models.Alert{
		Number:                1,
		Resolution:            &resolution,
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
	assert.Equal(t, proto.AlertResolution_ALERT_RESOLUTION_POLICY_CHANGED, resp.Alert.Resolution)
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

func TestRequestAlertDismissal_InvalidTransition(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// Create an alert and manually set its status to Closed
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
	r.Equal(models.Open, alert.Status)

	retrievedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
	r.NoError(err)

	err = s.CloseAlertWithEvent(ctx, retrievedAlert, nil, models.ExceptionAdded, nil)
	r.NoError(err)
	retrievedAlert, err = s.GetAlert(ctx, repositoryID, alert.Number)
	r.NoError(err)
	r.Equal(models.Closed, retrievedAlert.Status)

	req := &proto.RequestAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
		UserId:       1,
	}
	_, err = server.RequestAlertDismissal(ctx, req)
	require.Error(t, err)

	var twirpErr twirperr.Error
	assert.True(t, errors.As(err, &twirpErr))
	assert.Equal(t, twirperr.ErrorCode("failed_precondition"), twirpErr.Code())

	retrievedAlert, err = s.GetAlert(ctx, repositoryID, alert.Number)
	r.NoError(err)
	r.Equal(models.Closed, retrievedAlert.Status) // still Closed
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
	r.Equal(models.Open, alert.Status)

	req := &proto.RequestAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
		UserId:       1,
	}
	_, err = server.RequestAlertDismissal(ctx, req)
	r.NoError(err)

	updatedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
	r.NoError(err)
	r.Equal(models.ReviewRequested, updatedAlert.Status)

	// Check that an AlertEvent was created
	events, err := s.GetAlertEvents(ctx, updatedAlert.ID)
	r.NoError(err)
	r.Len(events, 1)
	assert.Equal(t, models.EventReviewRequested, events[0].EventType)
	assert.Equal(t, &req.UserId, events[0].UserID)
	assert.JSONEq(t, "{}", string(events[0].EventBody))
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
	r.Equal(models.Open, alert.Status)

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

func TestDenyAlertDismissal_InvalidTransition(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// Create an alert and leave its status as Open
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
	}

	_, err = s.CreateAlert(ctx, alert)
	require.NoError(t, err)
	retrievedAlert, err := s.GetAlert(ctx, repositoryID, alert.Number)
	require.NoError(t, err)
	require.Equal(t, models.Open, retrievedAlert.Status)
	req := &proto.DenyAlertDismissalRequest{
		RepositoryId: repositoryID,
		Number:       alert.Number,
		UserId:       1,
		Comment:      "Not valid",
	}

	_, err = server.DenyAlertDismissal(ctx, req)
	require.Error(t, err)

	var twirpErr twirperr.Error
	assert.True(t, errors.As(err, &twirpErr))
	assert.Equal(t, twirperr.ErrorCode("failed_precondition"), twirpErr.Code())

	retrievedAlert, err = s.GetAlert(ctx, repositoryID, alert.Number)
	require.NoError(t, err)
	assert.Equal(t, models.Open, retrievedAlert.Status)
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
	r.Equal(models.Open, alert.Status)

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
	require.Equal(t, models.ReviewDenied, updatedAlert.Status)

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

func TestGetReviewableAlerts_OrgAndEnterprise(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	ctx := t.Context()
	orgID := uint64(100)
	entID := uint64(200)

	// Create alerts with different statuses and org/enterprise IDs
	alerts := []models.Alert{
		{Number: 1, OrganizationID: orgID, Status: models.ReviewRequested, PackageName: "a"},
		{Number: 2, OrganizationID: orgID, Status: models.Open, PackageName: "b"},
		{Number: 3, EnterpriseID: &entID, Status: models.ReviewRequested, PackageName: "c"},
		{Number: 4, EnterpriseID: &entID, Status: models.Closed, PackageName: "d"},
		{Number: 5, OrganizationID: orgID, Status: models.ReviewRequested, PackageName: "e"},
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
	r.Equal(models.Open, createdAlert.Status)

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
