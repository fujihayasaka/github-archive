package tags

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
	typesv2 "github.com/github/spokes-proto/gen/go/v2/types"
)

var (
	repository = types.NewRepository(1)
	name       = []byte("test-tag")
	target     = types.NewObjectID("1234567890123456789012345678901234567890")
	tagger     = typesv2.NewAttribution([]byte("A U Thor"), []byte("me@example.com"), time.Now())
	message    = []byte("My example tag message")

	reqCtx                   = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE, types.WithTransactionState([]byte("transaction")))
	reqCtxWithoutTransaction = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestNewCreateTagRequest(t *testing.T) {
	req := NewCreateTagRequest(reqCtx, repository, name, target, tagger, message)
	require.Equal(t, req, &CreateTagRequest{
		RequestContext: reqCtx,
		Repository:     repository,
		Name:           name,
		Target:         target,
		Tagger:         tagger,
		Message:        message,
	})
}

func TestCreateTagRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *CreateTagRequest
		err  string
	}{
		{
			"empty",
			&CreateTagRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewCreateTagRequest(reqCtx, nil, name, target, tagger, message),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewCreateTagRequest(reqCtx, &types.Repository{}, name, target, tagger, message),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing transaction_state",
			NewCreateTagRequest(reqCtxWithoutTransaction, repository, name, target, tagger, message),
			"twirp error invalid_argument: request_context.transaction_state is required",
		},
		{
			"missing name",
			NewCreateTagRequest(reqCtx, repository, []byte{}, target, tagger, message),
			"twirp error invalid_argument: name is required",
		},
		{
			"invalid name (starts with -)",
			NewCreateTagRequest(reqCtx, repository, []byte("-invalid-tag"), target, tagger, message),
			"twirp error invalid_argument: name may not begin with '-'",
		},
		{
			"invalid name (refname rules)",
			NewCreateTagRequest(reqCtx, repository, []byte("another/tag/../name"), target, tagger, message),
			"twirp error invalid_argument: name may not have a path component that begins with '.'",
		},
		{
			"missing target",
			NewCreateTagRequest(reqCtx, repository, name, nil, tagger, message),
			"twirp error invalid_argument: target is required",
		},
		{
			"invalid target",
			NewCreateTagRequest(reqCtx, repository, name, &types.ObjectID{}, tagger, message),
			"twirp error invalid_argument: object_id.id is required",
		},
		{
			"missing tagger",
			NewCreateTagRequest(reqCtx, repository, name, target, nil, message),
			"twirp error invalid_argument: tagger is required",
		},
		{
			"invalid tagger",
			NewCreateTagRequest(reqCtx, repository, name, target, typesv2.NewAttribution([]byte("A U Thor"), []byte("<>"), time.Now()), message),
			"twirp error invalid_argument: attribution.email consists only of disallowed characters",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestCreateTagRequestValidate(t *testing.T) {
	var tests = []struct {
		name string
		req  *CreateTagRequest
	}{
		{
			"normal",
			NewCreateTagRequest(reqCtx, repository, name, target, tagger, message),
		},
		{
			"empty message",
			NewCreateTagRequest(reqCtx, repository, name, target, tagger, []byte{}),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.NoError(t, tt.req.Validate())
		})
	}
}

func TestCreateTagResponseSetTransactionContext(t *testing.T) {
	resp := &CreateTagResponse{}
	require.Nil(t, resp.GetTransactionContext())

	respCtx := types.NewTransactionContext([]byte("test"))
	resp.SetTransactionContext(respCtx)
	require.Equal(t, respCtx, resp.GetTransactionContext())
}
