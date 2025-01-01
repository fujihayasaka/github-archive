package devices

import (
	"context"
	"database/sql"
	"strconv"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/feature"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	layoutProto "github.com/github/notifyd/proto/layouts/mobile"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
	"gopkg.in/guregu/null.v4"
)

const (
	notificationProfileName = "GitHub"
	notificationAvatarURL   = "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png"
)

func (mdm *MobileDeviceManager) RequestDeviceAuth(ctx context.Context, req *pb.RequestDeviceAuthRequest) (*pb.RequestDeviceAuthResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "request_device_auth")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.RequestDeviceAuth")
	defer span.End()

	// attaching a logger to the context that includes request type, so it does not need to be repeated in all logging statements
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.devices.request.type", req.Type))

	// Same as with the logger, attaching a statter to the context with a request type tag
	ctx = diagnostics.WithStatterTags(ctx, stats.Tags{"request_type": req.Type})
	statter := diagnostics.Statter(ctx)

	diagnostics.Logger(ctx).Info("received RequestDeviceAuth request")

	resp, err := mdm.requestDeviceAuth(ctx, req)
	if resp == nil {
		resp = &pb.RequestDeviceAuthResponse{
			Result: pb.RequestDeviceAuthResponse_RESULT_FAILED_GENERIC,
		}
	}
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("RequestDeviceAuth error", kvp.String("gh.authnd.devices.request.result", resp.Result.String()))
	}

	tags := stats.Tags{"result": resp.Result.String(), "skip_challenge": strconv.FormatBool(req.SkipChallenge)}
	statter.Counter("mobile_device.request_device_auth.count", tags, 1)
	statter.DistributionMs("mobile_device.request_device_auth.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) requestDeviceAuth(ctx context.Context, req *pb.RequestDeviceAuthRequest) (*pb.RequestDeviceAuthResponse, error) {
	// check required arguments
	if req.UserId == 0 {
		return nil, twirp.RequiredArgumentError("UserId")
	}

	now := mdm.nowFunc()
	userId := req.UserId
	// check if the user has mobile device keys for auth
	_, err := mdm.store.FindMobileDeviceKeysByUserId(ctx, models.DeviceKeyType_Auth, uint64(req.UserId), now)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return &pb.RequestDeviceAuthResponse{
				Result: pb.RequestDeviceAuthResponse_RESULT_FAILED_NO_VALID_DEVICE_KEYS,
			}, nil
		}
		return nil, err
	}

	// check if the request type is a supported value
	requestType := req.Type
	requestTypeValue, err := mobiledeviceauth.GetRequestTypeValue(requestType)
	if err != nil {
		return nil, err
	}

	payload, err := mobiledeviceauth.GeneratePayload(now)
	if err != nil {
		return nil, err
	}
	lifetime := mobiledeviceauth.GetRequestLifetime(requestTypeValue)
	requestExpiresAt := now.Add(lifetime)
	request := &models.MobileAuthRequest{
		UserId:    uint64(userId),
		Payload:   payload,
		CreatedAt: models.NullMysqlDateTimeFromTime(now),
		ExpiresAt: models.NullMysqlDateTimeFromTime(requestExpiresAt),
		Type:      requestTypeValue,
	}
	if req.IpAddress != "" {
		request.FromIpAddress = null.StringFrom(req.IpAddress)
	}
	if req.DeviceDisplayName != "" {
		request.FromDisplayName = null.StringFrom(req.DeviceDisplayName)
	}

	// succeeds only if the user has no other outstanding requests
	result, challengeNumber, err := mdm.store.InsertMobileAuthRequest(ctx, request, req.SkipChallenge, now)
	if err != nil {
		return &pb.RequestDeviceAuthResponse{
			Result: apimodels.RequestDeviceAuthResultMap[result],
		}, twirp.InternalErrorWith(err)
	}

	// publish notifyD message on success
	if result == apimodels.RequestDeviceAuthResult_Success {
		common.WithBackgroundedOperation(
			ctx,
			"request_device_auth_publish_notification",
			func(innerContext context.Context) error {
				return mdm.publishNotification(ctx, userId, request.ID, requestTypeValue, now)
			},
			3*time.Second,
		)
	}

	response := &pb.RequestDeviceAuthResponse{
		Result:        apimodels.RequestDeviceAuthResultMap[result],
		Id:            int64(request.ID),
		ExpiresAtTime: timestamppb.New(requestExpiresAt),
	}

	if challengeNumber.Valid {
		response.Challenge = strconv.FormatInt(challengeNumber.Int64, 10)
	}

	return response, nil
}

func (mdm *MobileDeviceManager) publishNotification(ctx context.Context, userId int64, requestId uint64, requestTypeValue int, now time.Time) error {
	statter := diagnostics.Statter(ctx)
	startTime := time.Now()
	defer func() {
		statter.DistributionMs("mobile_device.request_device_auth.publish.duration", nil, time.Since(startTime))
	}()

	ffEnabled := feature.Enabled(ctx, "notifyd_rich_mobile_push")
	notificationData := createNotificationLayout(requestTypeValue, strconv.Itoa(int(requestId)), ffEnabled)
	err := mdm.publisher.PublishNotification(ctx, userId, notificationData, now)
	if err != nil {
		statter.Counter("mobile_device.request_device_auth.notify.error", nil, 1)
		diagnostics.Logger(ctx).WithError(err).Error("PublishNotification failed to publish mobile_auth_request", kvp.Int64("gh.user.id", userId))
		expireError := mdm.store.ExpireMobileAuthRequestByID(ctx, requestId, now)
		if expireError != nil {
			diagnostics.Logger(ctx).WithError(err).Error("failed to invalidate auth request after PublishNotification failure", kvp.Int64("gh.user.id", userId))
			statter.Counter("mobile_device.request_device_auth.expire.error", nil, 1)
		}
	}

	return err
}

func createNotificationLayout(requestTypeValue int, threadID string, ffEnableRichMobilePush bool) *layoutProto.Basic {
	var layoutData *layoutProto.Basic

	var threadType string
	switch requestTypeValue {
	case common.MobileRequestTypeTwoFactorLogin:
		layoutData = NewSignInRequestLayoutData()
		threadType = common.MobileRequestTypeTwoFactorLoginName
	case common.MobileRequestTypeDeviceVerification:
		layoutData = NewDeviceVerificationLayoutData()
		threadType = common.MobileRequestTypeDeviceVerificationName
	case common.MobileRequestTypeTwoFactorPasswordReset:
		layoutData = NewPasswordResetLayoutData()
		threadType = common.MobileRequestTypeTwoFactorPasswordResetName
	case common.MobileRequestTypeTwoFactorSudoChallenge:
		layoutData = NewSudoChallengeLayoutData()
		threadType = common.MobileRequestTypeTwoFactorSudoChallengeName
	}

	if ffEnableRichMobilePush {
		layoutData.AuthorProfileName = notificationProfileName
		layoutData.AvatarUrl = notificationAvatarURL
		layoutData.ThreadId = threadID
		layoutData.ThreadType = threadType
	}

	return layoutData
}
