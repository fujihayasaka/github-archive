package repositories

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func (req *ListAvailableReplicasRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *CreateForkRequest) Validate() error {
	if req.GetParent().GetRepository() == nil {
		return twirp.RequiredArgumentError("parent.repository")
	}

	if err := req.GetParent().GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetFork() == nil {
		return twirp.RequiredArgumentError("fork")
	}

	if req.GetFork().GetId() == req.GetParent().GetRepository().GetId() {
		return twirp.InvalidArgumentError("fork.id", "cannot be the same as parent repository id")
	}

	if len(req.GetFork().GetNwo()) == 0 {
		return twirp.RequiredArgumentError("fork.nwo")
	}

	if req.GetParent().GetRepository().GetType() != types.Repository_TYPE_REPOSITORY {
		return twirp.InvalidArgumentError("parent.repository.type", "enum must be of type repository")
	}

	if req.GetBranchMode() == CreateForkRequest_BRANCH_MODE_INVALID {
		return twirp.InvalidArgumentError("branch_mode", "must be set")
	}

	return nil
}

func (req *GetRepositoryMetadataRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}
