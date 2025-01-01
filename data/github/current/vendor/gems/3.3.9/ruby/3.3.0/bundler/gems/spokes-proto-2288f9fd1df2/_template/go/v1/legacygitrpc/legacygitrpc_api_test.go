package legacygitrpc

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

var (
	repository = types.NewRepository(1)
	reqCtx     = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestNewLegacyGitrpcReaderRequest(t *testing.T) {
	ernReq := &ErnicornRequest{
		Options:  []byte{},
		Function: "f",
		Args:     []byte{},
		Kwargs:   []byte{},
	}
	req := NewLegacyGitrpcReaderRequest(reqCtx, repository, ernReq, nil)
	require.Equal(t, req, &LegacyGitrpcReaderRequest{
		RequestContext:  reqCtx,
		Repository:      repository,
		ErnicornRequest: ernReq,
	})
}

func TestLegacyGitrpcReaderRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *LegacyGitrpcReaderRequest
		err  string
	}{
		{
			"empty",
			&LegacyGitrpcReaderRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewLegacyGitrpcReaderRequest(reqCtx, nil, nil, nil),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewLegacyGitrpcReaderRequest(reqCtx, &types.Repository{}, nil, nil),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"invalid options",
			NewLegacyGitrpcReaderRequest(reqCtx, repository, &ErnicornRequest{
				Options:  []byte{},
				Function: "f",
				Args:     []byte{1, 2},
				Kwargs:   []byte{3, 4},
			}, nil),
			"twirp error invalid_argument: options is required",
		},
		{
			"invalid args",
			NewLegacyGitrpcReaderRequest(reqCtx, repository, &ErnicornRequest{
				Options:  []byte{1, 2},
				Function: "f",
				Args:     []byte{},
				Kwargs:   []byte{3, 4},
			}, nil),
			"twirp error invalid_argument: args is required",
		},
		{
			"invalid kwargs",
			NewLegacyGitrpcReaderRequest(reqCtx, repository, &ErnicornRequest{
				Options:  []byte{1, 2},
				Function: "f",
				Args:     []byte{3, 4},
				Kwargs:   []byte{},
			}, nil),
			"twirp error invalid_argument: kwargs is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestNewLegacyGitrpcWriterRequest(t *testing.T) {
	ernReq := &ErnicornRequest{
		Options:  []byte{},
		Function: "f",
		Args:     []byte{},
		Kwargs:   []byte{},
	}
	req := NewLegacyGitrpcWriterRequest(reqCtx, repository, ernReq, nil)
	require.Equal(t, req, &LegacyGitrpcWriterRequest{
		RequestContext:  reqCtx,
		Repository:      repository,
		ErnicornRequest: ernReq,
	})
}

func TestLegacyGitrpcWriterRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *LegacyGitrpcWriterRequest
		err  string
	}{
		{
			"empty",
			&LegacyGitrpcWriterRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewLegacyGitrpcWriterRequest(reqCtx, nil, nil, nil),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewLegacyGitrpcWriterRequest(reqCtx, &types.Repository{}, nil, nil),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"invalid options",
			NewLegacyGitrpcWriterRequest(reqCtx, repository, &ErnicornRequest{
				Options:  []byte{},
				Function: "f",
				Args:     []byte{1, 2},
				Kwargs:   []byte{3, 4},
			}, nil),
			"twirp error invalid_argument: options is required",
		},
		{
			"invalid args",
			NewLegacyGitrpcWriterRequest(reqCtx, repository, &ErnicornRequest{
				Options:  []byte{1, 2},
				Function: "f",
				Args:     []byte{},
				Kwargs:   []byte{3, 4},
			}, nil),
			"twirp error invalid_argument: args is required",
		},
		{
			"invalid kwargs",
			NewLegacyGitrpcWriterRequest(reqCtx, repository, &ErnicornRequest{
				Options:  []byte{1, 2},
				Function: "f",
				Args:     []byte{3, 4},
				Kwargs:   []byte{},
			}, nil),
			"twirp error invalid_argument: kwargs is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}

func TestGetCacheKeyRequestValidate(t *testing.T) {
	req := &GetCacheKeyRequest{}
	require.Error(t, req.Validate())

	req = &GetCacheKeyRequest{Repository: types.NewRepository(1)}
	require.NoError(t, req.Validate())
}

func TestGetCacheKeysRequestValidate(t *testing.T) {
	manyRepositories := func(n int) []*types.Repository {
		res := make([]*types.Repository, 0, n)
		for i := 0; i < n; i++ {
			res = append(res, types.NewRepository(uint64(i)))
		}
		return res
	}

	t.Run("not valid", func(t *testing.T) {
		var notValid = []struct {
			name string
			req  *GetCacheKeysRequest
			err  string
		}{
			{
				"empty",
				&GetCacheKeysRequest{},
				"twirp error invalid_argument: repositories is required",
			},
			{
				"missing repository id",
				&GetCacheKeysRequest{Repositories: []*types.Repository{types.NewRepository(0)}},
				"twirp error invalid_argument: repository.id is required",
			},
			{
				"non-repository type",
				&GetCacheKeysRequest{Repositories: []*types.Repository{types.NewWiki(1)}},
				"twirp error invalid_argument: repository.type must be repository",
			},
			{
				"too many repositories",
				&GetCacheKeysRequest{Repositories: manyRepositories(1001)},
				"twirp error invalid_argument: repositories may contain up to 1000 items",
			},
		}

		for _, tt := range notValid {
			t.Run(tt.name, func(t *testing.T) {
				require.EqualError(t, tt.req.Validate(), tt.err)
			})
		}
	})

	t.Run("valid", func(t *testing.T) {
		var valid = []struct {
			name string
			req  *GetCacheKeysRequest
		}{
			{
				"one repository",
				&GetCacheKeysRequest{Repositories: []*types.Repository{types.NewRepository(1)}},
			},
			{
				"many repositories",
				&GetCacheKeysRequest{Repositories: []*types.Repository{types.NewRepository(1), types.NewRepository(2)}},
			},
		}

		for _, tt := range valid {
			t.Run(tt.name, func(t *testing.T) {
				require.NoError(t, tt.req.Validate())
			})
		}
	})
}
