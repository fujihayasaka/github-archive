package repositories

import (
	repositoriesv2 "github.com/github/spokes-proto/gen/go/v2/repositories"
)

// ToGetRepositoryMetadataRequestV2 converts v1 GetRepositoryMetadataRequest to v2
func ToGetRepositoryMetadataRequestV2(req *GetRepositoryMetadataRequest) *repositoriesv2.GetRepositoryMetadataRequest {
	return &repositoriesv2.GetRepositoryMetadataRequest{
		Target: &repositoriesv2.GetRepositoryMetadataRequest_Repository{
			Repository: req.GetRepository(),
		},
	}
}

// ToGetRepositoryMetadataResponseV1 converts v2 GetRepositoryMetadataResponse to v1
func ToGetRepositoryMetadataResponseV1(res *repositoriesv2.GetRepositoryMetadataResponse) *GetRepositoryMetadataResponse {
	return &GetRepositoryMetadataResponse{
		HashAlgorithm: res.GetHashAlgorithm(),
		RefFormat:     res.GetRefFormat(),
	}
}
