package hooks

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
)

var (
	repository = types.NewRepository(1)
	ref        = types.NewReference([]byte("refs/heads/main"))
	oid        = types.NewObjectID("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refUpdate  = types.NewReferenceUpdate(ref, oid, oid)
	refUpdates = []*types.ReferenceUpdate{refUpdate}
	reqCtx     = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
	Sockstat   = &types.Sockstat{
		Data: []*types.SockstatKV{
			{
				Key: "test",
				Value: &types.SockstatKV_Int64Value{
					Int64Value: 1,
				},
			},
		}}
)

func TestRunPreReceiveHooksRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *RunPreReceiveHooksRequest
		err  string
	}{
		{
			"empty",
			&RunPreReceiveHooksRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing hook mode",
			&RunPreReceiveHooksRequest{
				RequestContext:   reqCtx,
				ReferenceUpdates: refUpdates,
				Sockstat:         Sockstat,
				Repository:       repository,
			},
			"twirp error invalid_argument: hook_mode is required",
		},
		{
			"missing ref updates",
			&RunPreReceiveHooksRequest{
				RequestContext: reqCtx,
				HookMode:       RunPreReceiveHooksRequest_HOOK_MODE_QUARANTINE,
				Sockstat:       Sockstat,
				Repository:     repository,
			},
			"twirp error invalid_argument: reference_updates is required",
		},
		{
			"missing sock stat",
			&RunPreReceiveHooksRequest{
				RequestContext:   reqCtx,
				ReferenceUpdates: refUpdates,
				HookMode:         RunPreReceiveHooksRequest_HOOK_MODE_QUARANTINE,
				Repository:       repository,
			},
			"twirp error invalid_argument: sockstat is required",
		},
		{
			"empty sock stat",
			&RunPreReceiveHooksRequest{
				RequestContext:   reqCtx,
				ReferenceUpdates: refUpdates,
				HookMode:         RunPreReceiveHooksRequest_HOOK_MODE_QUARANTINE,
				Sockstat:         &types.Sockstat{Data: []*types.SockstatKV{}},
				Repository:       repository,
			},
			"twirp error invalid_argument: sockstat.data is required",
		},
		{
			"empty repo",
			&RunPreReceiveHooksRequest{
				RequestContext:   reqCtx,
				ReferenceUpdates: refUpdates,
				HookMode:         RunPreReceiveHooksRequest_HOOK_MODE_QUARANTINE,
				Sockstat:         &types.Sockstat{Data: []*types.SockstatKV{}},
			},
			"twirp error invalid_argument: repository is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestRunPreReceiveHooksRequestValidate(t *testing.T) {
	req := NewRunPreReceiveHooksRequest(reqCtx, repository, refUpdates, RunPreReceiveHooksRequest_HOOK_MODE_QUARANTINE, Sockstat)
	require.NoError(t, req.Validate())
}
