package models

import "github.com/github/osslicensecompliance/pkg/proto/v0"

// EnterprisePolicy represents an enterprise-level license policy.
type EnterprisePolicy struct {
	Data             *proto.EnterprisePolicy
	packageAccessors map[string]*packagePolicyAccessor
}

// NewEnterprisePolicy creates a new EnterprisePolicy with supporting infrastructure.
func NewEnterprisePolicy(data *proto.EnterprisePolicy) *EnterprisePolicy {
	if data == nil {
		return nil
	}
	packageAccessors := make(map[string]*packagePolicyAccessor)
	for _, distributionPolicy := range data.DistributionPolicies {
		packageAccessors[distributionPolicy.Name] = newPackagePolicyAccessor(distributionPolicy.Packages)
	}
	return &EnterprisePolicy{
		Data:             data,
		packageAccessors: packageAccessors,
	}
}
