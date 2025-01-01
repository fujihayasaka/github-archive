package devices

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/twitchtv/twirp"
)

func (mdm *MobileDeviceManager) FindDeviceKeyRegistration(ctx context.Context, req *pb.FindDeviceKeyRegistrationRequest) (*pb.FindDeviceKeyRegistrationResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "find_device_key_registration")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.FindDeviceKeyRegistration")
	defer span.End()

	diagnostics.Logger(ctx).Info("received FindDeviceKeyRegistration request")

	// parse the type of request
	var request *pb.RegistrationRequest
	switch req.GetKind().(type) {
	case *pb.FindDeviceKeyRegistrationRequest_AuthRegistrationRequest:
		request = req.GetAuthRegistrationRequest()
	default:
		err := errors.Errorf("unknown FindDeviceKeyRegistration request: %T", req.GetKind())
		diagnostics.Logger(ctx).WithError(err).Info("FindDeviceKeyRegistration error")
		return &pb.FindDeviceKeyRegistrationResponse{
			Result: pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_GENERIC,
		}, err
	}

	diagnostics.Logger(ctx).Info("parsed FindDeviceKeyRegistration request type")

	resp, err := mdm.findDeviceKeyRegistration(ctx, request)
	if resp == nil {
		resp = &pb.FindDeviceKeyRegistrationResponse{
			Result: pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_GENERIC,
		}
	}
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("FindDeviceKeyRegistration error", kvp.String("result", resp.Result.String()))
	}

	tags := stats.Tags{"result": resp.Result.String()}
	statter := diagnostics.Statter(ctx)
	statter.Counter("mobile_device.find_device_key_registration.count", tags, 1)
	statter.DistributionMs("mobile_device.find_device_key_registration.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) findDeviceKeyRegistration(ctx context.Context, req *pb.RegistrationRequest) (*pb.FindDeviceKeyRegistrationResponse, error) {
	// check required arguments
	err := mdm.checkFindDeviceKeyRegistrationArguments(ctx, req)
	if err != nil {
		return nil, err
	}

	ctx = diagnostics.WithLoggerFields(ctx, kvp.Int64("gh.oauth.access.id", req.OauthAccessId), kvp.Int64("gh.user.id", req.UserId))
	now := mdm.nowFunc()
	key, err := mdm.store.FindMobileDeviceKeyByUserIdAndOauthAccessId(ctx, models.DeviceKeyType_Auth, uint64(req.UserId), uint64(req.OauthAccessId), now)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("findDeviceKeyRegistration key lookup error")
		diagnostics.Statter(ctx).Counter("mobile_device.find_device_key_registration.unexpected", stats.Tags{"err": err.Error()}, 1)

		if errors.Is(err, common.StoreErrUnexpectedMultipleResults) {
			return &pb.FindDeviceKeyRegistrationResponse{
				Result: pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_GENERIC,
			}, nil
		}
		if errors.Is(err, common.StoreErrDeviceKeyUnexpectedExpired) || errors.Is(err, common.StoreErrDeviceKeyUnexpectedRevoked) || errors.Is(err, sql.ErrNoRows) {
			return &pb.FindDeviceKeyRegistrationResponse{
				Result: pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_NOT_FOUND,
			}, nil
		}
		return &pb.FindDeviceKeyRegistrationResponse{
			Result: pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_GENERIC,
		}, twirp.InternalErrorWith(err)
	}

	return &pb.FindDeviceKeyRegistrationResponse{
		Result: pb.FindDeviceKeyRegistrationResponse_RESULT_SUCCESS,
		Registration: &pb.DeviceKeyRegistration{
			Id:             int64(key.ID),
			DeviceName:     key.DeviceName,
			DeviceModel:    key.DeviceModel,
			DeviceOs:       key.DeviceOs,
			CreatedAtTime:  key.CreatedAt.ToProto(),
			ExpiresAtTime:  key.ExpiresAt.ToProto(),
			LastUsedAtTime: key.LastUsedAt.ToProto(),
			OauthAccessId:  int64(key.OauthAccessId),
		},
	}, nil
}

func (mdm *MobileDeviceManager) checkFindDeviceKeyRegistrationArguments(ctx context.Context, req *pb.RegistrationRequest) error {
	switch {
	case req.OauthAccessId == 0:
		return twirp.RequiredArgumentError("OauthAccessId")
	case req.UserId == 0:
		return twirp.RequiredArgumentError("UserId")
	}
	return nil
}
