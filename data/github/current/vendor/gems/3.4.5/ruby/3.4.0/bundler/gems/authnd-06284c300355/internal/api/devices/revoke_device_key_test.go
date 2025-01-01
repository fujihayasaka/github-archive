package devices

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
)

func TestRevokeDeviceKeyNoKindFailure(t *testing.T) {
	now := time.Now()
	mdm := createTestMobileDeviceManager(t, now, nil)

	req := &pb.RevokeDeviceKeyRequest{}
	resp, err := mdm.RevokeDeviceKey(context.Background(), req)

	assert.NotNil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.Equal(t, errors.New("unknown RevokeDeviceKey request: <nil>").Error(), err.Error())
}
