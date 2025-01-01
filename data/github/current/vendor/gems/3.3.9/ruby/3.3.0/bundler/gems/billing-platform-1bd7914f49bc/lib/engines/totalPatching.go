package engines

import (
	"context"

	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/github-telemetry-go/log"
)

type TotalPatchingEngine struct {
	*EngineParams
	log.Logger
}

func NewTotalPatchingEngine(params *EngineParams) *TotalPatchingEngine {
	return &TotalPatchingEngine{
		EngineParams: params,
	}
}

func (u *TotalPatchingEngine) PatchOrCreate(ctx context.Context, logger log.Logger, item interfaces.Patchable) error {
	err := u.db.CreateWithOptions(ctx, logger, item, nil)
	if err == nil {
		return nil
	}

	// only patch on 409 conflict
	if db.Is409Conflict(err) {
		return u.patch(ctx, logger, item)
	}

	return err
}

func (u *TotalPatchingEngine) patch(ctx context.Context, logger log.Logger, item interfaces.Patchable) error {
	patchOperations := item.GetPatchOperations()

	if err := u.db.PatchWithOptions(ctx, logger, item, patchOperations, nil); err != nil {
		logger.WithError(err).Error("could not patch")
		return err
	}

	return nil
}
