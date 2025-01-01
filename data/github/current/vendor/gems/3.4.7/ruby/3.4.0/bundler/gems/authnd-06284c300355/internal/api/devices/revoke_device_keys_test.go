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

func TestRevokeDeviceKeysByUserIdMissingUserId(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{},
		},
	}

	resp, err := mdm.RevokeDeviceKeys(context.Background(), req)

	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("UserId"))
}

func TestRevokeDeviceKeysByUserIdWithNoDeviceRegisteredToUser(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: int64(testfixtures.UserIdWithoutMobileDevicesKey),
			},
		},
	}

	resp, err := mdm.RevokeDeviceKeys(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceKeysByUserIdWithOneDeviceRegisteredToUser(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId),
			},
		},
	}

	resp, err := mdm.RevokeDeviceKeys(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
	assert.Equal(t, 1, len(resp.OauthAccessIds))
}

func TestRevokeDeviceKeysByUserIdWithMultipleDevicesRegisteredToUser(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: int64(testfixtures.UserIdWithMultipleValidDeviceKeys),
			},
		},
	}

	resp, err := mdm.RevokeDeviceKeys(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
	assert.Equal(t, 3, len(resp.OauthAccessIds))
}
