package devices

import (
	"context"
	"crypto/sha256"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-ctxutil"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

func (mdm *MobileDeviceManager) RegisterDeviceKey(ctx context.Context, req *pb.RegisterDeviceKeyRequest) (*pb.RegisterDeviceKeyResponse, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "register_device_key")

	startTime := time.Now()
	ctx, span := tracing.ChildSpan(ctx, "MobileDeviceManager.RegisterDeviceKey")
	defer span.End()

	diagnostics.Logger(ctx).Info("received RegisterDeviceKey request")

	var deviceKeyType models.DeviceKeyType
	var deviceKeyRequest *pb.DeviceKeyRequest
	switch req.GetKind().(type) {
	case *pb.RegisterDeviceKeyRequest_AuthKeyRequest:
		deviceKeyType = models.DeviceKeyType_Auth
		deviceKeyRequest = req.GetAuthKeyRequest()
	case *pb.RegisterDeviceKeyRequest_RecoveryKeyRequest:
		deviceKeyType = models.DeviceKeyType_Recovery
		deviceKeyRequest = req.GetRecoveryKeyRequest()
	default:
		err := errors.Errorf("unknown RegisterDeviceKey request: %T", req.GetKind())
		diagnostics.Logger(ctx).WithError(err).Info("RegisterDeviceKey error")
		return &pb.RegisterDeviceKeyResponse{
			Result: pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC,
		}, err
	}

	// determine if the request should verify the public key and add info to the logging context
	// verification is required for recovery key registration
	verifyPublicKey := deviceKeyType == models.DeviceKeyType_Recovery || (deviceKeyRequest.PublicKeyVerificationSignature != "" && deviceKeyRequest.PublicKeyVerificationMessage != "")
	ctx = diagnostics.WithLoggerFields(ctx, kvp.Bool("gh.authnd.devices.credential.requires_pub_key_verification", verifyPublicKey), kvp.String("gh.authnd.devices.credential.device_key_type", string(deviceKeyType)))
	diagnostics.Logger(ctx).Info("parsed RegisterDeviceKey request type")

	resp, err := mdm.registerDeviceKey(ctx, deviceKeyRequest, deviceKeyType, verifyPublicKey)
	if resp == nil {
		resp = &pb.RegisterDeviceKeyResponse{
			Result: pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC,
		}
	}
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("RegisterDeviceKey error", kvp.String("gh.authnd.devices.request.result", resp.Result.String()))
	}

	tags := stats.Tags{
		"result":                  resp.Result.String(),
		"hardware_backed":         strconv.FormatBool(deviceKeyRequest.IsHardwareBacked),
		"public_key_verification": strconv.FormatBool(verifyPublicKey),
		"device_key_type":         string(deviceKeyType),
		"device_os":               string(strings.ToLower(deviceKeyRequest.DeviceOs)),
	}
	statter := diagnostics.Statter(ctx)
	statter.Counter("mobile_device.register_device_key.count", tags, 1)
	statter.DistributionMs("mobile_device.register_device_key.duration", tags, time.Since(startTime))

	return resp, err
}

func (mdm *MobileDeviceManager) registerDeviceKey(ctx context.Context, req *pb.DeviceKeyRequest, deviceKeyType models.DeviceKeyType, verifyPublicKey bool) (*pb.RegisterDeviceKeyResponse, error) {
	err := mdm.checkRegisterDeviceKeyArguments(ctx, req, deviceKeyType)
	if err != nil {
		return nil, err
	}

	if req.DeviceName == "" {
		req.DeviceName = getFallbackDeviceName(req.DeviceOs)
	}
	if req.DeviceModel == "" {
		req.DeviceModel = getFallbackDeviceModel(req.DeviceOs)
	}

	ctx = diagnostics.WithLoggerFields(ctx, kvp.Int64("gh.oauth.access.id", req.OauthAccessId), kvp.Int64("gh.user.id", req.UserId))
	// create fingerprint for the public key
	keyFingerprint, err := crypto.GenerateECDSAFingerprint(req.PublicKey)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("Error creating fingerprint for public key")
		return nil, twirp.InvalidArgumentError("PublicKey", "Could not parse public key to create fingerprint")
	}

	// verify that the public key can be used to verify a signature provided by the client
	// this is mostly just a validation to protect against an incorrect or outdated calls - it is not a form of authentication
	// the client may register a device auth key without verifying the public key by not supplying the signature/message args in their request
	if verifyPublicKey {
		messageHash := sha256.Sum256([]byte(req.PublicKeyVerificationMessage))
		verifiedPublicKey, err := crypto.VerifyEcdsaSha256Signature(req.PublicKeyVerificationSignature, req.PublicKey, messageHash[:])
		if err != nil {
			diagnostics.Logger(ctx).WithError(err).Info("Error verifying the provided public key with the signature and message")
			return nil, twirp.InternalError("There was a problem verifying the provided public key with the signature and message")
		}
		if !verifiedPublicKey {
			return nil, twirp.InvalidArgumentError("PublicKey", "The provided public key could not be verified with the signature and message")
		}
	}

	// check if the oauth access id has an existing key of this type, if so, revoke it
	// note: we aren't doing this inside a transaction because at the time the device is calling register, they are asking for a new key
	// registration. This means they would have already replaced their "old" key pair reference if the had one.
	// so the case where this revoke succeeds but the registration fails is OK - because they likely don't have a reference to the old one anymore anyway
	now := mdm.nowFunc()
	rowsAffected, err := mdm.store.RevokeMobileDeviceKeysByOauthAccessId(ctx, deviceKeyType, uint64(req.OauthAccessId), now)
	if err != nil {
		diagnostics.Logger(ctx).WithError(err).Info("Error revoking key by oauth access id before registration")
		return nil, twirp.InternalError("There was a problem revoking keys for the given oauth access id")
	}
	if rowsAffected > 0 {
		diagnostics.Logger(ctx).Info("successfully revoked mobile device keys during registerDeviceKey", kvp.Int64("gh.authnd.devices.request.keys", rowsAffected))
		diagnostics.Statter(ctx).Counter("mobile_device.register_device_key.pre_revoke_had_affect.count", stats.Tags{
			"device_key_type": string(deviceKeyType),
			"device_os":       string(strings.ToLower(req.DeviceOs)),
			"rows_affected":   strconv.FormatInt(rowsAffected, 10),
		}, 1)
	}

	expiresAt := now.Add(common.DeviceAuthKeyLifetime)
	if deviceKeyType == models.DeviceKeyType_Recovery {
		expiresAt = now.Add(common.DeviceRecoveryKeyLifetime)
	}
	mobileDeviceKey := &models.MobileDeviceKey{
		UserId:               uint64(req.UserId),
		OauthAccessId:        uint64(req.OauthAccessId),
		DeviceName:           req.DeviceName,
		DeviceModel:          req.DeviceModel,
		DeviceOs:             strings.ToLower(req.DeviceOs),
		IsHardwareBacked:     req.IsHardwareBacked,
		Type:                 string(deviceKeyType),
		PublicKey:            req.PublicKey,
		PublicKeyFingerprint: keyFingerprint,
		CreatedAt:            models.NullMysqlDateTimeFromTime(now),
	}

	id, err := mdm.store.InsertMobileDeviceKey(ctx, mobileDeviceKey, now)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if deviceKeyType == models.DeviceKeyType_Recovery {
		go func() {
			detachedContext, cancel := context.WithTimeout(ctxutil.DetachedCancel(ctx), 3*time.Second)
			defer cancel()

			revokedKeyId, err := mdm.revokeLastRecentlyUsedKeyPastCapacity(detachedContext, deviceKeyType, req.UserId, now)
			if err != nil {
				diagnostics.Logger(detachedContext).WithError(err).Info("unable to revoke LRU recovery key", kvp.Uint64("gh.authnd.devices.request.key_id", revokedKeyId))
				diagnostics.Statter(ctx).Counter("mobile_device.recovery_key_past_capacity_revoked", stats.Tags{"result": "failure"}, 1)
				return
			}
			diagnostics.Logger(detachedContext).Info("successfully revoke LRU recovery key", kvp.Uint64("gh.authnd.devices.request.key_id", revokedKeyId))
			diagnostics.Statter(ctx).Counter("mobile_device.recovery_key_past_capacity_revoked", stats.Tags{"result": "success"}, 1)
		}()
	}

	return &pb.RegisterDeviceKeyResponse{
		Result:        pb.RegisterDeviceKeyResponse_RESULT_SUCCESS,
		Id:            id,
		ExpiresAtTime: timestamppb.New(expiresAt),
	}, nil
}

func (mdm *MobileDeviceManager) revokeLastRecentlyUsedKeyPastCapacity(ctx context.Context, deviceKeyType models.DeviceKeyType, userId int64, now time.Time) (uint64, error) {
	maxRecoveryKeys := 50

	var keyToRevokeId uint64
	deviceKeys, err := mdm.store.FindMobileDeviceKeysByUserId(ctx, deviceKeyType, uint64(userId), now)
	if err != nil {
		return keyToRevokeId, err
	}

	if len(deviceKeys) >= maxRecoveryKeys {
		sort.Slice(deviceKeys, func(i, j int) bool {
			return deviceKeys[i].CreatedAt.Time.Before(deviceKeys[j].CreatedAt.Time)
		})

		oldestKey := deviceKeys[0]
		keyToRevokeId = oldestKey.ID

		err := mdm.store.RevokeMobileDeviceKeyById(ctx, oldestKey.ID, now)
		if err != nil {
			return keyToRevokeId, err
		}
	}

	return keyToRevokeId, nil
}

func (mdm *MobileDeviceManager) checkRegisterDeviceKeyArguments(ctx context.Context, req *pb.DeviceKeyRequest, deviceKeyType models.DeviceKeyType) error {
	switch {
	case req.UserId == 0:
		return twirp.RequiredArgumentError("UserId")
	case req.OauthAccessId == 0:
		return twirp.RequiredArgumentError("OAuthAccessId")
	case req.DeviceOs == "":
		return twirp.RequiredArgumentError("DeviceOs")
	case strings.ToLower(req.DeviceOs) != "ios" && strings.ToLower(req.DeviceOs) != "android":
		return twirp.InvalidArgumentError("DeviceOs", "Must be 'iOS' or 'Android'")
	case req.PublicKey == "":
		return twirp.RequiredArgumentError("PublicKey")
	}

	// public key verification signature/messsage are required for device recovery key registration
	if deviceKeyType == models.DeviceKeyType_Recovery {
		switch {
		case req.PublicKeyVerificationSignature == "":
			return twirp.RequiredArgumentError("PublicKeyVerificationSignature")
		case req.PublicKeyVerificationMessage == "":
			return twirp.RequiredArgumentError("PublicKeyVerificationMessage")
		}
	} else {
		switch {
		// verification signature is only required if the verification message is supplied
		case req.PublicKeyVerificationSignature == "" && req.PublicKeyVerificationMessage != "":
			return twirp.RequiredArgumentError("PublicKeyVerificationSignature")
		// verification messages is only required if the verification signature is supplied
		case req.PublicKeyVerificationMessage == "" && req.PublicKeyVerificationSignature != "":
			return twirp.RequiredArgumentError("PublicKeyVerificationMessage")
		}
	}

	return nil
}

func getFallbackDeviceName(deviceOs string) string {
	switch strings.ToLower(deviceOs) {
	case "ios":
		return "Unknown iOS Device"
	case "android":
		return "Unknown Android Device"
	default:
		return "Unknown Device"
	}
}

func getFallbackDeviceModel(deviceOs string) string {
	switch strings.ToLower(deviceOs) {
	case "ios":
		return "Unknown iOS Device Model"
	case "android":
		return "Unknown Android Device Model"
	default:
		return "Unknown Device Model"
	}
}
