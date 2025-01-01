package transactions

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewBeginTransactionRequest(reqCtx *types.RequestContext, repository *types.Repository) *BeginTransactionRequest {
	return &BeginTransactionRequest{
		RequestContext: reqCtx,
		Repository:     repository,
	}
}

func (req *BeginTransactionRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	return nil
}

func NewCommitTransactionRequest(reqCtx *types.RequestContext, repository *types.Repository) *CommitTransactionRequest {
	return &CommitTransactionRequest{
		RequestContext: reqCtx,
		Repository:     repository,
	}
}

func (req *CommitTransactionRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetRequestContext().GetTransactionState() == nil {
		return twirp.RequiredArgumentError("request_context.transaction_state")
	}

	return nil
}

func NewRollbackTransactionRequest(reqCtx *types.RequestContext, repository *types.Repository) *RollbackTransactionRequest {
	return &RollbackTransactionRequest{
		RequestContext: reqCtx,
		Repository:     repository,
	}
}

func (req *RollbackTransactionRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetRequestContext().GetTransactionState() == nil {
		return twirp.RequiredArgumentError("request_context.transaction_state")
	}

	return nil
}
