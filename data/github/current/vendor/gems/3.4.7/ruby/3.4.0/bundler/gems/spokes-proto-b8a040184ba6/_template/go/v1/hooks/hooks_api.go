package hooks

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewRunPreReceiveHooksRequest(
	reqCtx *types.RequestContext,
	repository *types.Repository,
	referenceUpdates []*types.ReferenceUpdate,
	hookMode RunPreReceiveHooksRequest_HookMode,
	sockstat *types.Sockstat,
) *RunPreReceiveHooksRequest {
	return &RunPreReceiveHooksRequest{
		RequestContext:   reqCtx,
		ReferenceUpdates: referenceUpdates,
		HookMode:         hookMode,
		Sockstat:         sockstat,
		Repository:       repository,
	}
}

func (req *RunPreReceiveHooksRequest) Validate() error {
	repo := req.GetRepository()
	if repo == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := repo.Validate(); err != nil {
		return err
	}

	if req.GetHookMode() == RunPreReceiveHooksRequest_HOOK_MODE_INVALID {
		return twirp.RequiredArgumentError("hook_mode")
	}

	if req.GetSockstat() == nil {
		return twirp.RequiredArgumentError("sockstat")
	}

	if len(req.GetSockstat().GetData()) == 0 {
		return twirp.RequiredArgumentError("sockstat.data")
	}

	if len(req.GetReferenceUpdates()) == 0 {
		return twirp.RequiredArgumentError("reference_updates")
	}

	for _, ru := range req.GetReferenceUpdates() {
		if err := ru.Validate(); err != nil {
			return err
		}
	}

	return nil
}
