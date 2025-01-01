package tags

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/internal/validators"
	"github.com/github/spokes-proto/gen/go/v1/types"
	typesv2 "github.com/github/spokes-proto/gen/go/v2/types"
)

func NewCreateTagRequest(
	reqCtx *types.RequestContext,
	r *types.Repository,
	name []byte,
	target *types.ObjectID,
	tagger *typesv2.Attribution,
	message []byte,
) *CreateTagRequest {
	return &CreateTagRequest{
		RequestContext: reqCtx,
		Repository:     r,
		Name:           name,
		Target:         target,
		Tagger:         tagger,
		Message:        message,
	}
}

func (req *CreateTagRequest) Validate() error {
	if req.GetRepository() == nil {
		return twirp.RequiredArgumentError("repository")
	}

	if err := req.GetRepository().Validate(); err != nil {
		return err
	}

	if req.GetRequestContext().GetTransactionState() == nil {
		return twirp.RequiredArgumentError("request_context.transaction_state")
	}

	name := req.GetName()
	if len(name) == 0 {
		return twirp.RequiredArgumentError("name")
	}
	if name[0] == '-' {
		return twirp.InvalidArgumentError("name", "may not begin with '-'")
	}
	if err := validators.ReferenceName(name, "name"); err != nil {
		return err
	}

	target := req.GetTarget()
	if target == nil {
		return twirp.RequiredArgumentError("target")
	}

	if err := target.Validate(); err != nil {
		return err
	}

	tagger := req.GetTagger()
	if tagger == nil {
		return twirp.RequiredArgumentError("tagger")
	}

	if err := tagger.Validate(); err != nil {
		return err
	}

	return nil
}

func (resp *CreateTagResponse) SetTransactionContext(transactionContext *types.TransactionContext) {
	if resp != nil {
		resp.TransactionContext = transactionContext
	}
}
