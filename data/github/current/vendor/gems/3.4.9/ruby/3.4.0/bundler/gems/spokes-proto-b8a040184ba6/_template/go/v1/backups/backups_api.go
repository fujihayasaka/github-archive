package backups

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewPerformBackupRequest(reqCtx *types.RequestContext, repository *types.Repository, parentRepository *types.Repository) *PerformBackupRequest {
	return &PerformBackupRequest{
		RequestContext:     reqCtx,
		Repository:         repository,
		ParentRepository: parentRepository,
	}
}

func (req *PerformBackupRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	repo := req.GetRepository()
	if err := repo.Validate(); err != nil {
		return err
	}

	if req.GetParentRepository() != nil {
		parent := req.GetParentRepository()
		if err := parent.Validate(); err != nil {
			return err
		}

		if parent.GetType() != repo.GetType() {
			return twirp.InvalidArgument.Error("parent repository type must match target repository type")
		}
	}

	return nil
}
