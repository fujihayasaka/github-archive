package devices

import (
	"context"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

func (mdm *MobileDeviceManager) RevokeDeviceKey(ctx context.Context, req *pb.RevokeDeviceKeyRequest) (*pb.RevokeDeviceKeyResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "revoke_device_key")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.RevokeDeviceKey")
	defer span.End()

	diagnostics.Logger(ctx).Info("received RevokeDeviceKey request")

	var resp *pb.RevokeDeviceKeyResponse
	var err error
	var requestKind string
	switch req.GetKind().(type) {
	case *pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest:
		requestKind = "revoke_auth_key_request"
		ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.devices.request.kind", requestKind))
		resp, err = mdm.revokeDeviceAuthKey(ctx, req.GetRevokeAuthKeyRequest())
	default:
		err = errors.Errorf("unknown RevokeDeviceKey request: %T", req.GetKind())
	}

	if resp == nil {
		resp = &pb.RevokeDeviceKeyResponse{
			Result: pb.RevokeDeviceKeyResponse_RESULT_FAILED_GENERIC,
		}
	}
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("RevokeDeviceKey error", kvp.String("gh.authnd.devices.request.result", resp.Result.String()))
	}

	tags := stats.Tags{"result": resp.Result.String(), "request_kind": requestKind}
	statter := diagnostics.Statter(ctx)
	statter.Counter("mobile_device.revoke_device_key.count", tags, 1)
	statter.DistributionMs("mobile_device.revoke_device_key.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) revokeDeviceAuthKey(ctx context.Context, req *pb.RevokeDeviceAuthKeyRequest) (*pb.RevokeDeviceKeyResponse, error) {
	if req.OauthAccessId == 0 {
		return nil, twirp.RequiredArgumentError("OauthAccessId")
	}

	_, err := mdm.store.RevokeMobileDeviceKeysByOauthAccessId(ctx, models.DeviceKeyType_Auth, uint64(req.OauthAccessId), mdm.nowFunc())
	if err != nil {
		return &pb.RevokeDeviceKeyResponse{
			Result: pb.RevokeDeviceKeyResponse_RESULT_FAILED_GENERIC,
		}, twirp.InternalErrorWith(err)
	}

	return &pb.RevokeDeviceKeyResponse{
		Result: pb.RevokeDeviceKeyResponse_RESULT_SUCCESS,
	}, nil
}
