package devices

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/twitchtv/twirp"
)

func (mdm *MobileDeviceManager) GetDeviceAuthStatus(ctx context.Context, req *pb.GetDeviceAuthStatusRequest) (*pb.GetDeviceAuthStatusResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "get_device_auth_status")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.GetDeviceAuthStatus")
	defer span.End()

	diagnostics.Logger(ctx).Info("received GetDeviceAuthStatus request")

	resp, err := mdm.deviceAuthStatus(ctx, req)
	if resp == nil {
		resp = &pb.GetDeviceAuthStatusResponse{
			Result: pb.GetDeviceAuthStatusResponse_RESULT_FAILED_GENERIC,
		}
	}
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("GetDeviceAuthStatus error", kvp.String("gh.authnd.mobile_auth.request.result", resp.Result.String()))
	}

	tags := stats.Tags{"result": resp.Result.String()}
	tags["status"] = resp.Status.String()
	statter := diagnostics.Statter(ctx)
	statter.Counter("mobile_device.get_device_auth_status.count", tags, 1)
	statter.DistributionMs("mobile_device.get_device_auth_status.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) deviceAuthStatus(ctx context.Context, req *pb.GetDeviceAuthStatusRequest) (*pb.GetDeviceAuthStatusResponse, error) {
	err := mdm.checkGetDeviceAuthStatusArguments(ctx, req)
	if err != nil {
		return nil, err
	}

	authRequest, err := mdm.store.FindMobileAuthRequestByIdAndUserId(ctx, uint64(req.Id), uint64(req.UserId))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return &pb.GetDeviceAuthStatusResponse{
				Result: pb.GetDeviceAuthStatusResponse_RESULT_FAILED_NOT_FOUND,
			}, nil
		} else {
			return &pb.GetDeviceAuthStatusResponse{
				Result: pb.GetDeviceAuthStatusResponse_RESULT_FAILED_GENERIC,
			}, twirp.InternalErrorWith(err)
		}
	}

	requestType := mobiledeviceauth.GetRequestTypeName(authRequest.Type)
	// adding requestType implicitly to logger and statter
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.mobile_auth.request.type", requestType))
	ctx = diagnostics.WithStatterTags(ctx, stats.Tags{"request_type": requestType})
	diagnostics.Logger(ctx).Info("GetDeviceAuthStatus resolve request type")

	now := mdm.nowFunc()

	var status pb.GetDeviceAuthStatusResponse_Status
	switch {
	case authRequest.IsExpired(now): // expiration takes precedence over all statuses
		status = pb.GetDeviceAuthStatusResponse_STATUS_EXPIRED
	case authRequest.IsActive(now):
		status = pb.GetDeviceAuthStatusResponse_STATUS_ACTIVE
	case authRequest.IsRejected(now):
		status = pb.GetDeviceAuthStatusResponse_STATUS_REJECTED
	case authRequest.IsApproved(now):
		status = pb.GetDeviceAuthStatusResponse_STATUS_APPROVED
	default:
		status = pb.GetDeviceAuthStatusResponse_STATUS_UNKNOWN
	}

	return &pb.GetDeviceAuthStatusResponse{
		Result: pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS,
		Status: status,
	}, nil
}

func (mdm *MobileDeviceManager) checkGetDeviceAuthStatusArguments(ctx context.Context, req *pb.GetDeviceAuthStatusRequest) error {
	switch {
	case req.Id == 0:
		return twirp.RequiredArgumentError("Id")
	case req.UserId == 0:
		return twirp.RequiredArgumentError("UserId")
	}
	return nil
}
