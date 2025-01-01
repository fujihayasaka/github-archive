package devices

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
)

func TestRevokeDeviceAuthKeySuccess(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId),
			},
		},
	}
	resp, err := mdm.RevokeDeviceKey(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceAuthKeySuccessForOauthAccessIdThatHasMultipleKeys(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.OauthAccessId),
			},
		},
	}
	resp, err := mdm.RevokeDeviceKey(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceAuthKeyMissingOAuthAccessId(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{},
		},
	}
	resp, err := mdm.RevokeDeviceKey(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("OauthAccessId"))
}

func TestRevokeDeviceAuthKeyNotFoundReturnsSuccess(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: int64(testfixtures.MobileDeviceAuthKeyNotInStore.OauthAccessId),
			},
		},
	}
	resp, err := mdm.RevokeDeviceKey(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceAuthKeyAlreadyRevokedReturnsSuccess(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: int64(testfixtures.RevokedMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId),
			},
		},
	}
	resp, err := mdm.RevokeDeviceKey(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
}
