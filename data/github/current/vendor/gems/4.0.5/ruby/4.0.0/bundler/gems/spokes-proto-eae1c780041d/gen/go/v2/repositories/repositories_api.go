package repositories

import (
	"github.com/twitchtv/twirp"
)

func (req *GetRepositoryMetadataRequest) Validate() error {
	switch req.GetTarget().(type) {
	case *GetRepositoryMetadataRequest_Repository:
		if req.GetRepository() == nil {
			return twirp.RequiredArgumentError("repository")
		}

		if err := req.GetRepository().Validate(); err != nil {
			return err
		}
	case *GetRepositoryMetadataRequest_Network:
		if req.GetNetwork() == nil {
			return twirp.RequiredArgumentError("network")
		}

		if err := req.GetNetwork().Validate(); err != nil {
			return err
		}
	default:
		return twirp.RequiredArgumentError("repository or network")
	}

	return nil
}
