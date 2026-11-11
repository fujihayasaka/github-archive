package maintenance

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewMaintenanceInfoRequest(reqCtx *types.RequestContext, repository *types.Repository) *MaintenanceInfoRequest {
	return &MaintenanceInfoRequest{
		RequestContext: reqCtx,
		Repository:     repository,
	}
}

func (req *MaintenanceInfoRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}
