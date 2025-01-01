package interfaces

import (
	"context"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
)

type Patchable interface {
	models.ItemKey
	GetPatchOperations() azcosmos.PatchOperations
}

//go:generate pegomock generate -o ../../testing/fakes/mock_total_patching_engine.go --self_package=fakes --package=fakes TotalPatchingEngine
type TotalPatchingEngine interface {
	PatchOrCreate(ctx context.Context, logger log.Logger, item Patchable) error
}
