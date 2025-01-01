package devices

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestRegisterDeviceRecoveryKeySuccess(t *testing.T) {
	now := time.Now()
	mdm := createTestMobileDeviceManager(t, now, nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	assert.NotNil(t, resp.ExpiresAtTime)
	assert.Equal(t, timestamppb.New(now.Add(common.DeviceRecoveryKeyLifetime)), resp.ExpiresAtTime)
	assert.NotNil(t, resp.Id)
}

func TestRegisterDeviceRecoveryKeySuccessMissingDeviceNameAndModel(t *testing.T) {
	now := time.Now()
	mdm := createTestMobileDeviceManager(t, now, nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	assert.NotNil(t, resp.ExpiresAtTime)
	assert.Equal(t, timestamppb.New(now.Add(common.DeviceRecoveryKeyLifetime)), resp.ExpiresAtTime)
	assert.NotNil(t, resp.Id)
}

func TestRegisterDeviceRecoveryKeyMissingUserId(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("UserId"))
}

func TestRegisterDeviceRecoveryKeyMissingOAuthAccessId(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("OAuthAccessId"))
}

func TestRegisterDeviceRecoveryKeyMissingDeviceOs(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("DeviceOs"))
}

func TestRegisterDeviceRecoveryKeyInvalidDeviceOs(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "NotIt",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.InvalidArgumentError("DeviceOs", "Must be 'iOS' or 'Android'"))
}

func TestRegisterDeviceRecoveryKeyMissingPublicKey(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("PublicKey"))
}

func TestRegisterDeviceRecoveryKeyMissingPublicKeyVerificationSignature(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                       1,
				OauthAccessId:                2,
				DeviceName:                   "mona's phone",
				DeviceModel:                  "iPhone0",
				DeviceOs:                     "iOS",
				IsHardwareBacked:             false,
				PublicKey:                    testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationMessage: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("PublicKeyVerificationSignature"))
}

func TestRegisterDeviceRecoveryKeyMissingPublicKeyVerificationMessage(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("PublicKeyVerificationMessage"))
}

func TestRegisterDeviceRecoveryKeyInvalidPublicKey(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      "notABase64EncodedPubKey",
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.InvalidArgumentError("PublicKey", "Could not parse public key to create fingerprint"))
}

func TestRegisterDeviceRecoveryKeyInvalidPublicKeyVerification(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   "goodbye_ecdsa",
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.InvalidArgumentError("PublicKey", "The provided public key could not be verified with the signature and message"))
}

func TestRegisterDeviceRecoveryKeyRequiresPublicKeyVerification(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:           1,
				OauthAccessId:    2,
				DeviceName:       "mona's phone",
				DeviceModel:      "iPhone0",
				DeviceOs:         "iOS",
				IsHardwareBacked: false,
				PublicKey:        testfixtures.ValidUnregisteredMobileDeviceKey,
			},
		},
	}
	resp, err := mdm.RegisterDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("PublicKeyVerificationSignature"))
}
