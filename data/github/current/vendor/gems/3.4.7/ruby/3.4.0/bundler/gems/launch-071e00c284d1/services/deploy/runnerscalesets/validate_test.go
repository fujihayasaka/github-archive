package runnerscalesets_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	twirp "github.com/twitchtv/twirp"

	"github.com/github/launch/services/deploy/runnerscalesets"
	pbtypes "github.com/github/launch/services/pbtypes"
)

func TestGetRunnerScaleSetRequest_Validate(t *testing.T) {
	t.Run("invalid request", func(t *testing.T) {
		tests := []struct {
			name           string
			req            *runnerscalesets.GetRunnerScaleSetRequest
			expectedErrMsg string
		}{
			{
				name: "missing owner id",
				req: &runnerscalesets.GetRunnerScaleSetRequest{
					OwnerId:    nil,
					ScaleSetId: 1,
				},
				expectedErrMsg: "owner id cannot be nil",
			},
			{
				name: "missing global id",
				req: &runnerscalesets.GetRunnerScaleSetRequest{
					OwnerId: &pbtypes.Identity{
						GlobalId: "",
					},
					ScaleSetId: 1,
				},
				expectedErrMsg: "global id cannot be empty",
			},
			{
				name: "missing scale set id",
				req: &runnerscalesets.GetRunnerScaleSetRequest{
					OwnerId: &pbtypes.Identity{
						GlobalId: "123",
					},
					ScaleSetId: 0,
				},
				expectedErrMsg: "scale set id must be provided",
			},
		}

		for _, test := range tests {
			t.Run(test.name, func(t *testing.T) {
				err := test.req.Validate()
				require.NotNil(t, err)

				st, ok := err.(twirp.Error)
				require.True(t, ok)
				assert.Equal(t, twirp.InvalidArgument, st.Code())
				assert.Equal(t, test.expectedErrMsg, st.Msg())
			})
		}
	})

	t.Run("valid request", func(t *testing.T) {
		req := &runnerscalesets.GetRunnerScaleSetRequest{
			OwnerId: &pbtypes.Identity{
				GlobalId: "123",
			},
			ScaleSetId: 1,
		}

		err := req.Validate()
		assert.Nil(t, err)
	})
}

func TestListRunnerScaleSetsRequest_Validate(t *testing.T) {
	t.Run("invalid request", func(t *testing.T) {
		tests := []struct {
			name           string
			req            *runnerscalesets.ListRunnerScaleSetsRequest
			expectedErrMsg string
		}{
			{
				name: "missing owner id",
				req: &runnerscalesets.ListRunnerScaleSetsRequest{
					OwnerId: nil,
				},
				expectedErrMsg: "owner id cannot be nil",
			},
			{
				name: "missing global id",
				req: &runnerscalesets.ListRunnerScaleSetsRequest{
					OwnerId: &pbtypes.Identity{
						GlobalId: "",
					},
				},
				expectedErrMsg: "global id cannot be empty",
			},
		}

		for _, test := range tests {
			t.Run(test.name, func(t *testing.T) {
				err := test.req.Validate()
				require.NotNil(t, err)

				st, ok := err.(twirp.Error)
				require.True(t, ok)
				assert.Equal(t, twirp.InvalidArgument, st.Code())
				assert.Equal(t, test.expectedErrMsg, st.Msg())
			})
		}
	})

	t.Run("valid request", func(t *testing.T) {
		req := &runnerscalesets.ListRunnerScaleSetsRequest{
			OwnerId: &pbtypes.Identity{
				GlobalId: "123",
			},
		}

		err := req.Validate()
		assert.Nil(t, err)
	})
}
