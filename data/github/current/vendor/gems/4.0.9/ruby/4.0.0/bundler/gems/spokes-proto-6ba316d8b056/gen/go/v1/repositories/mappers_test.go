package repositories

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	repositoriesv2 "github.com/github/spokes-proto/gen/go/v2/repositories"
	"github.com/stretchr/testify/require"
)

func TestToGetRepositoryMetadataRequestV2(t *testing.T) {
	t.Run("with valid repository", func(t *testing.T) {
		req := &GetRepositoryMetadataRequest{
			Repository: types.NewRepository(1),
		}
		v2Req := ToGetRepositoryMetadataRequestV2(req)
		require.NotNil(t, v2Req)
		require.NotNil(t, v2Req.GetTarget())
		require.Equal(t, req.GetRepository(), v2Req.GetRepository())
	})

	t.Run("with nil repository", func(t *testing.T) {
		req := &GetRepositoryMetadataRequest{}
		v2Req := ToGetRepositoryMetadataRequestV2(req)
		require.NotNil(t, v2Req)
		require.NotNil(t, v2Req.GetTarget())
		require.Nil(t, v2Req.GetRepository())
	})
}

func TestToGetRepositoryMetadataResponseV1(t *testing.T) {
	t.Run("with both hash algorithm and ref format", func(t *testing.T) {
		res := &repositoriesv2.GetRepositoryMetadataResponse{
			HashAlgorithm: types.HashAlgorithm_HASH_ALGORITHM_SHA1,
			RefFormat:     types.RefFormat_REF_FORMAT_REFTABLE,
		}
		v1Res := ToGetRepositoryMetadataResponseV1(res)
		require.NotNil(t, v1Res)
		require.Equal(t, res.GetHashAlgorithm(), v1Res.GetHashAlgorithm())
		require.Equal(t, res.GetRefFormat(), v1Res.GetRefFormat())
	})

	t.Run("with nil hash algorithm", func(t *testing.T) {
		res := &repositoriesv2.GetRepositoryMetadataResponse{
			RefFormat: types.RefFormat_REF_FORMAT_REFTABLE,
		}
		v1Res := ToGetRepositoryMetadataResponseV1(res)
		require.NotNil(t, v1Res)
		require.Equal(t, types.HashAlgorithm_HASH_ALGORITHM_INVALID, v1Res.GetHashAlgorithm())
		require.Equal(t, res.GetRefFormat(), v1Res.GetRefFormat())
	})

	t.Run("with nil ref format", func(t *testing.T) {
		res := &repositoriesv2.GetRepositoryMetadataResponse{
			HashAlgorithm: types.HashAlgorithm_HASH_ALGORITHM_SHA1,
		}
		v1Res := ToGetRepositoryMetadataResponseV1(res)
		require.NotNil(t, v1Res)
		require.Equal(t, res.GetHashAlgorithm(), v1Res.GetHashAlgorithm())
		require.Equal(t, types.RefFormat_REF_FORMAT_INVALID, v1Res.GetRefFormat())
	})

	t.Run("with both nil", func(t *testing.T) {
		res := &repositoriesv2.GetRepositoryMetadataResponse{}
		v1Res := ToGetRepositoryMetadataResponseV1(res)
		require.NotNil(t, v1Res)
		require.Equal(t, types.HashAlgorithm_HASH_ALGORITHM_INVALID, v1Res.GetHashAlgorithm())
		require.Equal(t, types.RefFormat_REF_FORMAT_INVALID, v1Res.GetRefFormat())
	})
}
