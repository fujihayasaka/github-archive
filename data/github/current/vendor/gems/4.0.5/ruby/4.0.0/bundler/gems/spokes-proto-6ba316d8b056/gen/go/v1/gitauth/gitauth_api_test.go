package gitauth

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestGetNewOidsInPushRequestValidateErrors(t *testing.T) {
	reqCtx := types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)

	var tests = []struct {
		name string
		req  *GetNewOidsInPushRequest
		err  string
	}{
		{
			"empty",
			&GetNewOidsInPushRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&GetNewOidsInPushRequest{RequestContext: reqCtx, Repository: nil},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			&GetNewOidsInPushRequest{RequestContext: reqCtx, Repository: &types.Repository{}},
			"twirp error invalid_argument: repository.id is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestGetNewOidsInPushRequestValidate(t *testing.T) {
	repository := types.NewRepository(1)
	reqCtx := types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)

	req := &GetNewOidsInPushRequest{RequestContext: reqCtx, Repository: repository}
	require.NoError(t, req.Validate())
}

func TestNewHostStatus(t *testing.T) {
	var s *HostStatus

	s = OKHostStatus("dgit1", "localhost", "/a/b/c")
	assert.Equal(t, "dgit1", s.GetReplicaName())
	assert.Equal(t, "localhost", s.GetHost())
	assert.Equal(t, "/a/b/c", s.GetPath())
	assert.Nil(t, s.GetErrorResult())
	assert.NotNil(t, s.GetOkResult())

	s = FailedHostStatus("dgit1", "localhost", "/a/b/c", "boom")
	assert.Equal(t, "dgit1", s.GetReplicaName())
	assert.Equal(t, "localhost", s.GetHost())
	assert.Equal(t, "/a/b/c", s.GetPath())
	assert.Equal(t, "boom", s.GetErrorResult().GetErrorMessage())
	assert.Nil(t, s.GetOkResult())
}
