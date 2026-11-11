// Package models contains models we use in our domain logic
package models

import (
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// OrganizationPolicy represents an organisation level license policy.
type OrganizationPolicy struct {
	Data             *proto.OrganizationPolicy
	packageAccessors map[string]*packagePolicyAccessor
}

// NewOrganizationPolicy creates a new OrganizationPolicy with supporting infrastructure.
func NewOrganizationPolicy(data *proto.OrganizationPolicy) *OrganizationPolicy {
	if data == nil {
		return nil
	}

	packageAccessors := make(map[string]*packagePolicyAccessor)
	for _, distributionPolicy := range data.DistributionPolicies {
		packageAccessors[distributionPolicy.Name] = newPackagePolicyAccessor(distributionPolicy.Packages)
	}
	return &OrganizationPolicy{
		Data:             data,
		packageAccessors: packageAccessors,
	}
}
