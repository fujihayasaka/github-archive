package models

import (
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// RepositoryPolicy is the container for the policy for a single repository.
type RepositoryPolicy struct {
	Data            *proto.RepositoryPolicy
	packageAccessor *packagePolicyAccessor
}

// NewRepositoryPolicy creates a new RepositoryPolicy with supporting infrastructure.
func NewRepositoryPolicy(data *proto.RepositoryPolicy) *RepositoryPolicy {
	if data == nil {
		return nil
	}
	return &RepositoryPolicy{
		Data:            data,
		packageAccessor: newPackagePolicyAccessor(data.Packages),
	}
}
