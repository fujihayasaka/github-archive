package transactions

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
)

var (
	repository            = types.NewRepository(1)
	reqCtx                = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
	reqCtxWithTransaction = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE, types.WithTransactionState([]byte("transaction")))
)

func TestNewBeginTransactionRequest(t *testing.T) {
	req := NewBeginTransactionRequest(reqCtx, repository)
	require.Equal(t, reqCtx, req.RequestContext)
	require.Equal(t, repository, req.Repository)
}

func TestBeginTransactionRequestValidate(t *testing.T) {
	req := &BeginTransactionRequest{}
	require.Error(t, req.Validate())

	req = NewBeginTransactionRequest(reqCtx, types.NewRepository(1))
	require.NoError(t, req.Validate())
}

func TestNewCommitTransactionRequest(t *testing.T) {
	req := NewCommitTransactionRequest(reqCtx, repository)
	require.Equal(t, reqCtx, req.RequestContext)
	require.Equal(t, repository, req.Repository)
}

func TestCommitTransactionRequestValidate(t *testing.T) {
	req := NewCommitTransactionRequest(reqCtxWithTransaction, repository)
	require.NoError(t, req.Validate())
}

func TestCommitTransactionRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *CommitTransactionRequest
		err  string
	}{
		{
			"empty",
			&CommitTransactionRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewCommitTransactionRequest(reqCtx, &types.Repository{}),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing transaction state",
			NewCommitTransactionRequest(reqCtx, repository),
			"twirp error invalid_argument: request_context.transaction_state is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestNewRollbackTransactionRequest(t *testing.T) {
	req := NewRollbackTransactionRequest(reqCtx, repository)
	require.Equal(t, reqCtx, req.RequestContext)
	require.Equal(t, repository, req.Repository)
}

func TestRollbackTransactionRequestValidate(t *testing.T) {
	req := NewRollbackTransactionRequest(reqCtxWithTransaction, repository)
	require.NoError(t, req.Validate())
}

func TestRollbackTransactionRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *RollbackTransactionRequest
		err  string
	}{
		{
			"empty",
			&RollbackTransactionRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewRollbackTransactionRequest(reqCtx, &types.Repository{}),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"missing transaction state",
			NewRollbackTransactionRequest(reqCtx, repository),
			"twirp error invalid_argument: request_context.transaction_state is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}
