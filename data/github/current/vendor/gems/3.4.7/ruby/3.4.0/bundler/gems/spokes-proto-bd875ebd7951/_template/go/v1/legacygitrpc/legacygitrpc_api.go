package legacygitrpc

import (
	types "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewLegacyGitrpcReaderRequest(
	reqCtx *types.RequestContext, repository *types.Repository,
	ernReq *ErnicornRequest, tc *TopologyContext) *LegacyGitrpcReaderRequest {

	return &LegacyGitrpcReaderRequest{
		RequestContext:  reqCtx,
		Repository:      repository,
		ErnicornRequest: ernReq,
		TopologyContext: tc,
	}
}

func (req *ErnicornRequest) Validate() error {
	if options := req.GetOptions(); len(options) == 0 {
		return twirp.RequiredArgumentError("options")
	}

	if function := req.GetFunction(); function == "" {
		return twirp.RequiredArgumentError("function")
	}

	if args := req.GetArgs(); len(args) == 0 {
		return twirp.RequiredArgumentError("args")
	}

	if kwargs := req.GetKwargs(); len(kwargs) == 0 {
		return twirp.RequiredArgumentError("kwargs")
	}
	return nil
}

func (req *LegacyGitrpcReaderRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetErnicornRequest() == nil {
		return twirp.RequiredArgumentError("ernicorn_request")
	}

	if err := req.GetErnicornRequest().Validate(); err != nil {
		return err
	}

	return nil
}

func NewLegacyGitrpcWriterRequest(reqCtx *types.RequestContext, repository *types.Repository,
	ernReq *ErnicornRequest, tc *TopologyContext) *LegacyGitrpcWriterRequest {

	return &LegacyGitrpcWriterRequest{
		RequestContext:  reqCtx,
		Repository:      repository,
		ErnicornRequest: ernReq,
		TopologyContext: tc,
	}
}

func (req *LegacyGitrpcWriterRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetErnicornRequest() == nil {
		return twirp.RequiredArgumentError("ernicorn_request")
	}

	if err := req.GetErnicornRequest().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *BertrpcRequest) Validate() error {
	if req.GetHost() == "" {
		return twirp.RequiredArgumentError("host")
	}

	if req.GetPath() == "" {
		return twirp.RequiredArgumentError("path")
	}

	if req.GetErnicornRequest() == nil {
		return twirp.RequiredArgumentError("ernicorn_request")
	}

	if err := req.GetErnicornRequest().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *GetCacheKeyRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}

func (req *GetCacheKeysRequest) Validate() error {
	if len(req.GetRepositories()) == 0 {
		return twirp.RequiredArgumentError("repositories")
	}

	if len(req.GetRepositories()) > 1000 {
		return twirp.InvalidArgumentError("repositories", "may contain up to 1000 items")
	}

	for _, repository := range req.GetRepositories() {
		if err := repository.Validate(); err != nil {
			return err
		}
		if repository.GetType() != types.Repository_TYPE_REPOSITORY {
			return twirp.InvalidArgumentError("repository.type", "must be repository")
		}
	}

	return nil
}
