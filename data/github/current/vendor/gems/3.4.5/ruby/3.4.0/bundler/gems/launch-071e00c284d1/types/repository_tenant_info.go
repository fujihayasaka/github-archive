package types

import (
	runservice "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"
)

type RepositoryTenantInfo struct {
	RepoTenantInfo       *runservice.TenantInfo
	OwnerTenantInfo      *runservice.TenantInfo
	EnterpriseTenantInfo *runservice.TenantInfo
}
