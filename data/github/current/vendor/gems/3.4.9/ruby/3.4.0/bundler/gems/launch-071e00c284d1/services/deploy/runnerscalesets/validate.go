package runnerscalesets

import (
	svcerr "github.com/github/launch/services/errors"
)

func (req *GetRunnerScaleSetRequest) Validate() error {
	if req.OwnerId == nil {
		return svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	if req.OwnerId.GlobalId == "" {
		return svcerr.NewInvalidArgumentError("global id cannot be empty")
	}

	if req.ScaleSetId == 0 {
		return svcerr.NewInvalidArgumentError("scale set id must be provided")
	}

	return nil
}

func (req *ListRunnerScaleSetsRequest) Validate() error {
	if req.OwnerId == nil {
		return svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	if req.OwnerId.GlobalId == "" {
		return svcerr.NewInvalidArgumentError("global id cannot be empty")
	}

	return nil
}
