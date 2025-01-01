package devices

import (
	"context"
	"database/sql"
	"strconv"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

func (mdm *MobileDeviceManager) CompleteDeviceAuth(ctx context.Context, req *pb.CompleteDeviceAuthRequest) (*pb.CompleteDeviceAuthResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "complete_device_auth")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.CompleteDeviceAuth")
	defer span.End()

	diagnostics.Logger(ctx).Info("received CompleteDeviceAuth request")

	// parse the type of completion (approval or rejection)
	var completionType apimodels.CompleteDeviceAuthType
	var completionArgs *pb.CompleteDeviceAuthMessage
	switch req.GetKind().(type) {
	case *pb.CompleteDeviceAuthRequest_Approve:
		completionType = apimodels.CompleteDeviceAuthType_Approve
		completionArgs = req.GetApprove()
	case *pb.CompleteDeviceAuthRequest_Reject:
		completionType = apimodels.CompleteDeviceAuthType_Reject
		completionArgs = req.GetReject()
	default:
		err := errors.Errorf("unknown complete device auth request: %T", req.GetKind())
		diagnostics.Logger(ctx).WithError(err).Info("CompleteDeviceAuth error")
		return &pb.CompleteDeviceAuthResponse{
			Result: pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC,
		}, err
	}

	// add the completion type to the logging context
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.mobile_auth.completion.type", string(completionType)))
	diagnostics.Logger(ctx).Info("parsed CompleteDeviceAuth request")

	// trigger the completion logic
	resp, err := mdm.completeDeviceAuth(ctx, completionArgs, completionType)
	if resp == nil {
		resp = &pb.CompleteDeviceAuthResponse{
			Result: pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC,
		}
	}

	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("CompleteDeviceAuth error", kvp.String("result", resp.Result.String()))
	}

	tags := stats.Tags{"result": resp.Result.String(), "completion_type": string(completionType)}
	statter := diagnostics.Statter(ctx)
	statter.Counter("mobile_device.complete_device_auth.count", tags, 1)
	statter.DistributionMs("mobile_device.complete_device_auth.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) completeDeviceAuth(ctx context.Context, req *pb.CompleteDeviceAuthMessage, completionType apimodels.CompleteDeviceAuthType) (*pb.CompleteDeviceAuthResponse, error) {
	err := mdm.checkCompleteDeviceAuthArguments(ctx, req, completionType)
	if err != nil {
		return nil, err
	}
	response := &pb.CompleteDeviceAuthResponse{
		Result: pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC,
	}

	ctx = diagnostics.WithLoggerFields(ctx, kvp.Int64("gh.oauth.access.id", req.OauthAccessId), kvp.Int64("gh.user.id", req.UserId))
	now := mdm.nowFunc()
	deviceKey, err := mdm.store.FindMobileDeviceKeyByUserIdAndOauthAccessId(ctx, models.DeviceKeyType_Auth, uint64(req.UserId), uint64(req.OauthAccessId), now)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("CompleteDeviceAuth key lookup error")
		diagnostics.Statter(ctx).Counter("mobile_device.complete_device_auth_device_key.unexpected", stats.Tags{"err": err.Error()}, 1)

		if errors.Is(err, common.StoreErrUnexpectedMultipleResults) || errors.Is(err, common.StoreErrDeviceKeyUnexpectedExpired) || errors.Is(err, common.StoreErrDeviceKeyUnexpectedRevoked) || errors.Is(err, sql.ErrNoRows) {
			response.Result = pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND
			return response, nil
		}
		return response, twirp.InternalErrorWith(err)
	}

	authRequest, err := mdm.store.FindMobileAuthRequestByIdAndUserId(ctx, uint64(req.AuthRequestId), uint64(req.UserId))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			response.Result = pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_FOUND
			return response, nil
		}
		return response, twirp.InternalErrorWith(err)
	}

	requestType := mobiledeviceauth.GetRequestTypeName(authRequest.Type)
	// adding requestType implicitly to logger and statter
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.mobile_auth.request.type", requestType))
	ctx = diagnostics.WithStatterTags(ctx, stats.Tags{"request_type": requestType})

	// adding a metric to keep track of the different request types that are completed
	defer func() {
		tags := stats.Tags{"request_type": requestType, "result": response.Result.String()}
		diagnostics.Statter(ctx).Counter("mobile_device.complete_device_auth.request_type.count", tags, 1)
	}()

	if !authRequest.IsActive(now) {
		switch {
		case completionType == apimodels.CompleteDeviceAuthType_Approve:
			if authRequest.IsApproved(now) {
				response.Result = pb.CompleteDeviceAuthResponse_RESULT_ALREADY_APPROVED
				return response, nil
			}
		case completionType == apimodels.CompleteDeviceAuthType_Reject:
			if authRequest.IsRejected(now) {
				response.Result = pb.CompleteDeviceAuthResponse_RESULT_ALREADY_REJECTED
				return response, nil
			}
		}
		response.Result = pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE
		return response, nil
	}

	if !canUseDeviceKeyForAuthRequestCompletion(deviceKey, authRequest) {
		// statting this since it's a case that should be avoided by clients as much as possible
		diagnostics.Statter(ctx).Counter("mobile_device.cannot_use_key_for_auth_request_completion.count", nil, 1)
		response.Result = pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND
		return response, nil
	}
	// best effort: update the `last_used_at_utc` column for mobile device key. Don't fail the request if this write fails.
	common.WithBackgroundedOperation(
		ctx,
		"touch_mobile_device_key",
		func(innerContext context.Context) error {
			return mdm.touchMobileDeviceKey(innerContext, deviceKey, now)
		},
		3*time.Second,
	)

	// only approval needs to verify the signature
	if completionType == apimodels.CompleteDeviceAuthType_Approve {
		verified, err := mdm.approvalSignatureVerification(ctx, req, deviceKey, authRequest, now)

		// stat any non-verified approval signatures
		if !verified {
			has_verification_error := err != nil
			diagnostics.Statter(ctx).Counter("mobile_device.approval_not_verified.count", stats.Tags{"verification_error": strconv.FormatBool(has_verification_error)}, 1)
		}

		if err != nil {
			return nil, err
		}
		if !verified {
			// if the signature is not verified (e.g. bad challenge number), then the auth request needs to be marked as rejected
			_, err := mdm.store.CompleteMobileAuthRequest(ctx, uint64(req.AuthRequestId), apimodels.CompleteDeviceAuthType_Reject, now)
			if err != nil {
				// best effort: update the request as "rejected". Don't fail the request if this write fails.
				diagnostics.Statter(ctx).Counter("mobile_device.approval_not_verified_rejection_failure.count", nil, 1)
				diagnostics.Logger(ctx).WithError(err).Info("Failed to mark request as rejected after receiving a signature that could not be verified")
			}
			response.Result = pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED
			return response, nil
		}
	}

	resp, err := mdm.store.CompleteMobileAuthRequest(ctx, uint64(req.AuthRequestId), completionType, now)
	if err != nil {
		response.Result = apimodels.CompleteDeviceAuthResultMap[resp]
		return response, twirp.InternalErrorWith(err)
	}
	response.Result = pb.CompleteDeviceAuthResponse_RESULT_SUCCESS
	return response, nil
}

func (mdm *MobileDeviceManager) touchMobileDeviceKey(ctx context.Context, deviceKey *models.MobileDeviceKey, now time.Time) error {
	if err := mdm.store.TouchMobileDeviceKey(ctx, uint64(deviceKey.ID), now); err != nil {
		diagnostics.Statter(ctx).Counter("mobile_device.touch_mobile_device_key_failures.count", nil, 1)
		diagnostics.Logger(ctx).WithError(err).Info("Failed to touch the mobile device key during device auth completion")
		return err
	}
	return nil
}

func (mdm *MobileDeviceManager) approvalSignatureVerification(ctx context.Context, req *pb.CompleteDeviceAuthMessage, deviceKey *models.MobileDeviceKey, authRequest *models.MobileAuthRequest, now time.Time) (bool, error) {
	// if the auth request record has a NULL challenge, then the signature was expected to be created with a message constructed without a challenge
	var expectedMessageHash []byte
	if !authRequest.ChallengeNumber.Valid {
		expectedMessageHash = mobiledeviceauth.CreateExpectedApproveMessageWithoutChallengeHash(uint64(req.SignatureVersion), authRequest.Payload)
	} else {
		expectedMessageHash = mobiledeviceauth.CreateExpectedApproveMessageHash(uint64(req.SignatureVersion), authRequest.Payload, authRequest.ChallengeNumber.Int64)
	}

	verified, err := crypto.VerifyEcdsaSha256Signature(req.Signature, deviceKey.PublicKey, expectedMessageHash)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("Error verifying the signature")
		return false, twirp.InternalError("There was a problem verifying the signature")
	}

	return verified, nil
}

func (mdm *MobileDeviceManager) checkCompleteDeviceAuthArguments(ctx context.Context, req *pb.CompleteDeviceAuthMessage, completionType apimodels.CompleteDeviceAuthType) error {
	// args required for both approval and rejection
	switch {
	case req.AuthRequestId == 0:
		return twirp.RequiredArgumentError("AuthRequestId")
	case req.UserId == 0:
		return twirp.RequiredArgumentError("UserId")
	case req.OauthAccessId == 0:
		return twirp.RequiredArgumentError("OauthAccessId")
	}

	// args only required for approval
	if completionType == apimodels.CompleteDeviceAuthType_Approve {
		switch {
		case req.Signature == "":
			return twirp.RequiredArgumentError("Signature")
		case req.SignatureVersion == 0:
			return twirp.RequiredArgumentError("SignatureVersion")
		case req.SignatureVersion != 1:
			return twirp.InvalidArgumentError("SignatureVersion", "not a supported version")
		}
	}

	return nil
}
