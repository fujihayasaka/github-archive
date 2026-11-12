package twirp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/transportmapper"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// GetAlert retrieves a license compliance alert by repository ID and alert number.
func (s *Server) GetAlert(ctx context.Context, req *proto.GetAlertRequest) (*proto.GetAlertResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.Number == 0 {
		return nil, twirp.RequiredArgumentError("number")
	}

	alert, err := s.app.Subsystems.Storage.GetAlert(ctx, req.RepositoryId, req.Number)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if alert == nil {
		return &proto.GetAlertResponse{Alert: nil, Events: nil}, nil
	}

	// Fetch alert events
	events, err := s.app.Subsystems.Storage.GetAlertEvents(ctx, alert.ID)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	// Convert events to proto
	protoEvents := make([]*proto.AlertEvent, 0, len(events))
	for i := range events {
		protoEvents = append(protoEvents, transportmapper.ModelToProtoAlertEvent(&events[i]))
	}

	return &proto.GetAlertResponse{
		Alert:  modelToProtoAlert(alert),
		Events: protoEvents,
	}, nil
}

// modelToProtoAlert converts a models.Alert to a proto.Alert.
func modelToProtoAlert(alert *models.Alert) *proto.Alert {
	if alert == nil {
		return nil
	}
	return &proto.Alert{
		Id:                 alert.ID,
		Number:             alert.Number,
		Status:             transportmapper.ModelToProtoAlertStatus(alert.Status),
		Resolution:         transportmapper.ModelToProtoAlertResolution(alert.Resolution),
		CreatedAt:          timestamppb.New(alert.CreatedAt),
		RepositoryId:       alert.RepositoryID,
		OrganizationId:     alert.OrganizationID,
		EnterpriseId:       pointers.ValueOrZero(alert.EnterpriseID),
		ManifestName:       alert.ManifestName,
		ManifestLineNumber: alert.ManifestLineNumber,
		PackageEcosystem:   alert.PackageEcosystem,
		PackageName:        alert.PackageName,
		PackageVersion:     alert.PackageVersion,
		License:            alert.SPDXLicenseExpression,
		PullRequestNumber:  pointers.ValueOrZero(alert.PullRequestNumber),
	}
}

// RequestAlertDismissal requests the dismissal of an alert, changing its status to "ReviewRequested".
func (s *Server) RequestAlertDismissal(ctx context.Context, req *proto.RequestAlertDismissalRequest) (*proto.RequestAlertDismissalResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.Number == 0 {
		return nil, twirp.RequiredArgumentError("number")
	}
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("user_id")
	}

	alert, err := s.app.Subsystems.Storage.GetAlert(ctx, req.RepositoryId, req.Number)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if alert == nil {
		return nil, twirp.NotFoundError("alert not found")
	}

	err = s.app.Subsystems.Storage.UpdateAlertStatusWithEvent(ctx, alert, models.ReviewRequested, models.EventReviewRequested, json.RawMessage("{}"), &req.UserId)
	if err != nil {
		if errors.Is(err, storage.ErrStatusChangeNotAllowed) {
			return nil, twirp.FailedPrecondition.Error("alert status cannot be changed to review requested")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.RequestAlertDismissalResponse{
		Success: true,
	}, nil
}

// DenyAlertDismissal denies a previously requested alert dismissal, changing its status to "ReviewDenied".
func (s *Server) DenyAlertDismissal(ctx context.Context, req *proto.DenyAlertDismissalRequest) (*proto.DenyAlertDismissalResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.Number == 0 {
		return nil, twirp.RequiredArgumentError("number")
	}
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("user_id")
	}
	if req.Comment == "" {
		return nil, twirp.RequiredArgumentError("comment")
	}

	alert, err := s.app.Subsystems.Storage.GetAlert(ctx, req.RepositoryId, req.Number)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if alert == nil {
		return nil, twirp.NotFoundError("alert not found")
	}

	err = s.app.Subsystems.Storage.UpdateAlertStatusWithEvent(ctx, alert, models.ReviewDenied, models.EventReviewDenied, json.RawMessage(fmt.Sprintf(`{"comment": %q}`, req.Comment)), &req.UserId)
	if err != nil {
		if errors.Is(err, storage.ErrStatusChangeNotAllowed) {
			return nil, twirp.FailedPrecondition.Error("alert status cannot be changed to request denied")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.DenyAlertDismissalResponse{
		Success: true,
	}, nil
}

// GetReviewableAlerts retrieves all alerts with status "ReviewRequested" for a given organization or enterprise.
func (s *Server) GetReviewableAlerts(ctx context.Context, req *proto.GetReviewableAlertsRequest) (*proto.GetReviewableAlertsResponse, error) {
	if req.OrganizationId == 0 && req.EnterpriseId == 0 {
		return nil, twirp.InvalidArgumentError("organization_id or enterprise_id", "one of organization_id or enterprise_id must be set")
	}
	if req.OrganizationId != 0 && req.EnterpriseId != 0 {
		return nil, twirp.InvalidArgumentError("organization_id and enterprise_id", "organization_id and enterprise_id cannot both be set")
	}

	alerts, err := s.app.Subsystems.Storage.GetReviewableAlertsForOrgOrEnterprise(ctx, req.OrganizationId, req.EnterpriseId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	protoAlerts := make([]*proto.Alert, 0, len(alerts))
	for _, alert := range alerts {
		protoAlert := modelToProtoAlert(alert)
		protoAlerts = append(protoAlerts, protoAlert)
	}

	return &proto.GetReviewableAlertsResponse{
		Alerts: protoAlerts,
	}, nil
}
