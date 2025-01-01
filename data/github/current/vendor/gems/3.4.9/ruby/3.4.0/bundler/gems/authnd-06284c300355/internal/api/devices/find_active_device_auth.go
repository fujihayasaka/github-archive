package devices

import (
	"context"
	"database/sql"
	"encoding/base64"
	"time"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/twitchtv/twirp"
)

func (mdm *MobileDeviceManager) FindActiveDeviceAuth(ctx context.Context, req *pb.FindActiveDeviceAuthRequest) (*pb.FindActiveDeviceAuthResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "find_active_device_auth")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.FindActiveDeviceAuth")
	defer span.End()

	diagnostics.Logger(ctx).Info("received FindActiveDeviceAuth request")

	resp, err := mdm.findActiveDeviceAuth(ctx, req)
	if resp == nil {
		resp = &pb.FindActiveDeviceAuthResponse{
			Result: pb.FindActiveDeviceAuthResponse_RESULT_FAILED_GENERIC,
		}
	}
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("FindActiveDeviceAuth error", kvp.String("gh.authnd.mobile_auth.request.result", resp.Result.String()))
	}

	// attaching a logger to the context that includes request type, so it does not need to be repeated in all logging statements
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.mobile_auth.request.type", resp.Type))

	// Same as with the logger, attaching a statter to the context with a request type tag
	ctx = diagnostics.WithStatterTags(ctx, stats.Tags{"request_type": resp.Type})
	statter := diagnostics.Statter(ctx)

	tags := stats.Tags{"result": resp.Result.String(), "request_type": resp.Type}
	statter.Counter("mobile_device.find_active_device_auth.count", tags, 1)
	statter.DistributionMs("mobile_device.find_active_device_auth.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) findActiveDeviceAuth(ctx context.Context, req *pb.FindActiveDeviceAuthRequest) (*pb.FindActiveDeviceAuthResponse, error) {
	err := mdm.checkFindActiveDeviceAuthArguments(ctx, req)
	if err != nil {
		return nil, err
	}

	ctx = diagnostics.WithLoggerFields(ctx, kvp.Int64("gh.oauth.access.id", req.OauthAccessId), kvp.Int64("gh.user.id", req.UserId))
	now := mdm.nowFunc()

	// lookup whether the caller has a valid device key to be returned as response context
	hasValidDeviceKey := true
	deviceKey, err := mdm.store.FindMobileDeviceKeyByUserIdAndOauthAccessId(ctx, models.DeviceKeyType_Auth, uint64(req.UserId), uint64(req.OauthAccessId), now)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("findActiveDeviceAuth key lookup error")
		// this should never happen, but we should handle it gracefully
		// this is a case where an oauth access id ends up with multiple valid device auth keys
		// we protect against this at device auth key registration time
		if errors.Is(err, common.StoreErrUnexpectedMultipleResults) {
			// stat ambiguous result so we can make sure this isn't happening
			diagnostics.Statter(ctx).Counter("mobile_device.find_active_device_auth_device_key.unexpected", stats.Tags{"err": err.Error()}, 1)
		}
		// if the error is something other than not found, expired, revoked, ambiguous, stop here and return an error
		// otherwise, it's fine to continue and mark hasValidDeviceKey as false
		if !errors.Is(err, sql.ErrNoRows) && !errors.Is(err, common.StoreErrDeviceKeyUnexpectedRevoked) && !errors.Is(err, common.StoreErrDeviceKeyUnexpectedExpired) && !errors.Is(err, common.StoreErrUnexpectedMultipleResults) {
			return &pb.FindActiveDeviceAuthResponse{
				Result: pb.FindActiveDeviceAuthResponse_RESULT_FAILED_GENERIC,
			}, twirp.InternalErrorWith(err)
		}
		hasValidDeviceKey = false
	}

	// check if this user has any expired auth requests
	hasExpiredAuthRequest, err := mdm.store.HasExpiredMobileAuthRequestByUserID(ctx, uint64(req.UserId), now)

	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			diagnostics.Logger(ctx).WithError(err).Info("findActiveDeviceAuth expired request lookup error")
		}

		hasExpiredAuthRequest = false
	}

	// try to find an active auth request for the given user (there should only ever be 0 or 1)
	authRequest, err := mdm.store.FindActiveMobileAuthRequestByUserID(ctx, uint64(req.UserId), now)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("findActiveDeviceAuth request lookup error")
		if errors.Is(err, sql.ErrNoRows) {
			return &pb.FindActiveDeviceAuthResponse{
				Result:                pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND,
				HasValidDeviceKey:     hasValidDeviceKey,
				HasExpiredAuthRequest: hasExpiredAuthRequest,
			}, nil
		} else if errors.Is(err, common.StoreErrUnexpectedMultipleResults) {
			diagnostics.Statter(ctx).Counter("mobile_device.find_active_device_auth.ambiguous", nil, 1)
			return &pb.FindActiveDeviceAuthResponse{
				Result:                pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND,
				HasValidDeviceKey:     hasValidDeviceKey,
				HasExpiredAuthRequest: hasExpiredAuthRequest,
			}, nil
		} else {
			return &pb.FindActiveDeviceAuthResponse{
				Result: pb.FindActiveDeviceAuthResponse_RESULT_FAILED_GENERIC,
			}, twirp.InternalErrorWith(err)
		}
	}

	// get the requestType of the active auth request (should only contain supported values)
	requestType := mobiledeviceauth.GetRequestTypeName(authRequest.Type)

	// check that the device key (if one exists) can be used to approve the specific active request
	hasValidDeviceKey = hasValidDeviceKey && canUseDeviceKeyForAuthRequestCompletion(deviceKey, authRequest)

	// encode the payload before returning it
	encodedPayload := base64.StdEncoding.EncodeToString(authRequest.Payload)

	resp := &pb.FindActiveDeviceAuthResponse{
		Result:                pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS,
		Id:                    int64(authRequest.ID),
		Payload:               encodedPayload,
		ChallengeRequired:     authRequest.ChallengeNumber.Valid,
		HasValidDeviceKey:     hasValidDeviceKey,
		HasExpiredAuthRequest: hasExpiredAuthRequest,
		Type:                  requestType,
	}

	if authRequest.CreatedAt.Valid {
		resp.CreatedAtUtc = timestamppb.New(authRequest.CreatedAt.Time)
	}
	if authRequest.FromIpAddress.Valid {
		resp.IpAddress = authRequest.FromIpAddress.String
	}
	if authRequest.FromDisplayName.Valid {
		resp.DeviceDisplayName = authRequest.FromDisplayName.String
	}

	return resp, nil
}

func (mdm *MobileDeviceManager) checkFindActiveDeviceAuthArguments(ctx context.Context, req *pb.FindActiveDeviceAuthRequest) error {
	switch {
	case req.UserId == 0:
		return twirp.RequiredArgumentError("UserId")
	case req.OauthAccessId == 0:
		return twirp.RequiredArgumentError("OauthAccessId")
	}
	return nil
}
