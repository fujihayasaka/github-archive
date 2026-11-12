package repositories

import (
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
