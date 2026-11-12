package twirp

import (
	"context"
	"errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/github/osslicensecompliance/internal/remediation"
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
		PackageRepoNwo:     alert.PackageRepoNWO,
		ClosureReason:      transportmapper.ModelToProtoClosureReason(alert.ClosureReason),
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

	if err := s.requestAlertDismissal(ctx, alert, req.UserId, req.Comment, req.ClosureReason); err != nil {
		return nil, err
	}

	return &proto.RequestAlertDismissalResponse{
		Success: true,
	}, nil
}

// RequestAlertDismissalById requests the dismissal of an alert by its ID, changing its status to "ReviewRequested".
//
//nolint:revive // Method name matches generated proto interface (uses 'Id' for Ruby snake_case compatibility)
func (s *Server) RequestAlertDismissalById(ctx context.Context, req *proto.RequestAlertDismissalByIdRequest) (*proto.RequestAlertDismissalByIdResponse, error) {
	if req.AlertId == 0 {
		return nil, twirp.RequiredArgumentError("alert_id")
	}
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("user_id")
	}

	alert, err := s.app.Subsystems.Storage.GetAlertByID(ctx, req.AlertId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if alert == nil {
		return nil, twirp.NotFoundError("alert not found")
	}

	if err := s.requestAlertDismissal(ctx, alert, req.UserId, req.Comment, req.ClosureReason); err != nil {
		return nil, err
	}

	return &proto.RequestAlertDismissalByIdResponse{
		Success: true,
	}, nil
}

func (s *Server) requestAlertDismissal(ctx context.Context, alert *models.Alert, userID uint64, comment string, closureReason proto.ClosureReason) error {
	err := remediation.RequestAlertClosure(
		ctx, s.app, alert, userID, comment, models.ClosureReasonFromProto(closureReason),
	)

	if err != nil {
		if errors.Is(err, remediation.ErrStatusChangeNotAllowed) {
			return twirp.FailedPrecondition.Error("alert status cannot be changed to review requested")
		} else if errors.Is(err, storage.ErrConcurrentStatusChange) {
			return twirp.FailedPrecondition.Error("alert status has changed since last read; concurrent modification detected")
		}
		return twirp.InternalErrorWith(err)
	}

	return nil
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

	err = remediation.DenyClosureRequest(
		ctx, s.app, alert, req.UserId, req.Comment,
	)

	if err != nil {
		if errors.Is(err, remediation.ErrStatusChangeNotAllowed) {
			return nil, twirp.FailedPrecondition.Error("alert status cannot be changed to request denied")
		} else if errors.Is(err, storage.ErrConcurrentStatusChange) {
			return nil, twirp.FailedPrecondition.Error("alert status has changed since last read; concurrent modification detected")
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

// ExpireAlertDismissal expires a review request, changing the alert status from "ReviewRequested" back to "Open".
func (s *Server) ExpireAlertDismissal(ctx context.Context, req *proto.ExpireAlertDismissalRequest) (*proto.ExpireAlertDismissalResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.Number == 0 {
		return nil, twirp.RequiredArgumentError("number")
	}
	if req.ExpiryTimestamp == nil {
		return nil, twirp.RequiredArgumentError("expiry_timestamp")
	}

	alert, err := s.app.Subsystems.Storage.GetAlert(ctx, req.RepositoryId, req.Number)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if alert == nil {
		return nil, twirp.NotFoundError("alert not found")
	}

	err = remediation.ExpireClosureRequest(
		ctx, s.app, alert, req.ExpiryTimestamp.AsTime(),
	)
	if err != nil {
		if errors.Is(err, remediation.ErrStatusChangeNotAllowed) {
			return nil, twirp.FailedPrecondition.Error("alert not in review requested state")
		} else if errors.Is(err, storage.ErrConcurrentStatusChange) {
			return nil, twirp.FailedPrecondition.Error("alert status has changed since last read; concurrent modification detected")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	// Fetch updated alert events
	events, err := s.app.Subsystems.Storage.GetAlertEvents(ctx, alert.ID)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	// Convert events to proto
	protoEvents := make([]*proto.AlertEvent, 0, len(events))
	for i := range events {
		protoEvents = append(protoEvents, transportmapper.ModelToProtoAlertEvent(&events[i]))
	}

	return &proto.ExpireAlertDismissalResponse{
		Alert:  modelToProtoAlert(alert),
		Events: protoEvents,
	}, nil
}

// ExpireAlertDismissalByBatch expires a batch of review requests, changing alert statuses from "ReviewRequested" back to "Open".
func (s *Server) ExpireAlertDismissalByBatch(ctx context.Context, req *proto.ExpireAlertDismissalByBatchRequest) (*proto.ExpireAlertDismissalByBatchResponse, error) {
	if len(req.Dismissals) == 0 {
		return nil, twirp.RequiredArgumentError("dismissals")
	}

	expiredAlerts := []*proto.ExpiredAlert{}

	for _, dismissal := range req.Dismissals {
		if dismissal == nil {
			return nil, twirp.RequiredArgumentError("dismissal")
		}
		if dismissal.RepositoryId == 0 {
			return nil, twirp.RequiredArgumentError("repository_id")
		}
		if dismissal.AlertNumber == 0 {
			return nil, twirp.RequiredArgumentError("alert_number")
		}
		if dismissal.ExpiryTimestamp == nil {
			return nil, twirp.RequiredArgumentError("expiry_timestamp")
		}

		alert, err := s.app.Subsystems.Storage.GetAlert(ctx, dismissal.RepositoryId, dismissal.AlertNumber)
		if err != nil {
			return nil, twirp.InternalErrorWith(err)
		}
		if alert == nil {
			return nil, twirp.NotFoundError("alert not found")
		}

		err = remediation.ExpireClosureRequest(
			ctx, s.app, alert, dismissal.ExpiryTimestamp.AsTime(),
		)
		if err != nil {
			// Skip alerts that are not in ReviewRequested state or were already synced (changed to open) concurrently,
			// Not an error, since they're already in the desired state.
			if errors.Is(err, remediation.ErrStatusChangeNotAllowed) || errors.Is(err, storage.ErrConcurrentStatusChange) {
				s.app.Logger.Info("skipped expiring alert: alert already in desired status or status changed concurrently",
					kvp.Uint64("repository_id", dismissal.RepositoryId),
					kvp.Int64("alert_number", int64(dismissal.AlertNumber)),
					kvp.String("alert_status", alert.Status.String()),
					kvp.Err(err))
				continue
			}
			return nil, twirp.InternalErrorWith(err)
		}

		expiredAlerts = append(expiredAlerts, &proto.ExpiredAlert{
			RepositoryId: alert.RepositoryID,
			AlertId:      alert.ID,
			AlertNumber:  alert.Number,
		})
	}

	return &proto.ExpireAlertDismissalByBatchResponse{
		ExpiredAlerts: expiredAlerts,
	}, nil
}
