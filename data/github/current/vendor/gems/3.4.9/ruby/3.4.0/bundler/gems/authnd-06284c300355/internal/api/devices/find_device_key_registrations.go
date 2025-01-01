package devices

import (
	"context"
	"database/sql"
	"time"

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

func (mdm *MobileDeviceManager) FindDeviceKeyRegistrations(ctx context.Context, req *pb.FindDeviceKeyRegistrationsRequest) (*pb.FindDeviceKeyRegistrationsResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "find_device_key_registrations")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.FindDeviceKeyRegistrations")
	defer span.End()

	diagnostics.Logger(ctx).Info("received FindDeviceKeyRegistrations request")

	// parse the type of request
	var request *pb.RegistrationsRequest
	switch req.GetKind().(type) {
	case *pb.FindDeviceKeyRegistrationsRequest_AuthRegistrationsRequest:
		request = req.GetAuthRegistrationsRequest()
	default:
		err := errors.Errorf("unknown find device key registrations request: %T", req.GetKind())
		diagnostics.Logger(ctx).WithError(err).Info("FindDeviceKeyRegistrations error")
		return &pb.FindDeviceKeyRegistrationsResponse{
			Result: pb.FindDeviceKeyRegistrationsResponse_RESULT_FAILED_GENERIC,
		}, err
	}

	diagnostics.Logger(ctx).Info("parsed FindDeviceKeyRegistrations request type")

	resp, err := mdm.findDeviceKeyRegistrations(ctx, request)
	if resp == nil {
		resp = &pb.FindDeviceKeyRegistrationsResponse{
			Result: pb.FindDeviceKeyRegistrationsResponse_RESULT_FAILED_GENERIC,
		}
	}
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("FindDeviceKeyRegistrations error", kvp.String("result", resp.Result.String()))
	}

	tags := stats.Tags{"result": resp.Result.String()}
	statter := diagnostics.Statter(ctx)

	if len(resp.Registrations) > 0 {
		statter.Distribution("mobile_device.find_device_key_registrations.length", tags, float64(len(resp.Registrations)))
	}
	statter.Counter("mobile_device.find_device_key_registrations.count", tags, 1)
	statter.DistributionMs("mobile_device.find_device_key_registrations.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) findDeviceKeyRegistrations(ctx context.Context, req *pb.RegistrationsRequest) (*pb.FindDeviceKeyRegistrationsResponse, error) {
	// check required arguments
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("UserId")
	}

	now := mdm.nowFunc()
	deviceKeys, err := mdm.store.FindMobileDeviceKeysByUserId(ctx, models.DeviceKeyType_Auth, uint64(req.UserId), now)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return &pb.FindDeviceKeyRegistrationsResponse{
				Result: pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS,
			}, nil
		}
		return &pb.FindDeviceKeyRegistrationsResponse{
			Result: pb.FindDeviceKeyRegistrationsResponse_RESULT_FAILED_GENERIC,
		}, twirp.InternalErrorWith(err)
	}

	pbRegistrations := make([]*pb.DeviceKeyRegistration, len(deviceKeys))
	for i, deviceKey := range deviceKeys {
		pbRegistrations[i] = &pb.DeviceKeyRegistration{
			Id:             int64(deviceKey.ID),
			DeviceName:     deviceKey.DeviceName,
			DeviceModel:    deviceKey.DeviceModel,
			DeviceOs:       deviceKey.DeviceOs,
			CreatedAtTime:  deviceKey.CreatedAt.ToProto(),
			ExpiresAtTime:  deviceKey.ExpiresAt.ToProto(),
			LastUsedAtTime: deviceKey.LastUsedAt.ToProto(),
			OauthAccessId:  int64(deviceKey.OauthAccessId),
		}
	}

	return &pb.FindDeviceKeyRegistrationsResponse{
		Result:        pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS,
		Registrations: pbRegistrations,
	}, nil
}
