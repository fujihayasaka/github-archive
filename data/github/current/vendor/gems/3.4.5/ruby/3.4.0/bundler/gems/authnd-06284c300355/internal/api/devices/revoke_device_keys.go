package devices

import (
	"context"
	"strconv"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

func (mdm *MobileDeviceManager) RevokeDeviceKeys(ctx context.Context, req *pb.RevokeDeviceKeysRequest) (*pb.RevokeDeviceKeysResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "revoke_device_keys")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.RevokeDeviceKeys")
	defer span.End()

	diagnostics.Logger(ctx).Info("received RevokeDeviceKeys request")

	var resp *pb.RevokeDeviceKeysResponse
	var err error
	var requestKind string
	switch req.GetKind().(type) {
	case *pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest:
		requestKind = "revoke_device_keys_request"
		ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.devices.request.kind", requestKind))
		resp, err = mdm.revokeDeviceAuthKeys(ctx, req.GetRevokeAuthKeysRequest())
	case *pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByOauthAccessesRequest:
		requestKind = "revoke_all_device_keys_by_oauth_accesses_request"
		ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.devices.request.kind", requestKind))
		resp, err = mdm.revokeAllDeviceKeysByOauthAccesses(ctx, req.GetRevokeAllDeviceKeysByOauthAccessesRequest())
	case *pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByIdsRequest:
		requestKind = "revoke_all_device_keys_by_ids_request"
		ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.devices.request.kind", requestKind))
		resp, err = mdm.revokeAllDeviceKeysByIds(ctx, req.GetRevokeAllDeviceKeysByIdsRequest())
	default:
		err = errors.Errorf("unknown RevokeDeviceKeys request: %T", req.GetKind())
	}

	if resp == nil {
		resp = &pb.RevokeDeviceKeysResponse{
			Result: pb.RevokeDeviceKeysResponse_RESULT_FAILED_GENERIC,
		}
	}

	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("RevokeDeviceKeys error", kvp.String("gh.authnd.devices.request.result", resp.Result.String()))
	}

	tags := stats.Tags{"result": resp.Result.String(), "request_kind": requestKind}
	statter := diagnostics.Statter(ctx)

	statter.Distribution("mobile_device.revoke_device_keys.key_count", tags, float64(len(resp.OauthAccessIds)))
	statter.Counter("mobile_device.revoke_device_keys.count", tags, 1)
	statter.DistributionMs("mobile_device.revoke_device_key.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) revokeDeviceAuthKeys(ctx context.Context, req *pb.RevokeDeviceAuthKeysRequest) (*pb.RevokeDeviceKeysResponse, error) {
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("UserId")
	}

	now := mdm.nowFunc()
	oauthAccessIds, err := mdm.store.RevokeMobileDeviceKeysByUserId(ctx, models.DeviceKeyType_Auth, uint64(req.UserId), now)
	if err != nil {
		return &pb.RevokeDeviceKeysResponse{
			Result: pb.RevokeDeviceKeysResponse_RESULT_FAILED_GENERIC,
		}, twirp.InternalErrorWith(err)
	}

	return &pb.RevokeDeviceKeysResponse{
		Result:         pb.RevokeDeviceKeysResponse_RESULT_SUCCESS,
		OauthAccessIds: oauthAccessIds,
	}, nil
}

func (mdm *MobileDeviceManager) revokeAllDeviceKeysByOauthAccesses(ctx context.Context, req *pb.RevokeAllDeviceKeysByOauthAccessesRequest) (*pb.RevokeDeviceKeysResponse, error) {
	if len(req.OauthAccessIds) == 0 {
		return &pb.RevokeDeviceKeysResponse{
			Result: pb.RevokeDeviceKeysResponse_RESULT_SUCCESS,
		}, nil
	}
	now := mdm.nowFunc()
	rowsAffected, err := mdm.store.RevokeMobileDeviceKeysByOauthAccessIds(ctx, req.OauthAccessIds, now)
	if err != nil {
		return &pb.RevokeDeviceKeysResponse{
			Result: pb.RevokeDeviceKeysResponse_RESULT_FAILED_GENERIC,
		}, twirp.InternalErrorWith(err)
	}
	diagnostics.Statter(ctx).Counter("mobile_device.revoke_all_device_keys_by_oauth_accesses", stats.Tags{"rowsAffected": strconv.Itoa(int(rowsAffected))}, 1)
	return &pb.RevokeDeviceKeysResponse{
		Result: pb.RevokeDeviceKeysResponse_RESULT_SUCCESS,
	}, nil
}

func (mdm *MobileDeviceManager) revokeAllDeviceKeysByIds(ctx context.Context, req *pb.RevokeAllDeviceKeysByIdsRequest) (*pb.RevokeDeviceKeysResponse, error) {
	if len(req.Ids) == 0 {
		return &pb.RevokeDeviceKeysResponse{
			Result: pb.RevokeDeviceKeysResponse_RESULT_SUCCESS,
		}, nil
	}
	now := mdm.nowFunc()
	rowsAffected, err := mdm.store.RevokeMobileDeviceKeysByIds(ctx, req.Ids, now)
	if err != nil {
		return &pb.RevokeDeviceKeysResponse{
			Result: pb.RevokeDeviceKeysResponse_RESULT_FAILED_GENERIC,
		}, twirp.InternalErrorWith(err)
	}
	diagnostics.Statter(ctx).Counter("mobile_device.revoke_all_device_keys_by_ids", stats.Tags{"rowsAffected": strconv.Itoa(int(rowsAffected))}, 1)
	return &pb.RevokeDeviceKeysResponse{
		Result: pb.RevokeDeviceKeysResponse_RESULT_SUCCESS,
	}, nil
}
